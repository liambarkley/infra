# bootstrap-state

Creates the S3 bucket (versioned) and DynamoDB lock table that `envs/dev` (and every future env)
uses as its remote state backend.

This config deliberately lives outside `modules/` and uses a **local** backend, not S3 — it's the
config that creates the S3 backend, so it can't depend on it existing yet. Classic
chicken-and-egg; this is the standard way out of it.

## Running this (manual — Claude Code does not run `apply`)

```
cd infra/bootstrap-state
terraform init
terraform plan
terraform apply   # Liam runs this, not Claude Code
```

After it's applied, the bucket/table names here must match what `envs/dev/versions.tf`'s
`backend "s3"` block expects (`build-cache-tfstate` / `build-cache-tflock`). The local
`terraform.tfstate` this creates is the only state for *this* config — keep it (it's `.gitignore`d
from the parent `infra/.gitignore`, so don't lose the local copy; there's nothing to migrate it
to, since this bucket is what everything else migrates state *into*, not this config itself).
