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

module "bootstrap" {
  source = "../../modules/bootstrap"

  cluster_name                       = module.eks.cluster_name
  cluster_endpoint                   = module.eks.cluster_endpoint
  cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
  aws_region                         = var.aws_region

  # Same credentials as this config's own `aws` provider (provider.tf) - the exec plugin that
  # authenticates kubernetes/helm against the cluster needs its own copy, since it runs `aws`
  # as a subprocess that doesn't inherit a provider's `profile` argument. See
  # modules/bootstrap/main.tf's comment on exec_env for why this exists.
  aws_profile           = var.aws_profile
  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
  aws_session_token     = var.aws_session_token

  apps_repo_url = "https://github.com/liambarkley/platform.git"
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
