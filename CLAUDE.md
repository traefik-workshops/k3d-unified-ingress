# CLAUDE.md — k3d-unified-ingress

## What This Project Is

Local multi-cluster Traefik Hub demo environment using k3d (k3s in Docker). Provisions 3 clusters via Terraform and deploys the airlines demo platform showcasing API gateway, AI gateway, MCP integration, and multicluster management.

**Owner**: Zaid (solo primary developer)

## Architecture: 3 K3D Clusters

| Cluster | Role | Ports (HTTP/HTTPS) | Purpose |
|---------|------|-------------------|---------|
| **transit** | Hub parent | 8080 / 8443 | Central gateway, observability, dashboards, API portal |
| **app-workload** | Hub child | 8081 / 8444 | Flight Ops, Passenger Svc, Airport Ops APIs |
| **ai-workload** | Hub child | 8082 / 8445 | MCP servers, AI Gateway |

Uplink ports: 9444–9446 (API groups), 9447–9449 (MCP groups), 9450 (AI gateway).

## Related Repositories

This repo is the Terraform orchestration layer. Two sibling repos provide shared modules and application resources:

- **`../terraform-demo-modules/`** — Reusable Terraform modules: compute providers (k3d, AWS, Azure, etc.), Traefik Helm deployment, observability stack (Grafana/Prometheus/Loki/Tempo/OTel), tools (Redis, PostgreSQL, ArgoCD, cert-manager), AI modules (Ollama, vector DBs), security (Keycloak, Cognito, EntraID).
- **`../traefik-demo-resources/`** — Helm charts for demo applications. **This is where the airlines demo lives** (`airlines/helm/` for manifests, `airlines/dashboard-app/` for frontends). Also contains charts for: ai-gateway, keycloak, hoppscotch, dns-traefiker, embeddings, presidio.

**When editing the airlines demo, work in `traefik-demo-resources`**, not this repo. This repo wires everything together via Terraform.

## Key Files in This Repo

- `main.tf` — Transit cluster: Traefik Hub parent, observability, airlines Helm release
- `app-workload.tf` — App workload cluster: child hub with API services
- `ai-workload.tf` — AI workload cluster: child hub with MCP servers
- `providers.tf` — Kubernetes/Helm provider config for all 3 clusters
- `variables.tf` / `outputs.tf` — Inputs and dashboard/service URLs
- `mkcert.tf` — TLS cert generation and per-cluster secret creation
- `terraform.tfvars` — Active config (gitignored)
- `terraform.tfvars.example` — Template for setup

## Airlines Demo (in traefik-demo-resources)

The airlines demo is the primary workload. It's a realistic airline platform with 3 domains:

### 9 Mock APIs (Scalar Mock Server + OpenAPI specs)
- **Flight Ops**: flights (v1 deprecated + v2), pricing, crew
- **Passenger Services**: bookings, passengers, notifications
- **Airport Ops**: checkin, baggage, gates

### 3 MCP Servers (Python FastMCP, 5 tools each)
- `flight-ops-mcp`, `passenger-svc-mcp`, `airport-ops-mcp`

### 4 Dashboards (React 19 + Vue 3 + Vite + TailwindCSS)
- **Flight Board** — Public, split-flap animation, real-time SSE
- **Flight Ops** — OIDC-protected (flight-ops group)
- **Passenger Services** — OIDC-protected (passenger-svc group)
- **Airport Operations** — OIDC-protected (airport-ops group)

### Auth (Keycloak OIDC)
Users: `admin`/`dispatcher`/`agent`/`handler`/`analyst`/`reader` — all password: `topsecretpassword`
Groups: flight-ops, passenger-svc, airport-ops, admins, demo, reader, tools

## Domain Structure

Base: `demo.traefik.localhost` (configurable via `domain` variable)

- `dashboard.demo.traefik.localhost:8443` — Transit Traefik dashboard
- `airlines.demo.traefik.localhost:8443` — Airlines landing
- `portal.airlines.demo.traefik.localhost:8443` — API Portal
- `board.airlines.demo.traefik.localhost:8443` — Flight Board (public)
- `flight-ops.airlines.demo.traefik.localhost:8443` — Flight Ops dashboard
- `passenger-svc.airlines.demo.traefik.localhost:8443` — Passenger Svc dashboard
- `airport-ops.airlines.demo.traefik.localhost:8443` — Airport Ops dashboard
- `test.demo.traefik.localhost:8443` — Hoppscotch API tester
- `mcp-inspector.ai.demo.traefik.localhost:8445` — MCP Inspector

