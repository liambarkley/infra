terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.78, < 6.0.0" # 5.78+ for aws_iam_organizations_features (step 2)
    }
  }

  # Local state for now, per docs/PLAN.md's landing-zone stage. Migrates into the
  # shared-services bucket (../bootstrap-state) once that exists - see that module's
  # README for the exact terraform init -migrate-state steps.
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
