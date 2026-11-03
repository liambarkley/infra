# alerting

Phase 4. SES identity and a Lambda-behind-API-Gateway bridge for Alertmanager's alerts - the
AWS-side half; the Kubernetes-side half (Alertmanager's `webhook_configs`) is
`platform/apps/monitoring`.

## Why a Lambda bridge, not SES's SMTP endpoint directly

The first version of this module used SES's SMTP endpoint directly (an IAM user + access key,
since SMTP AUTH has no SigV4/role equivalent - see git history for that version if curious).
**That failed on a real apply**: this account's landing-zone SCP
(`workloads-guardrails` -> `DenyIamUserAndAccessKeyCreation`, `infra/landing-zone/scps.tf`)
flatly denies `iam:CreateUser` and `iam:CreateAccessKey` across the whole Workloads OU - a
guardrail set up deliberately in phase 1 ("access via IAM Identity Center ... rather than an
IAM user"), not an oversight to work around. Since an IAM access key is the *only* way to get
an SES SMTP password (there's no role-based equivalent - roles can't hold long-lived access
keys at all, by design), the SMTP route was never actually viable on this account specifically.

The fix routes around IAM users entirely rather than weakening the guardrail: Alertmanager's
generic `webhook_configs` POSTs its alert JSON to an API Gateway HTTP API, which invokes a small
Lambda (`lambda/handler.py`) that calls SES's **`SendEmail` API** (not SMTP) using its own
execution role - a normal IAM role, which the SCP doesn't touch, only users/keys. No long-lived
credential exists anywhere in this path - the one deliberate exception to this project's
keyless pattern that phase 4 started with is gone again.

## The one manual step

Same as before: `aws_sesv2_email_identity.sender` triggers a confirmation email only Liam can
click - Alertmanager's alerts will reach the Lambda and get rejected by SES (not silently -
`aws_cloudwatch_log_group.alert_bridge` has the function's logs) until that identity shows
Verified. The account is also in the SES sandbox, which is why `sender_email` is reused as both
the From and the only allowed To address.

## A second manual step, new with this design

This module's `webhook_url` output is AWS-generated and changes every time `envs/dev` is
destroyed and recreated - same category as `demo-spring-app`'s `BUILD_CACHE_URL` and the RDS
address, and like `BUILD_CACHE_URL` it has to be hand-copied into a committed file
(`platform/apps/monitoring/application.yaml`'s `alertmanager.config` `webhook_configs` `url`)
rather than resolved at pod startup - Alertmanager's webhook receiver has no `_file`-suffixed
option the way its SMTP settings did, so the trick that kept the old design's secret out of git
doesn't apply here (there's no secret to keep out - the URL is low-sensitivity, just
environment-specific). `scripts/up.sh` prints this value alongside the ALB hostname for exactly
this reason.

## Not auto-confirmed to actually work yet

Nothing here has been proven against real Alertmanager traffic - this was rebuilt after the
SMTP approach failed mid-apply, in the same session, and the next real apply is what actually
tests it end to end (Lambda invoked, SES call succeeds, email lands). If SES rejects the send
(most likely cause: the identity isn't Verified yet, or the sandbox's To-address restriction),
that shows up in the Lambda's own CloudWatch Logs, not as a silent failure.
