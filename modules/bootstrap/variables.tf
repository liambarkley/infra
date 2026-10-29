variable "cluster_name" {
  description = "EKS cluster name, used to fetch an auth token for the kubernetes/helm providers via `aws eks get-token`."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API server endpoint (modules/eks's cluster_endpoint output)."
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate (modules/eks's cluster_certificate_authority_data output)."
  type        = string
}

variable "aws_region" {
  description = "Region to pass to `aws eks get-token` - must match where the cluster actually is."
  type        = string
}

variable "argocd_chart_version" {
  description = "Pinned version of the argo-cd Helm chart (from https://argoproj.github.io/argo-helm)."
  type        = string
  default     = "7.7.11"
}

variable "argocd_namespace" {
  description = "Namespace ArgoCD and the root Application run in."
  type        = string
  default     = "argocd"
}

variable "apps_repo_url" {
  description = "Git URL of the platform repo ArgoCD watches."
  type        = string
}

variable "apps_repo_revision" {
  description = "Branch/tag of the platform repo the root Application tracks."
  type        = string
  default     = "main"
}

variable "apps_path" {
  description = "Path within the platform repo the root Application scans (app-of-apps)."
  type        = string
  default     = "apps"
}
