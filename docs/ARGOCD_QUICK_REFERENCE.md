# ArgoCD Quick Reference Card

## 🚀 One-Command Setup (Fresh Environment)
```bash
./scripts/bootstrap-argocd.sh dev
```

## 📊 Common Commands

### ArgoCD Access
```bash
# Port forward UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# UI: https://localhost:8080 (admin / <password>)
```

### Application Management
```bash
# List all applications
kubectl get applications -n argocd

# Check application status
kubectl get app <app-name> -n argocd -o yaml

# Force sync
kubectl patch app <app-name> -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Delete application
kubectl delete application <app-name> -n argocd
```

### Image Updater
```bash
# Check Image Updater status
kubectl get pods -n argocd-image-updater-system

# View logs
kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater -f

# List ImageUpdater CRs
kubectl get imageupdaters -n argocd-image-updater-system

# Describe ImageUpdater
kubectl describe imageupdater <name> -n argocd-image-updater-system
```

### Build & Deploy
```bash
# Build and push image
./scripts/build-push-ecr.sh <service-name>

# Example:
./scripts/build-push-ecr.sh notification-service
./scripts/build-push-ecr.sh event-ingestion

# Image Updater will detect new images within 2 minutes
```

### Deployment Status
```bash
# Check all deployments
kubectl get deployments -n gamemetrics

# Check specific deployment
kubectl get deployment <name> -n gamemetrics -o wide

# View deployment events
kubectl describe deployment <name> -n gamemetrics

# Scale deployment
kubectl scale deployment <name> --replicas=<count> -n gamemetrics
```

### Logs & Debugging
```bash
# Service logs
kubectl logs -n gamemetrics deployment/<service-name> -f

# ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller -f

# Image Updater logs
kubectl logs -n argocd-image-updater-system deployment/argocd-image-updater-controller -f

# All pods in namespace
kubectl get pods -n <namespace> -o wide
```

### ECR Operations
```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 647523695124.dkr.ecr.us-east-1.amazonaws.com

# List images in repository
aws ecr describe-images --repository-name <repo-name> --region us-east-1

# List all repositories
aws ecr describe-repositories --region us-east-1
```

## 🔧 Troubleshooting

### Application OutOfSync
```bash
# Check diff
kubectl get app <app-name> -n argocd -o yaml | grep -A 20 status:

# Force refresh
kubectl patch app <app-name> -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Manual sync
kubectl patch app <app-name> -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

### Image Not Updating
```bash
# Check Image Updater logs
kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater --tail=100 | grep -i error

# Verify ImageUpdater CR
kubectl get imageupdater -n argocd-image-updater-system -o yaml

# Check application annotations
kubectl get app <app-name> -n argocd -o jsonpath='{.metadata.annotations}'

# Test ECR access
kubectl run ecr-test --image=647523695124.dkr.ecr.us-east-1.amazonaws.com/<repo>:latest --rm -it --restart=Never
```

### Pod CrashLoopBackOff
```bash
# Check pod logs
kubectl logs -n gamemetrics <pod-name> --previous

# Describe pod
kubectl describe pod <pod-name> -n gamemetrics

# Check events
kubectl get events -n gamemetrics --sort-by='.lastTimestamp'

# Check resource constraints
kubectl top nodes
kubectl top pods -n gamemetrics
```

### RBAC Issues
```bash
# Check ServiceAccount
kubectl get sa -n <namespace>

# Check RBAC
kubectl get clusterrolebinding | grep <service-account>

# Describe for details
kubectl describe clusterrolebinding <name>
```

## 📁 File Locations

### Configuration Files
- **ArgoCD Applications:** `k8s/argocd/application-*.yaml`
- **Image Updater Base:** `k8s/argocd-image-updater/base/`
- **Image Updater Overlays:** `k8s/argocd-image-updater/overlays/<env>/`
- **Service Manifests:** `k8s/services/<service-name>/`
- **Bootstrap Script:** `scripts/bootstrap-argocd.sh`

### Credentials
- **ArgoCD Admin:** `.argocd-credentials` (auto-generated)
- **Kubeconfig:** `~/.kube/config`
- **AWS Credentials:** `~/.aws/credentials`

## 🌐 Important URLs

- **ArgoCD UI:** https://localhost:8080 (after port-forward)
- **GitHub Repo:** https://github.com/sheeffii/GameMetricsPro
- **ECR Registry:** 647523695124.dkr.ecr.us-east-1.amazonaws.com

## 📝 Environment Variables

```bash
# Set context
export KUBECONFIG=~/.kube/config

# AWS region
export AWS_REGION=us-east-1

# ECR registry
export ECR_REGISTRY=647523695124.dkr.ecr.us-east-1.amazonaws.com
```

## 🎯 Common Workflows

### Adding a New Service
1. Create service manifests in `k8s/services/<service-name>/`
2. Create ArgoCD Application in `k8s/argocd/application-<service>-dev.yaml`
3. Apply: `kubectl apply -f k8s/argocd/application-<service>-dev.yaml`
4. (Optional) Create ImageUpdater CR: `./scripts/create-image-updater-crs.sh`

### Updating a Service
1. Build new image: `./scripts/build-push-ecr.sh <service>`
2. Wait 2 minutes for auto-update OR
3. Manual sync: `kubectl patch app <app-name> -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'`

### Rolling Back
1. Find previous revision: `kubectl get app <app-name> -n argocd -o yaml | grep revision`
2. Rollback deployment: `kubectl rollout undo deployment/<name> -n gamemetrics`
3. OR sync to previous Git commit in ArgoCD UI

### Fresh Installation
```bash
# Complete fresh install
./scripts/bootstrap-argocd.sh dev

# Access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Check everything
kubectl get pods -n argocd
kubectl get pods -n argocd-image-updater-system
kubectl get applications -n argocd
kubectl get deployments -n gamemetrics
```

## 🔗 Quick Links

- [Full Setup Guide](./ARGOCD_SETUP.md)
- [Image Updater Details](../k8s/argocd-image-updater/README.md)
- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
- [Image Updater Docs](https://argocd-image-updater.readthedocs.io/)
