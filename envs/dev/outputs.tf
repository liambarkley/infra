output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs in the dev VPC."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs in the dev VPC."
  value       = module.network.private_subnet_ids
}

output "cluster_name" {
  description = "Name of the dev EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint for the dev cluster."
  value       = module.eks.cluster_endpoint
}

output "node_instance_profile_name" {
  description = "Instance profile name for platform/apps/karpenter's EC2NodeClass to reference."
  value       = module.eks.node_instance_profile_name
}

output "karpenter_interruption_queue_name" {
  description = "SQS queue name for platform/apps/karpenter's EC2NodeClass to reference."
  value       = module.eks.karpenter_interruption_queue_name
}
