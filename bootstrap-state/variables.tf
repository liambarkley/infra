variable "aws_region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "ca-central-1"
}

variable "aws_profile" {
  description = "AWS CLI/SSO profile for the management account. Used only to look up the shared-services account ID via Organizations - the bucket itself is created by assuming a role into shared-services."
  type        = string
  default     = "mgmt-admin"
}

variable "state_bucket_base_name" {
  description = "Base name for the S3 state bucket. The actual bucket is this plus a random suffix - see main.tf for why."
  type        = string
  default     = "build-cache-tfstate"
}
