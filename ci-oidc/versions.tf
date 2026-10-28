terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.78, < 6.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # bucket is omitted - see envs/dev/versions.tf for why and how to supply it at init time.
  backend "s3" {
    key          = "ci-oidc/terraform.tfstate"
    region       = "ca-central-1"
    profile      = "shared-services-admin" # from landing-zone's sso_config_snippet output
    use_lockfile = true
    encrypt      = true
  }
}
