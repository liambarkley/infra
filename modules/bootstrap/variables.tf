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

variable "aws_profile" {
  description = <<-EOT
    AWS CLI/SSO profile for local runs, passed into the kubernetes/helm providers' `exec`
    plugin via its own `env` block - NOT inherited from the ambient shell (the exec plugin
    runs `aws` as a plain subprocess, which only sees what's explicitly set here; a `-var` on
    the root `aws` provider's own `profile` argument has no effect on it). Ignored whenever
    aws_access_key_id is set (CI's case - see that variable), same pattern as envs/dev's own
    provider.tf.
  EOT
  type        = string
  default     = ""
}

variable "aws_access_key_id" {
  description = "Static credentials for CI, passed into the exec plugin's env the same way as aws_profile - see that variable's description. Leave empty for local runs."
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

variable "cluster_admin_access_ready" {
  description = <<-EOT
    modules/eks's cluster_admin_access_ready output - not used for any actual value here,
    only referenced (in the exec plugin's env, see main.tf) so Terraform's dependency graph
    sees that this module's helm releases depend on the cluster-admin access entry. A
    module-level `depends_on` can't express this directly: this module has its own local
    provider configurations, which Terraform refuses to let `depends_on` touch. See
    modules/eks/outputs.tf's description on cluster_admin_access_ready for why this matters -
    found live, on a real `terraform destroy`, not hypothetically.
  EOT
  type        = list(string)
  default     = []
}
