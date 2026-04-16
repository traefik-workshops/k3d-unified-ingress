# ── mkcert TLS ────────────────────────────────────────────────────────────────
# Generates a wildcard cert via mkcert and installs it as the default Traefik
# TLS certificate in all three clusters.
#
# Prerequisites:
#   brew install mkcert
#   mkcert -install   (one-time: adds the local CA to the system trust store)

# Resolve the mkcert CA root directory so we can mount it into k3d nodes.
# Resolve the Docker host gateway IP for hostAliases (must be a real IP, not a hostname).
data "external" "mkcert_caroot" {
  program = ["bash", "-c", "echo '{\"caroot\":\"'\"$(mkcert -CAROOT)\"'\"}'"]
}

data "external" "docker_host_ip" {
  program = ["bash", "-c", "echo '{\"ip\":\"'\"$(docker run --rm alpine getent hosts host.docker.internal | awk '{print $1}')\"'\"}'"]
}

locals {
  mkcert_ca_volume = "${data.external.mkcert_caroot.result.caroot}/rootCA.pem:/etc/ssl/certs/mkcert-ca.pem"

  # All *.domain subdomains that need to resolve to the host from inside k3d.
  # k3d's hostAliases injects these into /etc/hosts on nodes and CoreDNS.
  k3d_host_aliases = [{
    ip = data.external.docker_host_ip.result.ip
    hostnames = [
      var.domain,
      "keycloak.${var.domain}",
      "dashboard.${var.domain}",
      "airlines.${var.domain}",
      "portal.airlines.${var.domain}",
      "board.airlines.${var.domain}",
      "flight-ops.airlines.${var.domain}",
      "passenger-svc.airlines.${var.domain}",
      "airport-ops.airlines.${var.domain}",
      "test.${var.domain}",
      "grafana.${var.domain}",
    ]
  }]
}

resource "null_resource" "mkcert_cert" {
  triggers = {
    domain = var.domain
  }

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/mkcert && mkcert -cert-file ${path.module}/mkcert/cert.pem -key-file ${path.module}/mkcert/key.pem '*.${var.domain}' '${var.domain}' '*.app.${var.domain}' 'app.${var.domain}' '*.ai.${var.domain}' 'ai.${var.domain}' '*.airlines.${var.domain}' 'airlines.${var.domain}'"
  }
}

# ── Per-cluster kubeconfigs (built from module outputs) ───────────────────────

locals {
  kubeconfig_dir = "${path.module}/mkcert"

  kubeconfig_transit = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "transit"
    clusters = [{
      name = "transit"
      cluster = {
        server                     = module.transit_k3d.host
        certificate-authority-data = base64encode(module.transit_k3d.cluster_ca_certificate)
      }
    }]
    users = [{
      name = "transit"
      user = {
        client-certificate-data = base64encode(module.transit_k3d.client_certificate)
        client-key-data         = base64encode(module.transit_k3d.client_key)
      }
    }]
    contexts = [{
      name    = "transit"
      context = { cluster = "transit", user = "transit" }
    }]
  })

  kubeconfig_app_workload = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "app-workload"
    clusters = [{
      name = "app-workload"
      cluster = {
        server                     = module.app_workload_k3d.host
        certificate-authority-data = base64encode(module.app_workload_k3d.cluster_ca_certificate)
      }
    }]
    users = [{
      name = "app-workload"
      user = {
        client-certificate-data = base64encode(module.app_workload_k3d.client_certificate)
        client-key-data         = base64encode(module.app_workload_k3d.client_key)
      }
    }]
    contexts = [{
      name    = "app-workload"
      context = { cluster = "app-workload", user = "app-workload" }
    }]
  })

  kubeconfig_ai_workload = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "ai-workload"
    clusters = [{
      name = "ai-workload"
      cluster = {
        server                     = module.ai_workload_k3d.host
        certificate-authority-data = base64encode(module.ai_workload_k3d.cluster_ca_certificate)
      }
    }]
    users = [{
      name = "ai-workload"
      user = {
        client-certificate-data = base64encode(module.ai_workload_k3d.client_certificate)
        client-key-data         = base64encode(module.ai_workload_k3d.client_key)
      }
    }]
    contexts = [{
      name    = "ai-workload"
      context = { cluster = "ai-workload", user = "ai-workload" }
    }]
  })
}

