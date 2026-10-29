variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ca-central-1"
}

variable "aws_profile" {
  description = "AWS CLI/SSO profile for the management account. Used only to look up the shared-services account ID via Organizations - the roles themselves are created by assuming a role into shared-services."
  type        = string
  default     = "mgmt-admin"
}

variable "oidc_sub_claim_prefix" {
  description = <<-EOT
    The "repo:..." prefix GitHub actually puts in its OIDC token's sub claim for this repo.
    NOT "repo:liambarkley/infra" - this account has GitHub's "immutable subject claims"
    setting on by default, which uses numeric org/repo IDs instead. Get the real value with:
      gh api repos/liambarkley/infra/actions/oidc/customization/sub --jq .sub_claim_prefix
    Re-check this if these roles ever stop authorizing for no apparent code reason - it
    changes if the repo is ever recreated or transferred. It just did: this changed from
    .../infra@1437625509 on 2026-10-29, when making the repo public meant rewriting history
    (git-filter-repo, to scrub two account IDs out of old commits) via a brand-new repo of the
    same name rather than an in-place rewrite + force-push, which GitHub can't fully scrub from
    old PR pages either way. A new repo means a new immutable numeric ID, even with the old
    name - this value had to be re-pulled and this module re-applied for CI to authenticate
    again.
  EOT
  type        = string
  default     = "repo:liambarkley@8986270/infra@1438777351"
}

variable "state_bucket_name" {
  description = "S3 bucket holding Terraform remote state, in shared-services. Output of ../bootstrap-state (terraform output -raw state_bucket_name) - supply it with -var or a tfvars file, since it's in a separate Terraform state this config doesn't read."
  type        = string
}
