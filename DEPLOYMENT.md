# GameMetrics Pro - Deployment Guide

## Architecture Overview

The deployment is split into two phases:

1. **Infrastructure Deployment** (Manual, one-time)
   - AWS infrastructure via Terraform (VPC, EKS, RDS, ElastiCache, S3, ECR)
   - Kubernetes cluster setup and operators (Strimzi for Kafka)
   - Network and security configuration

2. **Application Deployment** (Automated via CI/CD or manual)
   - Docker image builds and push to ECR
   - Kubernetes deployment updates
   - Health checks and smoke tests

## Prerequisites

### Local Setup (for manual infrastructure deployment)
```bash
# Required tools
- AWS CLI v2
- Terraform >= 1.6.0
- kubectl >= 1.27
- Docker (for local testing)
- jq (for JSON parsing in scripts)

# AWS Credentials configured
aws configure
# OR set environment variables
export AWS_ACCESS_KEY_ID=xxxxx
export AWS_SECRET_ACCESS_KEY=xxxxx
export AWS_REGION=us-east-1
```

### GitHub Repository Setup (for CI/CD)
Add these secrets to GitHub repository settings (`Settings → Secrets and variables → Actions`):

```
AWS_ACCOUNT_ID          # Your AWS account ID (e.g., 647523695124)
AWS_ACCESS_KEY_ID       # AWS IAM user access key
AWS_SECRET_ACCESS_KEY   # AWS IAM user secret key
```

## Deployment Workflows

### 1. Initial Infrastructure Deployment (One-Time)

**Step 1: Deploy infrastructure only**
```bash
bash scripts/deploy-infra-only.sh
```

This will:
- Deploy AWS infrastructure via Terraform (VPC, EKS cluster, RDS, Redis, S3, ECR)
- Configure kubectl access
- Wait for 3 EKS nodes to be ready
- Deploy Kubernetes operators (Strimzi for Kafka)
- Create Kafka cluster and topics
- Update Kubernetes secrets from AWS Secrets Manager
- Output `.infra-output.env` with infrastructure details

**Expected output:**
```
✓ Infrastructure deployed
✓ kubectl configured
✓ All 3 nodes are ready
✓ K8s resources deployed
✓ Strimzi operator ready
✓ Kafka cluster ready
```

### 2. Deploy Applications to Kubernetes (Manual or Automated)

#### Option A: Manual Deployment (After Infrastructure)
```bash
bash scripts/deploy-apps-to-k8s.sh
```

This will:
- Load infrastructure details from `.infra-output.env`
- Fetch ECR repository URL
- Deploy/update `event-ingestion` service
- Verify deployment health
- Test health endpoints

**Expected output:**
```
✓ Connected to cluster
✓ ECR URL from Terraform: ...
✓ Deployment created and ready
✓ Health check passed
```

#### Option B: Automated CI/CD Deployment
When you push to GitHub:

- **Push to `develop` branch** → Automatic deployment to dev Kubernetes cluster
  - Builds Docker image
  - Pushes to ECR
  - Updates dev deployment
  - Runs smoke tests
  - No manual approval needed

- **Push to `main` branch** → Deployment to prod with manual approval
  - Builds Docker image
  - Pushes to ECR
  - Waits for environment approval in GitHub
  - Updates prod deployment after approval
  - Runs extensive smoke tests
  - Automatic rollback on failure

### 3. Daily Development Workflow

```
# 1. Make code changes
vim services/event-ingestion-service/cmd/main.go

# 2. Commit and push to develop
git add .
git commit -m "feat: add new feature"
git push origin develop

# 3. GitHub Actions automatically:
#    - Builds Docker image
#    - Runs tests and security scans
#    - Pushes image to ECR
#    - Deploys to dev cluster
#    - Runs health checks

# 4. Monitor deployment
kubectl get deployment event-ingestion -n gamemetrics
kubectl logs -n gamemetrics -l app=event-ingestion -f

# 5. When ready for production, create a PR and merge to main
#    Production deployment requires manual approval
```

