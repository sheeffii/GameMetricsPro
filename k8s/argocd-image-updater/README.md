# ArgoCD Image Updater Installation

This directory contains the Kustomize configuration for ArgoCD Image Updater, which automatically updates container images in ArgoCD Applications when new versions are pushed to ECR.

## Directory Structure

```
k8s/argocd-image-updater/
├── base/
│   ├── kustomization.yaml       # Base configuration
│   ├── configmap.yaml           # ArgoCD and ECR configuration
│   └── config-patch.yaml        # ConfigMap patch for customization
└── overlays/
    └── dev/
        └── kustomization.yaml   # Dev environment overlay
```

## What Gets Installed

- **ArgoCD Image Updater Controller** (v1.0.1)
- **Custom Resource Definitions** (ImageUpdater CRD)
- **RBAC** (ServiceAccount, ClusterRole, RoleBindings)
- **ConfigMap** with ArgoCD server and ECR registry configuration
- **Metrics Service** for monitoring

## Installation Methods

### Method 1: Using Bootstrap Script (Recommended for Fresh Environments)

The bootstrap script installs ArgoCD and Image Updater in the correct order:

```bash
# From project root
./scripts/bootstrap-argocd.sh dev
```

This script:
1. ✅ Checks prerequisites (kubectl, cluster connectivity)
2. ✅ Installs ArgoCD (if not present)
3. ✅ Retrieves admin credentials
4. ✅ Creates ArgoCD project
5. ✅ Installs Image Updater via Kustomize
6. ✅ Applies ArgoCD Applications
7. ✅ Verifies installation

### Method 2: Manual Installation with Kustomize

If you already have ArgoCD installed:

```bash
# Install Image Updater for dev environment
kubectl apply -k k8s/argocd-image-updater/overlays/dev

# Wait for rollout
kubectl rollout status deployment/argocd-image-updater-controller -n argocd-image-updater-system

# Verify pods
kubectl get pods -n argocd-image-updater-system
```

### Method 3: Via ArgoCD Application (GitOps)

Create an ArgoCD Application to manage Image Updater itself:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-image-updater
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/sheeffii/GameMetricsPro.git
    targetRevision: main
    path: k8s/argocd-image-updater/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd-image-updater-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Configuration

### ECR Registry Setup

The Image Updater is pre-configured for AWS ECR:

```yaml
registries:
- name: ECR
  prefix: 647523695124.dkr.ecr.us-east-1.amazonaws.com
  api_url: https://647523695124.dkr.ecr.us-east-1.amazonaws.com
  credentials: ext:/scripts/aws-ecr-creds.sh
  credsexpire: 10h
```

**Note:** For ECR authentication, ensure your EKS nodes have the appropriate IAM role with ECR pull permissions, or configure AWS credentials in the Image Updater pod.

### Customizing for Different Environments

Edit `overlays/<env>/kustomization.yaml` to add environment-specific patches:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

# Override for different AWS account/region
patchesStrategicMerge:
  - |-
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: argocd-image-updater-config
      namespace: argocd-image-updater-system
    data:
      registries.conf: |
        registries:
        - name: ECR
          prefix: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_REGION.amazonaws.com
          api_url: https://YOUR_ACCOUNT_ID.dkr.ecr.YOUR_REGION.amazonaws.com
          credentials: ext:/scripts/aws-ecr-creds.sh
          credsexpire: 10h
```

## How It Works

### ArgoCD Image Updater v1.0+ (CRD-Based)

This version uses **ImageUpdater Custom Resources** instead of annotations:

```yaml
apiVersion: argocd-image-updater.argoproj.io/v1alpha1
kind: ImageUpdater
metadata:
  name: notification-service
  namespace: argocd-image-updater-system
spec:
  sourceRef:
    kind: Application
    name: notification-service-dev
    namespace: argocd
  images:
    - image: 647523695124.dkr.ecr.us-east-1.amazonaws.com/notification-service
      updateStrategy:
        strategy: latest
  writeBack:
    method: argocd
```

### Legacy Annotation-Based (v0.12.x)

Your applications already have annotations configured:

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: notification-service=647523695124.dkr.ecr.us-east-1.amazonaws.com/notification-service
    argocd-image-updater.argoproj.io/notification-service.update-strategy: latest
    argocd-image-updater.argoproj.io/write-back-method: argocd
```

**Note:** If you prefer annotation-based updates, downgrade to v0.12.x by editing `base/kustomization.yaml`.

## Verification

### Check Installation

```bash
# Check Image Updater pods
kubectl get pods -n argocd-image-updater-system

# Expected output:
# NAME                                               READY   STATUS    RESTARTS   AGE
# argocd-image-updater-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

### View Logs

```bash
# Follow Image Updater logs
kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater -f

# Check for image update activity
kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater --tail=100 | grep -i "update"
```

### Test Image Update

1. Build and push a new image:
   ```bash
   ./scripts/build-push-ecr.sh notification-service
   ```

2. Image Updater will detect the new image within 2 minutes (default interval)

3. Check ArgoCD Application status:
   ```bash
   kubectl get application notification-service-dev -n argocd -o yaml
   ```

## Monitoring

### Health Check

```bash
# Check health endpoint
kubectl port-forward -n argocd-image-updater-system \
  svc/argocd-image-updater-controller-metrics-service 8081:8081

curl http://localhost:8081/healthz
```

### Metrics

Metrics are available at `:8443/metrics`:

```bash
kubectl port-forward -n argocd-image-updater-system \
  svc/argocd-image-updater-controller-metrics-service 8443:8443

curl -k https://localhost:8443/metrics
```

## Troubleshooting

### Image Updater Not Detecting Updates

1. **Check logs:**
   ```bash
   kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater --tail=100
   ```

2. **Verify ECR access:**
   ```bash
   # Check if pods can pull from ECR
   kubectl run ecr-test --image=647523695124.dkr.ecr.us-east-1.amazonaws.com/notification-service:latest --rm -it --restart=Never
   ```

3. **Check ImageUpdater CR status (if using CRD approach):**
   ```bash
   kubectl get imageupdaters -n argocd-image-updater-system -o yaml
   ```

### ArgoCD Connection Issues

Check ArgoCD server connectivity:

```bash
# Test from Image Updater pod
kubectl exec -n argocd-image-updater-system \
  deployment/argocd-image-updater-controller -- \
  curl -k https://argocd-server.argocd.svc.cluster.local
```

### RBAC Issues

Ensure the ServiceAccount has proper permissions:

```bash
# Check ClusterRoleBindings
kubectl get clusterrolebinding | grep argocd-image-updater

# Check pod logs for permission errors
kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater | grep -i forbidden
```

## Uninstallation

```bash
# Delete Image Updater
kubectl delete -k k8s/argocd-image-updater/overlays/dev

# Or delete namespace (removes everything)
kubectl delete namespace argocd-image-updater-system
```

## References

- [ArgoCD Image Updater Documentation](https://argocd-image-updater.readthedocs.io/)
- [GitHub Repository](https://github.com/argoproj-labs/argocd-image-updater)
- [ECR Authentication Guide](https://argocd-image-updater.readthedocs.io/en/stable/configuration/registries/#amazon-ecr)

## Support

For issues specific to this installation:
1. Check logs: `kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater`
2. Verify ArgoCD Applications: `kubectl get applications -n argocd`
3. Review configuration: `kubectl get configmap argocd-image-updater-config -n argocd-image-updater-system -o yaml`
