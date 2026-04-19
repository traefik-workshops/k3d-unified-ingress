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

variable "local_traefik_hub" {
  type        = bool
  description = "Use locally-built traefik-hub image from localhost:5001/traefik/traefik-hub:dev instead of upstream. Run `make build-hub` first."
  default     = false
}

variable "openai_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "OpenAI API key for the ai-gateway openai endpoint (aiGateway.apiKeys.openai)"
}

variable "gemini_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Google Gemini API key for the ai-gateway gemini endpoint (aiGateway.apiKeys.gemini)"
}

variable "anthropic_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Anthropic API key for the ai-gateway anthropic endpoint (aiGateway.apiKeys.anthropic)"
}

variable "anthropic_claude_mode" {
  type        = bool
  default     = false
  description = "When true, the messages-api plugin on the anthropic endpoint omits the token so a client-supplied `Authorization: Bearer …` (e.g. Claude Code Max-plan OAuth) reaches api.anthropic.com untouched."
}

locals {
  hub_image_registry   = var.local_traefik_hub ? "localhost:5001" : ""
  hub_image_repository = var.local_traefik_hub ? "traefik/traefik-hub" : ""
  hub_image_tag        = var.local_traefik_hub ? "dev" : ""
}

