# Next Steps to Complete ArgoCD + GitHub Actions Setup

## Current Status Check

✅ **Terraform Creates**:
- EKS cluster (gamemetrics-dev)
- 3 node groups: system, application, data
- ECR repository for event-ingestion-service
- RDS PostgreSQL database
- ElastiCache Redis
- VPC with public/private subnets

⚠️ **Issues Found**:
- ArgoCD not installed (argocd.tf is empty!)
- No Kubernetes namespaces created
- No secrets for database/Kafka credentials
- GitHub Actions bypasses ArgoCD (direct kubectl deployment)

❓ **Questions**:
- Has Terraform been run yet?
- Is EKS cluster live?

---

## Step 1: Run Terraform to Create Cluster (If Not Done)

### Check Current State
```powershell
cd c:\Users\Shefqet\Desktop\RealtimeGaming\terraform\environments\dev

# Show what will be created
terraform plan

# Apply to create resources (this takes 15-20 minutes)
terraform apply
```

### After Terraform Completes:
```powershell
# Get cluster credentials
aws eks update-kubeconfig --region us-east-1 --name gamemetrics-dev

# Verify connection
kubectl get nodes
# Should show 4 nodes (1 system + 2 application + 1 data)
```

---

## Step 2: Install ArgoCD in Cluster

### Option A: Add to Terraform (Recommended - GitOps)

Update `terraform/environments/dev/argocd.tf`:

```terraform
# ArgoCD Namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [module.eks]
}

# ArgoCD Helm Release
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.46.8"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      global = {
        domain = "argocd.gamemetrics.local"
      }
      configs = {
        secret = {
          argocdServerAdminPassword = base64encode(random_password.argocd_admin_password.result)
        }
      }
      server = {
        service = {
          type = "LoadBalancer"
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# Generate ArgoCD Admin Password
resource "random_password" "argocd_admin_password" {
  length  = 16
  special = true
}

output "argocd_admin_password" {
  value       = random_password.argocd_admin_password.result
  description = "ArgoCD admin password"
  sensitive   = true
}
```

Then apply:
```powershell
terraform apply
```

### Option B: Install Manually (If Terraform Not Available)

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for it to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

---

## Step 3: Create Namespaces & Secrets

### Create Application Namespace
```bash
kubectl create namespace gamemetrics
kubectl label namespace gamemetrics name=gamemetrics
```

### Create Database Secret
```bash
# Get RDS details from Terraform output
terraform output -raw rds_endpoint    # e.g., gamemetrics-dev.xxxxx.us-east-1.rds.amazonaws.com
terraform output -raw rds_password    # Generate or get from Terraform

# Create secret
kubectl create secret generic db-credentials \
  --from-literal=DB_HOST=gamemetrics-dev.xxxxx.us-east-1.rds.amazonaws.com \
  --from-literal=DB_PORT=5432 \
  --from-literal=DB_NAME=gamemetrics \
  --from-literal=DB_USER=dbadmin \
  --from-literal=DB_PASSWORD='your-rds-password' \
  -n gamemetrics

# Verify
kubectl get secret db-credentials -n gamemetrics
```

### Create Kafka Secret (For Dev/Test)
```bash
# For Kafka in cluster, use internal service name
kubectl create secret generic kafka-credentials \
  --from-literal=KAFKA_BOOTSTRAP_SERVERS=kafka-cluster-kafka-bootstrap.kafka:9092 \
  --from-literal=KAFKA_SECURITY_PROTOCOL=PLAINTEXT \
  -n gamemetrics

# Verify
kubectl get secret kafka-credentials -n gamemetrics
```

### Create ECR Pull Secret (For Private Images)
```bash
# Get AWS account ID from ECR module output
REGISTRY=$(terraform output -raw ecr_registry_url)
ACCOUNT_ID=$(echo $REGISTRY | cut -d'.' -f1)

# Create ECR credentials
kubectl create secret docker-registry ecr-secret \
  --docker-server=$REGISTRY \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-east-1) \
  -n gamemetrics

# Patch deployment to use it (will do in next step)
```

---

## Step 4: Fix GitHub Actions to Use GitOps (Critical!)

Your GitHub Actions workflow currently bypasses ArgoCD. We need to fix it.

### Current Problem Code
File: `.github/workflows/build-event-ingestion.yml` (lines 191-263)

```yaml
deploy-to-prod:
  name: Deploy to Production (Manual Approval)
  needs: build-and-push
  
  steps:
    - name: Deploy to Kubernetes
      run: |
        kubectl set image deployment/event-ingestion \
          event-ingestion=${{ needs.build-and-push.outputs.image-uri }} \
          -n gamemetrics
```

**Problem**: This directly updates Kubernetes, bypassing ArgoCD!

### Fix: Update Deployment Manifest Instead

Replace the entire `deploy-to-prod` job with:

