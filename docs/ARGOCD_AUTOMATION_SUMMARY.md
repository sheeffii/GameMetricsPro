# ArgoCD & Image Updater - Automated Setup Summary

## 🎯 What Was Created

This automation package makes ArgoCD and automated image updates easy to deploy in fresh environments.

### 📁 New Directory Structure

```
k8s/argocd-image-updater/
├── base/
│   ├── kustomization.yaml          # Base Kustomize config
│   ├── configmap.yaml              # ArgoCD & ECR configuration
│   └── config-patch.yaml           # ConfigMap customization patch
├── overlays/
│   └── dev/
│       └── kustomization.yaml      # Dev environment overlay
└── README.md                       # Detailed setup documentation

scripts/
├── bootstrap-argocd.sh             # 🚀 ONE-COMMAND fresh install
└── create-image-updater-crs.sh    # Helper to create ImageUpdater CRs

docs/
├── ARGOCD_SETUP.md                 # Complete setup guide
└── ARGOCD_QUICK_REFERENCE.md       # Quick command reference
```

## 🚀 Quick Start Commands

### For Fresh Environment (One Command)

```bash
# Install everything (ArgoCD + Image Updater + Applications)
./scripts/bootstrap-argocd.sh dev
```

**What this does:**
1. ✅ Installs ArgoCD v2.9.3
2. ✅ Retrieves and saves admin credentials
3. ✅ Creates ArgoCD project (`gamemetrics`)
4. ✅ Installs Image Updater via Kustomize
5. ✅ Configures ECR registry
6. ✅ Applies all ArgoCD Applications
7. ✅ Provides next steps

### For Existing ArgoCD (Image Updater Only)

```bash
# Install Image Updater
kubectl apply -k k8s/argocd-image-updater/overlays/dev

# Verify
kubectl get pods -n argocd-image-updater-system
```

### Access ArgoCD UI

```bash
# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get password
cat .argocd-credentials

# Open: https://localhost:8080
```

## 📦 What's Installed

### ArgoCD (Namespace: argocd)
- **argocd-server** - Web UI and API
- **argocd-application-controller** - Monitors and syncs apps
- **argocd-repo-server** - Git repository interface
- **argocd-dex-server** - SSO/OAuth
- **argocd-redis** - Caching

### ArgoCD Image Updater (Namespace: argocd-image-updater-system)
- **argocd-image-updater-controller** - Monitors ECR for new images
- **ImageUpdater CRD** - Custom resource definition
- **RBAC** - ServiceAccount, ClusterRole, Bindings
- **ConfigMap** - ArgoCD and ECR configuration

### ArgoCD Applications (Namespace: argocd)
- **event-ingestion-dev** - Event ingestion service
- **notification-service-dev** - Notification service
- (Other applications as configured)

## 🔄 How It Works

```
┌────────────────────────┐
│   Developer Pushes     │
│   Code to GitHub       │
└───────────┬────────────┘
            │
            ↓
┌────────────────────────┐         ┌──────────────────────┐
│   GitHub Actions CI    │────────→│    AWS ECR           │
│   Builds Docker Image  │         │  New image pushed    │
└────────────────────────┘         └──────────┬───────────┘
                                              │
                                              ↓
                                   ┌──────────────────────┐
                                   │  Image Updater       │
                                   │  Detects new image   │
                                   │  (every 2 minutes)   │
                                   └──────────┬───────────┘
                                              │
                                              ↓
                                   ┌──────────────────────┐
                                   │  ArgoCD Application  │
                                   │  Updated with new    │
                                   │  image tag           │
                                   └──────────┬───────────┘
                                              │
                                              ↓
                                   ┌──────────────────────┐
                                   │  ArgoCD Syncs        │
                                   │  Deploys to K8s      │
                                   └──────────┬───────────┘
                                              │
                                              ↓
                                   ┌──────────────────────┐
                                   │  Pods Rolling Update │
                                   │  New version live!   │
                                   └──────────────────────┘
```

## ⚙️ Configuration

### ECR Registry (Pre-configured)
- **Account ID:** 647523695124
- **Region:** us-east-1
- **Repositories:**
  - event-ingestion-service
  - notification-service

### Image Update Strategy
- **Method:** Latest tag (updates to newest image automatically)
- **Interval:** 2 minutes (configurable)
- **Write-back:** ArgoCD (updates Application directly)

### To Change ECR Settings

Edit: `k8s/argocd-image-updater/base/configmap.yaml`

```yaml
registries.conf: |
  registries:
  - name: ECR
    prefix: YOUR_ACCOUNT.dkr.ecr.YOUR_REGION.amazonaws.com
    api_url: https://YOUR_ACCOUNT.dkr.ecr.YOUR_REGION.amazonaws.com
    credentials: ext:/scripts/aws-ecr-creds.sh
    credsexpire: 10h
```

Then reapply:
```bash
kubectl apply -k k8s/argocd-image-updater/overlays/dev
kubectl rollout restart deployment/argocd-image-updater-controller -n argocd-image-updater-system
```

