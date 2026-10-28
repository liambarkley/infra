variable "aws_region" {
  description = "AWS region for the management account and all member accounts."
  type        = string
  default     = "ca-central-1"
}

variable "aws_profile" {
  description = "AWS CLI/SSO profile for the management account. All landing-zone API calls use this - never static keys."
  type        = string
  default     = "mgmt-admin"
}

variable "log_archive_account_email" {
  description = "Root email for the log-archive member account (Security OU). AWS requires a unique, real email per account."
  type        = string
  sensitive   = true
}

variable "shared_services_account_email" {
  description = "Root email for the shared-services member account (Workloads OU)."
  type        = string
  sensitive   = true
}

variable "platform_dev_account_email" {
  description = "Root email for the platform-dev member account (Workloads OU)."
  type        = string
  sensitive   = true
}

variable "budget_alert_email" {
  description = "Email address AWS Budgets notifications at $25 and $50/month go to."
  type        = string
  sensitive   = true
}

variable "platform_admins_group_name" {
  description = "Display name of the existing Identity Center group that gets AdministratorAccess on every new account."
  type        = string
  default     = "platform-admins"
}

variable "admin_permission_set_name" {
  description = "Name of the existing AdministratorAccess permission set created when Identity Center was enabled. Looked up, not managed - Terraform doesn't own it."
  type        = string
  default     = "AdministratorAccess"
}

variable "attach_workload_scps" {
  description = <<-EOT
    Attach the Workloads-OU SCPs (scps.tf). Leave false for the first apply: these SCPs deny
    IAM user/access-key creation and restrict regions, and a mistake in them is easiest to
    recover from before you've confirmed SSO access into shared-services and platform-dev
    actually works. Flip to true in terraform.tfvars once that's confirmed, then apply again.
  EOT
  type        = bool
  default     = false
}
