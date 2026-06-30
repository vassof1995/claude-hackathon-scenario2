variable "frontend_bucket_name" {
  description = "Name of the S3 bucket for the Vue SPA frontend assets"
  type        = string
  default     = "contoso-web-frontend-s3"
}

variable "assets_bucket_name" {
  description = "Name of the S3 bucket provisioned empty for future asset use"
  type        = string
  default     = "contoso-web-assets-s3"
}

variable "alb_dns_name" {
  description = "DNS name of the Application Load Balancer that fronts the ECS web-api service"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
}

variable "project" {
  description = "Project name used in resource tags"
  type        = string
  default     = "contoso"
}
