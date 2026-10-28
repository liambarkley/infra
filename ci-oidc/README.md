# ci-oidc

GitHub Actions OIDC trust for the `infra` repo, in shared-services and platform-dev: an
identity provider per account, a read-only plan role trusted only for pull-request-triggered
runs, and a separate write-capable apply role trusted only for the `main` branch. No long-lived
AWS keys stored in GitHub, and CI can never apply from a PR - enforced at the IAM trust-policy
layer, not just convention.

The two roles are defined once in `../modules/github-oidc-roles` and instantiated per account.
shared-services' pair exists because that's where Terraform state itself lives (every plan/
apply needs to read/lock it, regardless of which account the managed resources are in).
platform-dev's pair is what `envs/dev`'s CI plan/apply jobs actually assume.

## Applying this (manual, once `../bootstrap-state` exists)

```
cd infra/ci-oidc
terraform init -backend-config="bucket=<state_bucket_name output from bootstrap-state>"
terraform plan  -var="state_bucket_name=<same value>"
terraform apply -var="state_bucket_name=<same value>"   # Liam runs this, not Claude Code
```

(`state_bucket_name` is a plain variable, not read automatically, because it's an output of a
different Terraform state this config doesn't have access to.)

After applying, each of `envs/dev`'s plan (PR) and apply (`main`) jobs needs **two**
`aws-actions/configure-aws-credentials` steps, each writing to its own named profile via that
action's `aws-profile` input - one account's credentials can't cover both the provider
(platform-dev) and the backend (shared-services):

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: <platform_dev_plan_role_arn (or _apply_ for the main job)>
    aws-region: ca-central-1
    aws-profile: platform-dev-ci
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: <shared_services_plan_role_arn (or _apply_ for the main job)>
    aws-region: ca-central-1
    aws-profile: shared-services-ci
- working-directory: envs/dev
  run: |
    terraform init -backend-config="bucket=<state_bucket_name>" -backend-config="profile=shared-services-ci"
    terraform plan -var="aws_profile=platform-dev-ci"   # or apply, for the main job
```

Until this is wired up, the AWS-auth steps in `.github/workflows/ci.yml` stay disabled (as a
skeleton in comments) so CI doesn't fail on missing credentials.
