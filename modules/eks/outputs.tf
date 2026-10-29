output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate, for configuring the kubernetes/helm providers in modules/bootstrap."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider, for any future IRSA role outside this module."
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "node_role_arn" {
  description = "ARN of the shared node IAM role (system node group and Karpenter-launched nodes)."
  value       = aws_iam_role.node.arn
}

output "node_instance_profile_name" {
  description = "Instance profile name for Karpenter's EC2NodeClass (platform/apps/karpenter) to reference."
  value       = aws_iam_instance_profile.node.name
}

output "karpenter_interruption_queue_name" {
  description = "SQS queue name carrying spot interruption/rebalance notifications, for Karpenter's EC2NodeClass to reference."
  value       = aws_sqs_queue.karpenter_interruption.name
}

output "cluster_security_group_id" {
  description = <<-EOT
    ID of the security group EKS creates and attaches to every node automatically (system
    node group and Karpenter-launched nodes alike - Karpenter's own EC2NodeClass selects it by
    tag, see platform/apps/karpenter). Other modules (e.g. RDS) use this to allow ingress from
    "every pod in the cluster" without needing to enumerate node groups individually.
  EOT
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
