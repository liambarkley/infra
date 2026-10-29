# Step 4: Budgets alerts on the management account, per docs/PLAN.md's cost-control guardrail.
# $50/month limit with notifications at 50% ($25) and 100% ($50) of actual spend.
resource "aws_budgets_budget" "monthly_cost" {
  name         = "build-cache-monthly"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}

# --- Automatic cutoff at $100 actual spend: attach a deny-all SCP to Workloads ---
#
# This is a real, automatic lockdown - not a notification. Above the two alert thresholds in
# the budget itself, this is the backstop for "the alerts got missed and spend kept climbing."
# It denies every action in Workloads (shared-services, platform-dev) only - not Security, not
# the management account - until someone manually detaches the policy. See
# landing-zone/README.md for how to test this safely with a low threshold, and how to remove
# the SCP afterwards.

data "aws_caller_identity" "management" {}

data "aws_iam_policy_document" "deny_all" {
  statement {
    sid       = "DenyAll"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "budget_breach_deny_all" {
  name    = "budget-breach-deny-all"
  type    = "SERVICE_CONTROL_POLICY"
  content = data.aws_iam_policy_document.deny_all.json
}

# Trust and permissions AWS's own docs specify for a budget action's execution role:
# https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-action-role.html
data "aws_iam_policy_document" "budgets_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:budgets::${data.aws_caller_identity.management.account_id}:budget/*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.management.account_id]
    }
  }
}

resource "aws_iam_role" "budgets_action" {
  name               = "build-cache-budget-scp-action"
  assume_role_policy = data.aws_iam_policy_document.budgets_assume_role.json
}

# Scoped to just SCP attach/detach on this one policy and this one OU - not "*", and not the
# broader IAM-policy actions AWS's example bundles in, since this role only ever needs to
# manage one SCP on one OU.
data "aws_iam_policy_document" "budgets_action_permissions" {
  statement {
    effect  = "Allow"
    actions = ["organizations:AttachPolicy", "organizations:DetachPolicy"]
    resources = [
      "arn:aws:organizations::${data.aws_caller_identity.management.account_id}:policy/${aws_organizations_organization.this.id}/service_control_policy/${aws_organizations_policy.budget_breach_deny_all.id}",
      "arn:aws:organizations::${data.aws_caller_identity.management.account_id}:ou/${aws_organizations_organization.this.id}/${aws_organizations_organizational_unit.workloads.id}",
    ]
  }
}

resource "aws_iam_role_policy" "budgets_action_permissions" {
  name   = "scp-attach-detach"
  role   = aws_iam_role.budgets_action.id
  policy = data.aws_iam_policy_document.budgets_action_permissions.json
}

resource "aws_budgets_budget_action" "deny_all_at_100" {
  budget_name        = aws_budgets_budget.monthly_cost.name
  action_type        = "APPLY_SCP_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budgets_action.arn

  action_threshold {
    action_threshold_type  = "ABSOLUTE_VALUE"
    action_threshold_value = 100
  }

  definition {
    scp_action_definition {
      policy_id  = aws_organizations_policy.budget_breach_deny_all.id
      target_ids = [aws_organizations_organizational_unit.workloads.id]
    }
  }

  subscriber {
    address           = var.budget_alert_email
    subscription_type = "EMAIL"
  }
}
