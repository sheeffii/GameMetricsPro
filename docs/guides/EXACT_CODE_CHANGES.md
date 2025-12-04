# Exact Code Changes Required

## Problem Summary

Your current setup has 3 issues:

1. **GitHub Actions bypasses ArgoCD** (uses kubectl directly) ❌
2. **Deployment manifest has hardcoded AWS account ID** ❌
3. **ArgoCD never sees image updates** ❌

---

## Fix #1: Update GitHub Actions Workflow

### File: `.github/workflows/build-event-ingestion.yml`

Replace the entire `deploy-to-prod` job (lines ~191-263):

**CURRENT (WRONG)**:
```yaml
deploy-to-prod:
  name: Deploy to Production
  needs: build-and-push
  if: github.ref == 'refs/heads/main'
  environment:
    name: production
    url: https://event-ingestion.gamemetrics.local
  
  steps:
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: us-east-1
    
    - name: Update kubeconfig
      run: |
        aws eks update-kubeconfig \
          --name gamemetrics-dev \
          --region us-east-1
    
    - name: Deploy to Kubernetes
      run: |
        kubectl set image deployment/event-ingestion \
          event-ingestion=${{ needs.build-and-push.outputs.image-uri }} \
          -n gamemetrics --record
```

**NEW (CORRECT)**:
```yaml
deploy-to-prod:
  name: Update Production Manifest for ArgoCD
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
        
        # Verify change
        echo "✓ Updated deployment with image: ${{ env.NEW_IMAGE }}"
        grep "image:" k8s/services/event-ingestion/deployment.yaml

    - name: Commit and push to Git
      env:
        IMAGE_TAG: ${{ needs.build-and-push.outputs.image-tag }}
      run: |
        git config user.email "github-actions[bot]@users.noreply.github.com"
        git config user.name "GitHub Actions Bot"
        
        git add k8s/services/event-ingestion/deployment.yaml
        
        git commit -m "ci: bump event-ingestion image to ${{ env.IMAGE_TAG }}
        
        Build: ${{ github.run_number }}
        Commit: ${{ github.sha }}
        Image: ${{ needs.build-and-push.outputs.image-uri }}"
        
        git push origin main

    - name: Notify ArgoCD (optional)
      if: success()
      run: |
        echo "✓ Manifest updated in Git"
        echo "✓ ArgoCD will detect change within 3 minutes"
        echo "✓ Manual sync required for production"
        echo ""
        echo "Next: Approve sync in ArgoCD UI"
```

Also update `deploy-to-dev` similarly (replace direct kubectl with Git update):

**CURRENT (WRONG)**:
```yaml
deploy-to-dev:
  name: Auto-Deploy to Dev
  needs: build-and-push
  if: github.ref == 'refs/heads/develop'
  
  steps:
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      ...
    
    - name: Deploy
      run: |
        kubectl set image deployment/event-ingestion \
          event-ingestion=${{ needs.build-and-push.outputs.image-uri }} \
          -n gamemetrics --record
```

**NEW (CORRECT)**:
```yaml
deploy-to-dev:
  name: Auto-Deploy Dev Manifest
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
        
        echo "✓ Updated dev deployment"

    - name: Commit and push
      run: |
        git config user.email "github-actions[bot]@users.noreply.github.com"
        git config user.name "GitHub Actions Bot"
        
        git add k8s/services/event-ingestion/deployment.yaml
        git commit -m "ci: auto-bump dev image to ${{ needs.build-and-push.outputs.image-tag }}"
        git push origin develop

    - name: Wait for ArgoCD sync
      run: echo "✓ Dev manifest updated, ArgoCD will auto-sync"
```

---

## Fix #2: Update Deployment Manifest

### File: `k8s/services/event-ingestion/deployment.yaml`

Keep most of it the same, just verify:

1. **Add ECR pull secret**:
```yaml
spec:
  replicas: 2
  template:
    spec:
      imagePullSecrets:  # ← ADD THIS
      - name: ecr-secret
      
      containers:
      - name: event-ingestion
        image: 647523695124.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service:latest
```

2. **Ensure all secrets exist**:
```yaml
        env:
        # Database from secret
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
        
        # Kafka from secret
        - name: KAFKA_BOOTSTRAP_SERVERS
          valueFrom:
            secretKeyRef:
              name: kafka-credentials
              key: KAFKA_BOOTSTRAP_SERVERS
        
        # Static config
        - name: KAFKA_TOPIC_PLAYER_EVENTS
          value: "player-events"
        - name: KAFKA_TOPIC_USER_ACTIONS
          value: "user-actions"
```

---

## Fix #3: Create Required Secrets

### Command: Create All Secrets in Cluster

