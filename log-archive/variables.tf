variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ca-central-1"
}

variable "aws_profile" {
  description = "AWS CLI/SSO profile for the management account. Used both to look up the log-archive account ID via Organizations, and to create the organization trail itself (is_organization_trail only works from the management account)."
  type        = string
  default     = "mgmt-admin"
}
