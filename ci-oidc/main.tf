# Default provider: mgmt-admin, used only to look up account IDs via Organizations (that API
# only works from the management account, regardless of IAM permissions in the target account).
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_organizations_organization" "current" {}

locals {
  shared_services_account_id = one([
    for a in data.aws_organizations_organization.current.accounts : a.id
    if a.name == "shared-services"
  ])
  platform_dev_account_id = one([
    for a in data.aws_organizations_organization.current.accounts : a.id
    if a.name == "platform-dev"
  ])
}

# Roles are created in each account by assuming the role the management account always has
# access to in a member account it created - same pattern as ../bootstrap-state.
provider "aws" {
  alias  = "shared_services"
  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${local.shared_services_account_id}:role/OrganizationAccountAccessRole"
    session_name = "terraform-ci-oidc"
  }

  default_tags {
    tags = {
      project   = "build-cache"
      ManagedBy = "terraform"
      Component = "ci-oidc"
    }
  }
}

provider "aws" {
  alias  = "platform_dev"
  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${local.platform_dev_account_id}:role/OrganizationAccountAccessRole"
    session_name = "terraform-ci-oidc"
  }

  default_tags {
    tags = {
      project   = "build-cache"
      ManagedBy = "terraform"
      Component = "ci-oidc"
    }
  }
}

# Fetched once here and passed to every account instantiation of the module below, instead
# of each one making its own identical HTTPS call.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

module "shared_services" {
  source = "../modules/github-oidc-roles"
  providers = {
    aws = aws.shared_services
  }

  github_org        = var.github_org
  github_repo       = var.github_repo
  oidc_thumbprint   = data.tls_certificate.github.certificates[0].sha1_fingerprint
  state_bucket_name = var.state_bucket_name
}

# platform-dev: where envs/dev's resources actually live, now that its provider assumes into
# this account instead of the management-account default.
module "platform_dev" {
  source = "../modules/github-oidc-roles"
  providers = {
    aws = aws.platform_dev
  }

  github_org        = var.github_org
  github_repo       = var.github_repo
  oidc_thumbprint   = data.tls_certificate.github.certificates[0].sha1_fingerprint
  state_bucket_name = var.state_bucket_name
}
