# k3d Unified Ingress

Local multi-cluster Traefik Hub environment using k3d (k3s in Docker).

## Clusters

| Cluster | Role | HTTP | HTTPS | Uplink ports |
|---|---|---|---|---|
| `transit` | Hub parent | 8080 | 8443 | — |
| `app-workload` | Hub child (APIs) | 8081 | 8444 | 9444–9446 |
| `ai-workload` | Hub child (AI/MCP) | 8082 | 8445 | 9447–9449 |

## Prerequisites

### Tools

```bash
brew install mkcert kubectl k3d terraform
```

### Trust the local CA (one-time)

```bash
mkcert -install
```

This adds mkcert's local CA to your system and browser trust stores. Only needs to be done once per machine.

## Usage

1. Copy and fill in variables:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Apply:

```bash
terraform init
terraform apply
```

Terraform will:
- Spin up three k3d clusters
- Deploy Traefik Hub in parent/child mode
- Generate a wildcard mkcert cert for your domain and install it as the default TLS cert in all clusters
- Deploy the Airlines demo app and observability stack on transit

## Variables

| Variable | Description | Default |
|---|---|---|
| `domain` | Base domain | `demo.traefik.ai` |
| `traefik_hub_token` | Shared Hub token (fallback) | — |
| `transit_hub_token` | Hub token for transit (optional) | — |
| `app_workload_hub_token` | Hub token for app-workload (optional) | — |
| `ai_workload_hub_token` | Hub token for ai-workload (optional) | — |
| `enable_offline_mode` | Traefik Hub offline mode | `false` |

## TLS

Certificates are generated via `mkcert` at apply time and stored in `./mkcert/` (gitignored). The wildcard cert covers `*.domain` and `domain`. Traefik in each cluster is configured with a `TLSStore` pointing to the cert, so all HTTPS routes use it by default — no browser warnings after `mkcert -install`.

## Destroy

```bash
terraform destroy
```

k3d clusters are deleted automatically. The `./mkcert/` cert files remain locally; re-running `apply` regenerates them if the domain changes.
