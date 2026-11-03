output "shared_services_plan_role_arn" {
  description = "ARN of the read-only, PR-triggered plan role in shared-services."
  value       = module.shared_services.plan_role_arn
}

output "shared_services_apply_role_arn" {
  description = "ARN of the write-capable, main-branch-only apply role in shared-services."
  value       = module.shared_services.apply_role_arn
}

output "platform_dev_plan_role_arn" {
  description = "ARN of the read-only, PR-triggered plan role in platform-dev."
  value       = module.platform_dev.plan_role_arn
}

output "platform_dev_apply_role_arn" {
  description = "ARN of the write-capable, main-branch-only apply role in platform-dev."
  value       = module.platform_dev.apply_role_arn
}

output "demo_app_cache_lookup_role_arn" {
  description = "ARN of demo-spring-app's read-only ALB-lookup role - set this as that repo's own CACHE_LOOKUP_ROLE_ARN variable (gh variable set, not this repo's)."
  value       = aws_iam_role.demo_app_cache_lookup.arn
}
