terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.78, < 6.0.0"
    }
  }

  # Created by ../../bootstrap-state (applied once, by hand, before this backend works) in
  # the shared-services account. See bootstrap-state/README.md.
  # bucket is omitted - its name has a random suffix, unknown until bootstrap-state is
  # applied. Initialize with:
  #   terraform init -backend-config="bucket=<state_bucket_name output from bootstrap-state>"
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    region       = "ca-central-1"
    profile      = "shared-services-admin" # from landing-zone's sso_config_snippet output
    use_lockfile = true
    encrypt      = true
  }
}
