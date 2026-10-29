variable "aws_region" {
  description = "AWS region for the dev environment."
  type        = string
  default     = "ca-central-1"
}

variable "aws_profile" {
  description = <<-EOT
    AWS CLI/SSO profile to manage platform-dev resources with, for local runs - the SSO
    profile from landing-zone's sso_config_snippet output. Ignored whenever
    aws_access_key_id is set (CI's case - see that variable).
  EOT
  type        = string
  default     = "platform-dev-admin"
}

variable "aws_access_key_id" {
  description = <<-EOT
    Static credentials for CI: the platform-dev plan or apply role's temporary session
    credentials, from a configure-aws-credentials step with output-credentials: true (that
    action has no option to write a named profile - aws_profile above only ever applies
    locally). Leave empty for local runs, which use aws_profile instead. All three of
    aws_access_key_id/aws_secret_access_key/aws_session_token must be set together or not
    at all.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "Paired with aws_access_key_id - see its description."
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_session_token" {
  description = "Paired with aws_access_key_id - see its description."
  type        = string
  default     = ""
  sensitive   = true
}

locals {
  using_static_creds = var.aws_access_key_id != ""
}

provider "aws" {
  region = var.aws_region

  profile    = local.using_static_creds ? null : var.aws_profile
  access_key = local.using_static_creds ? var.aws_access_key_id : null
  secret_key = local.using_static_creds ? var.aws_secret_access_key : null
  token      = local.using_static_creds ? var.aws_session_token : null

  default_tags {
    tags = {
      project     = "build-cache"
      environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
