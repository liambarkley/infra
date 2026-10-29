# modules/github-oidc-roles

GitHub Actions OIDC trust for one AWS account: an identity provider, a read-only plan role
trusted for pull-request-triggered runs, and a write-capable apply role trusted only for the
main branch (or a protected GitHub Environment).

One account per instantiation - the caller passes a provider alias assuming into whichever
account this should exist in. See `ci-oidc/main.tf` for the current instantiations
(shared-services and platform-dev).

**`oidc_sub_claim_prefix` is required and has no default on purpose.** It's not simply
`"repo:<org>/<repo>"` - GitHub's "immutable subject claims" setting (on by default for this
account) puts numeric, immutable org/repo IDs in the actual token instead of the human-readable
names, specifically so a renamed or recreated repo can't inherit another repo's trust. Get the
real value with `gh api repos/<org>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix`
- this is exactly the mistake that broke the first real test of this module's roles (PR #7 in
`infra`): the trust policy was written against the plain `repo:org/repo` format, which doesn't
match what GitHub actually issues.
