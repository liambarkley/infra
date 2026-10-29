terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.78, < 6.0.0" # 5.78+ for aws_iam_organizations_features (step 2)
    }
  }

  # Migrated from local state once ../bootstrap-state existed - see that module's README for
  # the terraform init -migrate-state steps this came from.
  backend "s3" {
    key          = "landing-zone/terraform.tfstate"
    region       = "ca-central-1"
    profile      = "shared-services-admin"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      project   = "build-cache"
      ManagedBy = "terraform"
      Component = "landing-zone"
    }
  }
}
