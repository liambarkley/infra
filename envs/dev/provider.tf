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

# kubernetes/helm live here, not inside modules/bootstrap, specifically so module.bootstrap has
# no local provider configuration of its own - a module with one is flatly incompatible with
# `depends_on` ("Module is incompatible with count, for_each, and depends_on"), which is the
# actual reason bugs #5 and #6 below existed: nothing in the graph tied module.bootstrap's helm
# releases to specific module.eks resources beyond the handful of outputs these provider blocks
# happen to reference (cluster_endpoint/cluster_certificate_authority_data) - module.eks's
# system node group and the cluster-admin access entry were both free to be destroyed in any
# order relative to bootstrap's helm releases, and on a real `terraform destroy` (2026-10-29/
# 2026-11-02), both orders were hit: the access entry went first once (helm uninstall then
# failed outright, "cannot list resource secrets"), and the system node group went first another
# time (every ArgoCD pod went Pending with nowhere to schedule, permanently stranding root-app's
# own finalizer with no controller left to process it - unblocked by hand each time). Moving
# these two provider blocks up here, with no alias, lets module.bootstrap inherit them
# implicitly and removes its own `provider` blocks entirely - which is what makes
# `module "bootstrap" { depends_on = [module.eks] }` in main.tf legal, and that one explicit
# dependency is the actual fix: it forces every resource in module.bootstrap to be destroyed
# before any resource in module.eks, covering the node group and the access entry (and
# anything else added to either module later) with one mechanism instead of a one-off workaround
# per resource.
#
# Same exec-plugin auth modules/bootstrap used to configure directly: a short-lived token from
# `aws eks get-token`, not a data source (which would need the cluster to exist at plan time).
# The exec plugin runs `aws` as a subprocess - it does NOT inherit this file's own `aws`
# provider's profile/static creds above, only whatever's in its own `env` block.
locals {
  exec_env = merge(
    local.using_static_creds ? {
      AWS_ACCESS_KEY_ID     = var.aws_access_key_id
      AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
      AWS_SESSION_TOKEN     = var.aws_session_token
    } : {},
    (!local.using_static_creds && var.aws_profile != "") ? {
      AWS_PROFILE = var.aws_profile
    } : {},
  )

  exec_auth = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", module.eks.cluster_name,
      "--region", var.aws_region,
    ]
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = local.exec_auth.api_version
    command     = local.exec_auth.command
    args        = local.exec_auth.args
    env         = local.exec_env
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = local.exec_auth.api_version
      command     = local.exec_auth.command
      args        = local.exec_auth.args
      env         = local.exec_env
    }
  }
}
