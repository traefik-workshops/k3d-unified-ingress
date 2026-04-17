# k3d-unified-ingress
#
# Primary interface for managing the 3-cluster demo. Usage:
#   make apply     # full stack up (registry + sync + terraform apply)
#   make destroy   # tear down clusters (registry + cache persist)
#   make sync      # dump local Docker images into the registry cache
#   make plan      # preview changes
#   make registry  # start the registry container only
#
# One-time setup:  brew install skopeo terraform k3d kubectl mkcert

SHELL := /bin/bash

.PHONY: apply destroy plan sync sync-to-registry sync-from-registry \
        registry clean-registry fmt validate help

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  %-22s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# ── Lifecycle ─────────────────────────────────────────────────────────────────

apply: registry sync ## Start registry, sync local images, apply Terraform
	terraform apply -auto-approve

plan: ## Preview Terraform changes
	terraform plan

destroy: ## Destroy clusters (registry + cache persist)
	terraform destroy -auto-approve

# ── Registry / image sync ─────────────────────────────────────────────────────

registry: ## Create the registry container (idempotent)
	terraform apply -auto-approve -target=null_resource.registry_mirror

sync: registry sync-to-registry ## Push local Docker images to the registry

sync-to-registry: ## Mirror local Docker images -> registry (preserves digests)
	./scripts/sync-to-registry.sh

sync-from-registry: ## Pull registry images -> local Docker
	./scripts/sync-from-registry.sh

clean-registry: ## Delete registry container AND cache volume (wipes cache)
	@echo "This will wipe the image cache. Ctrl-C to abort, Enter to continue."
	@read _
	-docker rm -f k3d-registry-mirror
	-docker volume rm k3d-registry-mirror-data

# ── Housekeeping ──────────────────────────────────────────────────────────────

fmt: ## Run terraform fmt recursively
	terraform fmt -recursive .

validate: ## terraform validate
	terraform validate