## Common Operations

### View Infrastructure Status

```bash
# EKS cluster info
kubectl get nodes -o wide

# Kafka cluster
kubectl get pods -n kafka
kubectl get kafkatopic -n kafka

# Event ingestion service
kubectl get deployment event-ingestion -n gamemetrics
kubectl get pods -n gamemetrics -l app=event-ingestion
```

### Access Services

```bash
# Kafka UI (local port forward)
kubectl port-forward -n kafka svc/kafka-ui 8080:8080
# Open: http://localhost:8080

# Event Ingestion Service
kubectl port-forward -n gamemetrics svc/event-ingestion 8080:8080
# Open: http://localhost:8080/swagger-ui.html

# RDS Database (through bastion or direct)
# Endpoint: gamemetrics-dev.cwxu6k6ikgjr.us-east-1.rds.amazonaws.com:5432

# Redis Cache (through bastion or direct)
# Endpoint: gamemetrics-dev.xl8xkv.ng.0001.use1.cache.amazonaws.com:6379
```

### View Logs

```bash
# Application logs (real-time)
kubectl logs -f -n gamemetrics -l app=event-ingestion

# Previous pod logs (if crashed)
kubectl logs -n gamemetrics -l app=event-ingestion --previous

# Events in namespace
kubectl get events -n gamemetrics --sort-by='.lastTimestamp'

# Full pod description
kubectl describe pod -n gamemetrics -l app=event-ingestion
```

### Manual Deployment Update

```bash
# Update deployment with new image (if not using CI/CD)
ECR_URL=$(aws ecr describe-repositories --repository-names event-ingestion-service --query 'repositories[0].repositoryUri' --output text)

kubectl set image deployment/event-ingestion \
  event-ingestion=$ECR_URL:latest \
  -n gamemetrics

# Monitor rollout
kubectl rollout status deployment/event-ingestion -n gamemetrics
```

### Rollback Deployment

```bash
# View rollout history
kubectl rollout history deployment/event-ingestion -n gamemetrics

# Rollback to previous version
kubectl rollout undo deployment/event-ingestion -n gamemetrics

# Rollback to specific revision
kubectl rollout undo deployment/event-ingestion -n gamemetrics --to-revision=2
```

### Scale Deployment

```bash
# Scale to 3 replicas
kubectl scale deployment event-ingestion --replicas=3 -n gamemetrics

# Auto-scale (requires metrics server)
kubectl autoscale deployment event-ingestion --min=2 --max=5 -n gamemetrics
```

## Directory Structure

```
RealtimeGaming/
├── scripts/
│   ├── deploy-infra-only.sh           # Deploy infrastructure (manual)
│   ├── deploy-apps-to-k8s.sh          # Deploy applications (manual)
│   ├── update-deployment-images.sh    # Update images (legacy)
│   ├── update-secrets-from-aws.sh     # Sync K8s secrets from AWS Secrets Manager
│   └── build-push-ecr.sh              # Build and push to ECR
├── terraform/
│   ├── modules/                       # Reusable Terraform modules
│   └── environments/dev/
│       ├── main.tf                    # Infrastructure definition
│       ├── outputs.tf                 # Terraform outputs
│       └── terraform.tfstate          # State file (local)
├── k8s/
│   ├── kustomization.yaml             # Root kustomization
│   ├── namespaces/                    # Namespace definitions
│   ├── kafka/                         # Kafka cluster and topics
│   ├── services/
│   │   └── event-ingestion/           # Event ingestion service manifests
│   └── monitoring/                    # Prometheus, Grafana
├── services/
│   └── event-ingestion-service/       # Go application
├── .github/workflows/
│   ├── build-event-ingestion.yml      # CI/CD: Build, scan, deploy
│   └── ci-services.yml                # CI: Test other services
└── .infra-output.env                  # Generated by deploy-infra-only.sh
```

## CI/CD Pipeline Details

### Build Event Ingestion Workflow

**Trigger:** Push to `develop` or `main` branch, changes to `services/event-ingestion-service/**`

