variable "traefik_hub_token" {
  type        = string
  sensitive   = true
  default     = null
  description = "Default Traefik Hub license token used by all clusters unless overridden"
}

variable "transit_hub_token" {
  type        = string
  sensitive   = true
  default     = null
  description = "Traefik Hub license token for the transit cluster (falls back to traefik_hub_token)"
}

variable "app_workload_hub_token" {
  type        = string
  sensitive   = true
  default     = null
  description = "Traefik Hub license token for the app-workload cluster (falls back to traefik_hub_token)"
}

variable "ai_workload_hub_token" {
  type        = string
  sensitive   = true
  default     = null
  description = "Traefik Hub license token for the ai-workload cluster (falls back to traefik_hub_token)"
}

variable "domain" {
  type    = string
  default = "demo.traefik.ai"
}

variable "traefik_hub_tag" {
  type        = string
  description = "Traefik Hub version tag"
  default     = "v3.20.0"
}

variable "traefik_chart_version" {
  type        = string
  description = "Traefik Helm chart version"
  default     = "40.0.0-ea.1"
}

variable "enable_offline_mode" {
  type        = bool
  description = "Enable Traefik Hub offline mode across all clusters"
  default     = false
}

variable "preseed_arch" {
  type        = string
  description = "Architecture for image preseed (arm64 on Apple Silicon, amd64 on Intel). Detected from uname if empty."
  default     = null
}
