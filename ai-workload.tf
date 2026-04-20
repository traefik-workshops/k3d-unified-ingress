locals {
  ai_domain = "ai.${var.domain}"
}

# ── Namespaces ────────────────────────────────────────────────────────────────
resource "kubernetes_namespace_v1" "ai_workload_traefik" {
  provider = kubernetes.ai_workload
  metadata { name = "traefik" }
}

resource "kubernetes_namespace_v1" "ai_workload_tools" {
  provider = kubernetes.ai_workload
  metadata { name = "traefik-tools" }
}

resource "kubernetes_namespace_v1" "ai_workload_airlines" {
  provider = kubernetes.ai_workload
  metadata { name = "traefik-airlines" }
}

# ── Traefik Hub (child) ───────────────────────────────────────────────────────
module "ai_workload_traefik" {
  source = "../terraform-demo-modules/traefik/k8s"

  namespace = kubernetes_namespace_v1.ai_workload_traefik.metadata[0].name

  enable_api_gateway      = true
  enable_ai_gateway       = true
  enable_mcp_gateway      = true
  enable_api_management   = false
  traefik_hub_tag         = var.traefik_hub_tag
  traefik_chart_version   = var.traefik_chart_version
  custom_image_registry   = local.hub_image_registry
  custom_image_repository = local.hub_image_repository
  custom_image_tag        = local.hub_image_tag
  enable_offline_mode     = var.enable_offline_mode
  skip_gateway_api_crds   = true

  replica_count     = 1
  traefik_hub_token = coalesce(var.ai_workload_hub_token, var.traefik_hub_token)

  log_level                    = "INFO"
  enable_otlp_access_logs      = true
  enable_otlp_application_logs = true
  enable_otlp_metrics          = true
  enable_otlp_traces           = true
  otlp_service_name            = "traefik-ai-workload"
  # Push OTLP to transit's collector exposed via ingress
  # (host.docker.internal:8443 via hostAliases -> Traefik on transit).
  otlp_address = "https://collector.${var.domain}:8443"

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
    "ai-gateway" = {
      port   = 9450
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
    "--hub.uplinkEntryPoints.ai-gateway.address=:9450",
    "--hub.uplinkEntryPoints.ai-gateway.http.tls=true",
  ]

  kubernetes_namespaces = [
    kubernetes_namespace_v1.ai_workload_traefik.metadata[0].name,
    kubernetes_namespace_v1.ai_workload_tools.metadata[0].name,
    "traefik-airlines",
  ]

  additional_volumes       = local.mkcert_volumes
  additional_volume_mounts = local.mkcert_volume_mounts

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
  provider          = helm.ai_workload
  name              = "airlines"
  namespace         = "traefik-airlines"
  create_namespace  = false
  dependency_update = true

  chart = "${path.module}/../traefik-demo-resources/airlines/helm"

  values = [
    yamlencode({
      global = {
        # User-facing URLs (OIDC issuer/redirect, dashboard hosts, portal
        # trustedUrls) are served by the parent on var.domain:8443. Use those
        # values here so the airlines chart renders correct URLs from the
        # child cluster — local.ai_domain is only for this cluster's own
        # Traefik dashboard, which is wired by the Traefik module.
        domain = var.domain
        port   = 8443
        multicluster = {
          enabled = true
          mode    = "child"
          child = {
            groups = {
              flightOpsMcp    = true
              passengerSvcMcp = true
              airportOpsMcp   = true
              aiGateway       = true
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
      aiGateway = {
        enabled = true
        apiKeys = {
          openai    = var.openai_api_key
          gemini    = var.gemini_api_key
          anthropic = var.anthropic_api_key
        }
        claudeMode = {
          anthropic = var.anthropic_claude_mode
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
