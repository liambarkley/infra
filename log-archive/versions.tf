terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.78, < 6.0.0"
    }
  }

  # Local state for now, same reasoning as ../landing-zone. Can migrate into the
  # shared-services bucket later, same way - see ../bootstrap-state/README.md.
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
