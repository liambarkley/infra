# landing-zone

AWS Organizations setup: OUs, member accounts, centralized root access, Identity Center
assignments, Budgets alerts, and (gated) SCPs on Workloads. The organization CloudTrail lives
in `../log-archive`, not here - see "What's deliberately not here" below for why.

Local state for now - see `versions.tf`. Migrates into the shared-services state bucket once
`../bootstrap-state` has been applied; see that module's README for the exact
`terraform init -migrate-state` steps once you're ready to do that.

## Order of operations

1. `terraform init`, then **you** run (not Claude Code - import is off the table for it):
   ```
   terraform import aws_organizations_organization.this <org-id>
   ```
   Get `<org-id>` from `aws organizations describe-organization --profile mgmt-admin --query Organization.Id --output text`.
2. Copy `terraform.tfvars.example` to `terraform.tfvars`, fill in real account emails and your
   budget alert email. `terraform.tfvars` is gitignored - never commit it.
3. `terraform plan`, review, `terraform apply` (you run this too).
4. `terraform output -raw sso_config_snippet` and paste the result into `~/.aws/config`.
5. Confirm SSO access into `log-archive`, `shared-services` and `platform-dev` works with the
   new profiles.
6. Only then set `attach_workload_scps = true` in `terraform.tfvars` and apply again. These
   SCPs deny IAM user/access-key creation and restrict regions on the Workloads OU - easiest to
   recover from a mistake in them before they're attached, not after.
7. Once the accounts above exist, `../log-archive` can be applied - see its README.

## What's deliberately not here

- **The organization CloudTrail is in `../log-archive`, not here.** It was here originally,
  but its provider needs the log-archive account's ID, which doesn't exist until this config's
  own apply creates it - a provider block can't depend on a resource created in the same apply.
  That's what broke the first `landing-zone` apply (`terraform plan` would error trying to
  resolve `aws.log_archive`'s `assume_role.role_arn` before the account existed). Splitting it
  into its own root module, applied after this one, fixes it: by the time `log-archive`'s
  provider is evaluated, the account is real and its ID is a known value, looked up via
  Organizations rather than depended on directly.
- No resource manages the `AdministratorAccess` permission set itself - it's looked up (it
  already existed from when Identity Center was first enabled by hand), not owned by Terraform.
- The new `ReadOnly` permission set isn't assigned to anyone yet - no second Identity Center
  group exists to assign it to.
- `envs/dev`'s own provider still points at whatever the ambient credentials are (effectively
  the management account) - it isn't wired to assume into `platform-dev` yet. That's real,
  necessary follow-up work this stage doesn't do, not an oversight.
