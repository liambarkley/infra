# ci-oidc

GitHub Actions OIDC trust for the `infra` repo, in shared-services: an identity provider, a
read-only plan role trusted only for pull-request-triggered runs, and a separate write-capable
apply role trusted only for the `main` branch. No long-lived AWS keys stored in GitHub, and CI
can never apply from a PR - enforced at the IAM trust-policy layer, not just convention.

The two roles are defined once in `../modules/github-oidc-roles` and instantiated per account;
today that's shared-services only. See `landing-zone/README.md`'s "what's deliberately not
here yet" for why platform-dev doesn't have one yet.

## Applying this (manual, once `../bootstrap-state` exists)

```
cd infra/ci-oidc
terraform init -backend-config="bucket=<state_bucket_name output from bootstrap-state>"
terraform plan  -var="state_bucket_name=<same value>"
terraform apply -var="state_bucket_name=<same value>"   # Liam runs this, not Claude Code
```

(`state_bucket_name` is a plain variable, not read automatically, because it's an output of a
different Terraform state this config doesn't have access to.)

After applying, put `shared_services_plan_role_arn` and `shared_services_apply_role_arn` into
the `infra` repo's GitHub Actions workflow (`permissions: id-token: write` +
`aws-actions/configure-aws-credentials`, plan role for the PR job, apply role for a job gated
to `main`). Until then, the AWS-auth step in `.github/workflows/ci.yml` stays disabled so CI
doesn't fail on missing credentials.
