#!/usr/bin/env bash
# sync-from-registry.sh — Pull images from the registry mirror into the
# local Docker daemon. Useful if the cache has images local Docker lost
# (e.g. after `docker image prune`).
#
# Prereq:  brew install skopeo

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
  exit 1
fi

pull_one() {
  local img="$1"
  local path="${img#docker.io/}"
  echo "[pull] ${REGISTRY_HOST}/${path} -> local docker"
  skopeo copy \
    --src-tls-verify=false \
    "docker://${REGISTRY_HOST}/${path}" \
    "docker-daemon:${img}" >/dev/null
}

mapfile -t IMAGES < <(grep -vE '^\s*(#|$)' "$IMAGES_FILE")

echo "Pulling ${#IMAGES[@]} images from ${REGISTRY_HOST}..."
for img in "${IMAGES[@]}"; do
  pull_one "$img"
done
echo "Done."
