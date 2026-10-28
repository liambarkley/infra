# Step 2: centralized root access for member accounts. A native provider resource exists for
# this (added in hashicorp/aws v5.78.0), so no bootstrap.sh/aws-cli script is needed.
#
# This enables, org-wide, the ability to view and remove root credentials (password, access
# keys, signing certs, MFA) for every member account from the management account, without
# logging into each one. It does not by itself delete anything in log-archive,
# shared-services or platform-dev - that's a separate, deliberate action Liam takes per
# account once he's ready.
resource "aws_iam_organizations_features" "this" {
  enabled_features = [
    "RootCredentialsManagement",
    "RootSessions",
  ]

  depends_on = [aws_organizations_organization.this]
}
