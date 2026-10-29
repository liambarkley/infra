variable "aws_region" {
  description = "AWS region for the dev environment."
  type        = string
  default     = "ca-central-1"
}

variable "aws_profile" {
  description = <<-EOT
    AWS CLI profile to manage platform-dev resources with. Defaults to the SSO profile from
    landing-zone's sso_config_snippet output, for local runs. CI overrides this (-var) to a
    profile it creates itself via aws-actions/configure-aws-credentials after assuming the
    platform-dev plan or apply role from ../../ci-oidc. Either way, this never resolves to
    management-account credentials - and it's a different profile from the one the backend
    block (versions.tf) uses, since that one needs shared-services credentials instead.
  EOT
  type        = string
  default     = "platform-dev-admin"
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      project     = "build-cache"
      environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
