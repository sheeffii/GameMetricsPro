# Complete Project Deployment & Operations Guide

## ✅ What's Already Deployed

### AWS Infrastructure (via Terraform)
- **EKS Cluster**: `gamemetrics-dev` in us-east-1
- **RDS PostgreSQL**: `gamemetrics-dev.cwxu6k6ikgjr.us-east-1.rds.amazonaws.com:5432`
- **ElastiCache Redis**: `gamemetrics-dev.xl8xkv.ng.0001.use1.cache.amazonaws.com:6379`
- **VPC, Subnets, NAT, Security Groups**
- **S3 Buckets** for logs and data

### Kubernetes Resources (via Kustomize)
- **Namespaces**: kafka, gamemetrics, monitoring, databases, argocd
- **Strimzi Operator**: Kafka operator running
- **Kafka Cluster**: KRaft mode, 1 broker + 1 controller
- **Kafka Topics**: 6 topics (player.events.raw, player.events.processed, recommendations.generated, user.actions, notifications, dlq.events)
- **Kafka UI**: Running and accessible

---

## 🚀 Next Steps to Complete Setup

### 1. Verify Kafka UI Access
```bash
# Port-forward Kafka UI
kubectl -n kafka port-forward svc/kafka-ui 8080:80

# Open browser: http://localhost:8080
# You should now see the cluster "gamemetrics-dev" with all topics
```

### 2. Deploy Application Services

Create application deployments in `k8s/services/` using Kustomize:

#### Event Ingestion Service
```bash
# Create the service structure
mkdir -p k8s/services/event-ingestion/base
```

**File: `k8s/services/event-ingestion/base/deployment.yaml`**
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
      containers:
      - name: event-ingestion
        image: YOUR_ECR_REGISTRY/event-ingestion:latest
        ports:
        - containerPort: 8080
        env:
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "gamemetrics-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092"
        - name: REDIS_HOST
          value: "gamemetrics-dev.xl8xkv.ng.0001.use1.cache.amazonaws.com"
        - name: REDIS_PORT
          value: "6379"
        - name: DB_HOST
          value: "gamemetrics-dev.cwxu6k6ikgjr.us-east-1.rds.amazonaws.com"
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: "gamemetrics"
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: event-ingestion
  namespace: gamemetrics
spec:
  selector:
    app: event-ingestion
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
```

**File: `k8s/services/event-ingestion/base/kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: gamemetrics

resources:
  - deployment.yaml
```

### 3. Create Database Secrets
```bash
# Create PostgreSQL credentials secret
kubectl create secret generic db-credentials -n gamemetrics \
  --from-literal=username=postgres \
  --from-literal=password=YOUR_DB_PASSWORD

# Get the actual password from Terraform outputs or AWS Secrets Manager
```

### 4. Deploy Monitoring Stack (Prometheus + Grafana)

```bash
# Add Prometheus/Grafana using Helm via Kustomize
mkdir -p k8s/monitoring/base
```

**File: `k8s/monitoring/base/prometheus.yaml`**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
      - role: pod
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: config
        configMap:
          name: prometheus-config
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
```

### 5. Update Root Kustomization

**Update: `k8s/kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  # Namespaces
  - namespaces/namespaces.yml
  
  # Strimzi Operator (Kafka operator)
  - strimzi/base
  
  # Kafka Cluster (KRaft mode)
  - kafka/overlays/dev
  
  # Kafka UI
  - kafka-ui
  
  # Application Services
  - services/event-ingestion/base
  
  # Monitoring
  - monitoring/base

commonLabels:
  app.kubernetes.io/managed-by: kustomize
  environment: dev
  cluster: gamemetrics-dev
```

### 6. Build and Push Docker Images

```bash
# If you have services/ directory with code:
cd services/event-ingestion

# Build and push to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

docker build -t event-ingestion:latest .
docker tag event-ingestion:latest YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/event-ingestion:latest
docker push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/event-ingestion:latest
```

### 7. Deploy Everything
```bash
# Apply all resources
kubectl apply -k k8s/

# Verify all pods
kubectl get pods -A
```

---

## 🔍 Testing & Validation

