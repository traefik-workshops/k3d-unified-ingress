# k3d-unified-ingress
#
# Two-stage Terraform setup:
#   1. bootstrap/ — k3d clusters, mkcert wildcard cert, registry mirror,
#                   per-cluster kubeconfig files. Owns its own state.
#   2. .         — namespaces, Traefik Hub, observability, airlines demo.
#                   Reads cluster credentials from bootstrap's state via
#                   data.terraform_remote_state.
#
# The split exists because Terraform providers can't depend on resources that
# are themselves being replaced in the same apply (e.g. when k3d cluster ports
# change). Bootstrap runs first; root reads its outputs.
#
# Quick start:
#   make up        # bootstrap + apply
#   make plan      # preview root changes
#   make down      # destroy root + bootstrap
#   make nuke      # last-resort: wipe state + clusters + registry + kubeconfigs
#
# One-time setup:  brew install skopeo terraform k3d kubectl mkcert

SHELL := /bin/bash
BOOTSTRAP_DIR := bootstrap

# Extract `domain` from root's terraform.tfvars and pass it to bootstrap so
# both workspaces agree on the domain (k3d hostAliases, mkcert SANs, etc.).
# Falls back to bootstrap's default if terraform.tfvars is missing.
DOMAIN := $(shell awk -F'=' '/^[[:space:]]*domain[[:space:]]*=/ {gsub(/[[:space:]"]/,"",$$2); print $$2; exit}' terraform.tfvars 2>/dev/null)
BOOTSTRAP_VAR_ARGS := $(if $(DOMAIN),-var=domain=$(DOMAIN))

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# ── Bootstrap (clusters + mkcert + registry) ─────────────────────────────────
.PHONY: bootstrap-init bootstrap-plan bootstrap bootstrap-destroy
bootstrap-init: ## terraform init in bootstrap/
	terraform -chdir=$(BOOTSTRAP_DIR) init

bootstrap-plan: bootstrap-init ## terraform plan in bootstrap/
	terraform -chdir=$(BOOTSTRAP_DIR) plan $(BOOTSTRAP_VAR_ARGS)

bootstrap: bootstrap-init ## Apply bootstrap (creates clusters, mkcert cert, registry, kubeconfigs)
	terraform -chdir=$(BOOTSTRAP_DIR) apply -auto-approve $(BOOTSTRAP_VAR_ARGS)

bootstrap-destroy: ## Destroy clusters, registry, kubeconfigs
	terraform -chdir=$(BOOTSTRAP_DIR) destroy -auto-approve $(BOOTSTRAP_VAR_ARGS)

# ── Root (namespaces, Traefik, airlines) ─────────────────────────────────────
.PHONY: init plan apply destroy
init: ## terraform init in root
	terraform init

plan: init ## terraform plan in root (requires bootstrap state)
	terraform plan

apply: init sync ## Apply root (Traefik, airlines, observability). Runs sync first.
	terraform apply -auto-approve

destroy: ## Destroy root resources only (leaves clusters intact)
	terraform destroy -auto-approve

# ── Combined flows ───────────────────────────────────────────────────────────
.PHONY: up down nuke
up: bootstrap apply ## Full bring-up: bootstrap then apply

down: destroy bootstrap-destroy ## Full tear-down: destroy root then bootstrap

nuke: ## Last resort: wipe state + clusters + registry + kubeconfigs
	-terraform destroy -auto-approve
	-terraform -chdir=$(BOOTSTRAP_DIR) destroy -auto-approve
	-k3d cluster delete transit app-workload ai-workload
	-k3d registry delete k3d-registry-mirror
	-rm -rf $(BOOTSTRAP_DIR)/mkcert
	-rm -f terraform.tfstate terraform.tfstate.backup
	-rm -f $(BOOTSTRAP_DIR)/terraform.tfstate $(BOOTSTRAP_DIR)/terraform.tfstate.backup

# ── Registry / image sync ────────────────────────────────────────────────────
.PHONY: sync sync-to-registry sync-from-registry clean-registry
sync: bootstrap sync-to-registry ## Push local Docker images to the bootstrap registry

sync-to-registry: ## Mirror local Docker images -> registry (preserves digests)
	./$(BOOTSTRAP_DIR)/scripts/sync-to-registry.sh

sync-from-registry: ## Pull registry images -> local Docker
	./$(BOOTSTRAP_DIR)/scripts/sync-from-registry.sh

clean-registry: ## Delete registry container AND cache volume (wipes cache)
	@echo "This will wipe the image cache. Ctrl-C to abort, Enter to continue."
	@read _
	-docker rm -f k3d-registry-mirror
	-docker volume rm k3d-registry-mirror-data

# ── Housekeeping ─────────────────────────────────────────────────────────────
.PHONY: fmt validate
fmt: ## terraform fmt in both workspaces
	terraform fmt
	terraform -chdir=$(BOOTSTRAP_DIR) fmt

validate: bootstrap-init init ## terraform validate in both workspaces
	terraform -chdir=$(BOOTSTRAP_DIR) validate
	terraform validate
