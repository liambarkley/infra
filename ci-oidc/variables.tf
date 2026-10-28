variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "github_org" {
  description = "GitHub organization or user that owns the repo allowed to assume this role."
  type        = string
  default     = "liambarkley"
}

variable "github_repo" {
  description = "Repo (without the org prefix) allowed to assume this role via OIDC."
  type        = string
  default     = "infra"
}

variable "state_bucket_name" {
  description = "S3 bucket holding Terraform remote state (must match bootstrap-state's output)."
  type        = string
  default     = "build-cache-tfstate"
}

variable "lock_table_name" {
  description = "DynamoDB table used for state locking (must match bootstrap-state's output)."
  type        = string
  default     = "build-cache-tflock"
}
