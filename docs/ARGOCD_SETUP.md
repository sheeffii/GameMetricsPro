# ArgoCD Setup - Quick Start Guide

This guide explains how to set up ArgoCD and automated image updates for a fresh environment.

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start (Fresh Environment)](#quick-start-fresh-environment)
3. [Manual Installation](#manual-installation)
4. [Image Auto-Update Setup](#image-auto-update-setup)
5. [Deploying Applications](#deploying-applications)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

- Kubernetes cluster (EKS, kind, minikube, etc.)
- `kubectl` configured to access your cluster
- AWS credentials configured (for ECR)
- Git repository access

## Quick Start (Fresh Environment)

### One-Command Bootstrap

For a completely fresh environment, run:

```bash
./scripts/bootstrap-argocd.sh dev
```

This script will:
1. ✅ Install ArgoCD (v2.9.3)
2. ✅ Create ArgoCD project (`gamemetrics`)
3. ✅ Install ArgoCD Image Updater
4. ✅ Configure ECR registry
5. ✅ Apply all ArgoCD Applications
6. ✅ Provide admin credentials

**What you get:**
- ArgoCD UI accessible at `https://localhost:8080` (after port-forward)
- Admin credentials in `.argocd-credentials` file
- Image Updater running and watching your applications
- All services deployed via GitOps

### Accessing ArgoCD UI

```bash
# Port forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
cat .argocd-credentials

# Open browser: https://localhost:8080
```

## Manual Installation

If you prefer step-by-step manual installation:

### Step 1: Install ArgoCD

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.9.3/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd
```

### Step 2: Get Admin Credentials

```bash
# Get password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Step 3: Create ArgoCD Project

```bash
kubectl apply -f k8s/argocd/project.yaml
```

### Step 4: Install Image Updater

```bash
# Install via Kustomize
kubectl apply -k k8s/argocd-image-updater/overlays/dev

# Verify installation
kubectl get pods -n argocd-image-updater-system
```

### Step 5: Apply Applications

```bash
# Apply root application (if using app-of-apps pattern)
kubectl apply -f k8s/argocd/root-app.yaml

# Or apply individual applications
kubectl apply -f k8s/argocd/application-event-ingestion-dev.yaml
kubectl apply -f k8s/argocd/application-notification-service-dev.yaml
```

## Image Auto-Update Setup

ArgoCD Image Updater automatically updates your applications when new images are pushed to ECR.

### Method 1: Using ImageUpdater CRs (Recommended for v1.0+)

Create ImageUpdater custom resources:

```bash
# Generate CRs from existing applications
./scripts/create-image-updater-crs.sh

# Apply the CRs
kubectl apply -k k8s/argocd/image-updaters
```

### Method 2: Using Annotations (Legacy, v0.12.x)

Your applications already have annotations configured:

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: notification-service=647523695124.dkr.ecr.us-east-1.amazonaws.com/notification-service
    argocd-image-updater.argoproj.io/notification-service.update-strategy: latest
    argocd-image-updater.argoproj.io/write-back-method: argocd
```

**Note:** To use annotation-based updates with the current Image Updater, you may need to downgrade to v0.12.x. Edit `k8s/argocd-image-updater/base/kustomization.yaml` and change the resource URL.

### Testing Image Updates

1. Build and push a new image:
   ```bash
   ./scripts/build-push-ecr.sh notification-service
   ```

2. Wait ~2 minutes (default check interval)

3. Verify the update:
   ```bash
   # Check ArgoCD Application
   kubectl get application notification-service-dev -n argocd -o jsonpath='{.spec.source.kustomize.images}'
   
   # Check Image Updater logs
   kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater --tail=50
   ```

## Deploying Applications

### Using ArgoCD CLI

```bash
# Install ArgoCD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/download/v2.9.3/argocd-linux-amd64
sudo install -m 555 argocd /usr/local/bin/argocd

# Login
argocd login localhost:8080

# Sync application
argocd app sync notification-service-dev
```

### Using kubectl

```bash
# Check application status
kubectl get applications -n argocd

# Manually sync an application
kubectl patch application notification-service-dev -n argocd \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}'
```

### Via UI

1. Access ArgoCD UI: `https://localhost:8080`
2. Login with admin credentials
3. Click on application
4. Click "Sync" button

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        GitHub Repo                           │
│  (GameMetrics-Pro: main branch)                             │
│    └── k8s/                                                  │
│        ├── services/                                         │
│        │   ├── event-ingestion/                             │
│        │   └── notification-service/                        │
│        └── argocd/                                          │
│            └── applications/                                │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ Monitors Git
                 ↓
┌─────────────────────────────────────────────────────────────┐
│                         ArgoCD                               │
│  Namespace: argocd                                          │
│    • Monitors Git repository                                 │
│    • Applies manifests to cluster                           │
│    • Auto-syncs on Git changes                              │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ Updates
                 ↓
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│  Namespace: gamemetrics                                     │
│    • event-ingestion (deployment, service)                  │
│    • notification-service (deployment, service)             │
│    • kafka, timescaledb, etc.                               │
└─────────────────────────────────────────────────────────────┘
                 ↑
                 │ Monitors & Updates
┌────────────────┴────────────────────────────────────────────┐
│              ArgoCD Image Updater                            │
│  Namespace: argocd-image-updater-system                     │
│    • Watches ECR for new images                             │
│    • Updates ArgoCD Applications                            │
│    • Triggers re-sync (every 2min)                          │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ Pulls images
                 ↓
┌─────────────────────────────────────────────────────────────┐
│                      AWS ECR                                 │
│  (647523695124.dkr.ecr.us-east-1.amazonaws.com)            │
│    • event-ingestion-service:latest                         │
│    • notification-service:latest                            │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
.
├── k8s/
│   ├── argocd/                          # ArgoCD configuration
│   │   ├── project.yaml                 # ArgoCD project definition
│   │   ├── root-app.yaml                # App-of-apps root
│   │   ├── application-*-dev.yaml       # Individual applications
│   │   └── image-updaters/              # ImageUpdater CRs
│   ├── argocd-image-updater/            # Image Updater Kustomize
│   │   ├── base/                        # Base configuration
│   │   ├── overlays/dev/                # Environment overlays
│   │   └── README.md                    # Detailed documentation
│   ├── services/                        # Service manifests
│   │   ├── event-ingestion/
│   │   └── notification-service/
│   └── kustomization.yaml               # Main kustomization
└── scripts/
    ├── bootstrap-argocd.sh              # One-command installation
    ├── create-image-updater-crs.sh      # Generate ImageUpdater CRs
    └── build-push-ecr.sh                # Build & push images to ECR
```

## Troubleshooting

### ArgoCD Applications Not Syncing

```bash
# Check application status
kubectl describe application notification-service-dev -n argocd

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller

# Force refresh
kubectl patch application notification-service-dev -n argocd \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Image Updater Not Working

```bash
# Check Image Updater pods
kubectl get pods -n argocd-image-updater-system

# View logs
kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater -f

# Common issues:
# 1. ECR authentication - ensure IAM role has ECR pull permissions
# 2. ArgoCD connectivity - check network policies
# 3. CRD vs annotations - ensure using correct method for version
```

### ECR Authentication Issues

```bash
# Test ECR access from cluster
kubectl run ecr-test --image=647523695124.dkr.ecr.us-east-1.amazonaws.com/notification-service:latest --rm -it --restart=Never

# Check IAM role on nodes
kubectl get nodes -o jsonpath='{.items[*].spec.providerID}'
aws ec2 describe-instances --instance-ids <instance-id> --query 'Reservations[*].Instances[*].IamInstanceProfile'
```

### Pods Pending Due to Resource Constraints

```bash
# Check node resources
kubectl top nodes

# Check pod resource requests
kubectl describe pod <pod-name> -n <namespace>

# Scale down or adjust resource limits
kubectl scale deployment <name> --replicas=1 -n <namespace>
```

## Advanced Configuration

### Multi-Environment Setup

Create overlays for staging and production:

```bash
# Create staging overlay
mkdir -p k8s/argocd-image-updater/overlays/staging
cp k8s/argocd-image-updater/overlays/dev/kustomization.yaml \
   k8s/argocd-image-updater/overlays/staging/

# Bootstrap staging
./scripts/bootstrap-argocd.sh staging
```

### Custom Image Update Strategies

Edit ImageUpdater CRs to use semver or digest strategies:

```yaml
spec:
  images:
    - image: 647523695124.dkr.ecr.us-east-1.amazonaws.com/notification-service
      updateStrategy:
        strategy: semver      # Use semantic versioning
        constraint: ^1.0.0    # Match 1.x.x versions
```

### Monitoring and Alerting

```bash
# Enable metrics endpoint
kubectl port-forward -n argocd-image-updater-system \
  svc/argocd-image-updater-controller-metrics-service 8443:8443

# Scrape metrics
curl -k https://localhost:8443/metrics
```

## Next Steps

1. ✅ **Verify Installation:**
   ```bash
   kubectl get pods -n argocd
   kubectl get pods -n argocd-image-updater-system
   kubectl get applications -n argocd
   ```

2. ✅ **Deploy Your Services:**
   ```bash
   ./scripts/build-push-ecr.sh event-ingestion
   ./scripts/build-push-ecr.sh notification-service
   ```

3. ✅ **Access ArgoCD UI:**
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   # Open: https://localhost:8080
   ```

4. ✅ **Monitor Updates:**
   ```bash
   kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater -f
   ```

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Image Updater Documentation](https://argocd-image-updater.readthedocs.io/)
- [Kustomize Documentation](https://kustomize.io/)
- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)

## Support

For issues or questions:
1. Check logs: `kubectl logs -n <namespace> <pod-name>`
2. Review ArgoCD UI for application health
3. Verify Git repository connectivity
4. Check IAM permissions for ECR access
