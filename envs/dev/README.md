# envs/dev

The only environment this project runs. Wires `modules/network` in; `eks`, `bootstrap` and
`storage` modules get added here as they're built out in later phases.

Deploys into **platform-dev**, never the management account. Two separate credentials are in
play, since the provider (platform-dev) and the backend (shared-services, below) are different
accounts:
- Locally: `platform-dev-admin` and `shared-services-admin`, both SSO profiles from
  `landing-zone`'s `sso_config_snippet` output.
- In CI: `platform-dev-ci` and `shared-services-ci`, both named profiles CI creates itself via
  two `aws-actions/configure-aws-credentials` steps, assuming the matching plan or apply role
  from `../../ci-oidc` for each.

State lives in the shared-services bucket from `../../bootstrap-state` (S3 native locking, no
DynamoDB). `bucket` and the backend's `profile` are both supplied at `terraform init` time, not
committed - see the comment in `versions.tf`.

`fmt` and `validate` work without any of the above. `plan`/`apply` need the bucket to exist and
either the local SSO profile or an assumed CI role to be in place.

## Before phase 2 (EKS, Karpenter): check EC2 quotas in platform-dev

A brand-new account's default EC2 vCPU quotas are low enough to block Karpenter outright before
you'd even notice why. Check both, since Karpenter's spot-with-on-demand-fallback needs headroom
in both:

```
aws service-quotas get-service-quota --profile platform-dev-admin \
  --service-code ec2 --quota-code L-1216C47A   # Running On-Demand Standard instances (vCPUs)

aws service-quotas get-service-quota --profile platform-dev-admin \
  --service-code ec2 --quota-code L-34B43A08   # All Standard Spot Instance Requests (vCPUs)
```

Both default to 5 vCPUs on a new account - likely too low for even a small EKS node group plus
a couple of demo-app pods. Request an increase (Service Quotas console, or
`aws service-quotas request-service-quota-increase`) well before starting phase 2; increases
aren't instant.
