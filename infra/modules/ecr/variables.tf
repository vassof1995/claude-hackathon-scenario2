variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "contoso/web-api"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
}

variable "project" {
  description = "Project name for tagging"
  type        = string
  default     = "contoso"
}
