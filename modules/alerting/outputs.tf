output "sender_email" {
  description = "The verified sender/recipient address - Liam must click the SES confirmation email sent to it before the alert bridge can actually send (see README)."
  value       = var.sender_email
}

output "webhook_url" {
  description = <<-EOT
    API Gateway URL Alertmanager's webhook_configs posts to. Not a secret in the usual sense
    (it accepts unauthenticated POSTs, same accepted-risk shape as the Build Cache Node's
    unauthenticated-but-unguessable ALB hostname - see that app's README), but it IS an
    AWS-generated value that changes every time this module is destroyed and recreated -
    same category as BUILD_CACHE_URL and the RDS address, and like BUILD_CACHE_URL it has to be
    hand-copied into a committed file (platform/apps/monitoring/application.yaml's
    alertmanager.config.receivers webhook_configs url) since Alertmanager's generic webhook
    receiver has no "_file"-suffixed option the way its SMTP settings do. scripts/up.sh prints
    this value for exactly that reason.
  EOT
  value       = "${aws_apigatewayv2_api.alert_bridge.api_endpoint}/alert"
}
