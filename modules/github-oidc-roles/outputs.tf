output "plan_role_arn" {
  description = "ARN of the read-only, PR-triggered plan role."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "ARN of the write-capable, main-branch-only apply role."
  value       = aws_iam_role.apply.arn
}
