# envs/dev

The only environment this project runs. Wires `modules/network` in; `eks`, `bootstrap` and
`storage` modules get added here as they're built out in later phases.

Needs the S3 bucket + DynamoDB table from `../../bootstrap-state` to exist before
`terraform init` can configure this backend. Needs AWS credentials (console/CLI for Liam locally,
OIDC role for CI) before `plan`/`apply` will work — `fmt` and `validate` work without either.
