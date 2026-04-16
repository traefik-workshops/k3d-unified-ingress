locals {
  ai_domain = "ai.${var.domain}"
}

module "ai_workload_k3d" {
  source = "../terraform-demo-modules/compute/suse/k3d"

  cluster_name = "ai-workload"
  # MCP uplink ports: 9447-9449
  ports = [
    { from = 80,   to = 8082 },
    { from = 443,  to = 8445 },
    { from = 9447, to = 9447 },
    { from = 9448, to = 9448 },
    { from = 9449, to = 9449 },
  ]

  depends_on = [module.app_workload_k3d]
}

# ── Namespaces ────────────────────────────────────────────────────────────────
resource "kubernetes_namespace_v1" "ai_workload_traefik" {
  provider   = kubernetes.ai_workload
  depends_on = [module.ai_workload_k3d]
  metadata { name = "traefik" }
}

resource "kubernetes_namespace_v1" "ai_workload_tools" {
  provider   = kubernetes.ai_workload
  depends_on = [module.ai_workload_k3d]
  metadata { name = "traefik-tools" }
}

resource "kubernetes_namespace_v1" "ai_workload_airlines" {
  provider   = kubernetes.ai_workload
  depends_on = [module.ai_workload_k3d]
  metadata { name = "traefik-airlines" }
}

# ── Traefik Hub (child) ───────────────────────────────────────────────────────
module "ai_workload_traefik" {
  source = "../terraform-demo-modules/traefik/k8s"

  namespace = kubernetes_namespace_v1.ai_workload_traefik.metadata[0].name

  enable_api_gateway    = true
  enable_ai_gateway     = true
  enable_mcp_gateway    = true
  enable_api_management = false
  traefik_hub_tag       = var.traefik_hub_tag
  traefik_chart_version = var.traefik_chart_version
  enable_offline_mode   = var.enable_offline_mode
  skip_gateway_api_crds = true

  replica_count     = 1
  traefik_hub_token = coalesce(var.ai_workload_hub_token, var.traefik_hub_token)

  log_level                    = "INFO"
  enable_otlp_access_logs      = false
  enable_otlp_application_logs = false
  enable_otlp_metrics          = true
  enable_otlp_traces           = true

  dashboard_entrypoints = ["websecure"]
  dashboard_match_rule  = "Host(`dashboard.${local.ai_domain}`)"

  multicluster_provider = {
    enabled = true
    children = {
      nkp-flight-ops = {
        address          = "https://${local.k3d_host}:9444"
        serversTransport = { insecureSkipVerify = true }
      }
      nkp-passenger-svc = {
        address          = "https://${local.k3d_host}:9445"
        serversTransport = { insecureSkipVerify = true }
      }
      nkp-airport-ops = {
        address          = "https://${local.k3d_host}:9446"
        serversTransport = { insecureSkipVerify = true }
      }
    }
  }

  custom_ports = {
    "flight-ops-mcp" = {
      port   = 9447
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
    "passenger-svc-mcp" = {
      port   = 9448
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
    "airport-ops-mcp" = {
      port   = 9449
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }

  custom_arguments = [
    "--hub.uplinkEntryPoints.flight-ops-mcp.address=:9447",
    "--hub.uplinkEntryPoints.flight-ops-mcp.http.tls=true",
    "--hub.uplinkEntryPoints.passenger-svc-mcp.address=:9448",
    "--hub.uplinkEntryPoints.passenger-svc-mcp.http.tls=true",
    "--hub.uplinkEntryPoints.airport-ops-mcp.address=:9449",
    "--hub.uplinkEntryPoints.airport-ops-mcp.http.tls=true",
  ]

  kubernetes_namespaces = [
    kubernetes_namespace_v1.ai_workload_traefik.metadata[0].name,
    kubernetes_namespace_v1.ai_workload_tools.metadata[0].name,
    "traefik-airlines",
  ]

  depends_on = [kubernetes_namespace_v1.ai_workload_traefik]

  providers = {
    kubernetes = kubernetes.ai_workload
    helm       = helm.ai_workload
  }
}

# ── MCP Inspector ─────────────────────────────────────────────────────────────
module "ai_workload_mcp_inspector" {
  source = "../terraform-demo-modules/tools/mcp-inspector/k8s"

  name      = "mcp-inspector"
  namespace = kubernetes_namespace_v1.ai_workload_tools.metadata[0].name

  ingress            = true
  ingress_domain     = local.ai_domain
  ingress_entrypoint = "websecure"

  depends_on = [kubernetes_namespace_v1.ai_workload_tools]

  providers = {
    kubernetes = kubernetes.ai_workload
    helm       = helm.ai_workload
  }
}

# ── Airlines (child) ──────────────────────────────────────────────────────────
resource "helm_release" "ai_workload_airlines" {
  provider         = helm.ai_workload
  name             = "airlines"
  namespace        = "traefik-airlines"
  create_namespace = false

  chart = "${path.module}/../traefik-demo-resources/airlines/helm"

  values = [
    yamlencode({
      global = {
        domain = local.ai_domain
        multicluster = {
          enabled = true
          mode    = "child"
          child = {
            groups = {
              flightOpsMcp    = true
              passengerSvcMcp = true
              airportOpsMcp   = true
            }
            mcp = {
              base       = "http://traefik.traefik.svc.cluster.local"
              entryPoint = "web"
              groups = {
                flightOps    = "flight-ops@multicluster"
                passengerSvc = "passenger-svc@multicluster"
                airportOps   = "airport-ops@multicluster"
              }
            }
          }
        }
      }
      hoppscotch = { enabled = false }
      keycloak   = { enabled = false }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.ai_workload_airlines,
    module.ai_workload_traefik,
  ]
}
