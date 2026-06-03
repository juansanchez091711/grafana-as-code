resource "grafana_data_source" "prometheus" {
  name       = "Prometheus"
  type       = "prometheus"
  url        = var.prometheus_url
  is_default = true

  json_data_encoded = jsonencode({
    httpMethod        = "POST"
    prometheusType    = "Prometheus"
    prometheusVersion = "2.44.0"
  })
}
