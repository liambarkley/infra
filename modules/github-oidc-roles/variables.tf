variable "github_org" {
  description = "GitHub organization or user that owns the repo allowed to assume these roles."
  type        = string
}

variable "github_repo" {
  description = "Repo (without the org prefix) allowed to assume these roles."
  type        = string
}

variable "oidc_thumbprint" {
  description = "SHA1 thumbprint of GitHub's OIDC TLS certificate (fetched once by the caller, shared across every account this module is instantiated for)."
  type        = string
}

variable "plan_role_name" {
  description = "Name of the read-only, PR-triggered plan role."
  type        = string
  default     = "build-cache-ci-plan"
}

variable "apply_role_name" {
  description = "Name of the write-capable, main-branch-only apply role."
  type        = string
  default     = "build-cache-ci-apply"
}

variable "apply_trusted_subs" {
  description = "GitHub OIDC 'sub' claim patterns (StringLike) allowed to assume the apply role. Default: only the main branch. Switch an entry to \"repo:<org>/<repo>:environment:<name>\" to gate on a protected GitHub Environment instead."
  type        = list(string)
  default     = null
}

variable "state_bucket_name" {
  description = "S3 bucket holding Terraform remote state, for scoping the plan/apply roles' state and lock-file access."
  type        = string
}
