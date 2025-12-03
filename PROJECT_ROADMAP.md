# GameMetrics Pro - Complete Project Roadmap

## Current Status ✅

### Infrastructure (Complete)
- [x] AWS VPC with 3 AZs, NAT gateways, VPC endpoints
- [x] EKS cluster (upgrading 1.28 → 1.29)
- [x] 3 Node groups (system: t3.micro→t3.small, application: t3.small, data: t3.small)
- [x] RDS PostgreSQL 15 (db.t3.micro)
- [x] ElastiCache Redis 7.0 (cache.t3.micro)
- [x] S3 buckets (logs, backups, artifacts, velero)
- [x] ECR repository (event-ingestion-service)
- [x] IAM roles, security groups, networking

### Kubernetes Platform (Complete)
- [x] Namespaces (kafka, databases, monitoring, argocd, gamemetrics, default)
- [x] Strimzi operator (Kafka management)
- [x] Kafka cluster (KRaft mode, 1 broker + 1 controller)
- [x] 6 Kafka topics (player.events.raw, player.events.processed, notifications, dlq.events, user.actions, recommendations.generated)
- [x] Kafka UI (web interface)
- [x] ArgoCD deployed (separate from main kustomization)
- [x] Database/Redis/Kafka secrets
- [x] Root Kustomize (single-command deployment)

### Automation (Complete)
- [x] Terraform modules (VPC, EKS, RDS, Redis, S3, ECR)
- [x] Deployment scripts (deploy-infrastructure.sh, deploy-argocd.sh)
- [x] Teardown script (safe cleanup with protection handling)
- [x] Status checking script
- [x] Kafka testing script
- [x] ECR build/push script

### Known Issues 🔴
- [ ] Kafka broker stuck in Pending (insufficient memory on t3.small - fixing with system node upgrade)
- [ ] Event ingestion service has InvalidImageName (expected - needs Docker image)
- [ ] RDS password in secrets still uses placeholder

---

## Phase 1: Infrastructure Stabilization 🔧

### Task 1.1: Complete EKS Upgrade ⏳ (IN PROGRESS)
**Status:** Deleting old system node group
**Actions:**
- [x] Update EKS version 1.28 → 1.29 in Terraform
- [x] Upgrade system node from t3.micro → t3.small
- [x] Remove old node group from state
- [ ] Wait for node group deletion (5-10 minutes)
- [ ] Apply Terraform to create new node group
- [ ] Verify Kafka broker can schedule

**Commands:**
```bash
# After node deletion completes:
wsl bash -c "cd /mnt/c/Users/Shefqet/Desktop/RealtimeGaming/terraform/environments/dev && terraform apply -auto-approve"

# Verify nodes:
wsl bash -c "kubectl get nodes -o wide"
```

### Task 1.2: Verify Kafka Cluster Health
**Actions:**
- [ ] Check Kafka broker is Running
- [ ] Verify all 6 topics are Ready
- [ ] Test message produce/consume via quick-kafka-test.sh
- [ ] Verify Kafka UI is accessible

**Commands:**
```bash
wsl bash -c "kubectl get pods -n kafka"
wsl bash -c "kubectl get kafkatopic -n kafka"
wsl bash -c "bash scripts/quick-kafka-test.sh"
wsl bash -c "kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
```

### Task 1.3: Fix Database Secrets
**Actions:**
- [ ] Get actual RDS password from Secrets Manager
- [ ] Update k8s/secrets/db-secrets.yaml with real values
- [ ] Apply secrets to cluster

**Commands:**
```bash
# Get RDS password:
wsl bash -c "aws secretsmanager get-secret-value --secret-id gamemetrics-dev-master-password --region us-east-1 --query SecretString --output text | jq -r .password"

# Get endpoints from Terraform:
wsl bash -c "cd terraform/environments/dev && terraform output rds_endpoint"
wsl bash -c "cd terraform/environments/dev && terraform output elasticache_primary_endpoint"

# Update secrets file, then apply:
wsl bash -c "kubectl apply -f k8s/secrets/db-secrets.yaml"
```

---

## Phase 2: Application Deployment 📦

### Task 2.1: Build and Push Docker Image
**Actions:**
- [ ] Ensure Docker Desktop is running
- [ ] Build event-ingestion-service image
- [ ] Push to ECR
- [ ] Update deployment manifest with ECR image URL

