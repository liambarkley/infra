resource "aws_organizations_account" "log_archive" {
  name      = "log-archive"
  email     = var.log_archive_account_email
  parent_id = aws_organizations_organizational_unit.security.id

  # Removing this from Terraform (or from the org) detaches it; it does NOT delete the
  # account or its data. Closing a log-archive account by mistake is the kind of thing
  # that should take a deliberate separate action, not a stray `terraform destroy`.
  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_organizations_account" "shared_services" {
  name      = "shared-services"
  email     = var.shared_services_account_email
  parent_id = aws_organizations_organizational_unit.workloads.id

  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_organizations_account" "platform_dev" {
  name      = "platform-dev"
  email     = var.platform_dev_account_email
  parent_id = aws_organizations_organizational_unit.workloads.id

  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
  }
}
