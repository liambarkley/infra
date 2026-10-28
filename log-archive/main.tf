# This config runs after ../landing-zone has created the log-archive account - it looks that
# account's ID up via Organizations rather than hardcoding it or reading landing-zone's state
# directly (landing-zone may still be on local state, and even once migrated, reaching across
# root modules' state on every plan is more coupling than a one-line data source needs).
#
# This split exists because a provider block's arguments can't depend on a resource created in
# the same apply: the first landing-zone apply failed because its log_archive provider alias
# assumed a role using an account ID that didn't exist yet. Splitting this out means that by
# the time this config's provider is evaluated, the account already exists and its ID is a
# known value, not a computed one.
data "aws_organizations_organization" "current" {}

locals {
  log_archive_account_id = one([
    for a in data.aws_organizations_organization.current.accounts : a.id
    if a.name == "log-archive"
  ])

  org_trail_name = "build-cache-org-trail"
  # Built from known parts rather than referencing aws_cloudtrail.org.arn, which would be a
  # cycle: the bucket policy needs the trail's ARN, but the trail needs the bucket (with that
  # policy already in place) to exist first. CloudTrail trail ARNs are deterministic, so this
  # is safe.
  org_trail_arn = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.management.account_id}:trail/${local.org_trail_name}"
}

data "aws_caller_identity" "management" {}

provider "aws" {
  alias  = "log_archive"
  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${local.log_archive_account_id}:role/OrganizationAccountAccessRole"
    session_name = "terraform-log-archive"
  }

  default_tags {
    tags = {
      project   = "build-cache"
      ManagedBy = "terraform"
      Component = "log-archive"
    }
  }
}

resource "aws_s3_bucket" "org_trail" {
  provider = aws.log_archive
  bucket   = "build-cache-org-trail"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "org_trail" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.org_trail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "org_trail" {
  provider                = aws.log_archive
  bucket                  = aws_s3_bucket.org_trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "org_trail" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.org_trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "org_trail" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.org_trail.id

  rule {
    id     = "expire-old-trail-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 365 # a year of org-wide audit trail; cost control over keeping it forever
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "org_trail_bucket" {
  statement {
    sid    = "CloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.org_trail.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.org_trail_arn]
    }
  }

  statement {
    sid    = "CloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.org_trail.arn}/AWSLogs/${data.aws_organizations_organization.current.id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.org_trail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "org_trail" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.org_trail.id
  policy   = data.aws_iam_policy_document.org_trail_bucket.json
}

# No provider = ... here: is_organization_trail only works from the management account, so
# this uses the default provider (var.aws_profile, i.e. mgmt-admin), not aws.log_archive.
resource "aws_cloudtrail" "org" {
  name                          = local.org_trail_name
  s3_bucket_name                = aws_s3_bucket.org_trail.id
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.org_trail]
}