## 🌍 Multi-Environment Support

### Create New Environment (e.g., staging)

```bash
# Create overlay
mkdir -p k8s/argocd-image-updater/overlays/staging
cp k8s/argocd-image-updater/overlays/dev/kustomization.yaml \
   k8s/argocd-image-updater/overlays/staging/

# Bootstrap staging
./scripts/bootstrap-argocd.sh staging
```

### Environment-Specific Configuration

Create patches in overlay directories:

```yaml
# k8s/argocd-image-updater/overlays/staging/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

patchesStrategicMerge:
  - |-
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: argocd-image-updater-config
    data:
      interval: "5m"  # Check every 5 minutes in staging
```

## 📚 Documentation

### Comprehensive Guides
- **[ARGOCD_SETUP.md](./ARGOCD_SETUP.md)** - Complete installation and configuration guide
- **[ARGOCD_QUICK_REFERENCE.md](./ARGOCD_QUICK_REFERENCE.md)** - Command cheatsheet
- **[k8s/argocd-image-updater/README.md](../k8s/argocd-image-updater/README.md)** - Image Updater details

### Scripts
- **bootstrap-argocd.sh** - Automated fresh installation
- **create-image-updater-crs.sh** - Generate ImageUpdater custom resources
- **build-push-ecr.sh** - Build and push images to ECR

## 🔍 Verification

### Check Installation

```bash
# All namespaces
kubectl get pods -A | grep argocd

# ArgoCD
kubectl get pods -n argocd

# Image Updater
kubectl get pods -n argocd-image-updater-system

# Applications
kubectl get applications -n argocd

# Services
kubectl get deployments -n gamemetrics
```

### Test Image Update

```bash
# 1. Build and push new image
./scripts/build-push-ecr.sh notification-service

# 2. Wait 2 minutes

# 3. Check if Application updated
kubectl get application notification-service-dev -n argocd -o jsonpath='{.spec.source.kustomize.images}'

# 4. Verify deployment
kubectl get deployment notification-service -n gamemetrics -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## 🐛 Troubleshooting

### Image Updater Not Working

```bash
# Check logs
kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater -f

# Common issues:
# 1. ECR authentication - ensure IAM role has ECR permissions
# 2. ArgoCD connectivity - check if Image Updater can reach argocd-server
# 3. CRD vs annotations - v1.0+ uses CRDs by default
```

### Application OutOfSync

```bash
# Force refresh
kubectl patch application notification-service-dev -n argocd \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Check diff
kubectl get application notification-service-dev -n argocd -o yaml
```

### RBAC Errors

```bash
# Check ServiceAccount
kubectl get sa argocd-image-updater-controller -n argocd-image-updater-system

# Check ClusterRole
kubectl get clusterrole argocd-image-updater-manager-role

# Check ClusterRoleBinding
kubectl get clusterrolebinding argocd-image-updater-manager-rolebinding
```

## 🎓 Best Practices

### Image Tagging Strategy
- **Development:** Use `latest` tag with auto-update
- **Staging:** Use semantic versions (e.g., `v1.2.3`)
- **Production:** Pin to specific digest for maximum stability

### Security
- ✅ Use IAM roles for ECR authentication (IRSA on EKS)
- ✅ Enable ArgoCD RBAC for multi-tenant environments
- ✅ Use Git as single source of truth
- ✅ Review image updates before production

### Monitoring
- Monitor Image Updater logs for errors
- Set up alerts for Application OutOfSync status
- Track image update frequency and success rate
- Use ArgoCD notifications for deployment events

## 🆘 Support

### Quick Commands
```bash
# Get help
./scripts/bootstrap-argocd.sh --help

# Check status
kubectl get all -n argocd
kubectl get all -n argocd-image-updater-system

# View logs
kubectl logs -n argocd deployment/argocd-application-controller -f
kubectl logs -n argocd-image-updater-system deployment/argocd-image-updater-controller -f
```

### References
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Image Updater Docs](https://argocd-image-updater.readthedocs.io/)
- [Kustomize Documentation](https://kustomize.io/)

## ✅ Success Checklist

After running `./scripts/bootstrap-argocd.sh dev`:

- [ ] ArgoCD UI accessible at https://localhost:8080
- [ ] Admin credentials saved in `.argocd-credentials`
- [ ] Image Updater pod Running (1/1)
- [ ] All ArgoCD Applications showing in UI
- [ ] Services deployed in `gamemetrics` namespace
- [ ] Can build and push images to ECR
- [ ] Image updates detected within 2 minutes

## 🚀 Next Steps

1. **Access ArgoCD UI** and explore your applications
2. **Build your first image:** `./scripts/build-push-ecr.sh notification-service`
3. **Watch auto-update happen** in ArgoCD UI (wait 2 minutes)
4. **Set up monitoring** for production environments
5. **Configure staging/prod** overlays for multi-environment

---

**Congratulations!** 🎉 You now have a fully automated GitOps deployment pipeline with automatic image updates!
