# Step 5: organization CloudTrail logging to a bucket in log-archive.
#
# The trail itself must be created from the management account (is_organization_trail only
# works there). The bucket lives in log-archive, reached via an assumed role - member accounts
# created by Organizations trust the management account's OrganizationAccountAccessRole by
# default, so the mgmt-admin SSO role (AdministratorAccess) can assume it without any extra
# setup.
provider "aws" {
  alias   = "log_archive"
  region  = var.aws_region
  profile = var.aws_profile

  assume_role {
    role_arn     = "arn:aws:iam::${aws_organizations_account.log_archive.id}:role/OrganizationAccountAccessRole"
    session_name = "terraform-landing-zone"
  }

  default_tags {
    tags = {
      project   = "build-cache"
      ManagedBy = "terraform"
      Component = "landing-zone"
    }
  }
}

data "aws_caller_identity" "management" {}

locals {
  org_trail_name = "build-cache-org-trail"
  # Built from known parts rather than referencing aws_cloudtrail.org.arn, which would be a
  # cycle: the bucket policy needs the trail's ARN, but the trail needs the bucket (with that
  # policy already in place) to exist first. CloudTrail trail ARNs are deterministic, so this
  # is safe.
  org_trail_arn = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.management.account_id}:trail/${local.org_trail_name}"
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
    resources = ["${aws_s3_bucket.org_trail.arn}/AWSLogs/${aws_organizations_organization.this.id}/*"]

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

resource "aws_cloudtrail" "org" {
  name                          = local.org_trail_name
  s3_bucket_name                = aws_s3_bucket.org_trail.id
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.org_trail]
}