**Commands:**
```bash
# Get ECR URL:
wsl bash -c "cd terraform/environments/dev && terraform output -json ecr_repository_urls"

# Build and push:
wsl bash -c "bash scripts/build-push-ecr.sh us-east-1 <ECR_REPO_URL> services/event-ingestion-service"

# Or enable Terraform auto-build:
wsl bash -c "cd terraform/environments/dev && TF_VAR_enable_local_ecr_build_push=true terraform apply"
```

### Task 2.2: Update Deployment Manifest
**Actions:**
- [ ] Edit k8s/services/event-ingestion/deployment.yaml
- [ ] Replace `REPLACE_WITH_YOUR_ECR_IMAGE:latest` with actual ECR URL
- [ ] Apply deployment via root kustomization

**Commands:**
```bash
# Update image in deployment.yaml manually or via script

# Apply:
wsl bash -c "kubectl apply -k k8s/"

# Verify:
wsl bash -c "kubectl get pods -n gamemetrics"
wsl bash -c "kubectl logs -n gamemetrics -l app=event-ingestion"
```

### Task 2.3: Test Application API
**Actions:**
- [ ] Port-forward event-ingestion service
- [ ] Test health endpoints
- [ ] Send test event via API
- [ ] Verify event appears in Kafka topic
- [ ] Check database for stored event

**Commands:**
```bash
# Port-forward:
wsl bash -c "kubectl port-forward -n gamemetrics svc/event-ingestion-service 8081:8080"

# Test health:
curl http://localhost:8081/health
curl http://localhost:8081/ready

# Send test event:
curl -X POST http://localhost:8081/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "playerId": "player-123",
    "eventType": "login",
    "timestamp": "2025-12-02T12:00:00Z",
    "metadata": {"device": "mobile"}
  }'

# Check Kafka UI:
wsl bash -c "kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
# Open: http://localhost:8080

# Check database:
wsl bash -c "kubectl run -it --rm psql --image=postgres:15 --restart=Never -- psql -h <RDS_ENDPOINT> -U dbadmin -d gamemetrics -c 'SELECT * FROM events LIMIT 10;'"
```

---

## Phase 3: GitOps with ArgoCD 🚀

### Task 3.1: Migrate to EKS-Managed ArgoCD (RECOMMENDED)
**Actions:**
- [ ] Review AWS EKS GitOps announcement (docs/EKS_GITOPS_NATIVE.md)
- [ ] Add EKS ArgoCD addon to Terraform
- [ ] Remove manual ArgoCD Kustomize install
- [ ] Test ArgoCD UI access

**Terraform Addition:**
```hcl
# terraform/environments/dev/main.tf
resource "aws_eks_addon" "argocd" {
  cluster_name  = module.eks.cluster_name
  addon_name    = "argo-cd"
  addon_version = "v2.10.0-eksbuild.1"  # Check latest: aws eks describe-addon-versions --addon-name argo-cd
}
```

**OR keep current Kustomize-based ArgoCD:**
```bash
# Already deployed via:
wsl bash -c "kubectl apply -k k8s/argocd/base/"
```

### Task 3.2: Configure GitHub Repository
**Actions:**
- [ ] Create GitHub repository or use existing
- [ ] Push RealtimeGaming code to GitHub
- [ ] Update argocd/app-of-apps.yml with real repo URL
- [ ] Update argocd/apps/applications.yml with real repo URL

**If private repository:**
```bash
# Option A: Add repo via ArgoCD UI (easier)
wsl bash -c "kubectl port-forward -n argocd svc/argocd-server 8082:80"
# Open: http://localhost:8082
# Settings → Repositories → Connect Repo

# Option B: Create K8s secret
kubectl create secret generic github-repo \
  -n argocd \
  --from-literal=url=https://github.com/<YOUR_ORG>/RealtimeGaming.git \
  --from-literal=username=<GITHUB_USERNAME> \
  --from-literal=password=<GITHUB_PAT>
kubectl label secret github-repo -n argocd argocd.argoproj.io/secret-type=repository
```

### Task 3.3: Deploy App-of-Apps Pattern
**Actions:**
- [ ] Apply app-of-apps manifest
- [ ] Verify ArgoCD syncs all applications
- [ ] Set up auto-sync for continuous deployment

