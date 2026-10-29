# modules/eks

EKS cluster, a small on-demand "system" node group, IRSA, and the IAM plumbing Karpenter
needs - built in phase 2.

## What's here vs. what isn't

This module creates the cluster and everything AWS-side that Karpenter needs to exist before
it can run: the shared node IAM role + instance profile, the controller's IAM role (bound via
EKS **Pod Identity**, not IRSA - see below), and the SQS queue + EventBridge rules for spot
interruption notifications.

**It does not install the Karpenter controller itself**, or any `NodePool`/`EC2NodeClass`.
Those are Kubernetes objects, not AWS resources, and `CLAUDE.md`'s hard rule reserves direct
Terraform-to-cluster changes for `modules/bootstrap` (ArgoCD itself) alone - everything else on
the cluster comes from a commit to `platform/` that ArgoCD syncs. Karpenter is deployed from
`platform/apps/karpenter`.

## Pod Identity, not IRSA, for Karpenter

The Karpenter controller's IAM role is bound to its Kubernetes service account with an
`aws_eks_pod_identity_association` (namespace + service account name), not the classic IRSA
OIDC-annotation pattern. That's deliberate: IRSA would mean putting the role's ARN - which
contains the AWS account ID - into `platform/apps/karpenter`'s Helm values, and `CLAUDE.md`
says account IDs never go into files. Pod Identity keeps that binding entirely on the AWS side;
`platform/` only needs to know the service account name (`karpenter` in `kube-system` by
default - see `var.karpenter_namespace` / `var.karpenter_service_account`), which carries no
account information.

The EBS CSI driver addon, by contrast, is fully Terraform-managed (an `aws_eks_addon`, not a
Helm release from another repo), so there's no cross-repo reason to avoid IRSA for it - it uses
the classic OIDC role pattern.

## Known limitation

`cluster_endpoint_public_access_cidrs` defaults to `0.0.0.0/0` - the project has no static
egress IP to restrict the EKS API's public endpoint to. Documented in the main README's
"Honest limits" section, not an oversight.

## Inputs / outputs

See `variables.tf` and `outputs.tf`. `envs/dev` wires this module's outputs into
`modules/bootstrap` (cluster endpoint/CA, for the kubernetes/helm providers).
