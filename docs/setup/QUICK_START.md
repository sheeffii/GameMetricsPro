# 🚀 Quick Start Guide - GameMetrics Pro

This guide will help you get the GameMetrics Pro platform running on AWS in under 2 hours for development environment.

## Prerequisites Checklist

### Required Tools
- [ ] AWS CLI (v2.x) - `aws --version`
- [ ] kubectl (v1.28+) - `kubectl version --client`
- [ ] Terraform (v1.6+) - `terraform version`
- [ ] Helm (v3.13+) - `helm version`
- [ ] Docker (v24+) - `docker version`
- [ ] Git - `git --version`

### AWS Account Setup
- [ ] AWS Account with admin access
- [ ] AWS CLI configured: `aws configure`
- [ ] Sufficient service quotas:
  - EKS clusters: 3
  - VPCs: 3
  - Elastic IPs: 9
  - NAT Gateways: 9

### Install Tools (if needed)

**Windows (PowerShell):**
```powershell
# Install Chocolatey first if not installed
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install tools
choco install awscli kubernetes-cli terraform kubernetes-helm docker-desktop -y
```

## Phase 1: Infrastructure Setup (30 minutes)

### Step 1: Configure AWS Credentials
```bash
aws configure
# Enter:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region: us-east-1
# - Default output format: json

# Verify
aws sts get-caller-identity
```

### Step 2: Deploy Development Infrastructure
```bash
# Navigate to terraform directory
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Review the plan
terraform plan -out=tfplan

# Apply (this takes ~20-25 minutes)
terraform apply tfplan
```

**What gets created:**
- VPC with 3 public and 3 private subnets
- EKS cluster with 3 node groups
- RDS PostgreSQL (Multi-AZ)
- ElastiCache Redis Cluster
- S3 buckets for backups/logs
- IAM roles and policies
- Security groups

### Step 3: Configure kubectl
```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name gamemetrics-dev

# Verify connection
kubectl cluster-info
kubectl get nodes
```

## Phase 2: Install Core Components (20 minutes)

### Step 4: Install Strimzi Kafka Operator
```bash
# Create Kafka namespace
kubectl create namespace kafka

# Install Strimzi operator
kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka

# Wait for operator to be ready
kubectl wait --for=condition=Ready pod -l name=strimzi-cluster-operator -n kafka --timeout=300s

# Deploy Kafka cluster
kubectl apply -f k8s/kafka/kafka-cluster.yml -n kafka

# Wait for Kafka to be ready (takes ~5 minutes)
kubectl wait kafka/gamemetrics-kafka --for=condition=Ready --timeout=600s -n kafka
```

### Step 5: Install Istio Service Mesh
```bash
# Download Istio
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
cd istio-1.20.0
export PATH=$PWD/bin:$PATH

# Install Istio
istioctl install --set profile=production -y

# Enable automatic sidecar injection for default namespace
kubectl label namespace default istio-injection=enabled

# Verify installation
kubectl get pods -n istio-system
```

### Step 6: Install ArgoCD
```bash
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access at: https://localhost:8080
# Username: admin
# Password: (from command above)
```

## Phase 3: Deploy Databases (15 minutes)

### Step 7: Deploy PostgreSQL
```bash
# Create database namespace
kubectl create namespace databases

# Deploy PostgreSQL with replication
kubectl apply -f k8s/databases/postgresql/ -n databases

# Wait for primary to be ready
kubectl wait --for=condition=Ready pod -l app=postgresql,role=primary -n databases --timeout=300s
```

### Step 8: Deploy Redis Cluster
```bash
# Deploy Redis
kubectl apply -f k8s/databases/redis/ -n databases

# Verify Redis cluster
kubectl exec -it redis-cluster-0 -n databases -- redis-cli cluster info
```

### Step 9: Deploy TimescaleDB
```bash
# Deploy TimescaleDB
kubectl apply -f k8s/databases/timescaledb/ -n databases

# Wait for ready
kubectl wait --for=condition=Ready pod -l app=timescaledb -n databases --timeout=300s
```

### Step 10: Deploy Qdrant Vector DB
```bash
kubectl apply -f k8s/databases/qdrant/ -n databases
```

## Phase 4: Deploy Monitoring Stack (15 minutes)

### Step 11: Install Prometheus Stack
```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values monitoring/prometheus/values.yaml \
  --wait

# Access Grafana
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80
# Access at: http://localhost:3000
# Username: admin
# Password: prom-operator
```

