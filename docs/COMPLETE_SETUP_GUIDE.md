# Complete Setup Guide - ArgoCD + GitHub Actions

## Prerequisites

Before starting, ensure you have:
- AWS CLI configured (`aws configure`)
- kubectl installed
- Helm 3+ installed
- Terraform 1.6+ installed
- Git configured
- Access to GitHub repo (sheeffii/RealtimeGaming)

---

## Step 1: Run Terraform to Create Infrastructure

```bash
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Check what will be created
terraform plan

# Apply to create resources (takes 15-20 minutes)
terraform apply
```

**What gets created**:
- EKS cluster with 4 nodes
- ECR repository for images
- RDS PostgreSQL database
- ElastiCache Redis
- VPC with networking

---

## Step 2: Connect to Your Kubernetes Cluster

```bash
# Get cluster credentials
aws eks update-kubeconfig --region us-east-1 --name gamemetrics-dev

# Verify connection
kubectl get nodes
# Should show 4 nodes (system, application x2, data)
```

---

## Step 3: Create Kubernetes Namespaces

```bash
# Create namespaces
kubectl create namespace gamemetrics
kubectl create namespace argocd

# Verify
kubectl get namespaces
```

---

## Step 4: Create Kubernetes Secrets

### Database Secret
```bash
# Get RDS endpoint from Terraform output
RDS_ENDPOINT=$(cd terraform/environments/dev && terraform output -raw rds_endpoint)
RDS_PASSWORD=$(cd terraform/environments/dev && terraform output -raw rds_password)

# Create secret
kubectl create secret generic db-credentials \
  --from-literal=DB_HOST=$RDS_ENDPOINT \
  --from-literal=DB_PORT=5432 \
  --from-literal=DB_NAME=gamemetrics \
  --from-literal=DB_USER=dbadmin \
  --from-literal=DB_PASSWORD=$RDS_PASSWORD \
  -n gamemetrics

# Verify
kubectl get secret db-credentials -n gamemetrics
```

### Kafka Secret
```bash
kubectl create secret generic kafka-credentials \
  --from-literal=KAFKA_BOOTSTRAP_SERVERS=kafka-cluster-kafka-bootstrap.kafka:9092 \
  --from-literal=KAFKA_SECURITY_PROTOCOL=PLAINTEXT \
  -n gamemetrics

# Verify
kubectl get secret kafka-credentials -n gamemetrics
```

### ECR Pull Secret
```bash
# Get ECR registry URL
ECR_REGISTRY=$(cd terraform/environments/dev && terraform output -raw ecr_registry_url)

# Create ECR secret
aws ecr get-login-password --region us-east-1 | \
kubectl create secret docker-registry ecr-secret \
  --docker-server=$ECR_REGISTRY \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-east-1) \
  -n gamemetrics

# Verify
kubectl get secret ecr-secret -n gamemetrics
```

---

## Step 5: Install ArgoCD via Terraform

The `terraform/environments/dev/argocd.tf` file now includes ArgoCD Helm installation.

```bash
cd terraform/environments/dev

# Apply Terraform again (will install ArgoCD)
terraform apply
```

**What happens**:
- Creates argocd namespace
- Installs ArgoCD using Helm
- Creates LoadBalancer service

**Terraform Outputs**:
```bash
# Get ArgoCD endpoint
terraform output argocd_server_endpoint

# Get initial password command
terraform output argocd_initial_password_note
```

---

## Step 6: Access ArgoCD UI

```bash
# Method 1: Port Forward (temporary)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Method 2: Get LoadBalancer endpoint
kubectl get svc argocd-server -n argocd -o wide
```

**Access**:
- URL: https://localhost:8080 (if port-forwarding) or https://<LoadBalancer-IP>
- Username: admin
- Password: (get from command below)

**Get Initial Password**:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

---

## Step 7: Deploy ArgoCD Applications

```bash
# Deploy production application
kubectl apply -f k8s/argocd/application-event-ingestion-prod.yaml

# Deploy development application
kubectl apply -f k8s/argocd/application-event-ingestion-dev.yaml

# Verify applications
kubectl get applications -n argocd
```

---

## Step 8: Fix GitHub Actions Workflow

Update `.github/workflows/build-event-ingestion.yml`:

**Remove** the kubectl deployment:
```yaml
- run: kubectl set image deployment/event-ingestion ...
```

