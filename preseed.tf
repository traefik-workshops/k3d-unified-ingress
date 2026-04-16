# ── Image preseeding ──────────────────────────────────────────────────────────
# Pulls rate-limited / large container images to the local Docker daemon and
# imports them into the k3d clusters. Avoids Docker Hub rate limits during
# terraform apply and speeds up pod startup.
#
# Images are grouped per cluster based on what actually gets scheduled there.
# Only Docker Hub images (rate-limited) and the large Traefik Hub image are
# preseeded; ghcr.io / quay.io / registry.k8s.io images aren't rate-limited.

locals {
  # Traefik Hub: pulled by all 3 clusters. Tag follows var.traefik_hub_tag.
  traefik_hub_image = "ghcr.io/traefik/traefik-hub:${var.traefik_hub_tag}"

  # Transit-only: observability stack + API management + airlines subcharts
  # (keycloak, hoppscotch, ai-gateway/presidio — enabled on parent only).
  # Discovery: `helm template` airlines chart with transit's values +
  # grep operator.yaml for RELATED_IMAGE_* env vars (operators pull extras).
  transit_images = [
    # Observability stack
    "docker.io/grafana/grafana:12.1.1",
    "docker.io/grafana/loki:3.5.5",
    "docker.io/kiwigrid/k8s-sidecar:1.30.10",
    "docker.io/redis:8.2.1",
    "grafana/tempo:2.8.2",
    "memcached:1.6.39-alpine",
    "otel/opentelemetry-collector-contrib:latest",
    "prom/memcached-exporter:v0.15.3",
    # Keycloak (operator + dynamically-pulled server image)
    "quay.io/keycloak/keycloak-operator:26.5.2",
    "quay.io/keycloak/keycloak:26.5.2",
    "postgres:15-alpine",
    "bitnami/kubectl:latest",
    # Hoppscotch API tester
    "hoppscotch/hoppscotch:2026.2.0",
    "postgres:16-alpine",
    # AI Gateway subcharts
    "mcr.microsoft.com/presidio-analyzer:2.2.358",
    # Traefik Hub
    local.traefik_hub_image,
  ]

  # App-workload: airlines API services (python) + dashboards (node build, nginx serve).
  app_workload_images = [
    "python:3.11-slim",
    "node:20-alpine",
    "nginx:alpine",
    local.traefik_hub_image,
  ]

  # AI-workload: MCP servers (python).
  ai_workload_images = [
    "python:3.11-slim",
    local.traefik_hub_image,
  ]
}

resource "null_resource" "preseed_transit" {
  triggers = {
    images = join(",", local.transit_images)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      for img in ${join(" ", local.transit_images)}; do
        echo "Pulling $img..."
        docker pull "$img"
        echo "Importing $img into k3d-transit..."
        k3d image import "$img" -c transit
      done
    EOT
  }

  depends_on = [module.transit_k3d]
}

resource "null_resource" "preseed_app_workload" {
  triggers = {
    images = join(",", local.app_workload_images)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      for img in ${join(" ", local.app_workload_images)}; do
        echo "Pulling $img..."
        docker pull "$img"
        echo "Importing $img into k3d-app-workload..."
        k3d image import "$img" -c app-workload
      done
    EOT
  }

  depends_on = [module.app_workload_k3d]
}

resource "null_resource" "preseed_ai_workload" {
  triggers = {
    images = join(",", local.ai_workload_images)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      for img in ${join(" ", local.ai_workload_images)}; do
        echo "Pulling $img..."
        docker pull "$img"
        echo "Importing $img into k3d-ai-workload..."
        k3d image import "$img" -c ai-workload
      done
    EOT
  }

  depends_on = [module.ai_workload_k3d]
}
