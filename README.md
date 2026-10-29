# infra

Terraform for the Build Cache Platform SRE portfolio project.

Full story, phases and "done when" criteria: see `docs/PLAN.md` in the parent `sre_portfolio/`
workspace (not part of this repo).

## Layout

- `modules/` — one module per concern (`network`, `eks`, `bootstrap`, `storage`). Environments
  only wire modules together; no resources live directly under `envs/`. `eks` and `bootstrap`
  are built as of phase 2; `storage` is still phase 5.
- `envs/dev/` — the only environment currently run.
- `bootstrap-state/` — one-off config (local backend) that creates the S3 bucket + DynamoDB table
  used as remote state backend for everything else. Applied once, by hand.
- `policy/` — OPA/conftest rules evaluated against `terraform plan` JSON in CI.
- `.github/workflows/` — fmt, validate, tflint, checkov (and eventually `plan`) on every PR.

## Hard rules

- No `terraform apply`, `destroy`, `import` or `state rm` from Claude Code — ask Liam to run them.
- Every resource tagged `project=build-cache`.
- Remote state in S3 with a DynamoDB lock table; see `bootstrap-state/README.md` for how that
  backend itself gets created.

## Git hooks

This repo is public. `scripts/git-hooks/pre-push` runs `gitleaks` against the full history plus
two custom checks (a tracked `.tfstate`/`.tfvars` file, a bare 12-digit AWS account ID) on every
push, and blocks it if any of the three find something - the same three checks that were run by
hand before making this repo public (see `docs/PLAN.md`'s phase 2 notes for why).

Not wired up by git on its own - each clone needs to opt in once:

```
git config core.hooksPath scripts/git-hooks
```

Requires `gitleaks` (`brew install gitleaks`).

<!-- CI smoke test: confirms fmt/validate/tflint/checkov all run on a PR -->

<!-- CI smoke test: confirms the plan job now authenticates via OIDC correctly -->
