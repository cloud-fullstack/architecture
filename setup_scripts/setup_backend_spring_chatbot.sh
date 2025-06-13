#!/bin/bash

# Create backend-spring-chatbot directory structure
mkdir -p k3s/backend-spring-chatbot/{charts,setup_scripts}

# Create chart directories
mkdir -p k3s/backend-spring-chatbot/charts/spring-client

# Create secrets directory structure
mkdir -p k3s/backend-spring-chatbot/secrets

# Create basic chart structure for each service
mkdir -p k3s/backend-spring-chatbot/charts/spring-client/{templates,values}
touch k3s/backend-spring-chatbot/charts/spring-client/Chart.yaml
touch k3s/backend-spring-chatbot/charts/spring-client/values.yaml
touch k3s/backend-spring-chatbot/charts/spring-client/templates/deployment.yaml
touch k3s/backend-spring-chatbot/charts/spring-client/templates/service.yaml
touch k3s/backend-spring-chatbot/charts/spring-client/templates/configmap.yaml
touch k3s/backend-spring-chatbot/charts/spring-client/templates/secrets.yaml
touch k3s/backend-spring-chatbot/charts/spring-client/templates/pvc.yaml
touch k3s/backend-spring-chatbot/secrets/spring-client-secrets.yaml

# Create GitHub Actions workflow
mkdir -p k3s/backend-spring/.github/workflows

cat > k3s/backend-spring/.github/workflows/deploy-charts.yml << 'EOL'
name: Deploy Backend Spring Charts

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
          helm package charts/spring-api/ --destination charts/
          helm package charts/spring-auth/ --destination charts/
          helm package charts/spring-config/ --destination charts/
          helm package charts/spring-gateway/ --destination charts/
          
          # Push to GitHub Packages
          helm push charts/spring-api-*.tgz ghcr.io/your-org/spring-backend
          helm push charts/spring-auth-*.tgz ghcr.io/your-org/spring-backend
          helm push charts/spring-config-*.tgz ghcr.io/your-org/spring-backend
          helm push charts/spring-gateway-*.tgz ghcr.io/your-org/spring-backend

      - name: Update chart repository
        run: |
          helm repo index . --url https://your-org.github.io/spring-backend
          git config --global user.name "GitHub Actions"
          git config --global user.email "actions@github.com"
          git add .
          git commit -m "Update chart repository"
          git push origin main
EOL

# Create README template
cat > k3s/backend-spring/README.md << 'EOL'
# Spring Backend Helm Charts

This directory contains Helm charts for all Spring-based microservices used in the backend infrastructure.

## Structure

```
backend-spring-chatbot/
├── auth-service/
├── charts/
│   └── spring-client/
│       ├── Chart.yaml
│       └── templates/
├── database/
├── notification-service/
└── subscription-service/
```

## Services

### Auth Service
- Authentication and authorization
- JWT token management
- User management
- Role-based access control

### Notification Service
- Email notifications
- SMS integration
- Push notifications
- Notification templates

### Subscription Service
- User subscriptions
- Plan management
- Billing integration
- Usage tracking

### Database
- PostgreSQL configuration
- Schema management
- Backup procedures
- Performance optimization

## Charts

### Spring Client
- Helm chart for Spring Boot services
- Configuration management
- Deployment templates
- Service discovery
- Health checks

### Spring Config
- Configuration management
- Environment-based configs
- Config refresh
- Config encryption

### Spring Gateway
- API Gateway
- Route management
- Request filtering
- Load balancing

## Secrets Management

All sensitive information is stored in the `secrets/` directory:
- Database credentials
- JWT secrets
- API keys
- Encryption keys
- OAuth credentials

## Usage

### Install Helm Repository
```bash
helm repo add spring-backend https://your-org.github.io/spring-backend
helm repo update
```

### Install Charts
```bash
# Example: Install Spring API with secrets
helm install spring-api spring-backend/spring-api -f values.yaml -f secrets/spring-api-secrets.yaml

# Example: Install Spring Auth with secrets
helm install spring-auth spring-backend/spring-auth -f values.yaml -f secrets/spring-auth-secrets.yaml
```

## Security

- All secrets are encrypted using SOPS
- RBAC enabled
- Network policies enforced
- TLS enabled for all services
- Rate limiting
- Request validation

## License

MIT
EOL