## Prerequisites

```bash
brew install mkcert kubectl k3d terraform
mkcert -install  # One-time: adds local CA to system trust store
```

## Setup & Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set domain, traefik_hub_token, versions
terraform init
terraform apply
```

## Current Configuration

- Traefik Hub: `v3.20.0-rc.1`
- Chart: `v40.0.0-ea.3`
- Offline mode: enabled
- Domain: `demo.traefik.localhost`

## Development Conventions

- **Commit before new tasks** — Always commit all changes across all affected repos before starting a new task
- **Terraform**: Always run `terraform fmt` and `terraform validate` before committing
- **Helm**: Always run `helm lint` and `helm template` before committing chart changes
- **Follow existing patterns** — match naming, structure, and style already in the codebase
- Airlines Helm chart uses `_helpers.tpl` extensively for domain/routing/multicluster logic — understand the helpers before modifying templates
- Each API group (flight-ops, passenger-svc, airport-ops) follows the same template pattern: API ConfigMap → Mock Server Deployment → Service → IngressRoute → API/APIVersion CRDs
- Dashboard entries are separate Vite entry points in `dashboard-app/src/entries/`
- Helm chart publishes to `oci://ghcr.io/traefik-workshops/<chart>` via GitHub Actions on `v*` tags

## Testing with Hoppscotch (when clusters are up)

The airlines demo includes a Hoppscotch collection with two sections:

- **"Airlines APIs"** — Functional tests for all API endpoints (Flight Operations, Passenger Services, Airport Operations). These include test scripts that validate response status codes, headers (e.g. deprecation), and payload structure. **Always run these after making changes to APIs, routes, middlewares, or multicluster config.**
- **"Traefik Demo"** — Demo walkthroughs for API Gateway, AI Gateway, MCP Gateway, Agentic Gateway, and API Management features.

**Access**: `https://test.demo.traefik.localhost:8443/import?type=hoppscotch&url=/airlines/collection.json`

**When to run**: After `terraform apply` when clusters are up and pods are healthy. Run the "Airlines APIs" section to verify nothing is broken. Enrich the test collection with assertions for any new features added.

**Collection source**: `traefik-demo-resources/airlines/helm/templates/hoppscotch-collection.yaml`

## Preseeding container images

`preseed.tf` pulls rate-limited / large images to the local Docker daemon and imports them into each k3d cluster before Helm releases run. This avoids Docker Hub rate limits and speeds up `terraform apply`.

**When to update**: Whenever a chart change adds/bumps images, or a new subchart is enabled, regenerate the image lists.

**Discovery method** (run from `traefik-demo-resources/airlines/helm`):

```bash
# 1. Render the chart with the exact values Terraform passes (see main.tf /
#    app-workload.tf / ai-workload.tf helm_release blocks) and extract images:
helm template airlines . \
  --set global.domain=demo.traefik.localhost \
  --set global.port=8443 \
  --set global.multicluster.enabled=true \
  --set global.multicluster.mode=parent \
  --set aiGateway.enabled=true --set keycloak.enabled=true --set hoppscotch.enabled=true \
  2>&1 | grep -E "^\s+image:" | sort -u

# 2. helm template misses operator-managed dynamic images. Grep subchart
#    operator manifests for RELATED_IMAGE_* env vars or hardcoded refs:
grep -r "quay.io\|mcr.microsoft.com\|docker.io" \
  ../../keycloak/helm/templates/ ../../ai-gateway/helm/templates/
```

Do this for each cluster's actual value set (transit = parent + aiGateway/keycloak/hoppscotch enabled, aiGateway workloads delegated to ai-workload via `parent.groups.aiGateway`; app-workload = child + ops groups; ai-workload = child + mcp groups + aiGateway). Add new images to the correct list in `preseed.tf`.

## Tech Stack Summary

| Layer | Technology |
|-------|-----------|
| IaC | Terraform (k3d + kubernetes + helm providers) |
| Clusters | k3d (k3s in Docker) |
| Gateway | Traefik Hub (parent/child multicluster) |
| APIs | Scalar Mock Server with OpenAPI specs |
| MCP | Python FastMCP servers |
| Auth | Keycloak OIDC with JWT validation |
| Dashboards | React 19, Vue 3, Vite, TailwindCSS, Framer Motion |
| Observability | OpenTelemetry, Prometheus, Grafana, Loki, Tempo |
| TLS | mkcert (local CA, wildcard certs) |
| AI | Traefik Hub AI Gateway + MCP Gateway |
