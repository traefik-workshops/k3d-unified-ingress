# ── Registry ───────────────────────────────────────────────────────────────────
# Plain Docker registry (no proxy). Local Docker is the source of truth —
# `make sync` mirrors your local images into this registry, then the clusters
# pull from it. Persistent named volume keeps the cache across container
# restarts; only `make clean-registry` wipes it.
#
# Containerd on each k3d node mirrors docker.io → this registry. Non-docker.io
# images (ghcr.io, quay.io, mcr.microsoft.com) are fetched directly from
# upstream since they don't rate-limit.
#
# To wipe cache:
#   docker rm -f k3d-registry-mirror && docker volume rm k3d-registry-mirror-data

locals {
  registry_mirror_name      = "registry-mirror"
  registry_mirror_container = "k3d-${local.registry_mirror_name}"
  registries_yaml           = <<-YAML
    mirrors:
      "docker.io":
        endpoint:
          - http://${local.registry_mirror_container}:5000
  YAML
}

resource "null_resource" "registry_mirror" {
  triggers = {
    name = local.registry_mirror_container
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -e
      NAME="${local.registry_mirror_container}"
      VOLUME="$${NAME}-data"

      if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
        echo "Registry mirror already exists: $NAME (leave intact to preserve cache)"
        exit 0
      fi

      docker volume create "$VOLUME" >/dev/null

      # Use `k3d registry create` so the container carries the k3d labels
      # that `registries.use` in each cluster's config looks for. We still
      # get our persistent volume via the -v flag.
      k3d registry create ${local.registry_mirror_name} \
        --port 0.0.0.0:5001 \
        -v "$VOLUME:/var/lib/registry"
    EOT
  }
}
