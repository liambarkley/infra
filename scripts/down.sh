#!/usr/bin/env bash
# Tears down infra/envs/dev in the correct order. Several AWS resources here are created by
# cluster-side controllers, not Terraform (the Build Cache Node's ALB, its PVC-backed EBS
# volume, Prometheus's own PVC-backed EBS volume added in phase 4, and any EC2 instances
# Karpenter provisioned) - `terraform destroy` has no idea any of them exist, so each gets
# deleted from Kubernetes and confirmed gone on the AWS side first, in order, before Terraform
# ever runs. Skipping that risks either an orphaned still-billing resource, or a destroy that
# fails outright on a VPC/subnet something is still attached to.
#
# Deletes the ArgoCD Applications themselves (build-cache-node, demo-spring-app), not their
# individual resources - found the hard way on the first real run: deleting the Ingress/
# StatefulSet/PVC directly just fights ArgoCD's own selfHeal, which recreates them within
# seconds, since their manifests are still committed to platform/. Each Application carries
# the resources-finalizer.argocd.argoproj.io finalizer (confirmed before relying on this), so
# deleting the Application cascades through every resource it owns - and each of those
# (Ingress, PVC) has its own finalizer blocking its own removal until the ALB/EBS volume are
# actually gone on AWS's side - before the Application object itself disappears.
#
# That fixed the first failure, but not the second: root-app (the app-of-apps root) also has
# selfHeal on, and it tracks every apps/<name>/application.yaml as one of ITS OWN managed
# resources - so deleting build-cache-node's Application just got fought one level up instead,
# with root-app recreating it within seconds of the first fix "working." Pausing root-app's
# own automated sync first (removing spec.syncPolicy.automated via a merge patch) stops that.
# Nothing needs to restore it afterward - the whole cluster, including this live patch, is
# destroyed by the end of this script anyway, and the next `terraform apply` creates a brand
# new root-app from the unmodified, git-committed chart regardless.
#
# Run by hand - never run by Claude Code (CLAUDE.md's hard rule: no `terraform destroy`, no
# `kubectl delete`). This is the "down" half of docs/PLAN.md's "make up / make down" guardrail
# (phase 6 checklist) - a plain `terraform apply` in envs/dev is already one command for "up",
# so there's no equivalent script for that side yet.
#
# Usage: ./scripts/down.sh [--profile <aws-profile>] [--yes]
#   --profile   AWS SSO profile (default: platform-dev-admin)
#   --yes       Skip terraform destroy's interactive confirmation prompt too. Default: no -
#               the Kubernetes-side cleanup is fully automated, but the actual
#               `terraform destroy` still stops and asks, on purpose.

set -euo pipefail

CLUSTER_NAME="build-cache-dev"
REGION="ca-central-1"
PROFILE="platform-dev-admin"
MAX_WAIT_SECONDS=300
POLL_INTERVAL=10
AUTO_APPROVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --yes)
      AUTO_APPROVE=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

log() {
  echo "[$(date +%H:%M:%S)] $*"
}

# wait_for <description> <check-command...> - polls until the check command exits 0, or gives
# up after MAX_WAIT_SECONDS and returns failure (the caller decides whether that's fatal).
wait_for() {
  local description="$1"
  shift
  local waited=0
  while true; do
    if "$@"; then
      log "$description: confirmed gone."
      return 0
    fi
    if [[ "$waited" -ge "$MAX_WAIT_SECONDS" ]]; then
      log "$description: still not confirmed after ${MAX_WAIT_SECONDS}s - giving up. Check manually before re-running this script or proceeding to terraform destroy."
      return 1
    fi
    sleep "$POLL_INTERVAL"
    waited=$((waited + POLL_INTERVAL))
  done
}

application_is_gone() {
  local app="$1"
  ! kubectl get application "$app" -n argocd >/dev/null 2>&1
}

alb_is_gone() {
  [[ -z "$(aws elbv2 describe-load-balancers --region "$REGION" --profile "$PROFILE" \
    --query 'LoadBalancers[].LoadBalancerName' --output text 2>/dev/null)" ]]
}

