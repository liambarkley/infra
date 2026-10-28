terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "build-cache-tfstate"
    key            = "ci-oidc/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "build-cache-tflock"
    encrypt        = true
  }
}
