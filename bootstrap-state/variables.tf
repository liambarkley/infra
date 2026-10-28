variable "aws_region" {
  description = "AWS region for the state bucket and lock table."
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform remote state. Must match the bucket named in envs/*/versions.tf backend blocks."
  type        = string
  default     = "build-cache-tfstate"
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table used for state locking. Must match the table named in envs/*/versions.tf backend blocks."
  type        = string
  default     = "build-cache-tflock"
}
