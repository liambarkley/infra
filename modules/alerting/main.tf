locals {
  tags = merge(
    {
      project   = "build-cache"
      ManagedBy = "terraform"
      Module    = "alerting"
    },
    var.tags,
  )
}

# Verifies ownership of the sender/recipient address with AWS - SES emails a confirmation link
# to it that only resolves to "Verified" once Liam clicks it (can't be automated from here, same
# category of manual step as demo-spring-app's BUILD_CACHE_URL repo variable). Required even in
# the SES sandbox, and required for both the From and To address - using one address for both
# keeps this to a single identity.
resource "aws_sesv2_email_identity" "sender" {
  email_identity = var.sender_email
  tags           = local.tags
}

# Originally built as SES SMTP (an IAM user + access key, since SMTP AUTH has no SigV4/role
# equivalent) - abandoned after a real apply hit this account's landing-zone SCP
# (workloads-guardrails -> DenyIamUserAndAccessKeyCreation, infra/landing-zone/scps.tf) with a
# flat, unconditional deny on iam:CreateUser/CreateAccessKey across the whole Workloads OU. That
# guardrail was deliberate (docs/PLAN.md's phase-1 notes: "access via IAM Identity Center ...
# rather than an IAM user"), so the fix is routing around IAM users entirely, not weakening it.
#
# This Lambda, fronted by an API Gateway HTTP API, is that route: Alertmanager's generic
# webhook_configs POSTs its alert JSON here, the function calls SES's SendEmail *API* (not
# SMTP) using its own execution role - a real IAM role, which the SCP doesn't touch at all,
# only users/keys. No long-lived credential exists anywhere in this path.
data "archive_file" "alert_bridge" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda/handler.zip"
}

