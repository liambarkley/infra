# Both providers authenticate with a short-lived token from `aws eks get-token`, via the exec
# plugin, rather than a data source - a data source would need the cluster to already exist at
# plan time in a way that breaks the very first `terraform plan` against a brand-new cluster in
# the same apply. The `aws` CLI binary itself must be on PATH wherever this runs (it already is,
# on GitHub's ubuntu-latest runners and on a Homebrew-provisioned Mac - see CLAUDE.md).
#
# The exec plugin runs `aws` as a plain subprocess - it does NOT inherit the `profile`/static
# credentials given to this module's own `aws` provider calls elsewhere in this config, only
# whatever's in its own `env` block below plus the ambient shell environment. Omitting `env`
# here was the actual cause of the first real apply's "Kubernetes cluster unreachable: the
# server has asked for the client to provide credentials" failure (2026-10-29): the subprocess
# had no AWS credentials of its own, so `aws eks get-token` either failed or (depending on what
# else happened to be in the shell) authenticated as the wrong principal - cluster, node group
# and every addon had already applied fine by that point, since none of those depend on this.
locals {
  using_static_creds = var.aws_access_key_id != ""

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
      "--cluster-name", var.cluster_name,
      "--region", var.aws_region,
    ]
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
  exec {
    api_version = local.exec_auth.api_version
    command     = local.exec_auth.command
    args        = local.exec_auth.args
    env         = local.exec_env
  }
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
    exec {
      api_version = local.exec_auth.api_version
      command     = local.exec_auth.command
      args        = local.exec_auth.args
      env         = local.exec_env
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = true
  wait             = true
}

# The one Kubernetes object this module manages directly beyond ArgoCD itself: the app-of-apps
# root Application, pointed at platform/apps. Everything under that path from here on is
# ArgoCD's job, not Terraform's - see CLAUDE.md's hard rule.
resource "helm_release" "root_app" {
  name      = "root-app"
  chart     = "${path.module}/charts/root-app"
  namespace = var.argocd_namespace

  values = [yamlencode({
    namespace      = var.argocd_namespace
    repoURL        = var.apps_repo_url
    targetRevision = var.apps_repo_revision
    path           = var.apps_path
  })]

  depends_on = [helm_release.argocd]
}
