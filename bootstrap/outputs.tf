# Per-cluster credentials and kubeconfig file paths consumed by the root module
# via `data.terraform_remote_state.bootstrap`. All cred values are sensitive.

output "transit" {
  description = "Transit cluster credentials + kubeconfig path"
  sensitive   = true
  value = {
    name                   = "transit"
    host                   = module.transit_k3d.host
    client_certificate     = module.transit_k3d.client_certificate
    client_key             = module.transit_k3d.client_key
    cluster_ca_certificate = module.transit_k3d.cluster_ca_certificate
    kubeconfig_path        = abspath(local_sensitive_file.kubeconfig_transit.filename)
  }
}

output "app_workload" {
  description = "App-workload cluster credentials + kubeconfig path"
  sensitive   = true
  value = {
    name                   = "app-workload"
    host                   = module.app_workload_k3d.host
    client_certificate     = module.app_workload_k3d.client_certificate
    client_key             = module.app_workload_k3d.client_key
    cluster_ca_certificate = module.app_workload_k3d.cluster_ca_certificate
    kubeconfig_path        = abspath(local_sensitive_file.kubeconfig_app_workload.filename)
  }
}

output "ai_workload" {
  description = "AI-workload cluster credentials + kubeconfig path"
  sensitive   = true
  value = {
    name                   = "ai-workload"
    host                   = module.ai_workload_k3d.host
    client_certificate     = module.ai_workload_k3d.client_certificate
    client_key             = module.ai_workload_k3d.client_key
    cluster_ca_certificate = module.ai_workload_k3d.cluster_ca_certificate
    kubeconfig_path        = abspath(local_sensitive_file.kubeconfig_ai_workload.filename)
  }
}

# Shared bits the root module needs (mkcert paths, host_aliases, registry name).
output "mkcert_ca_volume" {
  description = "host:container mount string for the mkcert CA bundle"
  value       = local.mkcert_ca_volume
}

output "mkcert_dir" {
  description = "Absolute path on disk where mkcert cert.pem/key.pem live"
  value       = abspath(local.mkcert_dir)
}

output "k3d_host_aliases" {
  description = "host_aliases passed to each k3d cluster"
  value       = local.k3d_host_aliases
}

output "registry_mirror_container" {
  description = "Name of the k3d registry mirror container (k3d-registry-mirror)"
  value       = local.registry_mirror_container
}
