locals {
  prometheus_port = 8889
  # host.k3d.internal resolves to the host machine from inside k3d clusters
  k3d_host = "host.k3d.internal"
}

module "transit_k3d" {
  source = "../terraform-demo-modules/compute/suse/k3d"

  cluster_name = "transit"
  ports = [
    { from = 80,  to = 8080 },
    { from = 443, to = 8443 },
  ]
}

# ── Namespaces ────────────────────────────────────────────────────────────────
resource "kubernetes_namespace_v1" "transit_traefik" {
  provider   = kubernetes.transit
  depends_on = [module.transit_k3d]
  metadata { name = "traefik" }
}

resource "kubernetes_namespace_v1" "transit_observability" {
  provider   = kubernetes.transit
  depends_on = [module.transit_k3d]
  metadata { name = "traefik-observability" }
}

resource "kubernetes_namespace_v1" "transit_apps" {
  provider   = kubernetes.transit
  depends_on = [module.transit_k3d]
  metadata { name = "apps" }
}

# ── Traefik Hub (parent) ──────────────────────────────────────────────────────
module "transit_traefik" {
  source = "../terraform-demo-modules/traefik/k8s"

  namespace = kubernetes_namespace_v1.transit_traefik.metadata[0].name

  enable_api_gateway    = true
  enable_ai_gateway     = true
  enable_mcp_gateway    = true
  enable_api_management = true
  traefik_hub_tag       = var.traefik_hub_tag
  traefik_chart_version = var.traefik_chart_version
  enable_offline_mode   = var.enable_offline_mode
  skip_gateway_api_crds = true
  enable_debug          = true

  replica_count     = 1
  traefik_hub_token = coalesce(var.transit_hub_token, var.traefik_hub_token)

  log_level                    = "INFO"
  enable_otlp_access_logs      = false
  enable_otlp_application_logs = false
  enable_otlp_metrics          = true
  enable_otlp_traces           = true

  dashboard_entrypoints = ["websecure"]
  dashboard_match_rule  = "Host(`dashboard.${var.domain}`)"

  multicluster_provider = {
    enabled      = true
    pollInterval = 5
    pollTimeout  = 5
    children = {
      app-workload = {
        address          = "https://${local.k3d_host}:9443"
        serversTransport = { insecureSkipVerify = true }
      }
      app-workload-flight-ops = {
        address          = "https://${local.k3d_host}:9444"
        serversTransport = { insecureSkipVerify = true }
      }
      app-workload-passenger-svc = {
        address          = "https://${local.k3d_host}:9445"
        serversTransport = { insecureSkipVerify = true }
      }
      app-workload-airport-ops = {
        address          = "https://${local.k3d_host}:9446"
        serversTransport = { insecureSkipVerify = true }
      }
      ai-workload-flight-ops-mcp = {
        address          = "https://${local.k3d_host}:9447"
        serversTransport = { insecureSkipVerify = true }
      }
      ai-workload-passenger-svc-mcp = {
        address          = "https://${local.k3d_host}:9448"
        serversTransport = { insecureSkipVerify = true }
      }
      ai-workload-airport-ops-mcp = {
        address          = "https://${local.k3d_host}:9449"
        serversTransport = { insecureSkipVerify = true }
      }
    }
  }

  kubernetes_namespaces = [
    kubernetes_namespace_v1.transit_traefik.metadata[0].name,
    kubernetes_namespace_v1.transit_observability.metadata[0].name,
    kubernetes_namespace_v1.transit_apps.metadata[0].name,
    "traefik-airlines",
  ]

  depends_on = [kubernetes_namespace_v1.transit_traefik]

  providers = {
    kubernetes = kubernetes.transit
    helm       = helm.transit
  }
}

# ── Observability ─────────────────────────────────────────────────────────────
module "transit_otel" {
  source = "../terraform-demo-modules/observability/opentelemetry/k8s"

  namespace         = kubernetes_namespace_v1.transit_observability.metadata[0].name
  enable_prometheus = true
  prometheus_port   = local.prometheus_port
  enable_loki       = true
  loki_endpoint     = "http://loki:3100/otlp/"
  enable_tempo      = true
  tempo_endpoint    = "http://tempo:4318"

  depends_on = [kubernetes_namespace_v1.transit_observability]

  providers = {
    kubernetes = kubernetes.transit
    helm       = helm.transit
  }
}

module "transit_grafana" {
  source = "../terraform-demo-modules/observability/grafana-stack/k8s"

  namespace          = kubernetes_namespace_v1.transit_observability.metadata[0].name
  metrics_host       = "opentelemetry-opentelemetry-collector"
  metrics_port       = local.prometheus_port
  ingress            = true
  ingress_domain     = var.domain
  ingress_entrypoint = "websecure"

  dashboards = {
    aigateway  = true
    mcpgateway = false
    apim       = false
  }

  depends_on = [kubernetes_namespace_v1.transit_observability]

  providers = {
    kubernetes = kubernetes.transit
    helm       = helm.transit
  }
}

# ── Airlines (parent) ─────────────────────────────────────────────────────────
resource "helm_release" "transit_airlines" {
  provider         = helm.transit
  name             = "airlines"
  namespace        = "traefik-airlines"
  create_namespace = true
  timeout          = 2400

  chart = "${path.module}/../traefik-demo-resources/airlines/helm"

  values = [
    yamlencode({
      global = {
        domain = var.domain
        port   = 8443
        multicluster = {
          enabled = true
          mode    = "parent"
          parent = {
            groups = {
              flightOps       = "app-workload-flight-ops"
              flightOpsMcp    = "ai-workload-flight-ops-mcp"
              passengerSvc    = "app-workload-passenger-svc"
              passengerSvcMcp = "ai-workload-passenger-svc-mcp"
              airportOps      = "app-workload-airport-ops"
              airportOpsMcp   = "ai-workload-airport-ops-mcp"
            }
          }
        }
      }
      aiGateway  = { enabled = true }
      hoppscotch = { enabled = true }
      keycloak   = { enabled = true }
    })
  ]

  depends_on = [module.transit_traefik]
}
