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

variable "github_org" {
  description = "GitHub organization or user that owns the repo allowed to assume these roles."
  type        = string
  default     = "liambarkley"
}

variable "github_repo" {
  description = "Repo (without the org prefix) allowed to assume these roles."
  type        = string
  default     = "infra"
}

variable "state_bucket_name" {
  description = "S3 bucket holding Terraform remote state, in shared-services. Output of ../bootstrap-state (terraform output -raw state_bucket_name) - supply it with -var or a tfvars file, since it's in a separate Terraform state this config doesn't read."
  type        = string
}
