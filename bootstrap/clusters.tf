# ── K3D Clusters ─────────────────────────────────────────────────────────────
# Three k3d clusters: transit (parent), app-workload, ai-workload (children).
# Port assignments:
#   transit:      80→8080, 443→8443
#   app-workload: 80→8081, 443→8444, uplinks 9444-9446 (API groups)
#   ai-workload:  80→8082, 443→8445, uplinks 9447-9449 (MCP), 9450 (AI gateway)

module "transit_k3d" {
  source = "../../terraform-demo-modules/compute/suse/k3d"

  cluster_name = "transit"
  ports = [
    { from = 80, to = 8080 },
    { from = 443, to = 8443 },
  ]
  volumes           = [local.mkcert_ca_volume]
  host_aliases      = local.k3d_host_aliases
  registries_use    = [local.registry_mirror_container]
  registries_config = local.registries_yaml

  depends_on = [null_resource.registry_mirror]
}

module "app_workload_k3d" {
  source = "../../terraform-demo-modules/compute/suse/k3d"

  cluster_name = "app-workload"
  ports = [
    { from = 80, to = 8081 },
    { from = 443, to = 8444 },
    { from = 9444, to = 9444 },
    { from = 9445, to = 9445 },
    { from = 9446, to = 9446 },
  ]
  volumes           = [local.mkcert_ca_volume]
  host_aliases      = local.k3d_host_aliases
  registries_use    = [local.registry_mirror_container]
  registries_config = local.registries_yaml

  depends_on = [module.transit_k3d, null_resource.registry_mirror]
}

module "ai_workload_k3d" {
  source = "../../terraform-demo-modules/compute/suse/k3d"

  cluster_name = "ai-workload"
  ports = [
    { from = 80, to = 8082 },
    { from = 443, to = 8445 },
    { from = 9447, to = 9447 },
    { from = 9448, to = 9448 },
    { from = 9449, to = 9449 },
    { from = 9450, to = 9450 },
  ]
  volumes           = [local.mkcert_ca_volume]
  host_aliases      = local.k3d_host_aliases
  registries_use    = [local.registry_mirror_container]
  registries_config = local.registries_yaml

  depends_on = [module.app_workload_k3d, null_resource.registry_mirror]
}
