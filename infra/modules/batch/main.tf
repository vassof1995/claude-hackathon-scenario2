# Batch workload — target architecture (ADR-0006, plan §3).
# EventBridge Scheduler (02:00) -> ecs:RunTask -> run-to-exit Fargate task that reconciles
# yesterday and exits. Reconciliation logic is unchanged from legacy/batch; only the trigger
# and hosting model move to infrastructure. Not applied to a live account — it must read right.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  name           = "${var.name_prefix}-batch"
  container_name = "batch"
}

# --- Logs -----------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "batch" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# --- Task security group: egress to the data tier only (no inbound; the task is run-to-exit) -
resource "aws_security_group" "task" {
  name        = "${local.name}-task"
  description = "Batch run-to-exit task; egress to RDS data tier only."
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_security_group_rule" "egress_to_rds" {
  type                     = "egress"
  description              = "Postgres to the RDS data tier."
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.task.id
  source_security_group_id = var.data_tier_security_group_id
}

# --- IAM: execution role (pull image, fetch secrets, write logs) ----------------------------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

# Managed policy covers ECR pull + base CloudWatch Logs for the execution role.
resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Least privilege: read ONLY the one batch secret to inject it as an env var.
data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid       = "ReadBatchSecretOnly"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.batch_db_password_secret_arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "${local.name}-exec-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# --- IAM: task role (the app itself; talks to RDS over JDBC, needs no AWS API beyond logs) ---
resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "task_logs" {
  statement {
    sid       = "WriteOwnLogStream"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.batch.arn}:*"]
  }
}

resource "aws_iam_role_policy" "task_logs" {
  name   = "${local.name}-task-logs"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_logs.json
}

# --- Task definition: run-to-exit ------------------------------------------------------------
resource "aws_ecs_task_definition" "batch" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  tags                     = var.tags

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = var.image
      essential = true
      # Cloud profile disables @Scheduled (the schedule now lives in EventBridge) and runs the
      # reconciliation once on start, then the container exits. See ADR-0006.
      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "cloud" },
        { name = "SPRING_DATASOURCE_URL", value = var.datasource_url },
        { name = "SPRING_DATASOURCE_USERNAME", value = var.datasource_username }
      ]
      # Secret injected by reference from Secrets Manager — never a literal (ADR-0003).
      secrets = [
        { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = var.batch_db_password_secret_arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.batch.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "batch"
        }
      }
    }
  ])
}

# --- IAM: scheduler role (EventBridge Scheduler may only RunTask + PassRole for this task) ---
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid       = "RunBatchTask"
    actions   = ["ecs:RunTask"]
    resources = ["${aws_ecs_task_definition.batch.arn_without_revision}:*", aws_ecs_task_definition.batch.arn]
  }
  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.task.arn]
    condition {
      test     = "StringLike"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${local.name}-scheduler"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}

# --- The schedule: same 02:00 cron the legacy @Scheduled used -------------------------------
resource "aws_scheduler_schedule" "nightly" {
  name = "${local.name}-nightly"
  flexible_time_window {
    mode = "OFF"
  }
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  target {
    arn      = var.ecs_cluster_arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.batch.arn_without_revision
      launch_type         = "FARGATE"
      network_configuration {
        subnets          = var.private_app_subnet_ids
        security_groups  = [aws_security_group.task.id]
        assign_public_ip = false
      }
    }

    retry_policy {
      # C3: if the app schema isn't ready yet the task fails fast; let the schedule retry.
      maximum_retry_attempts       = 3
      maximum_event_age_in_seconds = 3600
    }
  }
}

# Manual 4am re-run path: same target, disabled by default; ops enable / one-off RunTask.
resource "aws_scheduler_schedule" "manual" {
  name  = "${local.name}-manual"
  state = "DISABLED"
  flexible_time_window {
    mode = "OFF"
  }
  schedule_expression = var.schedule_expression

  target {
    arn      = var.ecs_cluster_arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.batch.arn_without_revision
      launch_type         = "FARGATE"
      network_configuration {
        subnets          = var.private_app_subnet_ids
        security_groups  = [aws_security_group.task.id]
        assign_public_ip = false
      }
    }
  }
}
