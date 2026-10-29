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

  apps_repo_url = "https://github.com/liambarkley/platform.git"
}
