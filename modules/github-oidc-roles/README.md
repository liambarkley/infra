# modules/github-oidc-roles

GitHub Actions OIDC trust for one AWS account: an identity provider, a read-only plan role
trusted for pull-request-triggered runs, and a write-capable apply role trusted only for the
main branch (or a protected GitHub Environment).

One account per instantiation - the caller passes a provider alias assuming into whichever
account this should exist in. See `ci-oidc/main.tf` for the current instantiation
(shared-services only, for now).
