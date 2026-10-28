output "ci_role_arn" {
  description = "ARN of the role GitHub Actions assumes via OIDC to run terraform plan."
  value       = aws_iam_role.ci.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider."
  value       = aws_iam_openid_connect_provider.github.arn
}
