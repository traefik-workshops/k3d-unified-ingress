# Transit
output "transit_traefik_dashboard_url" {
  value = nonsensitive("https://dashboard.${var.domain}:8443")
}

output "transit_airlines_urls" {
  value = [
    nonsensitive("https://portal.airlines.${var.domain}:8443"),
    nonsensitive("https://flight-ops.airlines.${var.domain}:8443"),
    nonsensitive("https://passenger-svc.airlines.${var.domain}:8443"),
    nonsensitive("https://airport-ops.airlines.${var.domain}:8443"),
    nonsensitive("https://board.airlines.${var.domain}:8443"),
    nonsensitive("https://test.${var.domain}:8443/import?type=hoppscotch&url=/airlines/collection.json"),
  ]
}

# App-workload
output "app_workload_traefik_dashboard_url" {
  value = nonsensitive("https://dashboard.${local.app_domain}:8444")
}

# AI-workload
output "ai_workload_traefik_dashboard_url" {
  value = nonsensitive("https://dashboard.${local.ai_domain}:8445")
}