pvc_volume_is_gone() {
  local pvc_name="$1"
  [[ -z "$(aws ec2 describe-volumes --region "$REGION" --profile "$PROFILE" \
    --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=$pvc_name" \
    --query 'Volumes[].VolumeId' --output text 2>/dev/null)" ]]
}

karpenter_nodes_are_gone() {
  [[ "$(kubectl get nodes -l karpenter.sh/nodepool --no-headers 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]]
}

automated_sync_is_off() {
  local app="$1"
  [[ "$(kubectl get application "$app" -n argocd -o jsonpath='{.spec.syncPolicy.automated}' 2>/dev/null)" == "" ]]
}

if ! kubectl get nodes >/dev/null 2>&1; then
  log "Cluster unreachable (kubeconfig stale, or the cluster's already gone) - skipping Kubernetes cleanup steps."
  log "If the cluster genuinely still exists, fix kubeconfig first:"
  log "  aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION --profile $PROFILE"
else
  log "Step 1/6: pausing root-app's automated sync, so deleting its children below doesn't"
  log "just get self-healed back a level up..."
  kubectl patch application root-app -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
  wait_for "root-app automated sync" automated_sync_is_off root-app

  log "Step 2/6: deleting the build-cache-node Application (cascades through its Ingress, so"
  log "the ALB controller deprovisions the ALB - each resource's own finalizer blocks the"
  log "cascade until that's actually confirmed)..."
  kubectl delete application build-cache-node -n argocd --ignore-not-found
  wait_for "build-cache-node Application" application_is_gone build-cache-node
  wait_for "ALB" alb_is_gone

  # The StatefulSet's PVC does NOT go with it: found the hard way - Kubernetes deliberately
  # retains StatefulSet-generated PVCs on deletion by default (data safety), and since this
  # PVC is auto-generated from volumeClaimTemplates rather than a manifest ArgoCD applied
  # directly, the Application's own cascade doesn't touch it either. Explicit delete, which
  # does trigger the gp3 StorageClass's reclaimPolicy: Delete properly.
  kubectl delete pvc data-build-cache-node-0 -n build-cache-node --ignore-not-found
  wait_for "build-cache-node PVC-backed EBS volume" pvc_volume_is_gone data-build-cache-node-0

  log "Step 3/6: deleting the demo-spring-app Application (frees the Karpenter-provisioned"
  log "node(s) it was running on, so they're not needed by the time the next step runs)..."
  kubectl delete application demo-spring-app -n argocd --ignore-not-found
  wait_for "demo-spring-app Application" application_is_gone demo-spring-app

  # Added phase 4, same PVC-retention gotcha as build-cache-node's - Prometheus's StatefulSet
  # (platform/apps/monitoring) has its own 8Gi gp3 volumeClaimTemplate that doesn't go with
  # the Application's cascade delete either. Alertmanager has no storageSpec configured, so
  # no PVC of its own to worry about. The PVC name is chart-generated and long
  # (prometheus-<release>-<chart-fullname>-prometheus-db-prometheus-<release>-<chart-fullname>-
  # prometheus-0) - confirmed live rather than guessed, since getting this wrong silently
  # leaves the real EBS volume running.
  log "Step 4/6: deleting the monitoring Application (kube-prometheus-stack, YACE, the SLO"
  log "burn-rate rules, the alert bridge's webhook target)..."
  kubectl delete application monitoring -n argocd --ignore-not-found
  wait_for "monitoring Application" application_is_gone monitoring
  kubectl delete pvc -n monitoring \
    prometheus-monitoring-kube-prometheus-prometheus-db-prometheus-monitoring-kube-prometheus-prometheus-0 \
    --ignore-not-found
  wait_for "Prometheus PVC-backed EBS volume" pvc_volume_is_gone \
    prometheus-monitoring-kube-prometheus-prometheus-db-prometheus-monitoring-kube-prometheus-prometheus-0

  log "Step 5/6: deleting any remaining Karpenter NodeClaims (terminates any EC2 instances it"
  log "launched - Karpenter's own consolidation would eventually do this on its own now that"
  log "demo-spring-app and monitoring are gone, but not waiting on that)..."
  kubectl delete nodeclaim --all --ignore-not-found
  wait_for "Karpenter-provisioned node(s)" karpenter_nodes_are_gone

  # Confirmed live: leaving the karpenter Application for root-app's own finalizer cascade
  # (during terraform destroy's helm uninstall) is a real deadlock risk - that cascade deletes
  # the EC2NodeClass/NodePool (which carry a karpenter.k8s.aws/termination finalizer only the
  # Karpenter *controller* can process) alongside the controller Deployment itself, with no
  # ordering guarantee between the two. If the controller pod terminates first, that finalizer
  # can never clear again - stranding the object (and root-app's own cascade behind it)
  # permanently. Deleting the CRs explicitly here, while the controller is still running,
  # avoids the race entirely; only then is the now-empty Application deleted.
  #
  # Confirmed live the hard way, one level deeper: pausing root-app's automated sync above
  # does NOT pause karpenter's *own* syncPolicy.automated - a plain `kubectl delete ec2nodeclass`
  # got recreated by karpenter's own selfHeal within the same second (confirmed: the
  # "new" object's creationTimestamp landed exactly when the delete completed), stranding
  # that second copy's finalizer the instant the karpenter Application's own cascade raced
  # the controller shutdown again - the identical deadlock, one layer in. Same fix as
  # root-app, applied to karpenter's own Application first.
  log "Step 6/6: pausing karpenter's own automated sync, then deleting its EC2NodeClass/"
  log "NodePool while its controller can still process their finalizers, then the karpenter"
  log "Application itself..."
  # Confirmed live: on a re-run after the karpenter Application was already fully deleted
  # (e.g. a prior run got unstuck by hand and finished this step), a plain `kubectl patch`
  # has no --ignore-not-found equivalent and errors outright - fatal under `set -e`, unlike
  # every delete call in this script, which already tolerates "already gone". Guard on
  # existence first so re-running this script is always safe, not just the first time.
  if kubectl get application karpenter -n argocd >/dev/null 2>&1; then
    kubectl patch application karpenter -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
    wait_for "karpenter automated sync" automated_sync_is_off karpenter
  fi
  kubectl delete ec2nodeclass --all --ignore-not-found
  kubectl delete nodepool --all --ignore-not-found
  kubectl delete application karpenter -n argocd --ignore-not-found
  wait_for "karpenter Application" application_is_gone karpenter

  log "Kubernetes-side cleanup confirmed done."
fi

log "Running terraform destroy in envs/dev - not the foundational pieces (landing-zone,"
log "ci-oidc, log-archive, bootstrap-state), which stay applied."
log ""
log "Expect a warning here about ArgoCD's own CRDs being kept (Helm's resource-policy: keep,"
log "a deliberate safety default that stops a chart uninstall from cascading into deleting"
log "every custom resource of that type cluster-wide) - harmless on a full teardown like this"
log "one, since the whole cluster (and therefore those CRDs) is destroyed moments later anyway."

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../envs/dev" && pwd)"

# Captured now, before anything below destroys module.network itself - this is the only
# point in the script where `terraform output` can still resolve it. Used after Step 1 to
# sweep for orphaned ENIs/security groups (see that comment) by VPC ID rather than by tag,
# since the vpc_id output is exact and doesn't depend on the ALB controller or anything else
# having tagged the VPC itself with project=build-cache (nothing does).
VPC_ID="$(terraform output -raw vpc_id 2>/dev/null || true)"

# Confirmed live: module.network's NAT gateway/route tables/IGW/EIP have no Terraform-graph
# reason to wait for module.eks - nothing outside module.network references them directly
# (module.eks only takes the *subnet* IDs as input, which is a real dependency edge; the
# routing/NAT resources sitting alongside those subnets aren't), so an untargeted destroy is
# free to tear them down in parallel with (or before) the EKS cluster and its still-running
# node group - breaking live pod networking (DNS/internet egress for anything in a private
# subnet, including Karpenter's own ability to call the EC2 API) on a cluster that isn't gone
# yet. Can't fix this with a plain depends_on on module.network itself - module.eks needs
# module.network's subnet outputs to apply at all, so that would be a cycle. Staging the
# destroy here instead, the same way up.sh stages the apply for its own unrelated Terraform
# limitation: force module.eks (and everything that depends_on it - module.bootstrap) plus
# module.rds and module.alerting to go first, then a final untargeted destroy for whatever's
# left (module.network, mainly).
log "Step 1/2: destroying module.eks (and module.bootstrap, which depends_on it), module.rds"
log "and module.alerting first - leaves module.network's NAT/routing resources alone until"
log "the cluster that actually needs them is confirmed gone..."
if [[ "$AUTO_APPROVE" == true ]]; then
  terraform destroy -auto-approve -var="aws_profile=$PROFILE" \
    -target=module.eks -target=module.rds -target=module.alerting
else
  terraform destroy -var="aws_profile=$PROFILE" \
    -target=module.eks -target=module.rds -target=module.alerting
fi

# Confirmed live, twice, on the same day: the VPC CNI leaves a secondary ENI behind
# ("aws-K8S-i-...", status "available", unattached) and EKS leaves its own auto-created
# cluster security group (eks-cluster-sg-<cluster>-<suffix>) behind, in both cases well after
# module.eks reports fully destroyed - neither is tracked in Terraform state (EKS/the VPC CNI
# create them outside any Terraform resource), so `terraform destroy` has no idea they exist
# either. Left alone, each one blocks Step 2's subnet/VPC deletion for 10+ minutes while AWS's
# own async cleanup eventually catches up on its own - confirmed by direct `aws ec2
# delete-network-interface`/`delete-security-group` succeeding immediately by hand, well
# before AWS's own lag would have cleared them. Sweeping both explicitly here, right after
# module.eks is confirmed gone and right before module.network needs the VPC empty, so a
# future teardown doesn't need this same live firefighting again.
if [[ -n "$VPC_ID" ]]; then
  log "Checking for orphaned ENIs left behind by the VPC CNI in $VPC_ID..."
  ORPHAN_ENIS="$(aws ec2 describe-network-interfaces --region "$REGION" --profile "$PROFILE" \
    --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[].NetworkInterfaceId' \
    --output text 2>/dev/null || true)"
  for eni in $ORPHAN_ENIS; do
    log "  deleting orphaned ENI $eni..."
    aws ec2 delete-network-interface --region "$REGION" --profile "$PROFILE" \
      --network-interface-id "$eni" || log "  could not delete $eni - check manually before Step 2."
  done

  log "Checking for orphaned (non-default) security groups left behind in $VPC_ID..."
  ORPHAN_SGS="$(aws ec2 describe-security-groups --region "$REGION" --profile "$PROFILE" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || true)"
  for sg in $ORPHAN_SGS; do
    log "  deleting orphaned security group $sg..."
    aws ec2 delete-security-group --region "$REGION" --profile "$PROFILE" \
      --group-id "$sg" || log "  could not delete $sg - check manually before Step 2."
  done
else
  log "Could not resolve vpc_id from terraform output - skipping the orphaned ENI/security"
  log "group sweep. If Step 2 below stalls for 10+ minutes on subnet/VPC deletion, check for"
  log "these by hand (aws ec2 describe-network-interfaces/describe-security-groups --filters"
  log "Name=vpc-id,Values=<vpc-id>)."
fi

# Confirmed live: a plain, untargeted `terraform destroy` here fails outright -
# ("Invalid for_each argument", module.rds.aws_vpc_security_group_ingress_rule.postgres) -
# even though that resource is already fully destroyed and gone from state (step 1 handled
# it fine). An untargeted destroy still evaluates every resource *block in the configuration*
# while building its plan, not just what remains in state, and that resource's for_each
# still references module.eks.cluster_security_group_id - permanently unresolvable now that
# module.eks itself has no instances left at all. module.network is the only thing actually
# left to destroy at this point, so target it explicitly instead of the whole config.
log "Step 2/2: destroying module.network specifically - not an untargeted destroy, which"
log "re-evaluates every resource block in the full configuration (not just what's left in"
log "state) while planning, and fails on module.rds's for_each referencing module.eks's"
log "now-gone cluster_security_group_id output, even though that resource is already gone..."
if [[ "$AUTO_APPROVE" == true ]]; then
  terraform destroy -auto-approve -var="aws_profile=$PROFILE" -target=module.network
else
  terraform destroy -var="aws_profile=$PROFILE" -target=module.network
fi

log "Done."
