output "plan_role_arn" {
  description = "ARN of the read-only, PR-triggered plan role."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "ARN of the write-capable, main-branch-only apply role."
  value       = aws_iam_role.apply.arn
}

output "oidc_provider_arn" {
  description = "ARN of this account's GitHub Actions OIDC provider - an account-wide singleton (creating a second one for the same URL fails), so other roles that need to trust GitHub Actions in this account (e.g. a different repo's own read-only lookup role) should reference this output rather than creating their own provider."
  value       = aws_iam_openid_connect_provider.github.arn
}
