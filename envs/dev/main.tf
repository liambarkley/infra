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
