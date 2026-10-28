# policy

OPA/conftest rules evaluated against `terraform plan`'s JSON output in CI. Deny-by-default isn't
the goal here — just catching the hard rules from `CLAUDE.md` that are easy to forget in a single
PR, before they reach `apply`.

Run locally:

```
terraform -chdir=envs/dev plan -out=tfplan.binary
terraform -chdir=envs/dev show -json tfplan.binary > tfplan.json
conftest test --policy policy tfplan.json
```
