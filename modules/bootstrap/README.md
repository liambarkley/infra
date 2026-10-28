# modules/bootstrap

Installs ArgoCD onto the cluster and the root app-of-apps pointing at the `platform` repo. This
is the one sanctioned exception to "nothing changes on the cluster except through a commit
ArgoCD syncs" (see `CLAUDE.md`), since ArgoCD itself has to get onto the cluster somehow. Built
in phase 2.

Not implemented yet — stub only, so `terraform fmt`/`validate` have something to check.
