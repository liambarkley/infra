variable "name" {
  description = "Name prefix applied to the cluster and every resource this module creates."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string
  default     = "1.31"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the cluster's control plane ENIs, the system node group and Karpenter-launched nodes."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs, added to the cluster's VPC config so a future public-facing Service/Ingress can use them. No nodes run here."
  type        = list(string)
}

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the EKS API's public endpoint. Defaults to open, which is the known
    limitation documented in the README (the project has no static egress IP to restrict to) -
    tighten this if that changes.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "system_node_instance_types" {
  description = "Instance types for the small, always-on, on-demand system node group that runs ArgoCD and the Karpenter controller - deliberately not on spot, so controlling capacity can't itself be interrupted."
  type        = list(string)
  default     = ["t3.small"]
}

variable "system_node_desired_size" {
  description = "Desired node count for the system node group."
  type        = number
  default     = 1
}

variable "system_node_min_size" {
  description = "Minimum node count for the system node group."
  type        = number
  default     = 1
}

variable "system_node_max_size" {
  description = "Maximum node count for the system node group."
  type        = number
  default     = 2
}

variable "karpenter_namespace" {
  description = "Namespace the Karpenter controller runs in - must match platform/apps/karpenter's Helm release, since the Pod Identity association below is keyed on namespace + service account name."
  type        = string
  default     = "kube-system"
}

variable "karpenter_service_account" {
  description = "Service account name the Karpenter controller runs as - must match platform/apps/karpenter's Helm release."
  type        = string
  default     = "karpenter"
}

variable "tags" {
  description = "Extra tags merged onto every resource, in addition to project = build-cache."
  type        = map(string)
  default     = {}
}
