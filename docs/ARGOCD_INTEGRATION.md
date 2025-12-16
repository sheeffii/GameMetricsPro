# ArgoCD Image Updater - Integration into Main Kustomization

## 🎯 What Changed

The ArgoCD Image Updater is now **fully integrated** into the main Kustomization. When you deploy the stack, it automatically installs:

1. **ArgoCD** (v2.9.3)
2. **ArgoCD Image Updater** (v1.0.1) 
3. **All Services** and configurations

## 🚀 Deployment Methods

### Method 1: Deploy Everything with kubectl (Recommended)

```bash
# Deploy entire stack including ArgoCD and Image Updater
kubectl apply -k k8s/

# Or use kustomize directly
kubectl kustomize k8s/ | kubectl apply -f -
```

### Method 2: Production Deployment Script

```bash
# Full production deployment with infrastructure, k8s, and services
./scripts/production-deploy.sh us-east-1 prod
```

The script no longer calls `bootstrap-argocd.sh` separately. Everything is deployed via the main kustomization.

### Method 3: Selective Deployment

```bash
# Deploy only ArgoCD and Image Updater
kubectl apply -k k8s/argocd/overlays
kubectl apply -k k8s/argocd-image-updater/overlays/dev
```

## 📁 Directory Structure

```
k8s/
├── kustomization.yaml              # MAIN - includes all resources
│   ├── namespaces/
│   ├── argocd/overlays/            # ArgoCD (includes CRDs, UI, controllers)
│   ├── argocd-image-updater/overlays/dev/  # NEW: Image Updater auto-update
│   ├── strimzi/base/               # Kafka operator
│   ├── kafka-ui/                   # Kafka UI
│   ├── services/                   # Your microservices
│   ├── observability/              # Prometheus, Grafana, Loki
│   └── hpa/                        # Horizontal Pod Autoscaling
│
├── argocd-image-updater/
│   ├── base/
│   │   ├── kustomization.yaml      # References official manifest + patches
│   │   └── configmap-patch.yaml    # ECR & ArgoCD server configuration
│   └── overlays/
│       └── dev/
│           └── kustomization.yaml  # Dev environment specific
│
└── (other directories...)
```

## ⚙️ Configuration

### ECR Registry (Pre-configured)

The Image Updater is configured to work with your ECR:

- **Account ID:** 647523695124
- **Region:** us-east-1
- **Repositories:** event-ingestion-service, notification-service, etc.

### To Customize for Different Environments

Edit `k8s/argocd-image-updater/overlays/<env>/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

# Add environment-specific patches
patchesStrategicMerge:
  - |-
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: argocd-image-updater-config
    data:
      interval: "5m"  # Check every 5 minutes instead of 2
```

## 🔄 How It Works Now

```
┌─────────────────────────────────────────────┐
│  kubectl apply -k k8s/                     │
│  OR ./scripts/production-deploy.sh          │
└────────────┬────────────────────────────────┘
             │
             ↓
┌─────────────────────────────────────────────┐
│  Main Kustomization (k8s/kustomization.yaml)
│                                              │
│  Deploys:                                   │
│  ├─ Namespaces                              │
│  ├─ ArgoCD                                  │
│  ├─ ArgoCD Image Updater  ← NEW!            │
│  ├─ Kafka & Strimzi                         │
│  ├─ Services                                │
│  └─ Observability Stack                     │
└────────────┬────────────────────────────────┘
             │
             ↓
┌─────────────────────────────────────────────┐
│  All Resources Running:                     │
│  • ArgoCD Server (web UI)                   │
│  • ArgoCD Application Controller            │
│  • ArgoCD Image Updater Controller          │
│  • Kafka Broker & Controller                │
│  • Event Ingestion Service                  │
│  • Notification Service                     │
│  • Prometheus, Grafana, Loki                │
│  • And more...                              │
└─────────────────────────────────────────────┘
```

## ✨ Key Benefits

✅ **No Separate Scripts** - Single command deploys everything
✅ **Consistent Deployment** - Same kustomization for all environments
✅ **GitOps Native** - Everything managed via Git
✅ **Automatic Image Updates** - Images updated within 2 minutes of push
✅ **Environment Scalable** - Easy to add staging, production overlays

## 🧪 Verify Installation

