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
  # bucket and credentials are both omitted and supplied via -backend-config, since this
  # backend needs shared-services credentials - a different account from the aws provider
  # above (platform-dev), so one set of ambient credentials can never cover both:
  #   Local:  terraform init -backend-config="bucket=<state_bucket_name output>" \
  #                           -backend-config="profile=shared-services-admin"
  #   CI:     terraform init -backend-config="bucket=<state_bucket_name output>" \
  #                           -backend-config="access_key=<from a configure-aws-credentials
  #                             step with output-credentials: true, assuming
  #                             shared_services_plan_role_arn or _apply_role_arn>" \
  #                           -backend-config="secret_key=<same step's output>" \
  #                           -backend-config="token=<same step's output>"
  #           (aws-actions/configure-aws-credentials has no option to write a named profile -
  #           that's not a real input on this action, despite how it might look at a glance.)
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    region       = "ca-central-1"
    use_lockfile = true
    encrypt      = true
  }
}
