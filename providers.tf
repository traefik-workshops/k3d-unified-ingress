locals {
  transit_host                   = module.transit_k3d.host
  transit_client_certificate     = module.transit_k3d.client_certificate
  transit_client_key             = module.transit_k3d.client_key
  transit_cluster_ca_certificate = module.transit_k3d.cluster_ca_certificate

  app_workload_host                   = module.app_workload_k3d.host
  app_workload_client_certificate     = module.app_workload_k3d.client_certificate
  app_workload_client_key             = module.app_workload_k3d.client_key
  app_workload_cluster_ca_certificate = module.app_workload_k3d.cluster_ca_certificate

  ai_workload_host                   = module.ai_workload_k3d.host
  ai_workload_client_certificate     = module.ai_workload_k3d.client_certificate
  ai_workload_client_key             = module.ai_workload_k3d.client_key
  ai_workload_cluster_ca_certificate = module.ai_workload_k3d.cluster_ca_certificate
}

terraform {
  required_providers {
    k3d = {
      source  = "SneakyBugs/k3d"
      version = "~> 1.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

provider "k3d" {}

# ── Transit ───────────────────────────────────────────────────────────────────
provider "kubernetes" {
  alias                  = "transit"
  host                   = local.transit_host
  client_certificate     = local.transit_client_certificate
  client_key             = local.transit_client_key
  cluster_ca_certificate = local.transit_cluster_ca_certificate
}

provider "helm" {
  alias = "transit"
  kubernetes = {
    host                   = local.transit_host
    client_certificate     = local.transit_client_certificate
    client_key             = local.transit_client_key
    cluster_ca_certificate = local.transit_cluster_ca_certificate
  }
}

# ── App-workload ──────────────────────────────────────────────────────────────
provider "kubernetes" {
  alias                  = "app_workload"
  host                   = local.app_workload_host
  client_certificate     = local.app_workload_client_certificate
  client_key             = local.app_workload_client_key
  cluster_ca_certificate = local.app_workload_cluster_ca_certificate
}

provider "helm" {
  alias = "app_workload"
  kubernetes = {
    host                   = local.app_workload_host
    client_certificate     = local.app_workload_client_certificate
    client_key             = local.app_workload_client_key
    cluster_ca_certificate = local.app_workload_cluster_ca_certificate
  }
}

# ── AI-workload ───────────────────────────────────────────────────────────────
provider "kubernetes" {
  alias                  = "ai_workload"
  host                   = local.ai_workload_host
  client_certificate     = local.ai_workload_client_certificate
  client_key             = local.ai_workload_client_key
  cluster_ca_certificate = local.ai_workload_cluster_ca_certificate
}

provider "helm" {
  alias = "ai_workload"
  kubernetes = {
    host                   = local.ai_workload_host
    client_certificate     = local.ai_workload_client_certificate
    client_key             = local.ai_workload_client_key
    cluster_ca_certificate = local.ai_workload_cluster_ca_certificate
  }
}
