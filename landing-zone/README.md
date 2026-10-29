# landing-zone

AWS Organizations setup: OUs, member accounts, centralized root access, Identity Center
assignments, Budgets alerts (including an automatic SCP-based cutoff at $100 actual spend -
see "Testing and removing the budget-breach SCP" below), and (gated) SCPs on Workloads. The
organization CloudTrail lives in `../log-archive`, not here - see "What's deliberately not
here" below for why.

Local state for now - see `versions.tf`. Migrates into the shared-services state bucket once
`../bootstrap-state` has been applied; see that module's README for the exact
`terraform init -migrate-state` steps once you're ready to do that.

## Resume here

Picking this back up after a pause? This is where things stand and what's left, in order.
Each step lists a check to confirm it actually worked before moving to the next.

**Already applied and live:** the org import, Security/Workloads OUs, the three member
accounts, centralized root access, `platform-admins`'s `AdministratorAccess` on all three
accounts, the Budget, and - in `../log-archive`, not here - the organization CloudTrail (its
first apply failed on a bucket policy issue, fixed; see
`platform/docs/postmortems/2026-10-org-trail-bucket-policy.md`).

**Still to apply, in order:**

1. **`../bootstrap-state`** - creates the shared-services state bucket.
   ```
   cd infra/bootstrap-state && terraform init && terraform plan && terraform apply
   terraform output -raw state_bucket_name   # note this down, you'll need it below
   ```
   Check: `aws s3api get-bucket-versioning --profile shared-services-admin --bucket <name>`
   returns `Enabled`.

2. **This config** (`landing-zone`), to apply the `platform-admins` `ReadOnly` assignment and
   the budget-breach SCP action (both from PR #4):
   ```
   terraform plan && terraform apply
   ```
   Check: `aws budgets describe-budget-actions --profile mgmt-admin --account-id <management-account-id> --budget-name build-cache-monthly`
   lists the new action; SSO profiles ending `-readonly` now actually work.

3. **Migrate this config's state** into the bucket from step 1 - see
   `../bootstrap-state/README.md`'s "Migrating landing-zone's state in" for the exact backend
   block and `terraform init -migrate-state` command.
   Check: `terraform plan` immediately after shows 0 changes.

4. **`../ci-oidc`**:
   ```
   cd infra/ci-oidc
   terraform init -backend-config="bucket=<state_bucket_name from step 1>"
   terraform plan  -var="state_bucket_name=<same value>"
   terraform apply -var="state_bucket_name=<same value>"
   ```
   Check: `terraform output` shows all four role ARNs (shared-services and platform-dev,
   plan and apply).

5. **SCPs on Workloads** - only once SSO access into all three accounts is confirmed working:
   set `attach_workload_scps = true` in `landing-zone/terraform.tfvars`, then
   `terraform plan && terraform apply` here again.
   Check: `aws organizations list-policies-for-target --profile mgmt-admin --filter SERVICE_CONTROL_POLICY --target-id <Workloads OU ID>`
   lists both `workloads-guardrails` and `deny-other-regions`.

**Deliberately not in this list:** `envs/dev` is written and validated but stays unapplied
until phase 2 - its NAT gateway costs hourly the moment it exists, so there's no reason to
have it running before anything actually uses it.

## Order of operations (historical - the first apply, already done)

Kept for reference; if you're resuming after a pause, use "Resume here" above instead.

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

## Testing and removing the budget-breach SCP

`aws_budgets_budget_action.deny_all_at_100` attaches a **deny-all** SCP to the Workloads OU,
automatically, the moment actual spend crosses $100 for the month - no approval step. Test it
deliberately before trusting it, and know how to undo it before you need to.

**To test safely:** don't lower the real budget's threshold to something today's near-zero
spend might cross by accident while you're not watching. Instead, either:
- Wait until there's a predictable charge (e.g. phase 2's EKS cluster running for a few hours)
  and watch the action fire at the real $100 threshold, or
- Temporarily edit `action_threshold_value` to something you can trigger on purpose (e.g. $1,
  right after a small, known charge has posted - Cost Explorer data lags actual usage by
  hours, so "triggered" means the budget recalculated, not that it's instant), apply, confirm
  it fires, then immediately revert the threshold back to 100 and apply again.

**To check whether it's fired:**
```
aws budgets describe-budget-action-histories --profile mgmt-admin \
  --account-id <management-account-id> --budget-name build-cache-monthly \
  --action-id <action id, from describe-budget-actions>
```

**To remove the SCP once attached** (whether from a real breach or a deliberate test):
```
aws organizations detach-policy --profile mgmt-admin \
  --policy-id <budget_breach_deny_all policy ID> \
  --target-id <Workloads OU ID>
```
This works regardless of whether AWS Budgets' own console "reverse action" option is available
for this specific action - `detach-policy` is the authoritative, always-available fix. Spend
causing the breach doesn't go away when you detach the SCP; fix the actual cost driver too.

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
- `platform-admins` gets both `AdministratorAccess` and `ReadOnly` on every account - there's no
  separate read-only-only group. Day-to-day checks are meant to use the `-readonly` SSO
  profiles out of habit, not because anything enforces it.
