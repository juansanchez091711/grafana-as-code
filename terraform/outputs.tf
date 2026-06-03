output "prometheus_datasource_uid" {
  description = "UID of the provisioned Prometheus datasource"
  value       = grafana_data_source.prometheus.uid
}

output "dashboard_urls" {
  description = "Grafana URLs for each provisioned dashboard"
  value = {
    for k, v in grafana_dashboard.from_json :
    k => "${var.grafana_url}/d/${jsondecode(v.config_json).uid}"
  }
}