### Test Kafka End-to-End
```bash
# Produce a test message
kubectl -n kafka exec gamemetrics-kafka-broker-0 -- bash -lc '
echo "{\"player_id\":\"test123\",\"event\":\"login\",\"timestamp\":\"$(date -Iseconds)\"}" | \
/opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic player.events.raw
'

# Consume from topic
kubectl -n kafka exec gamemetrics-kafka-broker-0 -- bash -lc '
/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic player.events.raw --from-beginning --max-messages 1
'
```

### Test Database Connection
```bash
# Port-forward RDS (if not publicly accessible)
# Or use psql from a pod
kubectl run -it --rm psql-client --image=postgres:15 --restart=Never -n gamemetrics -- \
  psql -h gamemetrics-dev.cwxu6k6ikgjr.us-east-1.rds.amazonaws.com -U postgres -d gamemetrics
```

### Test Redis Connection
```bash
kubectl run -it --rm redis-client --image=redis:7 --restart=Never -n gamemetrics -- \
  redis-cli -h gamemetrics-dev.xl8xkv.ng.0001.use1.cache.amazonaws.com ping
```

---

## 📊 Access UIs

### Kafka UI
```bash
kubectl -n kafka port-forward svc/kafka-ui 8080:80
# http://localhost:8080
```

### Prometheus (after deployment)
```bash
kubectl -n monitoring port-forward svc/prometheus 9090:9090
# http://localhost:9090
```

### Grafana (if deployed)
```bash
kubectl -n monitoring port-forward svc/grafana 3000:3000
# http://localhost:3000
```

---

## 🔄 Common Operations

### Update Kafka Configuration
```bash
# Edit k8s/kafka/overlays/dev/kafka-patch.yaml
# Then:
kubectl apply -k k8s/

# Kafka will rolling restart automatically
```

### Add New Kafka Topic
Create `k8s/kafka/base/new-topic.yaml`:
```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: my.new.topic
  labels:
    strimzi.io/cluster: gamemetrics-kafka
spec:
  partitions: 3
  replicas: 1
  config:
    retention.ms: 604800000
    compression.type: lz4
```

Add to `k8s/kafka/base/kustomization.yaml` resources, then `kubectl apply -k k8s/`

### Scale Application
```bash
# Edit deployment replicas in manifest or:
kubectl scale deployment event-ingestion -n gamemetrics --replicas=5

# Make it permanent by updating the YAML
```

### View Logs
```bash
# Kafka broker logs
kubectl logs -n kafka gamemetrics-kafka-broker-0 -f

# Application logs
kubectl logs -n gamemetrics -l app=event-ingestion -f --tail=100
```

---

## 🛡️ Security Checklist

- [ ] Rotate database passwords
- [ ] Enable Kafka authentication (SCRAM-SHA-512)
- [ ] Enable Kafka TLS
- [ ] Set up Network Policies
- [ ] Configure Pod Security Standards
- [ ] Enable audit logging
- [ ] Set up secrets management (AWS Secrets Manager or Vault)

---

## 🧹 Cleanup

### Delete Kubernetes Resources
```bash
kubectl delete -k k8s/
```

### Delete AWS Infrastructure
```bash
cd terraform/environments/dev
terraform destroy
```

---

## 📝 Summary of Connection Strings

| Service | Connection String |
|---------|------------------|
| **Kafka (in-cluster)** | `gamemetrics-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092` |
| **RDS PostgreSQL** | `gamemetrics-dev.cwxu6k6ikgjr.us-east-1.rds.amazonaws.com:5432` |
| **ElastiCache Redis** | `gamemetrics-dev.xl8xkv.ng.0001.use1.cache.amazonaws.com:6379` |
| **Kafka UI** | `kubectl port-forward svc/kafka-ui -n kafka 8080:80` |

---

## 🎯 Current Status

✅ **Completed:**
- AWS infrastructure provisioned
- Kubernetes cluster configured
- Kafka cluster running (KRaft mode)
- 6 topics created and ready
- Kafka UI deployed and accessible
- All managed via Kustomize (no scripts)

⏳ **Remaining:**
- Build and deploy application services (event-ingestion, analytics, etc.)
- Create database secrets
- Deploy monitoring stack (Prometheus/Grafana)
- Set up CI/CD pipeline (ArgoCD recommended)
- Configure ingress/load balancer for external access
- Enable authentication and TLS
- Set up alerting rules

**You are now ready to deploy your application services and start processing events!**
