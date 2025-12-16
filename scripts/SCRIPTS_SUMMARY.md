# GameMetrics Pro - Scripts Summary

## 📋 Overview

This document provides a quick reference for all scripts in the `scripts/` directory, organized by purpose.

---

## 🎯 Primary Scripts (Use These)

### Production Deployment
- **`production-deploy.sh`** ⭐ - Complete production deployment (infrastructure + applications + monitoring)
- **`complete-teardown.sh`** ⭐ - Complete cloud cleanup (deletes everything)

### Infrastructure Management
- **`deploy-infrastructure.sh`** - Deploy AWS + Kubernetes infrastructure only
- **`deploy-argocd.sh`** - Install and configure ArgoCD
- **`update-secrets-from-aws.sh`** - Sync secrets from AWS Secrets Manager

### Image Management
- **`build-push-ecr.sh`** - Build and push Docker images to ECR

### Monitoring & Status
- **`check-status.sh`** - Display system status
- **`access-monitoring.sh`** - Access Grafana/Prometheus/Kafka UI

### Testing
- **`send-test-events.sh`** - Send test events to ingestion service
- **`test-application.sh`** - Run basic health checks
- **`load_test_events.sh`** - Perform load testing

### Setup Scripts
- **`setup/health-check.sh`** - Comprehensive health checks
- **`setup/test-event-flow.sh`** - End-to-end event flow test

### Troubleshooting
- **`cleanup-partial-deploy.sh`** - Clean up failed deployments

---

## 🗑️ Deprecated Scripts (Don't Use)

These scripts are deprecated and will be removed:
- `deploy-complete.sh` → Use `production-deploy.sh`
- `deploy-infra-only.sh` → Use `deploy-infrastructure.sh`
- `deploy-apps-to-k8s.sh` → Use `production-deploy.sh`
- `update-deployment-image.sh` → Use `production-deploy.sh`
- `update-secrets.sh` → Use `update-secrets-from-aws.sh`
- `teardown-infrastructure.sh` → Use `complete-teardown.sh`

---

## 🚀 Quick Start

### First Time Deployment
```bash
# 1. Deploy everything
./scripts/production-deploy.sh us-east-1 prod

# 2. Check status
./scripts/check-status.sh

# 3. Access monitoring
./scripts/access-monitoring.sh grafana
```

### Daily Operations
```bash
# Check system health
./scripts/setup/health-check.sh

# Send test events
./scripts/send-test-events.sh 10

# Test event flow
./scripts/setup/test-event-flow.sh
```

### Cleanup (When Done)
```bash
# Delete everything
./scripts/complete-teardown.sh us-east-1 prod
```

---

## 📊 Script Categories

| Category | Scripts | Purpose |
|----------|---------|---------|
| **Deployment** | `production-deploy.sh`, `deploy-infrastructure.sh`, `deploy-argocd.sh` | Deploy platform components |
| **Teardown** | `complete-teardown.sh` | Remove all resources |
| **Management** | `update-secrets-from-aws.sh`, `build-push-ecr.sh` | Manage secrets and images |
| **Monitoring** | `check-status.sh`, `access-monitoring.sh` | Monitor system health |
| **Testing** | `send-test-events.sh`, `test-application.sh`, `load_test_events.sh` | Test functionality |
| **Health** | `setup/health-check.sh`, `setup/test-event-flow.sh` | Health checks and validation |
| **Troubleshooting** | `cleanup-partial-deploy.sh` | Fix deployment issues |

---

## 🔧 Prerequisites

All scripts require:
- **AWS CLI** - Configured with credentials
- **kubectl** - Installed and configured
- **terraform** - Installed (for infrastructure scripts)
- **jq** - Installed (for JSON parsing)
- **Docker** - Installed (for build scripts)

---

## 📝 Notes

- All scripts include error handling (`set -e` or `set -euo pipefail`)
- Scripts output colored status messages
- Most scripts support environment variables
- Production scripts include comprehensive verification
- Deprecated scripts show warnings but still work

---

## 🆘 Getting Help

1. Check script comments: `head -20 scripts/script-name.sh`
2. Read README: `cat scripts/README.md`
3. Check prerequisites: Ensure all tools are installed
4. Verify AWS credentials: `aws sts get-caller-identity`
5. Verify kubectl: `kubectl cluster-info`

---

## 📚 Related Documentation

- [Scripts README](README.md) - Detailed script documentation
- [Architecture Overview](../ARCHITECTURE_OVERVIEW.md) - System architecture
- [Production Readiness](../PRODUCTION_READINESS_CHECKLIST.md) - Production checklist
- [ArgoCD Workflow](../ARGOCD_WORKFLOW_EXPLAINED.md) - GitOps workflow



