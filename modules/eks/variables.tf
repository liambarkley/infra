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

variable "cluster_admin_role_name_regex" {
  description = <<-EOT
    Regex matching IAM role names (under /aws-reserved/sso.amazonaws.com/) that should get
    cluster-admin access via an EKS access entry - looked up dynamically with
    data.aws_iam_roles so the account ID embedded in the matched role's ARN never has to be
    written into this repo. Default matches this project's AdministratorAccess Identity Center
    permission set role (landing-zone's platform-admins group).
  EOT
  type        = string
  default     = "^AWSReservedSSO_AdministratorAccess_.*$"
}

variable "system_node_instance_types" {
  description = <<-EOT
    Instance types for the small, always-on, on-demand system node group that runs ArgoCD and
    the Karpenter controller - deliberately not on spot, so controlling capacity can't itself
    be interrupted. t3.medium, not t3.small: phase 4 hit the same EKS max-pods ceiling
    system_node_desired_size documents again, this time for real, live - two of three
    node-exporter DaemonSet pods stuck permanently Pending ("Too many pods") once
    kube-prometheus-stack's handful of pods pushed the two t3.small system nodes to 11/11 and
    10/11. t3.medium's max-pods is 17 (3 ENIs x 5 usable IPs + 2, EKS's standard formula) -
    comfortably more headroom than t3.small's 11, at roughly double the hourly cost (~US$0.0416
    -> ~US$0.0832/hr combined for both nodes) - still destroyed between sessions
    (docs/PLAN.md's cost section), so a few extra cents per session in practice.
  EOT
  type        = list(string)
  default     = ["t3.medium"]
}

variable "system_node_desired_size" {
  description = <<-EOT
    Desired node count for the system node group. 2, not 1: at the original t3.small size, EKS
    max-pods was 11 - the EKS system daemonsets (vpc-cni, kube-proxy, coredns x2,
    ebs-csi-controller x2, ebs-csi-node, pod-identity-agent) already use 8 of those on a single
    node, leaving only 3 free - not enough for the argo-cd chart's 7 pods. Confirmed the hard
    way on the first real apply: argocd-server/repo-server/notifications-controller stuck
    Pending ("FailedScheduling... 1 Too many pods"), and dex-server crash-looping on a missing
    secret that argocd-server generates on its own first boot and therefore never created.
    min/max match desired - this group exists specifically to run ArgoCD plus Karpenter's
    controller, not to autoscale. (See system_node_instance_types for the same ceiling being
    hit again in phase 4, this time fixed by sizing up rather than needing a second node.)
  EOT
  type        = number
  default     = 2
}

variable "system_node_min_size" {
  description = "Minimum node count for the system node group - see system_node_desired_size."
  type        = number
  default     = 2
}

variable "system_node_max_size" {
  description = "Maximum node count for the system node group - see system_node_desired_size."
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

variable "lb_controller_namespace" {
  description = "Namespace the AWS Load Balancer Controller runs in - must match platform/apps/aws-load-balancer-controller's Helm release."
  type        = string
  default     = "kube-system"
}

variable "lb_controller_service_account" {
  description = "Service account name the AWS Load Balancer Controller runs as - must match platform/apps/aws-load-balancer-controller's Helm release."
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "demo_app_namespace" {
  description = "Namespace the demo Spring app runs in - must match platform/apps/demo-spring-app's manifests."
  type        = string
  default     = "demo-spring-app"
}

variable "demo_app_service_account" {
  description = "Service account name the demo Spring app runs as - must match platform/apps/demo-spring-app's manifests."
  type        = string
  default     = "demo-spring-app"
}

variable "demo_app_secretsmanager_arns" {
  description = "Secrets Manager secret ARNs the demo app's Pod Identity role may call secretsmanager:GetSecretValue on - typically modules/rds's master_user_secret_arn output."
  type        = list(string)
  default     = []
}

variable "demo_app_ssm_parameter_arns" {
  description = "SSM Parameter Store ARNs the demo app's Pod Identity role may call ssm:GetParameter on - typically modules/rds's address_parameter_arn output."
  type        = list(string)
  default     = []
}

variable "cloudwatch_exporter_namespace" {
  description = "Namespace the CloudWatch exporter (YACE) runs in - must match platform/apps/monitoring's manifest. Phase 4: the Build Cache Node has no native Prometheus endpoint (confirmed against the official BCN manual - centralized monitoring is a Develocity-registration-only feature this project deliberately doesn't use), so cache hit rate and latency come from the ALB's own free CloudWatch metrics instead."
  type        = string
  default     = "monitoring"
}

variable "cloudwatch_exporter_service_account" {
  description = "Service account name the CloudWatch exporter (YACE) runs as - must match platform/apps/monitoring's manifest."
  type        = string
  default     = "cloudwatch-exporter"
}

variable "alertmanager_namespace" {
  description = "Namespace Alertmanager runs in - must match platform/apps/monitoring's kube-prometheus-stack release."
  type        = string
  default     = "monitoring"
}

variable "alertmanager_service_account" {
  description = "Service account name Alertmanager's pod runs as - must match platform/apps/monitoring's kube-prometheus-stack values (alertmanager.serviceAccount.name)."
  type        = string
  default     = "alertmanager"
}

variable "alertmanager_smtp_key_secret_arns" {
  description = "Secrets Manager secret ARN (modules/alerting's smtp_key_secret_arn output), as a single-element list - a list, not a bare string, so its length is known at plan time even on a from-scratch apply where that secret doesn't exist yet either (see main.tf's comment on the alertmanager resources). Lets Alertmanager's initContainer call secretsmanager:GetSecretValue to derive its SES SMTP password at pod startup. Empty skips creating the role/association entirely."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags merged onto every resource, in addition to project = build-cache."
  type        = map(string)
  default     = {}
}
