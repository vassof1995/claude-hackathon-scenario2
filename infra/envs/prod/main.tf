# prod environment — batch workload slice (ADR-0006).
# Wires the reusable batch module to the shared infra (passed via variables). Other workloads
# (web-api, frontend, reporting-db) get their own slices; this one is the batch migration.

provider "aws" {
  region = var.region

  # Tag everything, everywhere (infra/CLAUDE.md). Missing tags is a known-bad Scorecard pattern.
  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    owner       = "team-4am-club"
    workload    = "batch"
    env         = "prod"
    cost-center = var.cost_center
    managed-by  = "terraform"
  }
}

module "batch" {
  source = "../../modules/batch"

  name_prefix = var.name_prefix
  region      = var.region
  tags        = local.common_tags

  ecs_cluster_arn             = var.ecs_cluster_arn
  vpc_id                      = var.vpc_id
  private_app_subnet_ids      = var.private_app_subnet_ids
  data_tier_security_group_id = var.data_tier_security_group_id

  image               = var.batch_image
  datasource_url      = "jdbc:postgresql://${var.rds_endpoint}:5432/contoso"
  datasource_username = "batch_user"

  batch_db_password_secret_arn = var.batch_db_password_secret_arn

  # Same 02:00 schedule the legacy @Scheduled fired; timezone pinned (discovery #6).
  schedule_expression = "cron(0 2 * * ? *)"
  schedule_timezone   = "Europe/Berlin"
}
