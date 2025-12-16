# GameMetrics Pro - Scripts Documentation

This directory contains deployment, management, and testing scripts for the GameMetrics Pro platform.

## 🚀 Production Scripts (Recommended)

### `production-deploy.sh` ⭐ **USE THIS FOR PRODUCTION**
Complete production deployment script that deploys everything:
- AWS Infrastructure (EKS, RDS, ElastiCache, S3, ECR)
- Kubernetes Infrastructure (namespaces, RBAC, operators)
- Kafka Cluster and Topics
- ArgoCD for GitOps
- All Microservices
- Observability Stack
- Security Components

**Usage:**
```bash
./scripts/production-deploy.sh [region] [environment]
./scripts/production-deploy.sh us-east-1 prod
```

**Environment Variables:**
- `AWS_REGION` - AWS region (default: us-east-1)
- `ENVIRONMENT` - Environment name (default: prod)
- `SKIP_BUILD` - Skip Docker builds (default: false)
- `SKIP_ARGO` - Skip ArgoCD (default: false)

---

### `complete-teardown.sh` ⭐ **USE THIS TO DELETE EVERYTHING**
Complete cloud teardown script that removes all resources:
- Kubernetes resources
- Load Balancers and ENIs
- RDS databases
- S3 buckets
- ECR repositories
- Secrets Manager secrets
- Terraform infrastructure

**Usage:**
```bash
./scripts/complete-teardown.sh [region] [environment]
./scripts/complete-teardown.sh us-east-1 prod
```

**⚠️ WARNING:** This will DELETE ALL resources. Requires confirmation.

**Environment Variables:**
- `AWS_REGION` - AWS region (default: us-east-1)
- `ENVIRONMENT` - Environment name (default: prod)
- `CONFIRM_DELETE` - Skip confirmation (default: false)

---

## 🔧 Infrastructure Scripts

### `deploy-infrastructure.sh`
Deploys AWS infrastructure and Kubernetes base components (no applications).

**Usage:**
```bash
./scripts/deploy-infrastructure.sh
```

**Environment Variables:**
- `AWS_REGION` - AWS region (default: us-east-1)
- `APPLY_KAFKA` - Deploy Kafka (default: true)

---

### `deploy-argocd.sh`
Installs and configures ArgoCD for GitOps.

**Usage:**
```bash
./scripts/deploy-argocd.sh
```

**Prerequisites:**
- Kubernetes cluster running
- kubectl configured

---

### `build-push-ecr.sh`
Builds and pushes a Docker image to AWS ECR.

**Usage:**
```bash
./scripts/build-push-ecr.sh <region> <repo_url> <service_path>
./scripts/build-push-ecr.sh us-east-1 123456789.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service services/event-ingestion-service
```

**Environment Variables:**
- `TAG` - Docker image tag (default: latest)

---

### `update-secrets-from-aws.sh`
Syncs secrets from AWS Secrets Manager to Kubernetes.

**Usage:**
```bash
./scripts/update-secrets-from-aws.sh [region]
```

**Prerequisites:**
- AWS Secrets Manager secrets exist
- kubectl configured
- Kafka cluster running (for bootstrap servers)

---

## 📊 Monitoring & Status Scripts

### `check-status.sh`
Displays current system status (AWS, Kubernetes, Kafka).

**Usage:**
```bash
./scripts/check-status.sh
```

---

### `access-monitoring.sh`
Provides quick access to observability tools via port-forwarding.

**Usage:**
```bash
./scripts/access-monitoring.sh [grafana|prometheus|kafka-ui|all]
./scripts/access-monitoring.sh grafana
```

---

## 🧪 Testing Scripts

### `send-test-events.sh`
Sends test events to the event-ingestion service.

**Usage:**
```bash
./scripts/send-test-events.sh [num_events]
./scripts/send-test-events.sh 50
```

---

### `test-application.sh`
Runs basic health checks and functional tests.

**Usage:**
```bash
./scripts/test-application.sh
```

---

### `load_test_events.sh`
Performs load testing by sending multiple events.

**Usage:**
```bash
./scripts/load_test_events.sh [count] [rate_per_second]
./scripts/load_test_events.sh 1000 100
```

**Environment Variables:**
- `INGESTION_SERVICE_URL` - Service URL (default: http://localhost:8080)

---

## 🗑️ Deprecated Scripts

The following scripts are deprecated and will be removed in future versions:

- `deploy-complete.sh` → Use `production-deploy.sh`
- `deploy-infra-only.sh` → Use `deploy-infrastructure.sh`
- `deploy-apps-to-k8s.sh` → Use `production-deploy.sh`
- `update-deployment-image.sh` → Use `production-deploy.sh`
- `update-secrets.sh` → Use `update-secrets-from-aws.sh`
- `teardown-infrastructure.sh` → Use `complete-teardown.sh`

---

## 📋 Quick Reference

### Deploy Everything (Production)
```bash
./scripts/production-deploy.sh us-east-1 prod
```

### Delete Everything
```bash
./scripts/complete-teardown.sh us-east-1 prod
```

### Deploy Infrastructure Only
```bash
./scripts/deploy-infrastructure.sh
```

### Check Status
```bash
./scripts/check-status.sh
```

### Access Grafana
```bash
./scripts/access-monitoring.sh grafana
```

### Send Test Events
```bash
./scripts/send-test-events.sh 10
```

---

## 🔐 Prerequisites

All scripts require:
- **AWS CLI** - Configured with appropriate credentials
- **kubectl** - Installed and configured
- **terraform** - Installed (for infrastructure scripts)
- **jq** - Installed (for JSON parsing)
- **Docker** - Installed (for build scripts)

---

## 📝 Notes

- All scripts use `set -e` or `set -euo pipefail` for error handling
- Scripts output colored status messages (green=success, yellow=warning, red=error)
- Most scripts support environment variables for configuration
- Production scripts include comprehensive error handling and verification
- Deprecated scripts still work but show warnings

---

## 🆘 Troubleshooting

### Script fails with "command not found"
- Ensure script is executable: `chmod +x scripts/script-name.sh`
- Check that required tools are installed and in PATH

### AWS credentials not found
- Run `aws configure` to set up AWS credentials
- Verify with `aws sts get-caller-identity`

### kubectl not connected
- Run `aws eks update-kubeconfig --region <region> --name <cluster-name>`
- Verify with `kubectl cluster-info`

### Terraform errors
- Ensure Terraform is initialized: `terraform init`
- Check Terraform state file exists

---

## 📚 Related Documentation

- [Architecture Overview](../ARCHITECTURE_OVERVIEW.md)
- [Production Readiness Checklist](../PRODUCTION_READINESS_CHECKLIST.md)
- [ArgoCD Workflow](../ARGOCD_WORKFLOW_EXPLAINED.md)
- [Quick Start Guide](../QUICK_START_INSTANT_SYNC.md)



