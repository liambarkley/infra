locals {
  tags = merge(
    {
      project   = "build-cache"
      ManagedBy = "terraform"
      Module    = "eks"
    },
    var.tags,
  )
}

# --- cluster ---

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Envelope-encrypts Kubernetes Secrets at rest with a customer-managed key, on top of EKS's own
# default encryption - cheap enough (~$1/month for the key, same trade-off the project already
# accepts for the tfstate bucket and CloudTrail) that there's no reason to skip it the way the
# CI workflow skips the pricier KMS CMK cases.
resource "aws_kms_key" "eks_secrets" {
  description         = "Envelope encryption for ${var.name} EKS Secrets."
  enable_key_rotation = true
  tags                = local.tags
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    # checkov:skip=CKV_AWS_39: no VPN/bastion in this project - CI and Liam's laptop both need
    # the public endpoint. See modules/eks/README.md's "Known limitation".
    # checkov:skip=CKV_AWS_38: same reason - no static egress IP to scope
    # public_access_cidrs to; documented limitation, not an oversight.
    endpoint_public_access = true
    public_access_cidrs    = var.cluster_endpoint_public_access_cidrs
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
  }

  # checkov:skip=CKV_AWS_37: control plane -> CloudWatch Logs audit logging is a real gap, same
  # as the CloudTrail -> CloudWatch Logs and VPC flow logs gaps already deferred in
  # .github/workflows/ci.yml - ongoing ingestion/storage cost, picked up in phase 4
  # (observability), not skipped forever.

  # API only, no aws-auth ConfigMap: cluster-admin access is granted via the explicit access
  # entries below, not the implicit "cluster creator gets admin" mechanism
  # (bootstrap_cluster_creator_admin_permissions, which AWS's own docs say defaults true) - the
  # first real apply showed that mechanism doesn't actually produce an access entry in
  # practice (confirmed via `aws eks list-access-entries` right after a successful apply: only
  # the EKS service-linked role and the Karpenter node role were present). Explicit entries are
  # also just better practice regardless - reviewable in a diff, not dependent on who happened
  # to run `apply`.
  access_config {
    authentication_mode = "API"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]

  tags = merge(local.tags, { Name = var.name })
}

# Cluster-admin access for whoever holds the AdministratorAccess Identity Center permission set
# in this account (platform-admins, per landing-zone) - looked up by name pattern rather than
# hardcoded, so the account ID embedded in the role's ARN never has to be written here.
data "aws_iam_roles" "cluster_admin" {
  name_regex  = var.cluster_admin_role_name_regex
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

resource "aws_eks_access_entry" "cluster_admin" {
  for_each      = data.aws_iam_roles.cluster_admin.arns
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "cluster_admin" {
  for_each      = data.aws_iam_roles.cluster_admin.arns
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_admin]
}

# --- IRSA (OIDC provider) - used by the EBS CSI driver's addon role below ---

data "tls_certificate" "cluster_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster_oidc.certificates[0].sha1_fingerprint]

  tags = local.tags
}

# --- node IAM role, shared by the system managed node group and Karpenter-launched nodes ---

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_read" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# SSM instead of SSH for node debugging - no bastion, no open port 22 to manage.
resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Karpenter's EC2NodeClass references this by name, not the implicit instance profile that
# aws_eks_node_group below manages for itself.
resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-eks-node"
  role = aws_iam_role.node.name
  tags = local.tags
}

# Lets nodes that join via Karpenter (not through a managed node group, which EKS wires up
# automatically) actually authenticate against the API-only access config above.
resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"
}

# --- system node group: small, on-demand, always on. Runs ArgoCD and the Karpenter
# controller - deliberately not spot, so the thing that manages spot capacity can't itself be
# interrupted by it. Everything else runs on nodes Karpenter provisions. ---

# EKS's own default launch template caps IMDS at one network hop
# (HttpPutResponseHopLimit = 1) - fine for the host itself, but a pod is one hop further out,
# so any pod that needs instance metadata (the AWS Load Balancer Controller auto-detecting
# its VPC ID, for one - confirmed on the live node via `aws ec2 describe-instances` before
# writing this fix) times out reaching it. Raising it to 2 is AWS's own documented fix for
# exactly this.
resource "aws_launch_template" "system_node" {
  name_prefix = "${var.name}-system-"

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.name}-system" })
  }

  tags = local.tags
}

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  capacity_type  = "ON_DEMAND"
  instance_types = var.system_node_instance_types

  launch_template {
    id      = aws_launch_template.system_node.id
    version = aws_launch_template.system_node.latest_version
  }

  scaling_config {
    desired_size = var.system_node_desired_size
    min_size     = var.system_node_min_size
    max_size     = var.system_node_max_size
  }

  labels = {
    "node-pool" = "system"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr_read,
  ]

  tags = local.tags
}

# --- core addons ---

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = local.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = local.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # CoreDNS pods need somewhere to schedule; the system node group exists by the time this
  # addon's pods actually get placed, but there's no hard ordering guarantee without this.
  depends_on = [aws_eks_node_group.system]

  tags = local.tags
}

# Pod Identity, not just IRSA: lets platform/apps/karpenter bind its service account to an IAM
# role by namespace + name alone, with no OIDC annotation (and no account ID) in that repo.
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.system]
  tags                        = local.tags
}

