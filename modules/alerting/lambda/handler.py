import json
import os

import boto3

ses = boto3.client("ses")

SENDER_EMAIL = os.environ["SENDER_EMAIL"]
RECIPIENT_EMAIL = os.environ["RECIPIENT_EMAIL"]


def handler(event, context):
    """Alertmanager webhook receiver (API Gateway HTTP API, Lambda proxy integration v2.0) -
    forwards an Alertmanager webhook payload to SES's SendEmail API. Exists only because
    Alertmanager has no native AWS receiver (email_configs needs SMTP, which needs an IAM user
    this account's landing-zone SCP flatly denies - see infra/modules/alerting/README.md) and
    SES's SendEmail API itself needs no IAM user, only this function's own execution role.
    """
    body = json.loads(event.get("body") or "{}")
    status = body.get("status", "unknown")
    alerts = body.get("alerts", [])

    lines = [f"Alertmanager webhook status: {status}", ""]
    for alert in alerts:
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})
        lines.append(
            f"[{alert.get('status', '?')}] {labels.get('alertname', '?')} "
            f"(severity={labels.get('severity', '?')}, slo={labels.get('slo', '-')})"
        )
        if annotations.get("summary"):
            lines.append(f"  {annotations['summary']}")
        if annotations.get("description"):
            lines.append(f"  {annotations['description']}")
        lines.append("")

    ses.send_email(
        Source=SENDER_EMAIL,
        Destination={"ToAddresses": [RECIPIENT_EMAIL]},
        Message={
            "Subject": {"Data": f"[build-cache-dev] Alertmanager: {status}"},
            "Body": {"Text": {"Data": "\n".join(lines) or "(empty alert payload)"}},
        },
    )

    return {"statusCode": 200, "body": "ok"}