```bash
# Check all namespaces
kubectl get ns | grep -E "argocd|gamemetrics|kafka"

# Check ArgoCD pods
kubectl get pods -n argocd

# Check Image Updater pods
kubectl get pods -n argocd-image-updater-system

# Check Image Updater is ready
kubectl get deployment argocd-image-updater-controller -n argocd-image-updater-system

# View Image Updater logs
kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater -f
```

## 🔐 What Gets Installed by Kustomization

### ArgoCD Components
- `argocd-server` - Web UI and API
- `argocd-application-controller` - Syncs applications
- `argocd-repo-server` - Clones Git repos
- `argocd-dex-server` - OAuth/SSO
- `argocd-redis` - Cache
- `argocd-notifications-controller` - Webhook notifications

### Image Updater Components
- `argocd-image-updater-controller` - Watches ECR for new images
- **ImageUpdater CRD** - Custom resource for configuration
- **RBAC** - ServiceAccount, ClusterRole, RoleBindings
- **ConfigMap** - ArgoCD and registry configuration
- **Metrics Service** - Prometheus metrics endpoint

### Kubernetes Infrastructure
- Namespaces (argocd, argocd-image-updater-system, gamemetrics, kafka, monitoring, databases)
- Strimzi Operator (Kafka management)
- Kafka Cluster & Topics
- Services, Secrets, ConfigMaps
- NetworkPolicies
- ResourceQuotas

## 📊 Comparison: Before vs After

### Before (Multiple Commands)
```bash
# Manual ArgoCD bootstrap
./scripts/bootstrap-argocd.sh dev

# Manual service deployment
kubectl apply -k k8s/services/

# Manual infrastructure
kubectl apply -k k8s/kafka/
kubectl apply -k k8s/observability/
```

### After (Single Command) ✨
```bash
# Everything in one command
kubectl apply -k k8s/

# Or with infrastructure
./scripts/production-deploy.sh us-east-1 prod
```

## 🎓 Common Workflows

### Deploy Fresh Environment

```bash
# Ensure kubeconfig is set
export KUBECONFIG=~/.kube/config

# Deploy everything
kubectl apply -k k8s/

# Wait for readiness
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd
```

### Update Services

```bash
# Build and push new image
./scripts/build-push-ecr.sh notification-service

# Image Updater detects within 2 minutes and updates ArgoCD Applications
# Which triggers pod restart via Kubernetes

# Monitor the update
kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater -f
```

### Add New Environment (e.g., Staging)

```bash
# Create staging overlay
mkdir -p k8s/argocd-image-updater/overlays/staging
cp k8s/argocd-image-updater/overlays/dev/kustomization.yaml \
   k8s/argocd-image-updater/overlays/staging/

# Create kustomization patch for different interval/config if needed
# Then deploy:
kubectl apply -k k8s/argocd-image-updater/overlays/staging
```

## 🔗 Related Documentation

- [ARGOCD_QUICK_REFERENCE.md](./ARGOCD_QUICK_REFERENCE.md) - Common commands
- [ARGOCD_SETUP.md](./ARGOCD_SETUP.md) - Detailed setup guide
- [k8s/argocd-image-updater/README.md](../k8s/argocd-image-updater/README.md) - Image Updater specifics

## ❓ FAQ

**Q: Do I still need bootstrap-argocd.sh?**
A: No! It's now optional. Use `kubectl apply -k k8s/` instead.

**Q: How do I deploy just Image Updater without ArgoCD?**
A: `kubectl apply -k k8s/argocd-image-updater/overlays/dev`

**Q: Can I skip Image Updater installation?**
A: Remove the line from `k8s/kustomization.yaml` and redeploy.

**Q: How do I verify everything deployed correctly?**
A: Run: `./scripts/validate-argocd-setup.sh`

**Q: What if Image Updater pod fails to start?**
A: Check logs: `kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater`

## 🚀 Next Steps

1. **Deploy the stack:**
   ```bash
   kubectl apply -k k8s/
   ```

2. **Verify installation:**
   ```bash
   ./scripts/validate-argocd-setup.sh
   ```

3. **Access ArgoCD UI:**
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   # Open: https://localhost:8080
   ```

4. **Build and push an image:**
   ```bash
   ./scripts/build-push-ecr.sh notification-service
   ```

5. **Watch auto-update happen** (wait ~2 minutes and check ArgoCD UI)

---

**Result:** Fully automated GitOps with automatic image updates, all from a single `kubectl apply -k k8s/` command! 🎉