resource "local_sensitive_file" "kubeconfig_transit" {
  filename = "${local.kubeconfig_dir}/kubeconfig-transit.yaml"
  content  = local.kubeconfig_transit
}

resource "local_sensitive_file" "kubeconfig_app_workload" {
  filename = "${local.kubeconfig_dir}/kubeconfig-app-workload.yaml"
  content  = local.kubeconfig_app_workload
}

resource "local_sensitive_file" "kubeconfig_ai_workload" {
  filename = "${local.kubeconfig_dir}/kubeconfig-ai-workload.yaml"
  content  = local.kubeconfig_ai_workload
}

# ── Per-cluster TLS secret + TLSStore ─────────────────────────────────────────

locals {
  tlsstore_manifest = <<-MANIFEST
apiVersion: traefik.io/v1alpha1
kind: TLSStore
metadata:
  name: default
  namespace: traefik
spec:
  defaultCertificate:
    secretName: mkcert-tls
MANIFEST
}

resource "null_resource" "mkcert_transit" {
  triggers = { domain = var.domain }

  provisioner "local-exec" {
    command = <<-EOT
      docker exec k3d-transit-server-0 sh -c 'cat /etc/ssl/certs/mkcert-ca.pem >> /etc/ssl/certs/ca-certificates.crt'
      kubectl --kubeconfig=${local_sensitive_file.kubeconfig_transit.filename} -n traefik create secret tls mkcert-tls \
        --cert=${path.module}/mkcert/cert.pem \
        --key=${path.module}/mkcert/key.pem \
        --dry-run=client -o yaml | kubectl --kubeconfig=${local_sensitive_file.kubeconfig_transit.filename} apply -f -
      echo '${local.tlsstore_manifest}' | kubectl --kubeconfig=${local_sensitive_file.kubeconfig_transit.filename} apply -f -
    EOT
  }

  depends_on = [null_resource.mkcert_cert, local_sensitive_file.kubeconfig_transit, module.transit_traefik]
}

resource "null_resource" "mkcert_app_workload" {
  triggers = { domain = var.domain }

  provisioner "local-exec" {
    command = <<-EOT
      docker exec k3d-app-workload-server-0 sh -c 'cat /etc/ssl/certs/mkcert-ca.pem >> /etc/ssl/certs/ca-certificates.crt'
      kubectl --kubeconfig=${local_sensitive_file.kubeconfig_app_workload.filename} -n traefik create secret tls mkcert-tls \
        --cert=${path.module}/mkcert/cert.pem \
        --key=${path.module}/mkcert/key.pem \
        --dry-run=client -o yaml | kubectl --kubeconfig=${local_sensitive_file.kubeconfig_app_workload.filename} apply -f -
      echo '${local.tlsstore_manifest}' | kubectl --kubeconfig=${local_sensitive_file.kubeconfig_app_workload.filename} apply -f -
    EOT
  }

  depends_on = [null_resource.mkcert_cert, local_sensitive_file.kubeconfig_app_workload, module.app_workload_traefik]
}

resource "null_resource" "mkcert_ai_workload" {
  triggers = { domain = var.domain }

  provisioner "local-exec" {
    command = <<-EOT
      docker exec k3d-ai-workload-server-0 sh -c 'cat /etc/ssl/certs/mkcert-ca.pem >> /etc/ssl/certs/ca-certificates.crt'
      kubectl --kubeconfig=${local_sensitive_file.kubeconfig_ai_workload.filename} -n traefik create secret tls mkcert-tls \
        --cert=${path.module}/mkcert/cert.pem \
        --key=${path.module}/mkcert/key.pem \
        --dry-run=client -o yaml | kubectl --kubeconfig=${local_sensitive_file.kubeconfig_ai_workload.filename} apply -f -
      echo '${local.tlsstore_manifest}' | kubectl --kubeconfig=${local_sensitive_file.kubeconfig_ai_workload.filename} apply -f -
    EOT
  }

  depends_on = [null_resource.mkcert_cert, local_sensitive_file.kubeconfig_ai_workload, module.ai_workload_traefik]
}
