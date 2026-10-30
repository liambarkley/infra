output "endpoint" {
  description = "Connection endpoint (host:port)."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname only, no port."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port Postgres listens on."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Default database name."
  value       = aws_db_instance.this.db_name
}

output "master_username" {
  description = "Master username - not a secret by itself, but see master_user_secret_arn for the password."
  value       = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret holding the auto-generated master password - the demo app reads this at runtime via Pod Identity, never a value written anywhere in this repo."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "ID of the security group attached to this instance."
  value       = aws_security_group.this.id
}

output "address_parameter_name" {
  description = "SSM Parameter Store name holding the instance's address - the demo app reads this at runtime so no environment-specific hostname has to live in platform/apps/demo-spring-app."
  value       = aws_ssm_parameter.address.name
}

output "address_parameter_arn" {
  description = "ARN of the same parameter, for scoping the demo app's IAM role to read exactly this one."
  value       = aws_ssm_parameter.address.arn
}
