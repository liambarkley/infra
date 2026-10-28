# This AWS Organization already exists - it was created automatically when IAM Identity
# Center was enabled. Importing it (rather than using a data source) is what lets Terraform
# manage aws_service_access_principals and enabled_policy_types declaratively; a data source
# can only read those, not change them, and step 6's SCPs need SERVICE_CONTROL_POLICY enabled
# at the root first.
#
# After `terraform init`, run (Liam, not Claude Code - import is off-limits):
#   terraform import aws_organizations_organization.this <org-id>
# Get <org-id> from: aws organizations describe-organization --profile mgmt-admin --query Organization.Id --output text
# Not written into any file here - it's not sensitive, just kept out of committed files per convention.
resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  aws_service_access_principals = [
    "sso.amazonaws.com",        # IAM Identity Center - already enabled, keep it that way
    "cloudtrail.amazonaws.com", # required for the organization trail (cloudtrail.tf)
    "iam.amazonaws.com",        # required for centralized root access (iam.tf)
  ]

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY", # required before scps.tf can attach anything to Workloads
  ]
}

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.this.roots[0].id
}
