#!/usr/bin/env bash
# Tears down infra/envs/dev in the correct order. Three AWS resources here are created by
# cluster-side controllers, not Terraform (the Build Cache Node's ALB, its PVC-backed EBS
# volume, and any EC2 instances Karpenter provisioned) - `terraform destroy` has no idea any
# of them exist, so each gets deleted from Kubernetes and confirmed gone on the AWS side
# first, in order, before Terraform ever runs. Skipping that risks either an orphaned
# still-billing resource, or a destroy that fails outright on a VPC/subnet something is still
# attached to.
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

alb_is_gone() {
  [[ -z "$(aws elbv2 describe-load-balancers --region "$REGION" --profile "$PROFILE" \
    --query 'LoadBalancers[].LoadBalancerName' --output text 2>/dev/null)" ]]
}

pvc_volume_is_gone() {
  [[ -z "$(aws ec2 describe-volumes --region "$REGION" --profile "$PROFILE" \
    --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=data-build-cache-node-0" \
    --query 'Volumes[].VolumeId' --output text 2>/dev/null)" ]]
}

karpenter_nodes_are_gone() {
  [[ "$(kubectl get nodes -l karpenter.sh/nodepool --no-headers 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]]
}

if ! kubectl get nodes >/dev/null 2>&1; then
  log "Cluster unreachable (kubeconfig stale, or the cluster's already gone) - skipping Kubernetes cleanup steps."
  log "If the cluster genuinely still exists, fix kubeconfig first:"
  log "  aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION --profile $PROFILE"
else
  log "Step 1/3: deleting build-cache-node's Ingress (lets the ALB controller deprovision its ALB)..."
  kubectl delete ingress build-cache-node -n build-cache-node --ignore-not-found
  wait_for "ALB" alb_is_gone

  log "Step 2/3: deleting build-cache-node's StatefulSet + PVC (releases its 10Gi EBS volume)..."
  kubectl delete statefulset build-cache-node -n build-cache-node --ignore-not-found
  kubectl delete pvc data-build-cache-node-0 -n build-cache-node --ignore-not-found
  wait_for "PVC-backed EBS volume" pvc_volume_is_gone

  log "Step 3/3: deleting all Karpenter NodeClaims (terminates any EC2 instances it launched)..."
  kubectl delete nodeclaim --all --ignore-not-found
  wait_for "Karpenter-provisioned node(s)" karpenter_nodes_are_gone
fi

log "Kubernetes-side cleanup done. Running terraform destroy in envs/dev - not the foundational"
log "pieces (landing-zone, ci-oidc, log-archive, bootstrap-state), which stay applied."

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../envs/dev" && pwd)"

if [[ "$AUTO_APPROVE" == true ]]; then
  terraform destroy -auto-approve -var="aws_profile=$PROFILE"
else
  terraform destroy -var="aws_profile=$PROFILE"
fi

log "Done."