```yaml
deploy-to-prod:
  name: Update Manifest for ArgoCD (Manual Approval)
  needs: build-and-push
  if: github.ref == 'refs/heads/main'
  environment:
    name: production
  
  permissions:
    contents: write
  
  steps:
    - name: Checkout code
      uses: actions/checkout@v4
      with:
        ref: main
        token: ${{ secrets.GITHUB_TOKEN }}

    - name: Update deployment image
      env:
        NEW_IMAGE: ${{ needs.build-and-push.outputs.image-uri }}
      run: |
        # Update the deployment.yaml with new image
        sed -i "s|image:.*event-ingestion-service:.*|image: ${{ env.NEW_IMAGE }}|g" \
          k8s/services/event-ingestion/deployment.yaml
        
        # Verify the change
        echo "Updated deployment.yaml:"
        grep "image:" k8s/services/event-ingestion/deployment.yaml

    - name: Commit and push to Git
      run: |
        git config user.email "github-actions[bot]@users.noreply.github.com"
        git config user.name "GitHub Actions Bot"
        
        git add k8s/services/event-ingestion/deployment.yaml
        git commit -m "ci: update event-ingestion image to ${{ needs.build-and-push.outputs.image-uri }}
        
        New image tag: ${{ needs.build-and-push.outputs.image-uri }}
        Build commit: ${{ github.sha }}"
        
        git push origin main

    - name: Trigger ArgoCD sync (optional)
      env:
        ARGOCD_SERVER: ${{ secrets.ARGOCD_SERVER }}
        ARGOCD_AUTH_TOKEN: ${{ secrets.ARGOCD_AUTH_TOKEN }}
      run: |
        # Optional: Tell ArgoCD to sync immediately
        curl -X POST ${{ env.ARGOCD_SERVER }}/api/v1/applications/event-ingestion-prod/sync \
          -H "Authorization: Bearer ${{ env.ARGOCD_AUTH_TOKEN }}"
```

Also remove/disable the `deploy-to-dev` manual kubectl deployment and replace with:

```yaml
deploy-to-dev:
  name: Update Dev Manifest
  needs: build-and-push
  if: github.ref == 'refs/heads/develop'
  
  permissions:
    contents: write
  
  steps:
    - name: Checkout code
      uses: actions/checkout@v4
      with:
        ref: develop
        token: ${{ secrets.GITHUB_TOKEN }}

    - name: Update deployment image
      env:
        NEW_IMAGE: ${{ needs.build-and-push.outputs.image-uri }}
      run: |
        sed -i "s|image:.*event-ingestion-service:.*|image: ${{ env.NEW_IMAGE }}|g" \
          k8s/services/event-ingestion/deployment.yaml

    - name: Commit and push to Git
      run: |
        git config user.email "github-actions[bot]@users.noreply.github.com"
        git config user.name "GitHub Actions Bot"
        
        git add k8s/services/event-ingestion/deployment.yaml
        git commit -m "ci: update event-ingestion dev image to ${{ needs.build-and-push.outputs.image-uri }}"
        git push origin develop
```

---

## Step 5: Create ArgoCD Applications (If Not Already)

These should already exist in your repo, but verify they match:

### File: `k8s/argocd/application-event-ingestion-prod.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: event-ingestion-prod
  namespace: argocd
spec:
  project: gamemetrics
  
  source:
    repoURL: https://github.com/sheeffii/RealtimeGaming.git
    targetRevision: main
    path: k8s/services/event-ingestion
  
  destination:
    server: https://kubernetes.default.svc
    namespace: gamemetrics
  
  syncPolicy:
    # Manual for production (safe!)
    automated:
      selfHeal: false
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### File: `k8s/argocd/application-event-ingestion-dev.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: event-ingestion-dev
  namespace: argocd
spec:
  project: gamemetrics
  
  source:
    repoURL: https://github.com/sheeffii/RealtimeGaming.git
    targetRevision: develop
    path: k8s/services/event-ingestion
  
  destination:
    server: https://kubernetes.default.svc
    namespace: gamemetrics
  
  syncPolicy:
    # Auto-sync for development
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Apply to cluster:
```bash
kubectl apply -f k8s/argocd/application-event-ingestion-prod.yaml
kubectl apply -f k8s/argocd/application-event-ingestion-dev.yaml
```

---

## Step 6: Update Deployment Manifest

Make sure `k8s/services/event-ingestion/deployment.yaml` has:

1. **Correct image reference** (no hardcoded account ID):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: event-ingestion
  namespace: gamemetrics
