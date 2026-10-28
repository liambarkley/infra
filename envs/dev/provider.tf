variable "aws_region" {
  description = "AWS region for the dev environment."
  type        = string
  default     = "ca-central-1"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project     = "build-cache"
      environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