**Steps:**
1. **Checkout** - Get latest code
2. **Docker Build & Push to ECR**
   - Build multi-arch image (linux/amd64)
   - Cache layers for speed
   - Push to ECR with tags: `branch-sha`, `branch-latest`, `latest` (on main)
3. **Trivy Security Scan**
   - Scan for CRITICAL, HIGH, MEDIUM vulnerabilities
   - Report in workflow logs (no GitHub Security tab for private repos)
4. **Cosign Image Signing** (if not PR)
   - Sign image with keyless OIDC
   - Enables supply chain security
5. **Deploy to Kubernetes** (if not PR)
   - On `develop`: Auto-deploys to dev cluster
   - On `main`: Waits for environment approval, then deploys to prod
6. **Health Checks**
   - Port-forward to pod
   - Test `/health/live` and `/health/ready` endpoints
   - Rollback on failure

### Secondary CI Services Workflow

**Trigger:** After build-event-ingestion succeeds (on main/develop)

**Steps:**
1. **Detect Changes** - Identify which services changed
2. **Build & Test Each Service**
   - Run unit tests
   - Security scans (Trivy, optional Snyk)
   - Build Docker image
   - Generate SBOM

## Troubleshooting

### Issue: "Deployment not found" during CI/CD

**Cause:** Infrastructure not deployed before CI/CD runs
**Solution:** Run `bash scripts/deploy-infra-only.sh` first

### Issue: "Pod is in CrashLoopBackOff"

**Debug:**
```bash
kubectl describe pod -n gamemetrics -l app=event-ingestion
kubectl logs -n gamemetrics -l app=event-ingestion --previous
```

**Common causes:**
- Image not found in ECR
- Missing environment variables or secrets
- Database connectivity issues

### Issue: "No running pods found" in smoke tests

**Cause:** Pods still starting or in ImagePullBackOff
**Debug:**
```bash
kubectl get pods -n gamemetrics -l app=event-ingestion -o wide
kubectl describe pod -n gamemetrics -l app=event-ingestion
```

### Issue: ECR login fails in CI/CD

**Cause:** AWS credentials missing or expired
**Solution:** 
1. Verify secrets in GitHub: `Settings → Secrets and variables → Actions`
2. Check IAM user has ECR push permissions
3. Regenerate access keys if needed

## Security Best Practices

1. **Credentials**
   - Store AWS credentials in GitHub Secrets (never in code/git)
   - Rotate credentials regularly
   - Use separate IAM user for CI/CD with minimal permissions

2. **Images**
   - Always scan images for vulnerabilities before production
   - Use image signing (Cosign) for supply chain security
   - Keep base images updated

3. **Kubernetes**
   - Use RBAC for service accounts
   - Network policies to restrict traffic
   - Pod security policies for container isolation
   - Secrets encrypted in etcd

4. **Database**
   - RDS encryption enabled
   - Automated backups to S3
   - VPC-only access (no public endpoint)

## Cost Optimization

- **Single NAT Gateway** (dev environment)
- **Small EKS node group** (develop uses t3.medium)
- **Auto-scaling** disabled for dev
- **S3 lifecycle policies** for log retention
- **RDS backup retention** limited to 7 days

For production, consider:
- Multi-AZ deployments
- Larger node groups
- Reserved instances
- Auto-scaling policies

## Next Steps

1. ✅ Deploy infrastructure: `bash scripts/deploy-infra-only.sh`
2. ✅ Deploy applications: `bash scripts/deploy-apps-to-k8s.sh`
3. ✅ Push to develop branch and verify CI/CD
4. 📧 Set up monitoring and alerts
5. 📋 Create runbooks for common issues
6. 🔄 Set up automated backup verification

## Support

For issues or questions:
- Check workflow logs: GitHub → Actions tab
- Check pod logs: `kubectl logs -f -n gamemetrics ...`
- Check events: `kubectl get events -n gamemetrics`
- Review Terraform state: `cat .infra-output.env`