resource "aws_iam_role" "alert_bridge" {
  name = "${var.name}-alert-bridge"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "alert_bridge_logs" {
  role       = aws_iam_role.alert_bridge.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Needed for the function's tracing_config (Active) below - without this, X-Ray segments fail
# to publish silently (a log warning, not a function failure, but tracing wouldn't actually
# show anything).
resource "aws_iam_role_policy_attachment" "alert_bridge_xray" {
  role       = aws_iam_role.alert_bridge.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

data "aws_iam_policy_document" "alert_bridge_send" {
  statement {
    sid       = "SendFromVerifiedAddressOnly"
    effect    = "Allow"
    actions   = ["ses:SendEmail"]
    resources = ["*"] # ses:SendEmail has no resource-level ARN to scope to; the condition below is the real restriction.

    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [var.sender_email]
    }
  }
}

resource "aws_iam_role_policy" "alert_bridge_send" {
  name   = "send-from-verified-address-only"
  role   = aws_iam_role.alert_bridge.id
  policy = data.aws_iam_policy_document.alert_bridge_send.json
}

resource "aws_lambda_function" "alert_bridge" {
  # checkov:skip=CKV_AWS_117: deliberately NOT in a VPC - this function only calls SES's public
  # API, nothing in envs/dev's private subnets, so a VPC attachment would only add an ENI, cold
  # start, and (for real egress) a NAT dependency with no corresponding benefit.
  # checkov:skip=CKV_AWS_116: no DLQ - at this invocation volume (a handful of alerts at most),
  # a failed send is already visible in this function's own CloudWatch Logs; an SQS DLQ adds a
  # queue to manage for a case that's easy to notice by hand on a project this size.
  # checkov:skip=CKV_AWS_173: environment variables (just two email addresses, not secrets) are
  # already encrypted at rest with Lambda's default AWS-managed key - same reasoning as the
  # default-key skips on modules/rds's SSM parameters and modules/alerting's old Secrets
  # Manager secret.
  # checkov:skip=CKV_AWS_272: code-signing validation is an enterprise supply-chain control -
  # disproportionate for a single-function demo bridge with no third-party deploy pipeline.
  # checkov:skip=CKV_AWS_115: tried a small reserved_concurrent_executions as a real (not just
  # documented) mitigation for the API Gateway route having no authorizer - failed on a real
  # apply: "decreases account's UnreservedConcurrentExecution below its minimum value of [10]".
  # This account's shared Lambda concurrency pool is apparently too small right now (likely
  # low default quota on a low-usage dev account, same category as the EC2 vCPU quotas
  # envs/dev/README.md already flags) to safely reserve any amount without risking blocking
  # every *other* Lambda in the account. Not worth chasing a quota increase for a demo alerting
  # bridge - left unreserved instead.
  function_name = "${var.name}-alert-bridge"
  role          = aws_iam_role.alert_bridge.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  # arm64/Graviton - cheaper per invocation than the x86_64 default, and boto3 (all this
  # function needs beyond the standard library) ships with the Python runtime either way, so
  # there's no dependency-compatibility reason to prefer x86_64 here.
  architectures = ["arm64"]
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.alert_bridge.output_path
  source_code_hash = data.archive_file.alert_bridge.output_base64sha256

  environment {
    variables = {
      SENDER_EMAIL    = var.sender_email
      RECIPIENT_EMAIL = var.sender_email
    }
  }

  # Free at this volume (AWS X-Ray's always-free tier is far beyond what a handful of alerts a
  # month would ever use) and a nice, cheap bit of real observability for a project whose whole
  # point is demonstrating observability practice.
  tracing_config {
    mode = "Active"
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "alert_bridge" {
  # checkov:skip=CKV_AWS_158: default AWS-managed key - same reasoning as every other
  # default-key skip in this project (modules/rds's SSM parameters, this module's old Secrets
  # Manager secret). Log contents are alert text, not credentials.
  # checkov:skip=CKV_AWS_338: 14 days, not a year - this is a demo alerting bridge with no
  # compliance retention requirement; a year of logs for a handful of invocations a month is
  # cost with no corresponding benefit here.
  name              = "/aws/lambda/${aws_lambda_function.alert_bridge.function_name}"
  retention_in_days = 14
  tags              = local.tags
}

# HTTP API, not REST API - a fraction of the cost and configuration for a single POST route
# with no need for REST API's extra features (usage plans, request validation models, etc).
resource "aws_apigatewayv2_api" "alert_bridge" {
  name          = "${var.name}-alert-bridge"
  protocol_type = "HTTP"
  tags          = local.tags
}

resource "aws_apigatewayv2_stage" "default" {
  # checkov:skip=CKV_AWS_76: no separate access log - the Lambda's own CloudWatch Logs
  # (every invocation, payload, and SES call) already give full visibility into this single
  # route; a second log stream recording the same requests one layer up adds cost and noise,
  # not information, at this scale.
  api_id      = aws_apigatewayv2_api.alert_bridge.id
  name        = "$default"
  auto_deploy = true
  tags        = local.tags
}

resource "aws_apigatewayv2_integration" "alert_bridge" {
  api_id                 = aws_apigatewayv2_api.alert_bridge.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.alert_bridge.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "alert_bridge" {
  # checkov:skip=CKV_AWS_309: deliberately unauthenticated - Alertmanager's generic
  # webhook_configs can't sign a request (no SigV4/IAM auth support), and this project has no
  # domain for a custom-auth alternative. Same accepted-risk shape this project already made
  # once for the Build Cache Node's ALB (unauthenticated-but-unguessable endpoint, documented
  # trade-off, not an oversight). A reserved-concurrency cap on the Lambda would have bounded
  # the blast radius further but isn't viable on this account right now - see that resource's
  # checkov:skip=CKV_AWS_115 comment.
  api_id    = aws_apigatewayv2_api.alert_bridge.id
  route_key = "POST /alert"
  target    = "integrations/${aws_apigatewayv2_integration.alert_bridge.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alert_bridge.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.alert_bridge.execution_arn}/*/*"
}
