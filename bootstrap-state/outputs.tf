output "state_bucket_name" {
  description = "S3 bucket holding Terraform remote state, in shared-services. Name includes a random suffix - read this rather than guessing it."
  value       = local.state_bucket_name
}
