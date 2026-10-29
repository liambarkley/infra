variable "oidc_sub_claim_prefix" {
  description = <<-EOT
    The "repo:..." prefix GitHub actually puts in its OIDC token's sub claim for this repo,
    before the per-event suffix (":pull_request", ":ref:refs/heads/main", etc.). NOT simply
    "repo:<org>/<repo>" - GitHub's "immutable subject claims" setting (on by default for this
    account) replaces the human-readable org/repo names with immutable numeric IDs instead, to
    stop a renamed or recreated repo from inheriting another repo's trust. Get the real value
    with:
      gh api repos/<org>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
    If that setting is ever turned off for this repo, the value reverts to plain
    "repo:<org>/<repo>" instead - this is a fact to re-check if these roles stop authorizing
    for no apparent code reason, not something to assume stays constant forever.
  EOT
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
  description = "GitHub OIDC 'sub' claim patterns (StringLike) allowed to assume the apply role. Default: only the main branch, built from oidc_sub_claim_prefix. Switch an entry to \"<oidc_sub_claim_prefix>:environment:<name>\" to gate on a protected GitHub Environment instead."
  type        = list(string)
  default     = null
}

variable "state_bucket_name" {
  description = "S3 bucket holding Terraform remote state, for scoping the plan/apply roles' state and lock-file access."
  type        = string
}
