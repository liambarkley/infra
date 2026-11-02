variable "name" {
  description = "Name prefix applied to the IAM user and secret this module creates."
  type        = string
}

variable "sender_email" {
  description = <<-EOT
    Email address Alertmanager sends from, and - since this account is in the SES sandbox -
    also the only address it may send to (sandbox mode requires both the From and To address
    to be verified identities; using one address for both keeps this to a single identity).
    Not a secret: an email address alone grants no access, same reasoning as the RDS hostname
    in modules/rds.
  EOT
  type        = string
}

variable "tags" {
  description = "Extra tags merged onto every resource, in addition to project = build-cache."
  type        = map(string)
  default     = {}
}
