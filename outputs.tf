# ── Traefik dashboards (per cluster) ─────────────────────────────────────────
output "transit_traefik_dashboard_url" {
  value = nonsensitive("https://dashboard.${var.domain}:8443")
}

output "app_workload_traefik_dashboard_url" {
  value = nonsensitive("https://dashboard.${local.app_domain}:8444")
}

output "ai_workload_traefik_dashboard_url" {
  value = nonsensitive("https://dashboard.${local.ai_domain}:8445")
}

# ── Airlines demo (all served via the transit parent on :8443) ───────────────
output "airlines_portal_url" {
  value = nonsensitive("https://portal.airlines.${var.domain}:8443")
}

output "airlines_dashboard_urls" {
  description = "Airlines demo dashboards (board is public; the rest are OIDC-protected)"
  value = {
    flight_board  = nonsensitive("https://board.airlines.${var.domain}:8443")
    flight_ops    = nonsensitive("https://flight-ops.airlines.${var.domain}:8443")
    passenger_svc = nonsensitive("https://passenger-svc.airlines.${var.domain}:8443")
    airport_ops   = nonsensitive("https://airport-ops.airlines.${var.domain}:8443")
  }
}

output "ai_gateway_urls" {
  description = "AI gateway endpoints (served via transit, workloads run on ai-workload)"
  value = {
    gemini = nonsensitive("https://gemini.${var.domain}:8443")
    openai = nonsensitive("https://openai.${var.domain}:8443")
  }
}

output "hoppscotch_url" {
  value = nonsensitive("https://test.${var.domain}:8443/import?type=hoppscotch&url=/airlines/collection.json")
}

# ── Tools ────────────────────────────────────────────────────────────────────
output "mcp_inspector_url" {
  description = "MCP Inspector (deployed on ai-workload)"
  value       = nonsensitive("https://mcp-inspector.${local.ai_domain}:8445")
}

# ── Auth ─────────────────────────────────────────────────────────────────────
output "keycloak_url" {
  description = "Keycloak (used as OIDC provider for airlines dashboards and portal)"
  value       = nonsensitive("https://keycloak.${var.domain}:8443")
}
