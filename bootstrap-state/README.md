# bootstrap-state

Creates the S3 bucket (versioned, with S3 native locking - no DynamoDB table) that `envs/dev`,
`ci-oidc` and eventually `landing-zone` use as their remote state backend. Lives in the
**shared-services** account, not the management account.

This config deliberately lives outside `modules/` and uses a **local** backend, not S3 - it's
the config that creates the S3 backend, so it can't depend on it existing yet. Classic
chicken-and-egg; this is the standard way out of it.

It reaches shared-services by assuming `OrganizationAccountAccessRole` there from the
management account's `mgmt-admin` credentials (looking up the account ID via
`data.aws_organizations_organization`, which only works from the management account) - not via
a dedicated SSO profile, so this works before any of `landing-zone`'s Identity Center
assignments exist.

## Running this (manual — Claude Code does not run `apply`)

```
cd infra/bootstrap-state
terraform init
terraform plan
terraform apply   # Liam runs this, not Claude Code
terraform output -raw state_bucket_name   # note this down - it has a random suffix
```

The local `terraform.tfstate` this creates is the only state for *this* config - keep it (it's
`.gitignore`d from the parent `infra/.gitignore`, so don't lose the local copy; there's nothing
to migrate it to, since this bucket is what everything else migrates state *into*, not this
config itself).

## Wiring other configs up to this bucket

`envs/dev/versions.tf` and `ci-oidc/versions.tf` deliberately omit `bucket` from their `backend
"s3"` blocks (the name isn't known until after this is applied). Initialize them with:

```
terraform init -backend-config="bucket=<state_bucket_name output>"
```

## Migrating landing-zone's state in

`landing-zone` currently runs on local state. Once this bucket exists:

1. Add a backend block to `landing-zone/versions.tf`:
   ```
   backend "s3" {
     key          = "landing-zone/terraform.tfstate"
     region       = "ca-central-1"
     profile      = "shared-services-admin"
     use_lockfile = true
     encrypt      = true
   }
   ```
   (The backend needs its own credentials to reach the shared-services bucket, separate from
   the `aws` provider config used to manage resources. `shared-services-admin` is the SSO
   profile from `landing-zone`'s `sso_config_snippet` output - paste that into `~/.aws/config`
   before this step, same as for `envs/dev` and `ci-oidc`.)
2. From `infra/landing-zone`:
   ```
   terraform init -migrate-state -backend-config="bucket=<state_bucket_name output>"
   ```
3. Confirm with `terraform plan` that nothing changed, then delete the old local
   `terraform.tfstate*` files once you're confident the migration worked.