**Commands:**
```bash
# Apply app-of-apps:
wsl bash -c "kubectl apply -f argocd/app-of-apps.yml"

# Watch sync status:
wsl bash -c "kubectl get applications -n argocd -w"

# Access ArgoCD UI:
wsl bash -c "kubectl port-forward -n argocd svc/argocd-server 8082:80"

# Get admin password:
wsl bash -c "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
```

---

## Phase 4: Monitoring & Observability 📊

### Task 4.1: Install Prometheus Stack
**Actions:**
- [ ] Add Helm repo for kube-prometheus-stack
- [ ] Create monitoring/kustomization.yaml
- [ ] Deploy Prometheus Operator, Grafana, Alertmanager
- [ ] Configure ServiceMonitors for Kafka, app services

**Commands:**
```bash
# Install via Helm:
wsl bash -c "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update"

wsl bash -c "helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin \
  --set prometheus.prometheusSpec.retention=7d"

# Access Grafana:
wsl bash -c "kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
# Open: http://localhost:3000 (admin/admin)
```

**OR via Kustomize:**
```yaml
# monitoring/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - prometheus-operator.yaml
  - grafana.yaml
  - servicemonitors/
```

### Task 4.2: Configure Strimzi Kafka Metrics
**Actions:**
- [ ] Update Kafka CR with metricsConfig
- [ ] Enable JMX exporter for Kafka brokers
- [ ] Create ServiceMonitor for Kafka
- [ ] Import Strimzi Grafana dashboards

**Kafka Metrics Config:**
```yaml
# k8s/kafka/base/kafka.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: gamemetrics-kafka
spec:
  kafka:
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: kafka-metrics
          key: kafka-metrics-config.yml
```

### Task 4.3: Application Observability
**Actions:**
- [ ] Add Prometheus metrics endpoint to event-ingestion service (already in code)
- [ ] Create ServiceMonitor for event-ingestion
- [ ] Create Grafana dashboards for app metrics
- [ ] Set up alerting rules (pod restarts, high latency, error rates)

---

## Phase 5: CI/CD Pipeline 🔄

### Task 5.1: GitHub Actions Workflow
**Actions:**
- [ ] Create .github/workflows/ci.yml
- [ ] Add Docker build + ECR push job
- [ ] Add Terraform plan job for PR reviews
- [ ] Add ArgoCD image updater integration

**Example Workflow:**
```yaml
name: CI/CD
on:
  push:
    branches: [main]
jobs:
  build-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      - run: |
          aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REGISTRY
          docker build -t event-ingestion-service services/event-ingestion-service/
          docker tag event-ingestion-service:latest $ECR_REGISTRY/event-ingestion-service:$GITHUB_SHA
          docker push $ECR_REGISTRY/event-ingestion-service:$GITHUB_SHA
      - name: Update ArgoCD image tag
        run: |
          kubectl patch application event-ingestion-service -n argocd --type merge -p '{"spec":{"source":{"targetRevision":"'$GITHUB_SHA'"}}}'
```

### Task 5.2: ArgoCD Image Updater
**Actions:**
- [ ] Install ArgoCD Image Updater
- [ ] Configure auto-update for event-ingestion image
- [ ] Set up write-back to Git repo

**Commands:**
```bash
wsl bash -c "kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml"
```

---

## Phase 6: Production Readiness 🛡️

### Task 6.1: Backup & Disaster Recovery
**Actions:**
- [ ] Install Velero for cluster backups
- [ ] Configure S3 bucket for Velero (already created: gamemetrics-velero-dev)
- [ ] Set up scheduled backups
- [ ] Test restore procedure

**Commands:**
```bash
# Install Velero:
wsl bash -c "velero install \
  --provider aws \
  --bucket gamemetrics-velero-dev \
  --backup-location-config region=us-east-1 \
  --snapshot-location-config region=us-east-1"

# Create backup schedule:
wsl bash -c "velero schedule create daily-backup --schedule='@daily' --ttl 720h"
```

### Task 6.2: Security Hardening
**Actions:**
- [ ] Enable Pod Security Standards (restricted)
- [ ] Add Network Policies for namespace isolation
- [ ] Configure RBAC for least-privilege access
- [ ] Scan container images with Trivy/Snyk
- [ ] Enable audit logging

### Task 6.3: Cost Optimization
**Actions:**
- [ ] Set up Kubecost or AWS Cost Explorer tags
- [ ] Configure Cluster Autoscaler
- [ ] Add Horizontal Pod Autoscalers (HPA)
- [ ] Review resource requests/limits
- [ ] Consider Spot instances for non-critical workloads

