output "sender_email" {
  description = "The verified sender/recipient address - Liam must click the SES confirmation email sent to it before Alertmanager can actually send (see README)."
  value       = var.sender_email
}

output "smtp_key_secret_arn" {
  description = "Secrets Manager secret holding the raw IAM access key (id + secret) backing SES SMTP auth - platform/apps/monitoring's Alertmanager initContainer reads this via Pod Identity and derives the actual SMTP password at pod startup."
  value       = aws_secretsmanager_secret.smtp.arn
}
