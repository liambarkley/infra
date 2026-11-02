# alerting

Phase 4. SES identity and IAM plumbing for Alertmanager's email receiver - the AWS-side half;
the Kubernetes-side half (Alertmanager's config, the initContainer that turns the raw access
key into an SMTP password) is `platform/apps/monitoring`.

## What this is, and why it's not keyless like everything else

Every other credential in this project reaches a pod via OIDC or EKS Pod Identity - no access
keys, no secrets committed anywhere (`ci-oidc`, Karpenter, the AWS Load Balancer Controller,
the demo app's RDS access). Alertmanager's built-in `email_configs` receiver breaks that
pattern on one point: it only speaks SMTP, and SES's SMTP endpoint authenticates with a
password that's deterministically derived from a real IAM access key's secret - there is no
SigV4/STS equivalent for SMTP AUTH. An access key has to exist somewhere for this to work at
all. This module creates the smallest one it can: a dedicated IAM user whose only permission is
`ses:SendRawEmail`, conditioned on `ses:FromAddress` matching the one verified sender address -
it cannot send as anyone else, and can't do anything else in the account.

The raw key (not the derived SMTP password - see `main.tf`'s comment on `aws_secretsmanager_secret.smtp` for why) lands in Secrets Manager, never in this repo. `platform/apps/monitoring`'s
Alertmanager initContainer reads it via Pod Identity and derives the actual SMTP password at
pod startup, writing it to a file Alertmanager's `smtp_auth_password_file` points at.

## The one manual step

SES requires the sender address to be a verified identity before it will send anything, even
in sandbox mode - `aws_sesv2_email_identity` triggers a confirmation email, but only Liam
clicking the link in it actually verifies it. Until then, Alertmanager's send attempts will
fail outright (not silently - the init container logs the SES error). Same category of manual
step as `demo-spring-app`'s `BUILD_CACHE_URL` repo variable: AWS-triggered, human-confirmed,
can't be scripted from here.

The account is also in the SES sandbox (no request filed to leave it - no need to for a single
self-notification address): sandbox mode requires the **To** address to be verified too, which
is why `sender_email` is reused as the only alert recipient rather than having separate
from/to addresses.

## Worth confirming at apply time, not assumed here

Alertmanager added `smtp_auth_password_file` (and `smtp_auth_username_file`) as config options
specifically so SMTP credentials don't have to live in the chart's values - `platform/apps/monitoring` assumes both exist on whatever Alertmanager version `kube-prometheus-stack` pins.
If `smtp_auth_username_file` turns out not to exist on that version, the fallback is templating
the username (the IAM access key ID - not secret by itself, but CLAUDE.md's "no keys in files"
rule is written broadly enough to avoid hardcoding it anyway) into the config via an `envsubst`
init step instead of a literal value.
