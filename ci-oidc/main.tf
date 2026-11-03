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

  oidc_sub_claim_prefix = var.oidc_sub_claim_prefix
  oidc_thumbprint       = data.tls_certificate.github.certificates[0].sha1_fingerprint
  state_bucket_name     = var.state_bucket_name
}

# platform-dev: where envs/dev's resources actually live, now that its provider assumes into
# this account instead of the management-account default.
module "platform_dev" {
  source = "../modules/github-oidc-roles"
  providers = {
    aws = aws.platform_dev
  }

  oidc_sub_claim_prefix = var.oidc_sub_claim_prefix
  oidc_thumbprint       = data.tls_certificate.github.certificates[0].sha1_fingerprint
  state_bucket_name     = var.state_bucket_name
}

# demo-spring-app's CI: a narrowly-scoped, read-only role so its workflow can resolve the
# Build Cache Node's current ALB hostname at build time instead of reading a manually-updated
# BUILD_CACHE_URL repo variable - that ALB gets a brand-new DNS name every time envs/dev is
# destroyed and recreated (see docs/PLAN.md), and this was the one step `scripts/up.sh` could
# never automate itself (modifying a different repo's CI config is a human decision, not
# something either teardown/bring-up script does). Lives here, not in modules/github-oidc-roles,
# since that module is specifically about this *infra* repo's own plan/apply roles, trusts a
# different repo's OIDC subject entirely, and reuses platform-dev's existing OIDC provider
# (an account-wide singleton - a second module instantiation would try to create another one
# for the same URL and fail).
data "aws_iam_policy_document" "demo_app_cache_lookup_assume_role" {
  provider = aws.platform_dev

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.platform_dev.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Trusted for every event (not just main/PR, unlike infra's own plan/apply roles) - this
    # role can only ever read the ALB's hostname, nothing destructive or state-changing, so
    # there's no meaningful blast radius to restrict by trigger type the way infra's apply
    # role restricts to main-only.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${var.demo_app_oidc_sub_claim_prefix}:*"]
    }
  }
}

resource "aws_iam_role" "demo_app_cache_lookup" {
  provider           = aws.platform_dev
  name               = "build-cache-demo-app-cache-lookup"
  assume_role_policy = data.aws_iam_policy_document.demo_app_cache_lookup_assume_role.json
}

data "aws_iam_policy_document" "demo_app_cache_lookup" {
  statement {
    sid    = "FindTheAlbByItsProjectTag"
    effect = "Allow"
    # tag:GetResources has no resource-level ARN to scope to (it's a cross-service lookup
    # API) - the real scoping is the tag filter the workflow itself passes at call time
    # (project=build-cache, resource type elasticloadbalancing:loadbalancer), same reasoning
    # as cloudwatch_exporter's identical action in modules/eks.
    actions   = ["tag:GetResources", "elasticloadbalancing:DescribeLoadBalancers"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "demo_app_cache_lookup" {
  provider = aws.platform_dev
  name     = "find-build-cache-alb"
  role     = aws_iam_role.demo_app_cache_lookup.id
  policy   = data.aws_iam_policy_document.demo_app_cache_lookup.json
}