# --- EBS CSI driver: IRSA, since this addon (unlike Karpenter) is entirely Terraform-managed,
# so there's no cross-repo reason to prefer Pod Identity here. ---

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.system]
  tags                        = local.tags
}

# --- Karpenter: IAM plumbing only. The controller itself, and its NodePool/EC2NodeClass, are
# deployed via platform/apps/karpenter (ArgoCD) - CLAUDE.md's hard rule reserves direct
# Terraform-to-cluster changes for the bootstrap module (ArgoCD itself) alone. ---

# RunInstances/CreateFleet/CreateLaunchTemplate and the Describe* calls below don't support
# resource-level scoping for the cases Karpenter actually needs (launching nodes of types/AZs
# it chooses dynamically) - this matches Karpenter's own documented minimal controller policy
# at https://karpenter.sh, not a shortcut taken here. checkov's CKV_AWS_111/CKV_AWS_356 flag
# this policy regardless (inline checkov:skip doesn't resolve against a data source in the
# installed checkov version); skipped at the CI workflow level instead - see ci.yml.
data "aws_iam_policy_document" "karpenter_controller" {
  statement {
    sid    = "AllowScopedEC2InstanceAccess"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateTags",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:DeleteLaunchTemplate",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowScopedEC2InstanceTermination"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowEC2Read"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSpotPriceHistory",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowPricingRead"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  # No account ID in the resource ARN - deliberate, not a typo. AWS's own EKS-optimized-AMI SSM
  # parameters (what AMI alias resolution, e.g. "al2023@latest", actually reads) live under an
  # account-less ARN namespace. Scoping this to our own account ID (the obvious-looking choice)
  # silently matches nothing, since the real parameter ARN's account segment is empty - found
  # the hard way: AMIsReady stuck Unknown ("failed to discover any AMIs for alias") with no
  # explicit AccessDenied in the logs to point at it, confirmed by comparing against the
  # EC2NodeClass's actual AMI parameter path.
  statement {
    sid       = "AllowSSMRead"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:*::parameter/aws/service/*"]
  }

  # The instance-profile garbage-collection controller runs unconditionally, regardless of
  # whether any EC2NodeClass here uses Karpenter-managed instance profiles (ours doesn't - see
  # modules/eks/README.md) - it still needs to list/read them to confirm there's nothing of
  # its own to clean up. list/Get/Tag only, deliberately: Karpenter never gets
  # Create/Delete/AddRoleToInstanceProfile here, since the one instance profile that actually
  # exists (aws_iam_instance_profile.node, below) is Terraform's to manage, not Karpenter's.
  statement {
    sid    = "AllowInstanceProfileReadOnly"
    effect = "Allow"
    actions = [
      "iam:ListInstanceProfiles",
      "iam:GetInstanceProfile",
      "iam:TagInstanceProfile",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowPassingNodeRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node.arn]
  }

  statement {
    sid       = "AllowEKSDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.this.arn]
  }

  statement {
    sid    = "AllowInterruptionQueueAccess"
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name = "${var.name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name   = "karpenter-controller"
  role   = aws_iam_role.karpenter_controller.id
  policy = data.aws_iam_policy_document.karpenter_controller.json
}

resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = var.karpenter_namespace
  service_account = var.karpenter_service_account
  role_arn        = aws_iam_role.karpenter_controller.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

# Spot interruption / rebalance / state-change notifications, so Karpenter can drain a node
# before it's actually reclaimed instead of only finding out after the fact.
resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.name}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = local.tags
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeAndASG"
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption.arn
    }]
  })
}

locals {
  karpenter_interruption_events = {
    spot_interruption = "EC2 Spot Instance Interruption Warning"
    rebalance         = "EC2 Instance Rebalance Recommendation"
    state_change      = "EC2 Instance State-change Notification"
    scheduled_change  = "AWS Health Event"
  }
}

resource "aws_cloudwatch_event_rule" "karpenter_interruption" {
  for_each    = local.karpenter_interruption_events
  name        = "${var.name}-karpenter-${each.key}"
  description = "Forwards ${each.value} to Karpenter's interruption queue."

  event_pattern = jsonencode({
    source      = each.key == "scheduled_change" ? ["aws.health"] : ["aws.ec2"]
    detail-type = [each.value]
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "karpenter_interruption" {
  for_each = local.karpenter_interruption_events
  rule     = aws_cloudwatch_event_rule.karpenter_interruption[each.key].name
  arn      = aws_sqs_queue.karpenter_interruption.arn
}

# --- AWS Load Balancer Controller: IAM plumbing only, same split as Karpenter. The Helm
# release itself is platform/apps/aws-load-balancer-controller (ArgoCD) - CLAUDE.md's hard
# rule again. Pod Identity, not IRSA, for the same reason as Karpenter: no account ID in
# platform/'s Helm values. ---

resource "aws_iam_role" "lb_controller" {
  name = "${var.name}-lb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })

  tags = local.tags
}

# The exact, unmodified policy AWS publishes for this controller
# (kubernetes-sigs/aws-load-balancer-controller docs/install/iam_policy.json) - kept as a
# static file rather than rewritten in HCL, so it's trivially diffable against upstream
# instead of silently drifting from whatever AWS actually documents.
resource "aws_iam_role_policy" "lb_controller" {
  name   = "aws-load-balancer-controller"
  role   = aws_iam_role.lb_controller.id
  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = var.lb_controller_namespace
  service_account = var.lb_controller_service_account
  role_arn        = aws_iam_role.lb_controller.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}
