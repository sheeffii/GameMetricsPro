# Next Steps - GameMetrics Platform Deployment

## ✅ **What's Done**
- [x] AWS Infrastructure deployed (EKS, VPC, Redis)
- [x] Kubernetes cluster with 3 nodes running
- [x] Kafka cluster deployed (KRaft mode)
- [x] 6 Kafka topics created
- [x] Kafka UI deployed
- [x] Strimzi operator installed
- [x] All automation scripts created and tested

## 🚧 **What Needs to be Done**

### **Step 1: Fix RDS Database Issue**
The RDS instance is created but has password validation issues. You need to:

```bash
# Option A: Wait for current RDS to finish (it's still provisioning)
cd terraform/environments/dev
terraform output rds_endpoint

# Option B: Destroy and recreate RDS with new password
cd terraform/environments/dev
terraform destroy -target=module.rds.aws_db_instance.main -auto-approve
terraform destroy -target=module.rds.random_password.master -auto-approve
terraform destroy -target=module.rds.aws_secretsmanager_secret.db_password -auto-approve
terraform apply -auto-approve
```

**Get the RDS password:**
```bash
aws secretsmanager get-secret-value \
  --secret-id gamemetrics-dev-master-password \
  --region us-east-1 \
  --query SecretString \
  --output text | jq -r .password
```

### **Step 2: Update Kubernetes Secrets**
Update the database credentials in Kubernetes:

```bash
# Edit the secrets file
nano k8s/secrets/db-secrets.yaml

# Replace CHANGE_ME_TO_YOUR_RDS_PASSWORD with actual password from Step 1
# Also update the Redis endpoint if needed

# Apply the secrets
kubectl apply -f k8s/secrets/db-secrets.yaml
```

### **Step 3: Create ECR Repository**
Create a repository to store your Docker images:

```bash
# Create ECR repository
aws ecr create-repository \
  --repository-name event-ingestion-service \
  --region us-east-1

# Get ECR login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  647523695124.dkr.ecr.us-east-1.amazonaws.com
```

### **Step 4: Build and Push Docker Image**
Build the event ingestion service:

```bash
# Navigate to service directory
cd services/event-ingestion-service

# Build Docker image
docker build -t event-ingestion-service:latest .

# Tag for ECR
docker tag event-ingestion-service:latest \
  647523695124.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service:latest

# Push to ECR
docker push 647523695124.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service:latest
```

### **Step 5: Update Deployment with ECR Image**
Update the Kubernetes deployment to use your ECR image:

```bash
# Edit the deployment file
nano k8s/services/event-ingestion/deployment.yaml

# Change:
# image: REPLACE_WITH_YOUR_ECR_IMAGE:latest
# To:
# image: 647523695124.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service:latest

# Apply the deployment
kubectl apply -k k8s/services/event-ingestion/
```

### **Step 6: Verify Application Deployment**
Check if the application is running:

```bash
# Check pods
kubectl get pods -n gamemetrics

# Check logs
kubectl logs -n gamemetrics -l app=event-ingestion

# Port-forward to test locally
kubectl port-forward -n gamemetrics svc/event-ingestion-service 8081:8080

# Test the API
curl http://localhost:8081/health
curl http://localhost:8081/ready
```

### **Step 7: Test End-to-End Flow**
Send a test event through the API:

```bash
# Send event via API
curl -X POST http://localhost:8081/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "playerId": "player-123",
    "eventType": "login",
    "timestamp": "2025-12-02T10:00:00Z",
    "metadata": {
      "device": "mobile",
      "location": "US"
    }
  }'

# Verify in Kafka
kubectl exec -n kafka gamemetrics-kafka-broker-0 -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic player.events.raw \
  --from-beginning \
  --max-messages 5

# Check in Kafka UI
kubectl port-forward -n kafka svc/kafka-ui 8080:8080
# Open: http://localhost:8080
```

### **Step 8: (Optional) Set Up Monitoring**
Deploy Prometheus and Grafana for monitoring:

```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Default credentials: admin/prom-operator
```

### **Step 9: (Optional) Set Up CI/CD with ArgoCD**
Deploy ArgoCD for GitOps:

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8082:443

# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

## 🎯 **Quick Commands**

View all available commands:
```bash
bash scripts/commands.sh
```

Check system status:
```bash
bash scripts/check-status.sh
```

Access Kafka UI:
```bash
kubectl port-forward -n kafka svc/kafka-ui 8080:8080
```

## 📊 **Current System Status**

Run this to see everything:
```bash
bash scripts/check-status.sh
```

## 🔄 **Daily Workflow**

**Starting work:**
```bash
# Check if everything is running
bash scripts/check-status.sh

# If infrastructure is down, deploy it
bash scripts/deploy-infrastructure.sh
```

**Ending work (to save costs):**
```bash
# Destroy all infrastructure
bash scripts/teardown-infrastructure.sh
```

## 🆘 **Troubleshooting**

**Pods not starting:**
```bash
kubectl describe pod <pod-name> -n kafka
kubectl logs <pod-name> -n kafka
```

**Kafka topics not visible:**
```bash
kubectl get kafkatopic -n kafka
kubectl describe kafka gamemetrics-kafka -n kafka
```

**Can't connect to RDS:**
```bash
# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier gamemetrics-dev \
  --region us-east-1

# Test connection from pod
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql -h <RDS_ENDPOINT> -U dbadmin -d gamemetrics
```

## 📚 **Documentation**

- **Architecture**: See `docs/architecture.md` (to be created)
- **API Documentation**: See `services/event-ingestion-service/README.md`
- **Kafka Topics**: See `docs/kafka-topics.md` (to be created)

## 🎓 **Learning Resources**

- Strimzi Documentation: https://strimzi.io/docs/operators/latest/overview.html
- Kafka Documentation: https://kafka.apache.org/documentation/
- EKS Best Practices: https://aws.github.io/aws-eks-best-practices/

---

**Ready to proceed? Start with Step 1!** 🚀
