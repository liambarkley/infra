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

root_app_automated_sync_is_off() {
  [[ "$(kubectl get application root-app -n argocd -o jsonpath='{.spec.syncPolicy.automated}' 2>/dev/null)" == "" ]]
}

if ! kubectl get nodes >/dev/null 2>&1; then
  log "Cluster unreachable (kubeconfig stale, or the cluster's already gone) - skipping Kubernetes cleanup steps."
  log "If the cluster genuinely still exists, fix kubeconfig first:"
  log "  aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION --profile $PROFILE"
else
  log "Step 1/6: pausing root-app's automated sync, so deleting its children below doesn't"
  log "just get self-healed back a level up..."
  kubectl patch application root-app -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
  wait_for "root-app automated sync" root_app_automated_sync_is_off

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

  log "Step 6/6: Kubernetes-side cleanup confirmed done."
fi

log "Running terraform destroy in envs/dev - not the foundational pieces (landing-zone,"
log "ci-oidc, log-archive, bootstrap-state), which stay applied."
log ""
log "Expect a warning here about ArgoCD's own CRDs being kept (Helm's resource-policy: keep,"
log "a deliberate safety default that stops a chart uninstall from cascading into deleting"
log "every custom resource of that type cluster-wide) - harmless on a full teardown like this"
log "one, since the whole cluster (and therefore those CRDs) is destroyed moments later anyway."

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../envs/dev" && pwd)"

if [[ "$AUTO_APPROVE" == true ]]; then
  terraform destroy -auto-approve -var="aws_profile=$PROFILE"
else
  terraform destroy -var="aws_profile=$PROFILE"
fi

log "Done."
