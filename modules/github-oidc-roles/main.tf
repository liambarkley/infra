locals {
  apply_trusted_subs = coalesce(var.apply_trusted_subs, ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"])
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [var.oidc_thumbprint]
}

# --- plan role: read-only, trusted for pull_request-triggered runs only ---

data "aws_iam_policy_document" "plan_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name               = var.plan_role_name
  assume_role_policy = data.aws_iam_policy_document.plan_assume_role.json
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# s3:GetObject is bucket-wide (not one exact key) so adding a new env/root module later
# doesn't need this module touched. s3:PutObject/DeleteObject stay scoped to *.tflock objects
# only - that's the "write on the .tflock object only" the plan role needs to take and
# release the plan-time state lock, never the state file itself.
data "aws_iam_policy_document" "plan_state_access" {
  statement {
    sid     = "ReadState"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.state_bucket_name}",
      "arn:aws:s3:::${var.state_bucket_name}/*",
    ]
  }

  statement {
    sid       = "PlanTimeLockOnly"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state_access" {
  name   = "state-access"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state_access.json
}

# --- apply role: write-capable, trusted only for main (or a protected environment) ---

data "aws_iam_policy_document" "apply_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.apply_trusted_subs
    }
  }
}

resource "aws_iam_role" "apply" {
  name               = var.apply_role_name
  assume_role_policy = data.aws_iam_policy_document.apply_assume_role.json
}

# PowerUserAccess, not AdministratorAccess: this role can create/manage most resources but
# not IAM users, roles or account-level settings. The Workloads-OU SCPs (landing-zone/scps.tf)
# separately deny IAM user/access-key creation org-wide anyway - this is belt and suspenders,
# not reliance on one control.
resource "aws_iam_role_policy_attachment" "apply_power_user" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "apply_state_access" {
  statement {
    sid     = "ReadWriteState"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.state_bucket_name}",
      "arn:aws:s3:::${var.state_bucket_name}/*",
    ]
  }

  statement {
    sid       = "ApplyTimeLock"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "apply_state_access" {
  name   = "state-access"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_state_access.json
}