spec:
  replicas: 2
  selector:
    matchLabels:
      app: event-ingestion
  template:
    metadata:
      labels:
        app: event-ingestion
    spec:
      imagePullSecrets:
      - name: ecr-secret  # Use ECR secret created earlier
      
      containers:
      - name: event-ingestion
        # GitHub Actions will update this line
        image: 647523695124.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service:latest
        imagePullPolicy: Always
        
        ports:
        - name: http
          containerPort: 8080
        - name: metrics
          containerPort: 9090
        
        env:
        # Database
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_HOST
        - name: DB_PORT
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_PORT
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_NAME
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_PASSWORD
        
        # Kafka
        - name: KAFKA_BOOTSTRAP_SERVERS
          valueFrom:
            secretKeyRef:
              name: kafka-credentials
              key: KAFKA_BOOTSTRAP_SERVERS
        - name: KAFKA_TOPIC_PLAYER_EVENTS
          value: "player-events"
        - name: KAFKA_TOPIC_USER_ACTIONS
          value: "user-actions"
        
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

---

## Step 7: Verify Everything Works

### 1. Push the Fixed GitHub Actions Workflow
```bash
git add .github/workflows/build-event-ingestion.yml
git commit -m "feat: fix GitHub Actions to use GitOps (update manifests, not direct deployment)"
git push origin main
```

### 2. Test the Complete Flow
```bash
# Make a code change
echo "# Test change" >> services/event-ingestion-service/README.md

# Push it
git add services/event-ingestion-service/README.md
git commit -m "test: trigger CI/CD pipeline"
git push origin main

# Watch GitHub Actions
# Go to: https://github.com/sheeffii/RealtimeGaming/actions
# Watch the workflow run

# Check ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access: https://localhost:8080
# Username: admin
# Password: <from terraform output>

# Check if application shows "OutOfSync" (means GitHub Actions updated manifest)
# Then sync manually for production
```

### 3. Verify Deployment
```bash
# Check if deployment is running
kubectl get deployment event-ingestion -n gamemetrics

# Check pods
kubectl get pods -n gamemetrics

# Check logs
kubectl logs -n gamemetrics -l app=event-ingestion --tail=50

# Check if using new image
kubectl get deployment event-ingestion -n gamemetrics -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

## Step 8: Set Up GitHub Secrets for CI/CD Integration

### Add these secrets to GitHub repo:
```
Settings → Secrets and variables → Actions → New repository secret
```

| Secret Name | Value | Where From |
|------------|-------|-----------|
| ARGOCD_SERVER | https://\<ARGOCD-LOAD-BALANCER-IP\>:443 | kubectl get svc -n argocd argocd-server |
| ARGOCD_AUTH_TOKEN | \<token\> | Get from ArgoCD admin console |
| AWS_ACCOUNT_ID | 647523695124 | From ECR module output |

---

## Complete Flow After Fixes

```
1. Developer Commits Code
   └─ git push origin main

2. GitHub Actions Triggers
   ├─ build-and-push: Builds Docker image, pushes to ECR
   ├─ Output: image-uri (e.g., 647523695124.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service:main-abc123)
   └─ deploy-to-prod: ✨ UPDATES MANIFEST in Git ✨
      ├─ Updates: k8s/services/event-ingestion/deployment.yaml
      ├─ Changes image tag to: main-abc123
      └─ Commits back to main branch

3. ArgoCD Detects Change (every 3 minutes)
   ├─ Sees: deployment.yaml changed
   ├─ Status: OutOfSync
   └─ Shows in UI: "New image version available"

4. Operator Reviews & Approves (Manual Approval)
   └─ argocd app sync event-ingestion-prod

5. Kubernetes Applies Changes
   ├─ Updates deployment with new image
   ├─ Kubernetes pulls image from ECR
   ├─ Terminates old pods
   ├─ Creates new pods with new image
   └─ Service routes traffic to new pods

6. Done! ✓
   └─ New code running in production
```

---

## Troubleshooting

### ArgoCD shows "OutOfSync" but won't sync
- Check: Does ArgoCD have permission to read from GitHub repo?
- Solution: Add deploy key to GitHub repo

### Deployment not updating
- Check: Did GitHub Actions workflow run successfully?
- Check: Did manifest actually change in Git?
  ```bash
  git log --oneline k8s/services/event-ingestion/deployment.yaml
  ```

### Image pull fails
- Check: Is ECR secret created in namespace?
  ```bash
  kubectl get secret -n gamemetrics
  ```
- Check: Does pod have permission to pull from ECR?

### GitHub Actions fails on git push
- Check: Does the workflow have permission to commit?
- Solution: Use `GITHUB_TOKEN` with `contents: write` permission

---

## Quick Reference

| Action | Command |
|--------|---------|
| Check cluster | `kubectl get nodes` |
| View ArgoCD | `kubectl port-forward svc/argocd-server -n argocd 8080:443` |
| Check app status | `argocd app get event-ingestion-prod` |
| Manual sync | `argocd app sync event-ingestion-prod` |
| View logs | `kubectl logs -f -n gamemetrics -l app=event-ingestion` |
| Check image running | `kubectl get deployment event-ingestion -n gamemetrics -o jsonpath='{.spec.template.spec.containers[0].image}'` |