```bash
#!/bin/bash
# scripts/setup-secrets.sh

# Get Terraform outputs
RDS_ENDPOINT=$(cd terraform/environments/dev && terraform output -raw rds_endpoint)
RDS_PASSWORD=$(cd terraform/environments/dev && terraform output -raw rds_password)
ECR_REGISTRY=$(cd terraform/environments/dev && terraform output -raw ecr_registry_url)
AWS_ACCOUNT_ID=$(echo $ECR_REGISTRY | cut -d'.' -f1)

echo "Creating secrets in gamemetrics namespace..."

# 1. Database credentials
kubectl create secret generic db-credentials \
  --from-literal=DB_HOST=$RDS_ENDPOINT \
  --from-literal=DB_PORT=5432 \
  --from-literal=DB_NAME=gamemetrics \
  --from-literal=DB_USER=dbadmin \
  --from-literal=DB_PASSWORD=$RDS_PASSWORD \
  -n gamemetrics \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Database credentials secret created"

# 2. Kafka credentials (use Strimzi Kafka in cluster)
kubectl create secret generic kafka-credentials \
  --from-literal=KAFKA_BOOTSTRAP_SERVERS=kafka-cluster-kafka-bootstrap.kafka:9092 \
  --from-literal=KAFKA_SECURITY_PROTOCOL=PLAINTEXT \
  -n gamemetrics \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Kafka credentials secret created"

# 3. ECR credentials for image pulling
aws ecr get-login-password --region us-east-1 | \
kubectl create secret docker-registry ecr-secret \
  --docker-server=$ECR_REGISTRY \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-east-1) \
  -n gamemetrics \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ ECR pull secret created"

# 4. Verify all secrets
echo ""
echo "Secrets in gamemetrics namespace:"
kubectl get secrets -n gamemetrics
```

Run it:
```bash
chmod +x scripts/setup-secrets.sh
./scripts/setup-secrets.sh
```

---

## Fix #4: Verify ArgoCD Applications Exist

### File: `k8s/argocd/application-event-ingestion-prod.yaml`

Make sure it exists and has correct content:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: event-ingestion-prod
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
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
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - RespectIgnoreDifferences=true
    
    automated:
      prune: false
      selfHeal: false
    
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

Apply it:
```bash
kubectl apply -f k8s/argocd/application-event-ingestion-prod.yaml
```

---

## Fix #5: Add Terraform Support for ArgoCD

### File: `terraform/environments/dev/argocd.tf`

Replace the empty file with:

```terraform
# Create argocd namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      name = "argocd"
    }
  }

  depends_on = [module.eks]
}

# Install ArgoCD via Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.46.8"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "configs.secret.argocdServerAdminPassword"
    value = bcrypt(random_password.argocd_password.result)
  }

  depends_on = [kubernetes_namespace.argocd]
}

# Generate random password for ArgoCD admin
resource "random_password" "argocd_password" {
  length  = 16
  special = true
}

# Output ArgoCD admin password
output "argocd_admin_password" {
  description = "ArgoCD admin password"
  value       = random_password.argocd_password.result
  sensitive   = true
}

# Output ArgoCD Server Load Balancer
output "argocd_server_lb" {
  description = "ArgoCD Server Load Balancer DNS"
  value       = try(
    kubernetes_service.argocd_server[0].status[0].load_balancer[0].ingress[0].hostname,
    "pending..."
  )
}
```

Apply it:
```bash
cd terraform/environments/dev
terraform apply
```

---

## Summary of Changes

| File | Change | Type |
|------|--------|------|
| `.github/workflows/build-event-ingestion.yml` | Replace deploy jobs to update Git instead of kubectl | CRITICAL |
| `k8s/services/event-ingestion/deployment.yaml` | Add ECR pull secret | REQUIRED |
| `k8s/argocd/application-event-ingestion-prod.yaml` | Verify exists and correct | VERIFY |
| `terraform/environments/dev/argocd.tf` | Add ArgoCD Helm installation | REQUIRED |
| `scripts/setup-secrets.sh` | Create script to set up secrets | REQUIRED |

---

## Testing Checklist

After applying all changes:

```bash
# 1. Verify Terraform
cd terraform/environments/dev
terraform apply
terraform output argocd_admin_password

# 2. Verify cluster access
kubectl get nodes
# Should see 4 nodes

# 3. Verify ArgoCD installed
kubectl get pods -n argocd
# Should see argocd-server, argocd-controller, etc.

# 4. Create secrets
./scripts/setup-secrets.sh

# 5. Verify application
kubectl apply -f k8s/argocd/application-event-ingestion-prod.yaml

# 6. Check application status
kubectl get application -n argocd
argocd app get event-ingestion-prod

# 7. Test GitHub Actions
echo "# Test" >> services/event-ingestion-service/README.md
git add services/event-ingestion-service/README.md
git commit -m "test: trigger workflow"
git push origin main

# 8. Watch workflow run
# https://github.com/sheeffii/RealtimeGaming/actions

# 9. Check if manifest updated
git log --oneline k8s/services/event-ingestion/deployment.yaml
# Should see recent commit from "GitHub Actions Bot"

# 10. Check ArgoCD status
argocd app get event-ingestion-prod
# Should show "OutOfSync"

# 11. Sync in ArgoCD
argocd app sync event-ingestion-prod

# 12. Verify deployment
kubectl get deployment -n gamemetrics
kubectl get pods -n gamemetrics
kubectl logs -f -n gamemetrics -l app=event-ingestion
```

---

## Before and After

### BEFORE (Current - Broken)
```
Developer → GitHub Actions → builds image → kubectl set image → Kubernetes
                                          ↗ (bypasses ArgoCD)
ArgoCD watches → Confused (nothing changed in Git)
```

### AFTER (Fixed - GitOps)
```
Developer → GitHub Actions → builds image → updates Git → ArgoCD → Kubernetes
                                          ↗ (via Git commit)     ↖ (watches Git)
```

