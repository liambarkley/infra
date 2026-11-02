# The kubernetes/helm provider configurations this module's resources use live in the calling
# root module (envs/dev/provider.tf), not here - see that file's comment for why. This module
# declares no `provider` block of its own, so it inherits the root's default (unaliased)
# kubernetes/helm providers implicitly, and the module call in envs/dev/main.tf can carry a
# real `depends_on = [module.eks]`.

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
