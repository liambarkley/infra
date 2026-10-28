# Default provider: mgmt-admin, used only to look up shared-services' account ID via
# Organizations (that API only works from the management account, regardless of IAM
# permissions in the target account).
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_organizations_organization" "current" {}

locals {
  shared_services_account_id = one([
    for a in data.aws_organizations_organization.current.accounts : a.id
    if a.name == "shared-services"
  ])
}

# Actual resources live in shared-services, reached by assuming the role the management
# account always has access to in a member account it created.
provider "aws" {
  alias  = "target"
  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${local.shared_services_account_id}:role/OrganizationAccountAccessRole"
    session_name = "terraform-bootstrap-state"
  }

  default_tags {
    tags = {
      project   = "build-cache"
      ManagedBy = "terraform"
      Component = "bootstrap-state"
    }
  }
}

# A bucket name that was just deleted can stay reserved for a while, so this project's first,
# mistakenly-management-account bucket name isn't safe to reuse immediately. The suffix also
# means this never collides with a future re-run.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  state_bucket_name = "${var.state_bucket_base_name}-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket" "tfstate" {
  provider = aws.target
  bucket   = local.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  provider = aws.target
  bucket   = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  provider                = aws.target
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  provider = aws.target
  bucket   = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  provider = aws.target
  bucket   = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
