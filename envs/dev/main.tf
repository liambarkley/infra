locals {
  azs = ["${var.aws_region}a", "${var.aws_region}b"]
}

module "network" {
  source = "../../modules/network"

  name                 = "build-cache-dev"
  azs                  = local.azs
  vpc_cidr             = "10.20.0.0/16"
  public_subnet_cidrs  = ["10.20.0.0/20", "10.20.16.0/20"]
  private_subnet_cidrs = ["10.20.128.0/20", "10.20.144.0/20"]

  tags = {
    environment = "dev"
  }
}

module "eks" {
  source = "../../modules/eks"

  name               = "build-cache-dev"
  private_subnet_ids = module.network.private_subnet_ids
  public_subnet_ids  = module.network.public_subnet_ids

  # Not a module cycle, despite module.rds also taking an output from this module
  # (cluster_security_group_id) - these are different resources within each module, so
  # Terraform's graph interleaves them: the cluster and its security group exist long before
  # RDS does, and only this module's demo-app-specific IAM resources (evaluated separately,
  # late) wait on RDS's secret ARN.
  demo_app_secretsmanager_arns = [module.rds.master_user_secret_arn]
  demo_app_ssm_parameter_arns  = [module.rds.address_parameter_arn, module.rds.secret_arn_parameter_arn]

  tags = {
    environment = "dev"
  }
}

module "alerting" {
  source = "../../modules/alerting"

  name = "build-cache-dev"
  # Liam's own address - this is a single-operator demo, so the SES sandbox's "From and To
  # must both be verified" requirement is satisfied by one identity. See
  # modules/alerting/README.md for the manual verification-email step this still needs.
  sender_email = "liambarkley@gmail.com"

  tags = {
    environment = "dev"
  }
}

module "bootstrap" {
  source = "../../modules/bootstrap"

  apps_repo_url = "https://github.com/liambarkley/platform.git"

  # The real fix for bugs #5 and #6 (infra git history, 2026-10-29/2026-11-02): with no local
  # provider configuration left inside modules/bootstrap (see provider.tf), this module call is
  # now a plain module Terraform will accept a `depends_on` on. This one edge forces every
  # resource module.bootstrap manages (ArgoCD, the root Application) to be destroyed before any
  # resource module.eks manages - the system node group and the cluster-admin access entry
  # included, without needing a dedicated workaround per resource.
  depends_on = [module.eks]
}

module "rds" {
  source = "../../modules/rds"

  name                       = "build-cache-dev"
  vpc_id                     = module.network.vpc_id
  private_subnet_ids         = module.network.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  tags = {
    environment = "dev"
  }
}
