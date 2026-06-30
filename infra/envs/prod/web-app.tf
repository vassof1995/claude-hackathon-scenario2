# ---------------------------------------------------------------------------
# Network — shared VPC with three tiers (public, private-app, private-data)
# ---------------------------------------------------------------------------
module "network" {
  source = "../../modules/network"

  environment = var.environment
  project     = "contoso"
}

# ---------------------------------------------------------------------------
# ECR — container registry for the Spring Boot API image
# ---------------------------------------------------------------------------
module "ecr_web_api" {
  source = "../../modules/ecr"

  repository_name = "contoso/web-api"
  environment     = var.environment
  project         = "contoso"
}

# ---------------------------------------------------------------------------
# Secrets Manager — API database credentials
# Values MUST be set out-of-band via the AWS CLI (or console).
# NEVER store actual credentials here — this file is committed to git.
# ---------------------------------------------------------------------------

# Value set via: aws secretsmanager put-secret-value --secret-id contoso/web-api/db-url --secret-string VALUE
# NEVER store actual credentials here — this file is committed to git
resource "aws_secretsmanager_secret" "db_url" {
  name        = "contoso/web-api/db-url"
  description = "JDBC URL for the Contoso web-api RDS instance (prod)"

  tags = {
    Workload    = "web-app"
    Owner       = "contoso-team"
    CostCenter  = "infra"
    Environment = var.environment
  }
}

# Value set via: aws secretsmanager put-secret-value --secret-id contoso/web-api/db-username --secret-string VALUE
# NEVER store actual credentials here — this file is committed to git
resource "aws_secretsmanager_secret" "db_username" {
  name        = "contoso/web-api/db-username"
  description = "Database username for the Contoso web-api RDS instance (prod)"

  tags = {
    Workload    = "web-app"
    Owner       = "contoso-team"
    CostCenter  = "infra"
    Environment = var.environment
  }
}

# Value set via: aws secretsmanager put-secret-value --secret-id contoso/web-api/db-password --secret-string VALUE
# NEVER store actual credentials here — this file is committed to git
resource "aws_secretsmanager_secret" "db_password" {
  name        = "contoso/web-api/db-password"
  description = "Database password for the Contoso web-api RDS instance (prod)"

  tags = {
    Workload    = "web-app"
    Owner       = "contoso-team"
    CostCenter  = "infra"
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# ECS — Fargate service for the Spring Boot API behind an ALB
# ---------------------------------------------------------------------------
module "ecs_web_api" {
  source = "../../modules/ecs-web-api"

  vpc_id                   = module.network.vpc_id
  public_subnet_ids        = module.network.public_subnet_ids
  private_app_subnet_ids   = module.network.private_app_subnet_ids
  private_data_cidr_blocks = module.network.private_data_cidr_blocks

  image_url           = "${module.ecr_web_api.repository_url}:latest"
  ecr_repository_arn  = module.ecr_web_api.repository_arn

  db_secret_arns = {
    SPRING_DATASOURCE_URL      = aws_secretsmanager_secret.db_url.arn
    SPRING_DATASOURCE_USERNAME = aws_secretsmanager_secret.db_username.arn
    SPRING_DATASOURCE_PASSWORD = aws_secretsmanager_secret.db_password.arn
  }

  aws_region  = var.aws_region
  environment = var.environment
}

# ---------------------------------------------------------------------------
# S3 + CloudFront — Vue SPA hosting with ALB /api/* proxy behaviour
# Resolves coupling C1: SPA served from S3 cannot resolve Docker service names;
# CloudFront /api/* ordered behaviour forwards requests to the ALB so the
# same-origin contract is preserved with no CORS and no frontend code change.
# ---------------------------------------------------------------------------
module "s3_cloudfront" {
  source = "../../modules/s3-cloudfront"

  alb_dns_name         = module.ecs_web_api.alb_dns_name
  frontend_bucket_name = "contoso-web-frontend-s3"
  assets_bucket_name   = "contoso-web-assets-s3"
  environment          = var.environment
  project              = "contoso"
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "cloudfront_url" {
  description = "Public HTTPS URL of the CloudFront distribution (SPA entry point)"
  value       = "https://${module.s3_cloudfront.cloudfront_domain_name}"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer fronting the ECS web-api service"
  value       = module.ecs_web_api.alb_dns_name
}

output "ecr_repo_url" {
  description = "ECR repository URL — use this as the image registry for CI/CD pushes"
  value       = module.ecr_web_api.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster running the web-api Fargate service"
  value       = module.ecs_web_api.ecs_cluster_name
}
