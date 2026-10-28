# ci-oidc

IAM OIDC identity provider trusting `token.actions.githubusercontent.com`, and a role that
`liambarkley/infra`'s GitHub Actions workflow assumes to run `terraform plan`. No long-lived AWS
keys stored in GitHub.

The role is read-only on purpose: `AWS managed ReadOnlyAccess` plus just enough DynamoDB/S3 access
to read state and take the plan-time state lock. CI can never `apply` — same hard rule as Claude
Code, enforced at the IAM layer here instead of just by convention.

## Applying this (manual, once the AWS account + `bootstrap-state` exist)

```
cd infra/ci-oidc
terraform init    # uses the S3 backend created by ../bootstrap-state — no chicken-and-egg here
terraform plan
terraform apply   # Liam runs this, not Claude Code
```

After applying, put the role's ARN (output `ci_role_arn`) into the `infra` repo's GitHub Actions
workflow (`permissions: id-token: write` + `aws-actions/configure-aws-credentials` with
`role-to-assume`). Until then, the AWS-auth step in `.github/workflows/ci.yml` stays disabled so
CI doesn't fail on missing credentials — see the comment in that file.
