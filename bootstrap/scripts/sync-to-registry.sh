#!/usr/bin/env bash
# sync-to-registry.sh — Copy Docker Hub images from the local Docker daemon
# into the local k3d registry mirror. Uses skopeo so multi-arch manifests
# and digests are preserved (docker push re-serializes manifests and changes
# digests, breaking digest-pinned images like redis).
#
# Prereq:  brew install skopeo
#
# Flow per image:
#   1. If not in local Docker, `docker pull` it (so local Docker is a true
#      superset of what's needed).
#   2. `skopeo copy docker-daemon:<img> docker://<registry>/<path>:<tag>`
#      preserves the manifest bytes exactly.
#
# Run this whenever images.txt changes or after you pull new images locally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_FILE="${SCRIPT_DIR}/images.txt"
REGISTRY_HOST="localhost:5001"
REGISTRY_CONTAINER="k3d-registry-mirror"

if ! command -v skopeo >/dev/null 2>&1; then
  echo "ERROR: skopeo not found. Install with: brew install skopeo" >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$REGISTRY_CONTAINER"; then
  echo "ERROR: registry container '$REGISTRY_CONTAINER' is not running." >&2
  echo "Run 'make registry' or 'terraform apply -target=null_resource.registry_mirror' first." >&2
  exit 1
fi

sync_one() {
  local img="$1"
  # Strip leading "docker.io/" for the local tag path. Keep the rest.
  local path="${img#docker.io/}"

  # Pull into local Docker if missing (local Docker = source of truth).
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    echo "[pull] $img (not in local Docker)"
    docker pull "$img" >/dev/null
  fi

  # skopeo reads the manifest from the daemon and pushes it byte-for-byte.
  # --dest-tls-verify=false because the registry runs HTTP.
  echo "[push] $img -> ${REGISTRY_HOST}/${path}"
  skopeo copy \
    --dest-tls-verify=false \
    "docker-daemon:${img}" \
    "docker://${REGISTRY_HOST}/${path}" >/dev/null
}

# Read the image list, strip comments/blanks.
mapfile -t IMAGES < <(grep -vE '^\s*(#|$)' "$IMAGES_FILE")

echo "Syncing ${#IMAGES[@]} images to ${REGISTRY_HOST}..."
for img in "${IMAGES[@]}"; do
  sync_one "$img"
done
echo "Done."
