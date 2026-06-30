locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project
    Workload    = "web-app"
    Owner       = "contoso-team"
    CostCenter  = "infra"
  }
}

# ---------------------------------------------------------------------------
# SECURITY GROUPS
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project}-web-api-alb-sg"
  description = "Security group for the web-api ALB — allows inbound HTTP/HTTPS from the internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description              = "Forward traffic to ECS tasks on port 8080"
    from_port                = 8080
    to_port                  = 8080
    protocol                 = "tcp"
    source_security_group_id = aws_security_group.ecs.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-web-api-alb-sg"
  })
}

resource "aws_security_group" "ecs" {
  name        = "${var.project}-web-api-ecs-sg"
  description = "Security group for web-api ECS Fargate tasks"
  vpc_id      = var.vpc_id

  ingress {
    description              = "Allow traffic from ALB on container port"
    from_port                = 8080
    to_port                  = 8080
    protocol                 = "tcp"
    source_security_group_id = aws_security_group.alb.id
  }

  egress {
    description = "HTTPS egress for ECR pulls and Secrets Manager API calls"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "egress" {
    for_each = var.private_data_cidr_blocks
    content {
      description = "Postgres egress to data subnet ${egress.value}"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [egress.value]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-web-api-ecs-sg"
  })
}

# ---------------------------------------------------------------------------
# APPLICATION LOAD BALANCER
# ---------------------------------------------------------------------------

resource "aws_lb" "web_api" {
  name               = "${var.project}-web-api-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  tags = merge(local.common_tags, {
    Name = "${var.project}-web-api-alb"
  })
}

resource "aws_lb_target_group" "web_api" {
  name        = "${var.project}-web-api-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/actuator/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-web-api-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_api.arn
  }
}

# ---------------------------------------------------------------------------
# ECS CLUSTER + CLOUDWATCH LOG GROUP
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "web_api" {
  name = "contoso-web-api"

  tags = merge(local.common_tags, {
    Name = "contoso-web-api"
  })
}

resource "aws_cloudwatch_log_group" "web_api" {
  name              = "/ecs/contoso-web-api"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "/ecs/contoso-web-api"
  })
}

# ---------------------------------------------------------------------------
# IAM — TASK EXECUTION ROLE
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    sid     = "ECSTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.project}-web-api-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project}-web-api-task-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_extras" {
  # Stmt1: ECR authorisation token — must be Resource * (AWS requirement for this API)
  statement {
    sid     = "ECRGetAuthToken"
    effect  = "Allow"
    actions = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Stmt2: Pull the specific image from the known ECR repository
  statement {
    sid    = "ECRPullImage"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [var.ecr_repository_arn]
  }

  # Stmt3: Read only the DB secrets passed in by the caller
  statement {
    sid     = "ReadDBSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = values(var.db_secret_arns)
  }

  # Stmt4: Write container logs to the dedicated log group
  statement {
    sid    = "WriteLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.web_api.arn}:*"]
  }
}

resource "aws_iam_policy" "execution_extras" {
  name        = "${var.project}-web-api-execution-extras"
  description = "Extra permissions for the web-api ECS task execution role (ECR pull, Secrets Manager, CloudWatch Logs)"
  policy      = data.aws_iam_policy_document.execution_extras.json

  tags = merge(local.common_tags, {
    Name = "${var.project}-web-api-execution-extras"
  })
}

resource "aws_iam_role_policy_attachment" "execution_extras" {
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.execution_extras.arn
}

# ---------------------------------------------------------------------------
# IAM — TASK ROLE (runtime identity for the application)
# ---------------------------------------------------------------------------

resource "aws_iam_role" "task_role" {
  name               = "${var.project}-web-api-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  description        = "Runtime IAM role for the web-api ECS task. Attach application-level policies here (e.g. S3, SQS) as needed."

  tags = merge(local.common_tags, {
    Name = "${var.project}-web-api-task-role"
  })
}

# ---------------------------------------------------------------------------
# ECS TASK DEFINITION
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "web_api" {
  family                   = "contoso-web-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "web-api"
      image     = var.image_url
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      secrets = [
        for k, v in var.db_secret_arns : {
          name      = k
          valueFrom = v
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.web_api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "web-api"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -sf http://localhost:8080/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name = "contoso-web-api"
  })
}

# ---------------------------------------------------------------------------
# ECS FARGATE SERVICE
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "web_api" {
  name            = "contoso-web-api"
  cluster         = aws_ecs_cluster.web_api.id
  task_definition = aws_ecs_task_definition.web_api.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web_api.arn
    container_name   = "web-api"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]

  tags = merge(local.common_tags, {
    Name = "contoso-web-api"
  })
}