### Step 12: Install Loki for Logging
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --values monitoring/loki/values.yaml \
  --wait
```

### Step 13: Install Tempo for Tracing
```bash
helm install tempo grafana/tempo \
  --namespace monitoring \
  --values monitoring/tempo/values.yaml \
  --wait
```

## Phase 5: Deploy Applications (20 minutes)

### Step 14: Create Kafka Topics
```bash
# Apply topic definitions
kubectl apply -f k8s/kafka/topics/ -n kafka

# Verify topics
kubectl get kafkatopics -n kafka
```

### Step 15: Deploy Services via ArgoCD
```bash
# Apply app-of-apps pattern
kubectl apply -f argocd/app-of-apps.yml -n argocd

# Watch deployments
kubectl get applications -n argocd -w

# Check service status
kubectl get pods -n default
```

### Step 16: Configure Ingress
```bash
# Install NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# Apply ingress rules
kubectl apply -f k8s/ingress/
```

## Phase 6: Verify Installation (10 minutes)

### Step 17: Health Checks
```bash
# Run health check script
./scripts/setup/health-check.sh

# Manual checks
kubectl get pods --all-namespaces
kubectl get svc --all-namespaces
kubectl get ingress --all-namespaces
```

### Step 18: Test Event Flow
```bash
# Send test event to ingestion service
./scripts/setup/test-event-flow.sh

# Check Kafka consumer lag
kubectl exec -it gamemetrics-kafka-0 -n kafka -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group event-processor-group
```

### Step 19: Access Dashboards
```bash
# Grafana
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Admin Dashboard (when deployed)
kubectl port-forward svc/admin-dashboard 3001:3000
```

## 🎯 Verification Checklist

After completing all steps, verify:

- [ ] All pods in Running state: `kubectl get pods --all-namespaces`
- [ ] Kafka cluster healthy: `kubectl get kafka -n kafka`
- [ ] Databases accessible
- [ ] ArgoCD syncing applications
- [ ] Prometheus collecting metrics
- [ ] Grafana dashboards showing data
- [ ] Services can communicate through Kafka
- [ ] Ingress routing working
- [ ] No Critical alerts firing

## 🔍 Troubleshooting Common Issues

### Issue: EKS Cluster Creation Fails
```bash
# Check AWS quotas
aws service-quotas list-service-quotas --service-code eks

# Common issue: Insufficient IP addresses in subnets
# Solution: Check VPC CIDR in terraform/modules/vpc/variables.tf
```

### Issue: Kafka Not Starting
```bash
# Check operator logs
kubectl logs -n kafka -l name=strimzi-cluster-operator

# Check Kafka pods
kubectl describe pod gamemetrics-kafka-0 -n kafka

# Common issue: Insufficient resources
# Solution: Increase node instance type in terraform
```

### Issue: ArgoCD Not Syncing
```bash
# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Force sync
argocd app sync APPNAME --force

# Common issue: Git credentials
# Solution: Check argocd/projects/gamemetrics-project.yml
```

### Issue: Services Can't Connect to Kafka
```bash
# Check network policies
kubectl get networkpolicies -n default

# Test connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nc -zv gamemetrics-kafka-bootstrap.kafka.svc.cluster.local 9092
```

## 📊 What's Next?

Now that your dev environment is running:

1. **Explore the Platform**
   - Access Grafana dashboards
   - View ArgoCD applications
   - Check Kafka topics

2. **Deploy Staging Environment**
   ```bash
   cd terraform/environments/staging
   terraform init
   terraform apply
   ```

3. **Set Up CI/CD**
   - Configure GitHub Actions secrets
   - Push code to trigger builds
   - Watch automated deployments

4. **Run Load Tests**
   ```bash
   cd tests/load
   k6 run event-load-test.js
   ```

5. **Start Chaos Engineering**
   ```bash
   kubectl apply -f chaos/experiments/kafka-broker-failure.yml
   ```

## 🆘 Getting Help

- **Documentation**: Check `docs/runbooks/` for operational procedures
- **Logs**: `kubectl logs <pod-name> -n <namespace>`
- **Events**: `kubectl get events -n <namespace> --sort-by='.lastTimestamp'`
- **Describe**: `kubectl describe pod <pod-name> -n <namespace>`

## 🎉 Success!

You now have a fully functional development environment of GameMetrics Pro running on AWS EKS! 

**Time to complete**: ~90 minutes
**Cost estimate**: ~$150-200/month for dev environment

---

**Next**: Read [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for production deployment
