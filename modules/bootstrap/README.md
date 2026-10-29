# modules/bootstrap

Installs ArgoCD onto the cluster and the root app-of-apps Application pointing at the
`platform` repo's `apps/` directory. This is the one sanctioned exception to "nothing changes
on the cluster except through a commit to `platform/` that ArgoCD syncs" (see `CLAUDE.md`),
since ArgoCD itself has to get onto the cluster somehow - built in phase 2.

## Why two `helm_release`s and a local chart, not `kubernetes_manifest`

The root Application is an instance of a CRD (`argoproj.io/v1alpha1.Application`) that the
`argo-cd` chart itself installs. Terraform's own `kubernetes_manifest` resource validates a
manifest's schema against the live cluster **at plan time** - on a brand-new cluster, in the
same `terraform apply` that's also installing the CRD, that plan fails because the CRD doesn't
exist yet (a well-known chicken-and-egg problem with that resource). A tiny local Helm chart
(`charts/root-app/`) that just templates the `Application` object sidesteps it: Helm applies
server-side without needing to know the CRD's schema in advance, and `depends_on =
[helm_release.argocd]` keeps the ordering explicit.

## Auth: `aws eks get-token` via each provider's `exec` block

Both the `kubernetes` and `helm` providers authenticate with a short-lived token from `aws eks
get-token`, called through each provider's `exec` plugin at apply time - not a data source.
A data source would need to actually call AWS during `plan`, which is fine once the cluster
exists, but breaks the very first `plan` in the same run that creates it. The `exec` block only
runs when a resource in this module is actually evaluated, after `modules/eks` has already
applied. The `aws` CLI must be on `PATH` wherever this runs (already true in CI and on a
Homebrew-provisioned Mac).

## Inputs / outputs

See `variables.tf` and `outputs.tf`. `envs/dev` passes `modules/eks`'s cluster outputs in
directly, plus the `platform` repo's URL.
