terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Remote state — declared, not stood up live (scenario rule; infra/CLAUDE.md).
  # State is NEVER checked in (.gitignore covers *.tfstate). Validate offline with:
  #   terraform init -backend=false && terraform validate
  backend "s3" {
    bucket         = "contoso-tfstate-prod"
    key            = "batch/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "contoso-tfstate-locks"
    encrypt        = true
  }
}
