# Step 3: Identity Center permission sets and account assignments.

data "aws_ssoadmin_instances" "this" {}

locals {
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  member_accounts = {
    log-archive     = aws_organizations_account.log_archive.id
    shared-services = aws_organizations_account.shared_services.id
    platform-dev    = aws_organizations_account.platform_dev.id
  }
}

data "aws_identitystore_group" "platform_admins" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = var.platform_admins_group_name
    }
  }
}

# Created by hand via the console when Identity Center was first enabled - looked up, not
# managed, so Terraform doesn't fight whatever's already assigned on the management account.
data "aws_ssoadmin_permission_set" "admin" {
  instance_arn = local.sso_instance_arn
  name         = var.admin_permission_set_name
}

resource "aws_ssoadmin_permission_set" "read_only" {
  name             = "ReadOnly"
  description      = "Read-only access across the account. No ability to change anything."
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"
}

resource "aws_ssoadmin_managed_policy_attachment" "read_only" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.read_only.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# platform-admins gets AdministratorAccess on every new account, same as it already has on
# the management account.
resource "aws_ssoadmin_account_assignment" "admin" {
  for_each = local.member_accounts

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.aws_ssoadmin_permission_set.admin.arn
  principal_id       = data.aws_identitystore_group.platform_admins.group_id
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}

# platform-admins also gets ReadOnly on every new account - same group, both permission sets.
# There's no separate read-only-only group; Liam wants read-only available for day-to-day
# checks without reaching for AdministratorAccess every time.
resource "aws_ssoadmin_account_assignment" "read_only" {
  for_each = local.member_accounts

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.read_only.arn
  principal_id       = data.aws_identitystore_group.platform_admins.group_id
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}
