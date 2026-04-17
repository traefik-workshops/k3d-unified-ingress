locals {
  app_domain = "app.${var.domain}"
}

# ── Namespaces ────────────────────────────────────────────────────────────────
resource "kubernetes_namespace_v1" "app_workload_traefik" {
  provider = kubernetes.app_workload
  metadata { name = "traefik" }
}

resource "kubernetes_namespace_v1" "app_workload_airlines" {
  provider = kubernetes.app_workload
  metadata { name = "traefik-airlines" }
}

# ── Traefik Hub (child) ───────────────────────────────────────────────────────
module "app_workload_traefik" {
  source = "../terraform-demo-modules/traefik/k8s"

  namespace = kubernetes_namespace_v1.app_workload_traefik.metadata[0].name

  enable_api_gateway    = true
  enable_ai_gateway     = false
  enable_mcp_gateway    = false
  enable_api_management = false
  traefik_hub_tag       = var.traefik_hub_tag
  traefik_chart_version = var.traefik_chart_version
  enable_offline_mode   = var.enable_offline_mode
  skip_gateway_api_crds = true

  replica_count     = 1
  traefik_hub_token = coalesce(var.app_workload_hub_token, var.traefik_hub_token)

  log_level                    = "INFO"
  enable_otlp_access_logs      = false
  enable_otlp_application_logs = false
  enable_otlp_metrics          = true
  enable_otlp_traces           = true

  dashboard_entrypoints = ["websecure"]
  dashboard_match_rule  = "Host(`dashboard.${local.app_domain}`)"

  multicluster_provider = { enabled = true }

  custom_ports = {
    "flight-ops" = {
      port   = 9444
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
    "passenger-svc" = {
      port   = 9445
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
    "airport-ops" = {
      port   = 9446
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }

  custom_arguments = [
    "--hub.uplinkEntryPoints.flight-ops.address=:9444",
    "--hub.uplinkEntryPoints.flight-ops.http.tls=true",
    "--hub.uplinkEntryPoints.passenger-svc.address=:9445",
    "--hub.uplinkEntryPoints.passenger-svc.http.tls=true",
    "--hub.uplinkEntryPoints.airport-ops.address=:9446",
    "--hub.uplinkEntryPoints.airport-ops.http.tls=true",
  ]

  kubernetes_namespaces = [
    kubernetes_namespace_v1.app_workload_traefik.metadata[0].name,
    "traefik-airlines",
  ]

  additional_volumes       = local.mkcert_volumes
  additional_volume_mounts = local.mkcert_volume_mounts

  depends_on = [kubernetes_namespace_v1.app_workload_traefik]

  providers = {
    kubernetes = kubernetes.app_workload
    helm       = helm.app_workload
  }
}

# ── Airlines (child) ──────────────────────────────────────────────────────────
resource "helm_release" "app_workload_airlines" {
  provider         = helm.app_workload
  name             = "airlines"
  namespace        = "traefik-airlines"
  create_namespace = false

  chart = "${path.module}/../traefik-demo-resources/airlines/helm"

  values = [
    yamlencode({
      global = {
        # User-facing URLs (OIDC issuer/redirect, dashboard hosts, portal
        # trustedUrls) are served by the parent on var.domain:8443. Use those
        # values here so the airlines chart renders correct URLs from the
        # child cluster — local.app_domain is only for this cluster's own
        # Traefik dashboard, which is wired by the Traefik module.
        domain = var.domain
        port   = 8443
        multicluster = {
          enabled = true
          mode    = "child"
          child = {
            groups = {
              flightOps    = true
              passengerSvc = true
              airportOps   = true
            }
          }
        }
      }
      hoppscotch = { enabled = false }
      keycloak   = { enabled = false }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.app_workload_airlines,
    module.app_workload_traefik,
  ]
}
