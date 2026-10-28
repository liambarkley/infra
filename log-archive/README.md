# log-archive

Organization CloudTrail logging to a bucket in the log-archive account. Split out of
`landing-zone` because it can't live there: its provider needs the log-archive account's ID,
which doesn't exist until `landing-zone` has actually created that account, and a provider
block's arguments can't depend on a resource created in the same apply - that's exactly what
broke the first `landing-zone` apply.

Local state for now, same as `landing-zone` - see its README for why.

## Apply order

1. `../landing-zone` first - specifically, the `log-archive` account must exist and be named
   exactly `log-archive` (this config looks it up by name via Organizations, same pattern as
   `../bootstrap-state` and `../ci-oidc`).
2. Then this config:
   ```
   cd infra/log-archive
   terraform init
   terraform plan
   terraform apply   # Liam runs this, not Claude Code
   ```

Planning or applying this before step 1 will fail - the account lookup returns nothing, and the
assumed-role provider ends up with an invalid (empty) account ID in its role ARN. That's a loud,
expected failure, not a bug to chase.
