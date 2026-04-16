# ── Image preseeding ──────────────────────────────────────────────────────────
# Pulls rate-limited / large container images to the local Docker daemon and
# imports them into the k3d clusters. Avoids Docker Hub rate limits during
# terraform apply and speeds up pod startup.
#
# Images are grouped per cluster based on what actually gets scheduled there.
# Only Docker Hub images (rate-limited) and the large Traefik Hub image are
# preseeded; ghcr.io / quay.io / registry.k8s.io images aren't rate-limited.
#
# Implementation note: Docker Desktop's containerd image store produces
# multi-arch OCI tarballs that `k3d image import` / `ctr import` can't
# validate (missing platform-specific digests). Workaround: `docker save
# --platform <os/arch>` to export a single-arch tarball, then `docker cp`
# + `ctr -n k8s.io image import` directly into the node's containerd.

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

locals {
  # Architecture to preseed. k3d nodes run the host arch (arm64 on Apple
  # Silicon, amd64 on Intel). Override via TF_VAR if needed.
  preseed_platform = "linux/${coalesce(var.preseed_arch, "arm64")}"

  preseed_script = <<-BASH
    set -euo pipefail
    CLUSTER="$1"
    shift
    NODE="k3d-$${CLUSTER}-server-0"
    PLATFORM="${local.preseed_platform}"
    for img in "$@"; do
      echo "[$${CLUSTER}] pulling $$img ($$PLATFORM)..."
      docker pull --platform "$$PLATFORM" "$$img"
      TAR="$$(mktemp -t k3d-preseed-XXXXXX.tar)"
      trap 'rm -f "$$TAR"' EXIT
      docker save --platform "$$PLATFORM" "$$img" -o "$$TAR"
      docker cp "$$TAR" "$$NODE:/tmp/preseed.tar"
      docker exec "$$NODE" ctr -n k8s.io image import /tmp/preseed.tar
      docker exec "$$NODE" rm -f /tmp/preseed.tar
      rm -f "$$TAR"
      trap - EXIT
    done
  BASH
}

resource "null_resource" "preseed_transit" {
  triggers = {
    cluster_id = module.transit_k3d.host
    images     = join(",", local.transit_images)
  }

  provisioner "local-exec" {
    command = "bash -c '${local.preseed_script}' _ transit ${join(" ", local.transit_images)}"
  }

  depends_on = [module.transit_k3d]
}

resource "null_resource" "preseed_app_workload" {
  triggers = {
    cluster_id = module.app_workload_k3d.host
    images     = join(",", local.app_workload_images)
  }

  provisioner "local-exec" {
    command = "bash -c '${local.preseed_script}' _ app-workload ${join(" ", local.app_workload_images)}"
  }

  depends_on = [module.app_workload_k3d]
}

resource "null_resource" "preseed_ai_workload" {
  triggers = {
    cluster_id = module.ai_workload_k3d.host
    images     = join(",", local.ai_workload_images)
  }

  provisioner "local-exec" {
    command = "bash -c '${local.preseed_script}' _ ai-workload ${join(" ", local.ai_workload_images)}"
  }

  depends_on = [module.ai_workload_k3d]
}
