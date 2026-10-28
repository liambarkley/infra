# Step 6: SCPs on the Workloads OU only (never Security, never the management account).
# Gated behind var.attach_workload_scps - see variables.tf for why. Both policies are written
# now; only their attachment is deferred.

data "aws_iam_policy_document" "scp_guardrails" {
  statement {
    sid       = "DenyLeaveOrganization"
    effect    = "Deny"
    actions   = ["organizations:LeaveOrganization"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyRootUser"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:root"]
    }
  }

  statement {
    sid    = "DenyDisableCloudTrail"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:RemoveTags",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyIamUserAndAccessKeyCreation"
    effect    = "Deny"
    actions   = ["iam:CreateUser", "iam:CreateAccessKey"]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "workloads_guardrails" {
  count = var.attach_workload_scps ? 1 : 0

  name    = "workloads-guardrails"
  type    = "SERVICE_CONTROL_POLICY"
  content = data.aws_iam_policy_document.scp_guardrails.json
}

resource "aws_organizations_policy_attachment" "workloads_guardrails" {
  count = var.attach_workload_scps ? 1 : 0

  policy_id = aws_organizations_policy.workloads_guardrails[0].id
  target_id = aws_organizations_organizational_unit.workloads.id
}

# Deny everything outside ca-central-1, except the global services listed below (their API
# calls are either region-less or physically served from us-east-1 regardless of where the
# resource "lives"). NotAction list is AWS's own reference list for this pattern - see
# https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples_general.html
data "aws_iam_policy_document" "scp_deny_other_regions" {
  statement {
    sid    = "DenyAllOutsideAllowedRegion"
    effect = "Deny"
    not_actions = [
      "a4b:*",
      "acm:*",
      "aws-marketplace-management:*",
      "aws-marketplace:*",
      "aws-portal:*",
      "budgets:*",
      "ce:*",
      "chime:*",
      "cloudfront:*",
      "config:*",
      "cur:*",
      "directconnect:*",
      "ec2:DescribeRegions",
      "ec2:DescribeTransitGateways",
      "ec2:DescribeVpnGateways",
      "fms:*",
      "globalaccelerator:*",
      "health:*",
      "iam:*",
      "importexport:*",
      "kms:*",
      "mobileanalytics:*",
      "networkmanager:*",
      "organizations:*",
      "pricing:*",
      "route53:*",
      "route53domains:*",
      "s3:GetAccountPublic*",
      "s3:ListAllMyBuckets",
      "s3:PutAccountPublic*",
      "shield:*",
      "sts:*",
      "support:*",
      "trustedadvisor:*",
      "waf-regional:*",
      "waf:*",
      "wafv2:*",
      "wellarchitected:*",
    ]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

resource "aws_organizations_policy" "deny_other_regions" {
  count = var.attach_workload_scps ? 1 : 0

  name    = "deny-other-regions"
  type    = "SERVICE_CONTROL_POLICY"
  content = data.aws_iam_policy_document.scp_deny_other_regions.json
}

resource "aws_organizations_policy_attachment" "deny_other_regions" {
  count = var.attach_workload_scps ? 1 : 0

  policy_id = aws_organizations_policy.deny_other_regions[0].id
  target_id = aws_organizations_organizational_unit.workloads.id
}
