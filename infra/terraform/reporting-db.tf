# =============================================================================
# reporting-db.tf  —  TARGET-STATE SCAFFOLD (ILLUSTRATIVE SHAPE)
# -----------------------------------------------------------------------------
# THIS FILE IS NOT APPLIED. It is an illustrative target-shape scaffold that
# documents the intended Amazon RDS for PostgreSQL topology for the reporting-db
# workload. It is deliberately not wired into a backend, not `terraform apply`-ed,
# and several values are placeholders / variables. Do NOT run this as-is; it
# exists so an auditor can read the intended end state at a glance.
#
# Decision context: decisions/0002-target-cloud-aws.md selects "RDS Postgres +
# read replica" for reporting. Region: eu-central-1.
#
# Topology (decided — do NOT re-litigate here):
#   - ONE Multi-AZ RDS PostgreSQL primary holds BOTH the `app` and `reporting`
#     schemas (schema split is explicitly DEFERRED: batch_user needs cross-schema
#     access to read app.transactions while writing reporting.*).
#   - web-api writes `app` on the primary; batch writes `reporting` and reads
#     `app` on the primary.
#   - A read replica serves the five reporting teams; they connect to the
#     replica endpoint as report_reader (SELECT-only on `reporting`).
#   - The database is NEVER publicly accessible. Ingress on 5432 is allowed ONLY
#     from the app-tier security group and an approved analysts CIDR (variables;
#     never a literal, never 0.0.0.0/0).
#
# REMOTE STATE STORY (described, NOT stood up here):
#   State is intended to live in an S3 backend with a DynamoDB lock table
#   (versioned, encrypted bucket; lock table on a `LockID` hash key). That
#   backend block is intentionally omitted from this scaffold so nothing is
#   provisioned by reading this file. See infra/CLAUDE.md for the IaC rules.
#
# DATABASE ROLES (managed via SQL bootstrap, NOT Terraform):
#   The three LOGIN roles and their least-privilege grants — report_reader,
#   batch_user, app_user — are created and granted by the SQL bootstrap that
#   ports legacy/reporting-db/init/01-roles-and-schemas.sh. Terraform manages
#   only the RDS infrastructure (instances, subnet group, security group), never
#   the in-database roles/grants. Preserve the existing grants EXACTLY:
#     * app_user      : owns schema `app` (RW).
#     * batch_user    : owns schema `reporting` (RW); USAGE on `app` +
#                       SELECT on app tables (ALTER DEFAULT PRIVILEGES).
#     * report_reader : USAGE on `reporting` + SELECT on reporting tables only
#                       (no `app` access, no writes anywhere).
#   See the reporting-db migration runbook for the bootstrap procedure.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # backend "s3" {
  #   # TARGET (not stood up here): S3 backend + DynamoDB state lock.
  #   #   bucket         = "<state-bucket>"          # versioned, SSE-encrypted
  #   #   key            = "reporting-db/terraform.tfstate"
  #   #   region         = "eu-central-1"
  #   #   dynamodb_table = "<terraform-lock-table>"  # hash key: LockID
  #   #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# Variables — declare inputs; do NOT bake in account IDs, secrets, or CIDRs.
# -----------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for the reporting-db workload."
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod) used in tags."
  type        = string
}

variable "owner" {
  description = "Owning team/contact for the reporting-db workload (Owner tag)."
  type        = string
}

variable "cost_center" {
  description = "Cost center allocation code (CostCenter tag)."
  type        = string
}

variable "data_classification" {
  description = "Data classification for tagging. The app schema is the system of record."
  type        = string
  default     = "confidential"
}

variable "extra_tags" {
  description = "Additional tags merged onto the base tag set for every resource."
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC id hosting the database tier."
  type        = string
}

variable "private_subnet_ids" {
  description = "PRIVATE subnet ids for the DB subnet group. No public subnets."
  type        = list(string)
}

variable "app_tier_security_group_id" {
  description = "Security group id of the app tier (web-api + batch) permitted to reach 5432."
  type        = string
}

variable "analysts_cidr" {
  description = <<-EOT
    Approved analysts CIDR allowed to reach 5432 on the read replica.
    Must be a tightly-scoped corporate/VPN range. NEVER 0.0.0.0/0.
  EOT
  type        = string

  validation {
    condition     = var.analysts_cidr != "0.0.0.0/0"
    error_message = "analysts_cidr must not be 0.0.0.0/0; provide a scoped range."
  }
}

variable "instance_class" {
  description = "RDS instance class for the primary."
  type        = string
  default     = "db.r6g.large"
}

variable "replica_instance_class" {
  description = "RDS instance class for the read replica serving the reporting teams."
  type        = string
  default     = "db.r6g.large"
}

variable "engine_version" {
  description = "PostgreSQL engine major.minor version (legacy ran postgres:16)."
  type        = string
  default     = "16"
}

variable "allocated_storage" {
  description = "Allocated storage (GiB) for the primary."
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Initial database name (legacy db was 'contoso')."
  type        = string
  default     = "contoso"
}

variable "master_username" {
  description = "Master (superuser) username. NOT the application login roles."
  type        = string
  default     = "contoso_admin"
}

