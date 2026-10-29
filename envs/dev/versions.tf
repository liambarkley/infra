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
  #
  # bucket and profile are both omitted and supplied via -backend-config, since this backend
  # needs shared-services credentials - a different account from the aws provider above
  # (platform-dev), so one set of ambient credentials can never cover both:
  #   Local:  terraform init -backend-config="bucket=<state_bucket_name output>" \
  #                           -backend-config="profile=shared-services-admin"
  #   CI:     terraform init -backend-config="bucket=<state_bucket_name output>" \
  #                           -backend-config="profile=shared-services-ci"
  #           (shared-services-ci is a named profile CI creates itself via
  #           aws-actions/configure-aws-credentials, assuming shared_services_plan_role_arn or
  #           shared_services_apply_role_arn from ../../ci-oidc - separate from the
  #           platform-dev-ci profile the provider above uses in the same job.)
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    region       = "ca-central-1"
    use_lockfile = true
    encrypt      = true
  }
}
