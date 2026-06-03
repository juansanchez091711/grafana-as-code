# Grafana as Code

Centralized Terraform configuration for managing Grafana dashboards and datasources across multiple projects using GitHub Actions reusable workflows.

## Architecture

```
grafana-as-code/                        # This repo — Terraform config only
├── terraform/
│   ├── providers.tf
│   ├── variables.tf
│   ├── datasources.tf
│   ├── dashboards.tf
│   └── outputs.tf
└── .github/workflows/
    ├── terraform.yml                   # Infra changes (datasources, provider)
    └── deploy-dashboard.yml            # Reusable workflow — called by source repos

api-auth/                               # Source repo example
├── grafana/
│   └── dashboard.json
└── .github/workflows/
    └── grafana.yml                     # Calls deploy-dashboard.yml
```

Each project owns its dashboard. This repo only holds the Terraform configuration. Dashboards are never committed here — they are passed at runtime by each source repo.

## How it works

```
api-auth push to main
  → encode: reads grafana/dashboard.json → base64
  → deploy: calls grafana-as-code/deploy-dashboard.yml
              → checkout grafana-as-code (Terraform only)
              → writes JSON to /tmp/dashboards/ on the runner
              → terraform apply -target only that dashboard
              → dashboard live in Grafana ✓
```

## Prerequisites

- Self-hosted Grafana (Linux or Kubernetes) reachable from the GitHub Actions runner
- Prometheus instance reachable from Grafana (can be an internal/cluster URL)
- Terraform >= 1.5.0

## Setup

### 1. Grafana service account

```
Administration → Service accounts → Add service account
  Role: Admin
  → Add service account token → copy the glsa_xxx value
```

### 2. GitHub secrets

Configure these secrets wherever your workflows run. Using **organization secrets** is recommended so every project repo inherits them automatically.

| Secret | Description | Example |
|---|---|---|
| `GRAFANA_URL` | Grafana instance URL | `http://grafana.example.com` |
| `GRAFANA_AUTH` | Service account token | `glsa_xxxxxxxxxxxx` |
| `PROMETHEUS_URL` | Prometheus URL (can be internal) | `http://prometheus.monitoring.svc.cluster.local:9090` |

> `PROMETHEUS_URL` is resolved by Grafana, not by GitHub Actions — internal Kubernetes URLs work fine.
> `GRAFANA_URL` is resolved by Terraform from the runner. If Grafana is on a private network, use a self-hosted runner inside that network.

**Organization secrets:**
```
GitHub Org → Settings → Secrets and variables → Actions → New organization secret
```

**Per-repo secrets:**
```
Repo → Settings → Secrets and variables → Actions → New repository secret
```

### 3. GitHub environment (optional)

Create a `grafana` environment to add manual approval before apply:
```
grafana-as-code repo → Settings → Environments → New environment → grafana
```

## Adding a new project

1. Create a `grafana/` folder in the project repo
2. Add `dashboard.json` with a unique `uid`
3. Add the workflow file

```yaml
# .github/workflows/grafana.yml
name: Deploy Grafana Dashboard

on:
  push:
    branches: [main]
    paths:
      - "grafana/**"
  workflow_dispatch:

jobs:
  encode:
    runs-on: ubuntu-latest
    outputs:
      json: ${{ steps.encode.outputs.json }}
    steps:
      - uses: actions/checkout@v4
      - id: encode
        run: echo "json=$(base64 -w 0 grafana/dashboard.json)" >> $GITHUB_OUTPUT

  deploy:
    needs: encode
    uses: YOUR_ORG/grafana-as-code/.github/workflows/deploy-dashboard.yml@main
    with:
      dashboard_name: your-service-name
      dashboard_json: ${{ needs.encode.outputs.json }}
    secrets:
      GRAFANA_URL: ${{ secrets.GRAFANA_URL }}
      GRAFANA_AUTH: ${{ secrets.GRAFANA_AUTH }}
      PROMETHEUS_URL: ${{ secrets.PROMETHEUS_URL }}
```

Replace `YOUR_ORG` with your GitHub organization or username, and `your-service-name` with a unique identifier for the project.

## Dashboard JSON structure

The JSON must have a unique `uid` and a `title`. Use the `${datasource}` template variable to reference Prometheus:

```json
{
  "uid": "your-service-overview",
  "title": "Your Service Overview",
  "tags": ["your-service", "prometheus"],
  "schemaVersion": 38,
  "refresh": "30s",
  "panels": [
    {
      "id": 1,
      "type": "timeseries",
      "title": "Request Rate",
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{service=\"your-service\"}[5m]))",
          "legendFormat": "{{status_code}}"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "datasource",
        "type": "datasource",
        "query": "prometheus",
        "label": "Datasource"
      }
    ]
  }
}
```

## Workflows

### `deploy-dashboard.yml` (reusable)

Called by source repos. Accepts the dashboard JSON as a base64-encoded input and applies only that dashboard using `terraform apply -target`.

**Inputs:**

| Input | Required | Description |
|---|---|---|
| `dashboard_name` | yes | Filename without `.json` extension — must be unique across projects |
| `dashboard_json` | yes | Dashboard JSON content encoded in base64 |

### `terraform.yml` (internal)

Runs on changes to the `terraform/` directory. Manages infrastructure-level resources like datasources and providers. Uses `-target=grafana_data_source.prometheus` on apply to avoid touching dashboards.

## Pros and cons

**Pros**
- Dashboards are versioned alongside the code they monitor
- One place to manage Grafana connection and datasources
- Adding a new project requires copying 2 files and changing one value
- Credentials never touch the codebase
- Works for Grafana on Linux, Kubernetes, or any self-hosted instance

**Cons**
- Terraform owns the state: manual changes in Grafana UI will be overwritten on next apply
- The central repo is a shared dependency — a bug in its workflow affects all projects
- Each repo needs the 3 secrets configured (mitigated with organization secrets)
- Without a remote backend, Terraform state is not shared between runs (see below)

## Terraform state backend

By default Terraform stores state locally on the runner, which means state is lost after each run. For production use, configure a remote backend such as S3, GCS, or Terraform Cloud in `terraform/providers.tf`:

```hcl
terraform {
  backend "s3" {
    bucket = "your-tfstate-bucket"
    key    = "grafana/terraform.tfstate"
    region = "us-east-1"
  }
}
```
