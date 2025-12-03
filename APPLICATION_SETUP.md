# Application Deployment Guide

## 🎯 Current Status
✅ AWS Infrastructure ready (EKS, RDS, Redis)
✅ Kafka cluster running with 6 topics
✅ Kafka UI accessible
✅ Secrets configured
✅ Service manifests created

## 📋 Next Steps

### 1. Get RDS Password from Terraform Outputs
```bash
cd terraform/environments/dev
terraform output -json | grep -A 5 rds
```

Or check AWS Secrets Manager:
```bash
aws secretsmanager get-secret-value --secret-id gamemetrics-dev-db-password --region us-east-1 --query SecretString --output text
```

### 2. Update Database Secret
Edit `k8s/secrets/db-secrets.yaml` and replace:
```yaml
password: CHANGE_ME_TO_YOUR_RDS_PASSWORD
```
With your actual RDS password.

### 3. Build and Push Docker Image

**Option A: Using AWS ECR**
```bash
# Create ECR repository
aws ecr create-repository --repository-name event-ingestion-service --region us-east-1

# Get login credentials
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Build and push
cd services/event-ingestion-service
docker build -t event-ingestion-service:latest .
docker tag event-ingestion-service:latest YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service:latest
docker push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service:latest
```

**Option B: Using existing image**
If you already have an image, just update `k8s/services/event-ingestion/deployment.yaml`:
```yaml
image: YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service:latest
```

### 4. Deploy Everything
```bash
# Apply all resources
kubectl apply -k k8s/

# Watch deployment
kubectl get pods -n gamemetrics -w
```

### 5. Verify Application is Running
```bash
# Check pods
kubectl get pods -n gamemetrics

# Check logs
kubectl logs -n gamemetrics -l app=event-ingestion -f

# Check if it can connect to Kafka
kubectl logs -n gamemetrics -l app=event-ingestion | grep -i kafka

# Check if it can connect to DB
kubectl logs -n gamemetrics -l app=event-ingestion | grep -i database
```

### 6. Test the Event Ingestion API
```bash
# Port-forward to access the service
kubectl port-forward -n gamemetrics svc/event-ingestion 8080:80

# Send a test event (in another terminal)
curl -X POST http://localhost:8080/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "player_id": "player123",
    "event_type": "login",
    "timestamp": "2025-12-01T15:30:00Z",
    "metadata": {
      "ip": "192.168.1.1",
      "device": "mobile"
    }
  }'
```

### 7. Verify Message in Kafka UI
- Open Kafka UI: `kubectl port-forward -n kafka svc/kafka-ui 8080:80`
- Go to http://localhost:8080
- Click on `player.events.raw` topic
- Go to "Messages" tab
- You should see your event

---

## 🔍 How the System Works

### Message Flow
```
1. API Request → Event Ingestion Service (Port 8080)
2. Service validates event
3. Service writes to PostgreSQL (for persistence)
4. Service writes to Redis (for caching)
5. Service produces message to Kafka topic (player.events.raw)
6. Kafka stores message (visible in Kafka UI)
7. Consumer services can read from Kafka topics
```

### Automatic Topic Management
The Entity Operator (if running) watches KafkaTopic CRs and automatically:
- Creates topics in Kafka
- Updates topic configuration
- Manages topic lifecycle

Without Entity Operator, topics are managed manually via kafka-topics.sh commands.

### Connection Details
All connections use Kubernetes secrets:
- **Kafka**: `kafka-credentials` secret → `KAFKA_BOOTSTRAP_SERVERS` env var
- **PostgreSQL**: `db-credentials` secret → `DB_HOST`, `DB_USER`, `DB_PASSWORD` env vars
- **Redis**: `redis-credentials` secret → `REDIS_HOST`, `REDIS_PORT` env vars

---

## 🚀 What You Have Now

### Infrastructure
- ✅ EKS cluster with 3 nodes
- ✅ RDS PostgreSQL (db.t3.micro)
- ✅ ElastiCache Redis (cache.t3.micro)
- ✅ VPC, subnets, NAT gateway

### Kubernetes Components
- ✅ Namespaces: kafka, gamemetrics, monitoring
- ✅ Strimzi operator
- ✅ Kafka cluster (1 broker, 1 controller)
- ✅ 6 Kafka topics created
- ✅ Kafka UI running
- ✅ Secrets configured

### Application (Ready to Deploy)
- ✅ Event ingestion service deployment manifest
- ✅ Environment variables configured
- ✅ Health checks configured
- ✅ Resource limits set
- ⏳ Docker image needs to be built/pushed
- ⏳ RDS password needs to be set

---

## 📊 Next: Add Monitoring (Optional)

After your application is running, you can add monitoring:

### Quick Prometheus Setup
```bash
# Create monitoring namespace (already exists)
kubectl create namespace monitoring

# Install Prometheus via Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring

# Access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Default credentials: admin / prom-operator
```

---

## 🔧 Troubleshooting

### If deployment fails
```bash
# Check pod status
kubectl get pods -n gamemetrics

# Describe pod for events
kubectl describe pod -n gamemetrics POD_NAME

# Check logs
kubectl logs -n gamemetrics POD_NAME

# Common issues:
# - Image pull error: Check ECR credentials and image name
# - CrashLoopBackOff: Check environment variables and secrets
# - Pending: Check resource requests vs available capacity
```

### If can't connect to RDS
```bash
# Test from a pod
kubectl run -it --rm test-db --image=postgres:15 --restart=Never -n gamemetrics -- \
  psql -h gamemetrics-dev.cwxu6k6ikgjr.us-east-1.rds.amazonaws.com -U postgres -d gamemetrics
```

### If can't connect to Redis
```bash
# Test from a pod
kubectl run -it --rm test-redis --image=redis:7 --restart=Never -n gamemetrics -- \
  redis-cli -h gamemetrics-dev.xl8xkv.ng.0001.use1.cache.amazonaws.com ping
```

---

## 📝 Summary

**What's Configured:**
1. ✅ Database secrets (needs password update)
2. ✅ Event ingestion deployment manifest
3. ✅ Service endpoints
4. ✅ Health checks
5. ✅ Resource limits
6. ✅ Security context

**Your Action Items:**
1. Get RDS password from Terraform/AWS Secrets Manager
2. Update `k8s/secrets/db-secrets.yaml`
3. Build and push Docker image to ECR
4. Update image name in `k8s/services/event-ingestion/deployment.yaml`
5. Run `kubectl apply -k k8s/`
6. Test the API endpoint

**After Deployment:**
- Monitor with `kubectl get pods -n gamemetrics`
- Check logs with `kubectl logs -n gamemetrics -l app=event-ingestion -f`
- Test API with curl or Postman
- Verify messages in Kafka UI