variable "backup_retention_days" {
  description = "Automated backup retention in days (required for read replicas)."
  type        = number
  default     = 14
}

# -----------------------------------------------------------------------------
# Local tags — merged onto EVERY resource. Service is fixed for this workload.
# -----------------------------------------------------------------------------
locals {
  tags = merge(
    {
      Environment        = var.environment
      Service            = "reporting-db"
      Owner              = var.owner
      CostCenter         = var.cost_center
      DataClassification = var.data_classification
    },
    var.extra_tags,
  )
}

# -----------------------------------------------------------------------------
# DB subnet group — PRIVATE subnets only. The DB is never publicly reachable.
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "reporting" {
  name       = "reporting-db-private"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.tags, { Name = "reporting-db-private" })
}

# -----------------------------------------------------------------------------
# Security group — 5432 ingress ONLY from the app-tier SG and the analysts CIDR.
# No 0.0.0.0/0. No hardcoded CIDR literal.
# -----------------------------------------------------------------------------
resource "aws_security_group" "reporting_db" {
  name        = "reporting-db-sg"
  description = "Postgres 5432 ingress restricted to app tier and approved analysts"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "reporting-db-sg" })
}

# Ingress (1): app tier (web-api writes app; batch writes reporting + reads app).
resource "aws_security_group_rule" "ingress_app_tier" {
  type                     = "ingress"
  description              = "Postgres from app tier (web-api + batch)"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.reporting_db.id
  source_security_group_id = var.app_tier_security_group_id
}

# Ingress (2): approved analysts CIDR (the five reporting teams -> read replica).
resource "aws_security_group_rule" "ingress_analysts" {
  type              = "ingress"
  description       = "Postgres from approved analysts CIDR (reporting teams)"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = aws_security_group.reporting_db.id
  cidr_blocks       = [var.analysts_cidr]
}

resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  description       = "Allow all egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.reporting_db.id
  cidr_blocks       = ["0.0.0.0/0"] # egress only; not a DB ingress exposure
}

# -----------------------------------------------------------------------------
# Master credential — NO plaintext password anywhere.
#
# Pattern A (preferred): let RDS manage the master password in Secrets Manager
# via manage_master_user_password = true (set on the primary below). RDS creates
# and rotates the secret; Terraform never sees the literal.
#
# Pattern B (reference only): if an externally-managed secret is required, read
# it from Secrets Manager via a data source and pass .secret_string — still no
# literal in code. Example reference shape (commented; not used by default):
#
#   data "aws_secretsmanager_secret" "db_master" {
#     name = "reporting-db/master" # logical name, not a literal credential
#   }
#   data "aws_secretsmanager_secret_version" "db_master" {
#     secret_id = data.aws_secretsmanager_secret.db_master.id
#   }
#   # ...then on aws_db_instance.primary:
#   #   password = jsondecode(
#   #     data.aws_secretsmanager_secret_version.db_master.secret_string
#   #   )["password"]
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Primary — Multi-AZ, encrypted, private, holds BOTH app and reporting schemas.
# -----------------------------------------------------------------------------
resource "aws_db_instance" "primary" {
  identifier     = "reporting-db-primary"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.master_username

  # No plaintext credential: RDS manages + rotates the master password in
  # AWS Secrets Manager. The literal never appears in Terraform or state.
  manage_master_user_password = true

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2

  # Security posture
  multi_az            = true
  publicly_accessible = false
  storage_encrypted   = true

  db_subnet_group_name   = aws_db_subnet_group.reporting.name
  vpc_security_group_ids = [aws_security_group.reporting_db.id]

  # Required so a read replica can be created from this instance.
  backup_retention_period = var.backup_retention_days

  # Hygiene for a sensitive datastore.
  deletion_protection      = true
  copy_tags_to_snapshot    = true
  auto_minor_version_upgrade = true

  tags = merge(local.tags, { Name = "reporting-db-primary", Role = "primary" })
}

# -----------------------------------------------------------------------------
# Read replica — serves the five reporting teams (report_reader on `reporting`).
# replicate_source_db inherits engine/encryption from the primary.
# -----------------------------------------------------------------------------
resource "aws_db_instance" "reporting_replica" {
  identifier          = "reporting-db-replica"
  replicate_source_db = aws_db_instance.primary.identifier
  instance_class      = var.replica_instance_class

  # Inherit security posture; keep the replica private as well.
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.reporting_db.id]

  # storage_encrypted / kms is inherited from the encrypted source.
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  tags = merge(local.tags, { Name = "reporting-db-replica", Role = "read-replica" })
}

# -----------------------------------------------------------------------------
# Outputs — endpoints for app tier (primary) and reporting teams (replica).
# -----------------------------------------------------------------------------
output "primary_endpoint" {
  description = "Primary endpoint: web-api writes app; batch writes reporting + reads app."
  value       = aws_db_instance.primary.endpoint
}

output "reporting_replica_endpoint" {
  description = "Read replica endpoint for the five reporting teams (report_reader)."
  value       = aws_db_instance.reporting_replica.endpoint
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed master credential secret in Secrets Manager."
  value       = try(aws_db_instance.primary.master_user_secret[0].secret_arn, null)
}
