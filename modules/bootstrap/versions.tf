terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.16, < 3.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.35, < 3.0.0"
    }
  }
}
