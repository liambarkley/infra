#!/usr/bin/env bash
# Brings infra/envs/dev up, pairing with down.sh. Three things this handles that a plain
# `terraform apply` doesn't:
#
# 1. A from-scratch apply hits a real Terraform limitation: modules/rds's
#    aws_vpc_security_group_ingress_rule.postgres for_each is over
#    var.allowed_security_group_ids, which comes from module.eks.cluster_security_group_id -
#    unknown until the cluster exists, so Terraform refuses to plan it ("Invalid for_each
#    argument... cannot be determined until apply"). Confirmed live, 2026-11-02, straight off a
#    fully-destroyed state. Fixed here by always applying module.network + module.eks first,
#    which resolves that value, before the full apply - safe to run even when those modules are
#    already applied (a no-op converge), so this isn't conditional on state actually being
#    empty.
# 2. kubeconfig needs refreshing against whatever's now running - a brand-new cluster from a
#    from-scratch apply has a different endpoint/CA than any kubeconfig entry left over from
#    before.
# 3. ArgoCD's own sync is asynchronous: `terraform apply` completing just means helm_release.
#    argocd/root_app succeeded, not that any of the four child apps (karpenter,
#    aws-load-balancer-controller, build-cache-node, demo-spring-app) have actually synced and
#    gone Healthy yet.
#
# What this does NOT do, on purpose: update demo-spring-app's BUILD_CACHE_URL repo variable.
# The Build Cache Node's ALB gets a brand-new DNS name every time it's recreated from scratch -
# this script prints it at the end, but changing a different repo's CI configuration is a
# deliberate step for Liam to take, not something to automate here.
#
# Run by hand - never run by Claude Code (CLAUDE.md's hard rule: no `terraform apply`). This is
# the "up" half of docs/PLAN.md's "make up / make down" guardrail (phase 6 checklist).
#
# Usage: ./scripts/up.sh [--profile <aws-profile>] [--yes]
#   --profile   AWS SSO profile (default: platform-dev-admin)
#   --yes       Skip both terraform apply's interactive confirmations. Default: no.

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
      log "$description: ready."
      return 0
    fi
    if [[ "$waited" -ge "$MAX_WAIT_SECONDS" ]]; then
      log "$description: still not ready after ${MAX_WAIT_SECONDS}s - giving up. Check manually."
      return 1
    fi
    sleep "$POLL_INTERVAL"
    waited=$((waited + POLL_INTERVAL))
  done
}

application_is_healthy() {
  local app="$1"
  local health
  health="$(kubectl get application "$app" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  local sync
  sync="$(kubectl get application "$app" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  [[ "$health" == "Healthy" && "$sync" == "Synced" ]]
}

alb_hostname_ready() {
  [[ -n "$(kubectl get ingress build-cache-node -n build-cache-node \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)" ]]
}

log "Checking platform-dev's EC2 vCPU quotas (Karpenter needs headroom in both - a brand-new"
log "account's default of 5 vCPUs each blocks it outright before you'd notice why)..."
for quota in "L-1216C47A:On-Demand Standard vCPUs" "L-34B43A08:Spot Standard vCPUs"; do
  code="${quota%%:*}"
  label="${quota##*:}"
  value="$(aws service-quotas get-service-quota --profile "$PROFILE" --region "$REGION" \
    --service-code ec2 --quota-code "$code" \
    --query 'Quota.Value' --output text 2>/dev/null || echo "unknown")"
  log "  $label: $value"
  if [[ "$value" != "unknown" ]] && awk "BEGIN{exit !($value < 8)}"; then
    log "  WARNING: $label looks low for a system node group plus Karpenter headroom - request an increase if this apply fails to schedule."
  fi
done

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../envs/dev" && pwd)"

log "Step 1/4: applying module.network + module.eks first - resolves"
log "module.eks.cluster_security_group_id before module.rds's for_each needs it (a known"
log "Terraform limitation on a from-scratch apply, not an error in this config). A no-op if"
log "these are already applied."
if [[ "$AUTO_APPROVE" == true ]]; then
  terraform apply -auto-approve -var="aws_profile=$PROFILE" -target=module.network -target=module.eks
else
  terraform apply -var="aws_profile=$PROFILE" -target=module.network -target=module.eks
fi

log "Step 2/4: applying everything else (module.rds, module.bootstrap - ArgoCD, root-app)..."
if [[ "$AUTO_APPROVE" == true ]]; then
  terraform apply -auto-approve -var="aws_profile=$PROFILE"
else
  terraform apply -var="aws_profile=$PROFILE"
fi

log "Step 3/4: refreshing kubeconfig against the (possibly brand-new) cluster..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" --profile "$PROFILE"
wait_for "cluster reachable" bash -c "kubectl get nodes >/dev/null 2>&1"

log "Step 4/4: waiting for ArgoCD to sync root-app and its five child apps to Healthy..."
wait_for "root-app" application_is_healthy root-app
for app in aws-load-balancer-controller karpenter build-cache-node demo-spring-app monitoring; do
  wait_for "$app" application_is_healthy "$app"
done

log "Waiting for the Build Cache Node's ALB to get a hostname..."
if wait_for "ALB hostname" alb_hostname_ready; then
  hostname="$(kubectl get ingress build-cache-node -n build-cache-node \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
  log ""
  log "ALB hostname: http://$hostname"
  log "This is almost certainly NEW (ALBs don't keep their DNS name across a destroy/recreate) -"
  log "update demo-spring-app's BUILD_CACHE_URL repo variable by hand before re-running its CI"
  log "to re-confirm cache hits against this address."
fi

log ""
log "Alertmanager webhook URL: $(terraform output -raw alert_webhook_url 2>/dev/null)"
log "Also almost certainly NEW, same reason as the ALB hostname above - copy it into"
log "platform/apps/monitoring/application.yaml's webhook_configs url (REPLACE-ME placeholder)"
log "before trusting any SLO alert to actually reach an inbox."

log "Done. Everything in docs/PLAN.md's phases 2-4 should now be live."
