output "shared_services_plan_role_arn" {
  description = "ARN of the read-only, PR-triggered plan role in shared-services."
  value       = module.shared_services.plan_role_arn
}

output "shared_services_apply_role_arn" {
  description = "ARN of the write-capable, main-branch-only apply role in shared-services."
  value       = module.shared_services.apply_role_arn
}
