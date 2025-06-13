#!/bin/bash

# Create k3s directory structure
mkdir -p k3s/{charts,setup_scripts}

# Create chart directories
mkdir -p k3s/charts/{k3s-cluster,monitoring,storage,networking,security}

# Create secrets directory structure
mkdir -p k3s/secrets

# Create basic chart structure for each service
for service in k3s-cluster monitoring storage networking security; do
    mkdir -p k3s/charts/$service/{templates,values}
    touch k3s/charts/$service/Chart.yaml
    touch k3s/charts/$service/values.yaml
    touch k3s/charts/$service/templates/deployment.yaml
    touch k3s/charts/$service/templates/service.yaml
    touch k3s/charts/$service/templates/configmap.yaml
    touch k3s/charts/$service/templates/secrets.yaml
    touch k3s/charts/$service/templates/pvc.yaml
    touch k3s/secrets/${service}-secrets.yaml
done

# Create GitHub Actions workflow
mkdir -p k3s/.github/workflows

cat > k3s/.github/workflows/deploy-charts.yml << 'EOL'
name: Deploy K3s Charts

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

permissions:
  contents: read
  packages: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Helm
        uses: azure/setup-helm@v3
        with:
          version: v3.12.0

      - name: Login to GitHub Packages
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Package and push charts
        run: |
          helm package charts/k3s-cluster/ --destination charts/
          helm package charts/monitoring/ --destination charts/
          helm package charts/storage/ --destination charts/
          helm package charts/networking/ --destination charts/
          helm package charts/security/ --destination charts/
          
          # Push to GitHub Packages
          helm push charts/k3s-cluster-*.tgz ghcr.io/your-org/k3s-charts
          helm push charts/monitoring-*.tgz ghcr.io/your-org/k3s-charts
          helm push charts/storage-*.tgz ghcr.io/your-org/k3s-charts
          helm push charts/networking-*.tgz ghcr.io/your-org/k3s-charts
          helm push charts/security-*.tgz ghcr.io/your-org/k3s-charts
          helm push charts/auth-service-*.tgz ghcr.io/your-org/k3s-charts
          helm push charts/notification-service-*.tgz ghcr.io/your-org/k3s-charts
          helm push charts/subscription-service-*.tgz ghcr.io/your-org/k3s-charts
          helm push charts/k3s_engine_llm-*.tgz ghcr.io/your-org/k3s-charts

      - name: Update chart repository
        run: |
          helm repo index . --url https://your-org.github.io/k3s-charts
          git config --global user.name "GitHub Actions"
          git config --global user.email "actions@github.com"
          git add .
          git commit -m "Update chart repository"
          git push origin main
EOL

# Create README template
cat > k3s/README.md << 'EOL'
# K3s Infrastructure Helm Charts

This directory contains Helm charts for the K3s cluster infrastructure and supporting services.

## Structure

```
k3s/
├── charts/
│   ├── k3s-cluster/
│   ├── monitoring/
│   ├── storage/
│   ├── networking/
│   └── security/
├── auth-service/
├── notification-service/
├── subscription-service/
└── k3s_engine_llm/
```

## Charts

### K3s Cluster
- K3s cluster configuration
- Node management
- Cluster scaling
- Resource allocation

### Spring Services
- Auth Service
  - Authentication and authorization
  - JWT token management
  - User management
  - Role-based access control
- Notification Service
  - Email notifications
  - SMS integration
  - Push notifications
  - Notification templates
- Subscription Service
  - User subscriptions
  - Plan management
  - Billing integration
  - Usage tracking

### LLM Engine
- LLM Core
- Model Serving
- ML Services
  - MLflow
  - JupyterHub
  - Dask Cluster
- Cache Layer (Redis)

### Monitoring
- Prometheus
- Grafana
- Alertmanager
- Node Exporter

### Storage
- Persistent Volumes
- Storage Classes
- Volume Snapshots
- Backup configurations

### Networking
- Ingress controllers
- Network policies
- Load balancers
- Service meshes

### Security
- RBAC configurations
- Network policies
- Secrets management
- Pod security policies

## Secrets Management

All sensitive information is stored in the `secrets/` directory:
- K3s token
- TLS certificates
- Monitoring credentials
- Storage access keys
- Network configurations

## Usage

### Install Helm Repository
```bash
helm repo add k3s-charts https://your-org.github.io/k3s-charts
helm repo update
```

### Install Charts
```bash
# Example: Install K3s Cluster with secrets
helm install k3s-cluster k3s-charts/k3s-cluster -f values.yaml -f secrets/k3s-cluster-secrets.yaml

# Example: Install Monitoring with secrets
helm install monitoring k3s-charts/monitoring -f values.yaml -f secrets/monitoring-secrets.yaml
```

## Security

- All secrets are encrypted using SOPS
- RBAC enabled
- Network policies enforced
- TLS enabled for all services
- Regular security audits

## License

MIT
EOL
