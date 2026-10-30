locals {
  tags = merge(
    {
      project   = "build-cache"
      ManagedBy = "terraform"
      Module    = "rds"
    },
    var.tags,
  )
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.private_subnet_ids
  tags       = merge(local.tags, { Name = var.name })
}

resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "Allows Postgres (5432) from the EKS cluster security group only."
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name}-rds" })
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each                     = toset(var.allowed_security_group_ids)
  description                  = "Postgres from the EKS cluster security group."
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# No egress rule needed: RDS instances don't initiate outbound connections this project cares
# about, and the default security group behavior (no egress rules = no outbound allowed,
# since this is a non-default SG we created) is fine here - nothing it needs to reach.

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.master_username
  # No `password` attribute - RDS generates one and stores it in AWS Secrets Manager
  # automatically (manage_master_user_password), so the password itself never exists in
  # Terraform config, state diffs, or this repo. The demo app reads it from Secrets Manager
  # at runtime via Pod Identity - see platform/apps/demo-spring-app (not written yet).
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  multi_az = false
  # checkov:skip=CKV_AWS_157: single-AZ deliberately - a demo database with no real traffic,
  # destroyed between sessions anyway (docs/PLAN.md's cost-control section). Multi-AZ roughly
  # doubles RDS cost for resilience this project doesn't need yet.

  # No automated backups - this instance is destroyed between sessions along with the rest of
  # envs/dev (docs/PLAN.md's cost-control section), so there's nothing a backup would ever
  # restore into. Real backup/DR story for this project is Velero (phase 5), for the
  # cluster's own state, not this disposable demo database.
  backup_retention_period = 0

  skip_final_snapshot = true
  deletion_protection = false

  tags = merge(local.tags, { Name = var.name })
}

# The instance's address changes every time this is destroyed and recreated (AWS generates a
# random subdomain, same class of problem as the VPC ID the ALB controller auto-detects rather
# than anyone hardcoding) - storing it here means platform/apps/demo-spring-app never needs an
# environment-specific hostname written into a committed manifest. Not a secret (a hostname by
# itself grants no access - the security group is the actual control), so a plain String
# parameter, not SecureString.
resource "aws_ssm_parameter" "address" {
  name = "/${var.name}/rds/address"
  # SecureString with the default AWS-managed key, not plain String - free, no extra IAM
  # grant needed (unlike a customer-managed KMS key), and there's no reason not to.
  type  = "SecureString"
  value = aws_db_instance.this.address
  tags  = local.tags
}

# The master_user_secret's ARN is AWS-generated (a random UUID baked into it, not just this
# resource's own account ID) and changes on every destroy/recreate too - same reasoning as the
# address parameter above. Storing it here, under a name built only from var.name, means
# platform/apps/demo-spring-app's init container only ever needs one fixed, deterministic SSM
# parameter name to discover which secret to read - never the secret's own ARN, and never an
# account ID, written into a committed manifest.
resource "aws_ssm_parameter" "secret_arn" {
  name  = "/${var.name}/rds/secret-arn"
  type  = "SecureString"
  value = aws_db_instance.this.master_user_secret[0].secret_arn
  tags  = local.tags
}
