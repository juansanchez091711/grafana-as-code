variable "grafana_url" {
  description = "URL of the self-hosted Grafana instance"
  type        = string
}

variable "grafana_auth" {
  description = "Service account token or user:password for Grafana"
  type        = string
  sensitive   = true
}

variable "prometheus_url" {
  description = "URL of the Prometheus instance"
  type        = string
}

variable "dashboards_path" {
  description = "Path to the directory containing dashboard JSON files"
  type        = string
  default     = "../dashboards"
}