### Task 6.4: High Availability
**Actions:**
- [ ] Increase Kafka replicas (1 → 3 brokers)
- [ ] Enable RDS Multi-AZ
- [ ] Enable Redis Multi-AZ with replica
- [ ] Add Pod Disruption Budgets (PDB)
- [ ] Configure Topology Spread Constraints

---

## Phase 7: Additional Features 🎯

### Task 7.1: Event Processing Pipeline
**Actions:**
- [ ] Deploy Kafka Streams/Flink processing service
- [ ] Implement event transformation (raw → processed)
- [ ] Add event aggregation (user sessions, metrics)
- [ ] Store processed events in RDS

### Task 7.2: Real-time Analytics
**Actions:**
- [ ] Deploy ClickHouse or TimescaleDB for analytics
- [ ] Create materialized views for common queries
- [ ] Add Grafana dashboards for business metrics
- [ ] Implement real-time leaderboards

### Task 7.3: Notifications Service
**Actions:**
- [ ] Deploy notification service (consumes `notifications` topic)
- [ ] Integrate with SNS/SES for email
- [ ] Add push notification support
- [ ] Implement user preference management

### Task 7.4: Recommendations Service
**Actions:**
- [ ] Deploy ML model service
- [ ] Train model on player behavior events
- [ ] Produce recommendations to `recommendations.generated` topic
- [ ] Integrate with game client API

---

## Priority Order 🎯

### 🔴 Critical (Do Now)
1. **Complete EKS upgrade and node scaling** (Task 1.1) - Kafka needs memory
2. **Fix database secrets** (Task 1.3) - Apps need to connect to RDS
3. **Build and deploy event-ingestion** (Task 2.1, 2.2) - Core application

### 🟠 High (This Week)
4. **Test end-to-end event flow** (Task 2.3)
5. **Set up GitOps with ArgoCD** (Task 3.1-3.3)
6. **Install monitoring stack** (Task 4.1)

### 🟡 Medium (Next Week)
7. **CI/CD pipeline** (Task 5.1)
8. **Kafka metrics and dashboards** (Task 4.2)
9. **Backup and DR** (Task 6.1)

### 🟢 Low (Future)
10. **Security hardening** (Task 6.2)
11. **Cost optimization** (Task 6.3)
12. **Additional services** (Phase 7)

---

## Quick Commands Reference

**Infrastructure:**
```bash
# Deploy all infrastructure:
wsl bash -c "bash scripts/deploy-infrastructure.sh"

# Check status:
wsl bash -c "bash scripts/check-status.sh"

# Teardown everything:
wsl bash -c "bash scripts/teardown-infrastructure.sh"
```

**Kubernetes:**
```bash
# Deploy all K8s resources:
wsl bash -c "kubectl apply -k k8s/"

# Deploy ArgoCD separately:
wsl bash -c "kubectl apply -k k8s/argocd/base/"

# Check all pods:
wsl bash -c "kubectl get pods -A"
```

**Kafka:**
```bash
# Test Kafka:
wsl bash -c "bash scripts/quick-kafka-test.sh"

# Access Kafka UI:
wsl bash -c "kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
```

**ArgoCD:**
```bash
# Access ArgoCD UI:
wsl bash -c "kubectl port-forward -n argocd svc/argocd-server 8082:80"

# Get admin password:
wsl bash -c "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
```

---

## Success Criteria ✅

**Infrastructure:**
- [x] All Terraform resources deployed without errors
- [ ] EKS 1.29 with 3 Ready nodes
- [ ] Kafka broker Running (not Pending)
- [ ] All services accessible

**Application:**
- [ ] Event ingestion API responds to health checks
- [ ] Events successfully flow: API → RDS → Kafka
- [ ] Kafka UI shows messages in topics

**GitOps:**
- [ ] ArgoCD syncs applications from Git
- [ ] Git push triggers automatic deployment
- [ ] Rollback capability tested

**Monitoring:**
- [ ] Prometheus scraping metrics
- [ ] Grafana dashboards operational
- [ ] Alerts firing for critical issues

**Production:**
- [ ] Automated backups running
- [ ] CI/CD pipeline deploying on merge
- [ ] Security policies enforced
- [ ] Cost tracking enabled
