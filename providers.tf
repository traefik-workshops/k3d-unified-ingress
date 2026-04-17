terraform {
  required_providers {
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

# Cluster credentials produced by the bootstrap workspace (./bootstrap).
# Run `make bootstrap` (or `terraform -chdir=bootstrap apply`) before applying
# this workspace.
data "terraform_remote_state" "bootstrap" {
  backend = "local"
  config = {
    path = "${path.module}/bootstrap/terraform.tfstate"
  }
}

locals {
  transit      = data.terraform_remote_state.bootstrap.outputs.transit
  app_workload = data.terraform_remote_state.bootstrap.outputs.app_workload
  ai_workload  = data.terraform_remote_state.bootstrap.outputs.ai_workload
}

# ── Transit ───────────────────────────────────────────────────────────────────
provider "kubernetes" {
  alias                  = "transit"
  host                   = local.transit.host
  client_certificate     = local.transit.client_certificate
  client_key             = local.transit.client_key
  cluster_ca_certificate = local.transit.cluster_ca_certificate
}

provider "helm" {
  alias = "transit"
  kubernetes = {
    host                   = local.transit.host
    client_certificate     = local.transit.client_certificate
    client_key             = local.transit.client_key
    cluster_ca_certificate = local.transit.cluster_ca_certificate
  }
}

# ── App-workload ──────────────────────────────────────────────────────────────
provider "kubernetes" {
  alias                  = "app_workload"
  host                   = local.app_workload.host
  client_certificate     = local.app_workload.client_certificate
  client_key             = local.app_workload.client_key
  cluster_ca_certificate = local.app_workload.cluster_ca_certificate
}

provider "helm" {
  alias = "app_workload"
  kubernetes = {
    host                   = local.app_workload.host
    client_certificate     = local.app_workload.client_certificate
    client_key             = local.app_workload.client_key
    cluster_ca_certificate = local.app_workload.cluster_ca_certificate
  }
}

# ── AI-workload ───────────────────────────────────────────────────────────────
provider "kubernetes" {
  alias                  = "ai_workload"
  host                   = local.ai_workload.host
  client_certificate     = local.ai_workload.client_certificate
  client_key             = local.ai_workload.client_key
  cluster_ca_certificate = local.ai_workload.cluster_ca_certificate
}

provider "helm" {
  alias = "ai_workload"
  kubernetes = {
    host                   = local.ai_workload.host
    client_certificate     = local.ai_workload.client_certificate
    client_key             = local.ai_workload.client_key
    cluster_ca_certificate = local.ai_workload.cluster_ca_certificate
  }
}
