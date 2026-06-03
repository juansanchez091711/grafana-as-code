# Discovers every *.json file inside the dashboards directory at plan time.
locals {
  dashboard_files = fileset(var.dashboards_path, "*.json")
}

resource "grafana_dashboard" "from_json" {
  for_each = local.dashboard_files

  config_json = file("${var.dashboards_path}/${each.value}")

  # Re-create the dashboard when the JSON changes instead of updating in place,
  # which avoids Grafana version-mismatch errors on partial updates.
  lifecycle {
    create_before_destroy = true
  }
}
