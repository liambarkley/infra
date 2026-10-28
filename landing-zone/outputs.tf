output "sso_config_snippet" {
  description = "Paste into ~/.aws/config: one admin + one read-only profile per new account. Run: terraform output -raw sso_config_snippet"
  value = join("\n\n", [
    for name, id in local.member_accounts : join("\n", [
      "[profile ${name}-admin]",
      "sso_session = liam",
      "sso_account_id = ${id}",
      "sso_role_name = ${var.admin_permission_set_name}",
      "region = ${var.aws_region}",
      "output = yaml",
      "",
      "[profile ${name}-readonly]",
      "sso_session = liam",
      "sso_account_id = ${id}",
      "sso_role_name = ${aws_ssoadmin_permission_set.read_only.name}",
      "region = ${var.aws_region}",
      "output = yaml",
    ])
  ])
}
