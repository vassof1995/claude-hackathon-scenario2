variable "name_prefix" {
  description = "Prefix for all resource names, e.g. contoso-prod."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource (owner, workload, env, cost-center)."
  type        = map(string)
}

variable "region" {
  description = "AWS region (used for the awslogs driver)."
  type        = string
}

# --- Shared infrastructure, passed in (provisioned elsewhere; see ADR-0005 / plan §1) -------
variable "ecs_cluster_arn" {
  description = "ARN of the shared ECS cluster the run-to-exit task is launched into."
  type        = string
}

variable "private_app_subnet_ids" {
  description = "Private app-tier subnet IDs the Fargate task runs in (no public IP)."
  type        = list(string)
}

variable "data_tier_security_group_id" {
  description = "SG of the RDS data tier; the batch task SG is granted egress to :5432 here."
  type        = string
}

variable "vpc_id" {
  description = "VPC the task SG is created in."
  type        = string
}

# --- The image and its data dependencies ----------------------------------------------------
variable "image" {
  description = "ECR image URI for the batch (cloud-profile, run-to-exit). Same logic as legacy/batch."
  type        = string
}

variable "datasource_url" {
  description = "JDBC URL for the RDS primary, e.g. jdbc:postgresql://<rds-endpoint>:5432/contoso. Not a secret."
  type        = string
}

variable "datasource_username" {
  description = "DB role the batch connects as (RW reporting, RO app). Not a secret."
  type        = string
  default     = "batch_user"
}

variable "batch_db_password_secret_arn" {
  description = "Secrets Manager ARN holding BATCH_DB_PASSWORD. Injected by reference, never inlined (ADR-0003)."
  type        = string
}

# --- Schedule & sizing ----------------------------------------------------------------------
variable "schedule_expression" {
  description = "EventBridge Scheduler cron — the SAME 02:00 schedule the legacy @Scheduled used."
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "schedule_timezone" {
  description = "Timezone for the schedule. Pinning this addresses the wall-clock coupling (discovery #6)."
  type        = string
  default     = "Europe/Berlin"
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory (MiB)."
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the batch task."
  type        = number
  default     = 30
}
