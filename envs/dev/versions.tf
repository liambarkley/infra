terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Created by ../../bootstrap-state (applied once, by hand, before this backend works).
  # See bootstrap-state/README.md.
  backend "s3" {
    bucket         = "build-cache-tfstate"
    key            = "envs/dev/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "build-cache-tflock"
    encrypt        = true
  }
}
