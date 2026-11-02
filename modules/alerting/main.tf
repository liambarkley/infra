locals {
  tags = merge(
    {
      project   = "build-cache"
      ManagedBy = "terraform"
      Module    = "alerting"
    },
    var.tags,
  )
}

# Verifies ownership of the sender/recipient address with AWS - SES emails a confirmation link
# to it that only resolves to "Verified" once Liam clicks it (can't be automated from here, same
# category of manual step as demo-spring-app's BUILD_CACHE_URL repo variable). Required even in
# the SES sandbox, and required for both the From and To address - using one address for both
# keeps this to a single identity.
resource "aws_sesv2_email_identity" "sender" {
  email_identity = var.sender_email
  tags           = local.tags
}

# Phase 4's one deliberate exception to this project's otherwise keyless pattern (ci-oidc,
# Karpenter, the LB controller and the demo app's RDS access are all OIDC/Pod-Identity, no
# long-lived keys anywhere). Alertmanager's built-in email receiver only speaks SMTP, and SES's
# SMTP endpoint has no SigV4/STS equivalent - the password it accepts is deterministically
# derived from a real IAM access key's secret (AWS's own documented v4 signing algorithm), so an
# access key has to exist somewhere. Scoped as tightly as that allows: this user can only call
# ses:SendRawEmail, and only "From" the one verified address.
resource "aws_iam_user" "smtp" {
  # checkov:skip=CKV_AWS_273: deliberate, documented exception (see README) - SES SMTP has no
  # SSO/federated-identity path, only a password derived from a real IAM access key.
  name = "${var.name}-alertmanager-smtp"
  tags = local.tags
}

resource "aws_iam_access_key" "smtp" {
  user = aws_iam_user.smtp.name
}

data "aws_iam_policy_document" "smtp_send" {
  statement {
    sid       = "SendFromVerifiedAddressOnly"
    effect    = "Allow"
    actions   = ["ses:SendRawEmail"]
    resources = ["*"] # ses:SendRawEmail has no resource-level ARN to scope to; the condition below is the real restriction.

    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [var.sender_email]
    }
  }
}

resource "aws_iam_user_policy" "smtp_send" {
  # checkov:skip=CKV_AWS_40: group/role-based attachment is about human-identity governance
  # (so access reviews happen at the group level) - this user has console access disabled
  # (see aws_iam_user.smtp) and exists for exactly one service credential, not a human.
  name   = "send-from-verified-address-only"
  user   = aws_iam_user.smtp.name
  policy = data.aws_iam_policy_document.smtp_send.json
}

# The raw access key only - never the derived SMTP password. That derivation (AWS's documented
# SigV4-style algorithm: HMAC-SHA256("AWS4" + secret, "11111111" | region | "ses" |
# "aws4_request" | "SendRawEmail"), base64-encoded with a leading version byte) runs at pod
# startup instead, in platform/apps/monitoring's Alertmanager initContainer - see that app's
# README for why: Terraform's "external" data source doesn't propagate the `sensitive` marking
# from its input to its output, so deriving the password here would print it in plain text in
# every `terraform plan` - including CI's PR-triggered plan, which every PR in this repo runs.
# Keeping the derivation in a runtime script instead means the only thing Terraform ever holds
# is the access key itself, which the aws_iam_access_key resource's own `secret` attribute
# already marks sensitive.
resource "aws_secretsmanager_secret" "smtp" {
  # checkov:skip=CKV_AWS_149: default AWS-managed key, same reasoning as modules/rds's SSM
  # parameters - free, no extra IAM grant needed, and this isn't a cross-account secret.
  # checkov:skip=CKV2_AWS_57: no SES-SMTP-aware automatic rotation exists (rotation would need
  # a custom Lambda re-deriving the SMTP password and re-verifying it can still send) -
  # rotation is manual, same as the build-cache-node ci user's password (see that app's README).
  name = "${var.name}/alertmanager/ses-smtp-key"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "smtp" {
  secret_id = aws_secretsmanager_secret.smtp.id
  secret_string = jsonencode({
    access_key_id     = aws_iam_access_key.smtp.id
    secret_access_key = aws_iam_access_key.smtp.secret
  })
}