**Add** Git manifest update:
```yaml
- name: Update deployment image
  run: |
    sed -i "s|image:.*event-ingestion-service:.*|image: ${{ env.NEW_IMAGE }}|g" \
      k8s/services/event-ingestion/deployment.yaml

- name: Commit and push to Git
  run: |
    git config user.name "GitHub Actions Bot"
    git config user.email "actions@github.com"
    git add k8s/services/event-ingestion/deployment.yaml
    git commit -m "ci: bump event-ingestion image to ${{ env.IMAGE_TAG }}"
    git push origin main
```

**Commit changes**:
```bash
git add .github/workflows/build-event-ingestion.yml
git commit -m "fix: update GitHub Actions to use GitOps"
git push origin main
```

---

## Step 9: Test End-to-End

### Trigger the Workflow
```bash
# Make a test change
echo "# Test" >> services/event-ingestion-service/README.md
git add services/event-ingestion-service/README.md
git commit -m "test: trigger CI/CD"
git push origin main
```

### Watch GitHub Actions
- Go to: https://github.com/sheeffii/RealtimeGaming/actions
- Wait for workflow to complete
- Check that deployment.yaml was updated in Git:
  ```bash
  git log --oneline k8s/services/event-ingestion/deployment.yaml
  ```

### Check ArgoCD
- Go to ArgoCD UI
- Click on `event-ingestion-prod` application
- Should see status: "OutOfSync" ⚠️
- This means ArgoCD detected the Git change!

### Manual Sync
```bash
# Via CLI
argocd app sync event-ingestion-prod

# Or click [SYNC] button in ArgoCD UI
```

### Verify Deployment
```bash
# Check deployment is updated
kubectl get deployment event-ingestion -n gamemetrics

# Check pods are running with new image
kubectl get pods -n gamemetrics -l app=event-ingestion

# Check logs
kubectl logs -f -n gamemetrics -l app=event-ingestion
```

---

## Step 10: Verify All Components

```bash
# Cluster
kubectl get nodes

# Namespaces
kubectl get namespaces

# Secrets
kubectl get secrets -n gamemetrics

# ArgoCD
kubectl get pods -n argocd
kubectl get applications -n argocd

# Deployment
kubectl get deployment -n gamemetrics
kubectl get pods -n gamemetrics

# Service health
kubectl port-forward svc/event-ingestion -n gamemetrics 8080:8080
curl http://localhost:8080/health/live
```

---

## Commands Summary

| Command | Purpose |
|---------|---------|
| `kubectl get nodes` | Check cluster nodes |
| `kubectl get secrets -n gamemetrics` | Check secrets |
| `kubectl get applications -n argocd` | Check ArgoCD apps |
| `argocd app list` | List ArgoCD applications |
| `argocd app sync event-ingestion-prod` | Manual sync |
| `kubectl get pods -n gamemetrics` | Check deployment pods |
| `kubectl logs -n gamemetrics -l app=event-ingestion` | View app logs |

---

## Troubleshooting

### Pods Won't Start
```bash
# Check pod status
kubectl describe pod <pod-name> -n gamemetrics

# Check logs
kubectl logs <pod-name> -n gamemetrics

# Likely issue: Missing secrets
kubectl get secrets -n gamemetrics
```

### Image Pull Fails
```bash
# Verify ECR secret exists
kubectl get secret ecr-secret -n gamemetrics

# Check secret is referenced in deployment
kubectl get deployment event-ingestion -n gamemetrics -o yaml | grep imagePullSecrets
```

### ArgoCD Can't Sync
```bash
# Check ArgoCD can access GitHub repo
kubectl logs -n argocd deployment/argocd-repo-server

# Likely issue: SSH key not configured
# Add deploy key to GitHub repo: Settings → Deploy Keys
```

### Application Shows OutOfSync
This is NORMAL! It means:
1. GitHub Actions updated deployment.yaml
2. ArgoCD detected the change
3. Kubernetes doesn't match Git yet

Solution: Click [SYNC] button in ArgoCD UI

---

## What's Next?

1. ✅ Infrastructure created (Terraform)
2. ✅ Kubernetes secrets configured
3. ✅ ArgoCD installed and running
4. ✅ GitHub Actions fixed to use GitOps
5. ✅ Complete pipeline tested

Now you have:
- ✅ GitOps pipeline working
- ✅ All changes tracked in Git
- ✅ ArgoCD managing deployments
- ✅ GitHub Actions building images
- ✅ Complete audit trail

---

## Key Files

- `terraform/environments/dev/argocd.tf` - ArgoCD Helm installation
- `.github/workflows/build-event-ingestion.yml` - GitHub Actions (updated)
- `k8s/services/event-ingestion/deployment.yaml` - Kubernetes manifest
- `k8s/argocd/application-event-ingestion-prod.yaml` - ArgoCD application

