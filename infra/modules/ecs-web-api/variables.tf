variable "vpc_id" {
  description = "ID of the VPC where resources will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "private_app_subnet_ids" {
  description = "List of private application subnet IDs for ECS tasks"
  type        = list(string)
}

variable "private_data_cidr_blocks" {
  description = "CIDR blocks of the private data subnets (for ECS SG egress to RDS)"
  type        = list(string)
}

variable "image_url" {
  description = "ECR image URL with tag for the web-api container"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository (used to scope IAM pull permissions)"
  type        = string
}

variable "db_secret_arns" {
  description = "Map of environment variable names to Secrets Manager ARNs. Expected keys: SPRING_DATASOURCE_URL, SPRING_DATASOURCE_USERNAME, SPRING_DATASOURCE_PASSWORD"
  type        = map(string)
}

variable "aws_region" {
  description = "AWS region where resources are deployed"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging)"
  type        = string
}

variable "project" {
  description = "Project name used in tagging"
  type        = string
  default     = "contoso"
}
