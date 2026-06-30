variable "region" {
  description = "AWS region for the prod environment."
  type        = string
  default     = "eu-central-1"
}

variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
  default     = "contoso-prod"
}

variable "cost_center" {
  description = "Cost-center tag value."
  type        = string
}

# Shared infrastructure provisioned elsewhere (network, ECS cluster, RDS, secrets) — passed in
# so this batch slice is self-contained and auditable without the whole estate (plan §1, ADR-0005).
variable "vpc_id" {
  type        = string
  description = "VPC ID."
}

variable "private_app_subnet_ids" {
  type        = list(string)
  description = "Private app-tier subnet IDs."
}

variable "data_tier_security_group_id" {
  type        = string
  description = "RDS data-tier security group ID."
}

variable "ecs_cluster_arn" {
  type        = string
  description = "Shared ECS cluster ARN."
}

variable "batch_image" {
  type        = string
  description = "ECR image URI for the cloud-profile, run-to-exit batch."
}

variable "rds_endpoint" {
  type        = string
  description = "RDS primary endpoint host (no port), e.g. contoso-prod.xxxx.eu-central-1.rds.amazonaws.com."
}

variable "batch_db_password_secret_arn" {
  type        = string
  description = "Secrets Manager ARN for BATCH_DB_PASSWORD (reference only; ADR-0003)."
}
