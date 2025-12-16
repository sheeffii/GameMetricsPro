# 📊 k8s Folder vs Deployed Resources - Gap Analysis

**Analysis Date:** December 8, 2025  
**Root Kustomization:** `k8s/kustomization.yaml`  
**Deployed via:** `production-deploy.sh`

---

## 🎯 Summary

**What root kustomization includes:**
- ✅ Namespaces
- ✅ ArgoCD + Applications
- ✅ Secrets
- ✅ Strimzi Operator (Kafka)
- ✅ Kafka UI
- ✅ Observability Stack
- ✅ event-ingestion service

**What root kustomization EXCLUDES:**
- ❌ Databases (MinIO, Qdrant, TimescaleDB)
- ❌ Backup (Velero)
- ❌ External Secrets
- ❌ GDPR components
- ❌ HPAs (Horizontal Pod Autoscalers)
- ❌ Network Policies (except ArgoCD auto-created)
- ❌ Rollouts (Canary deployments)
- ❌ Service Mesh (Istio)
- ❌ Storage Classes
- ❌ Kyverno Policies
- ❌ Most microservices (7 of 8 missing)

---

## 📁 Folder-by-Folder Analysis

### 1️⃣ `/k8s/argocd/` ✅ DEPLOYED

**Status:** ✅ **Fully Deployed**

| Component | File | Deployed | Notes |
|-----------|------|----------|-------|
| ArgoCD Base | `base/` | ✅ Yes | 7 pods running |
| GitHub Credentials | `overlays/github-repo-creds.yaml` | ✅ Yes | Secret created |
| App of Apps | `app-of-apps.yaml` | ✅ Yes | Application created |
| Kafka App (Dev) | `application-kafka-dev.yaml` | ✅ Yes | Application created |
| Event Ingestion App | `application-event-ingestion-dev.yaml` | ✅ Yes | Application created |
| Project | `project-gamemetrics.yaml` | ❌ No | **Not in kustomization** |
| Prod Apps | `application-*-prod.yaml` | ❌ No | **Not in kustomization** |
| Notifications Config | `argocd-notifications-config.yaml` | ❌ No | **Not in kustomization** |
| Webhook Config | `argocd-webhook-config.yaml` | ❌ No | **Not in kustomization** |

**ArgoCD Apps Status:**
```
NAME                      SYNC STATUS   HEALTH STATUS
event-ingestion-dev       Unknown       Unknown
event-ingestion-service   Unknown       Unknown
gamemetrics-app-of-apps   Unknown       Unknown
kafka-cluster             Unknown       Unknown
kafka-dev                 Unknown       Unknown
monitoring-stack          Unknown       Unknown
root-app                  Unknown       Unknown
```
⚠️ Apps created but not synced yet

---

### 2️⃣ `/k8s/backup/` ❌ NOT DEPLOYED

**Status:** ❌ **NOT in kustomization.yaml**

| Component | File | Deployed | Reason |
|-----------|------|----------|--------|
| Velero | `velero-config.yaml` | ❌ No | Not referenced in root kustomization |

**What it would provide:**
- Kubernetes backup and restore
- Disaster recovery
- Volume snapshots to S3 (`gamemetrics-velero-dev` bucket exists)

**To deploy manually:**
```bash
kubectl apply -f k8s/backup/velero-config.yaml
```

---

### 3️⃣ `/k8s/databases/` ❌ NOT DEPLOYED

**Status:** ❌ **NOT in kustomization.yaml**

| Database | File | Deployed | Purpose |
|----------|------|----------|---------|
| MinIO | `minio-deployment.yaml` | ❌ No | S3-compatible object storage |
| Qdrant | `qdrant-deployment.yaml` | ❌ No | Vector database (for recommendations) |
| TimescaleDB | `timescaledb-deployment.yaml` | ❌ No | Time-series database (for analytics) |

**Current Status:**
```bash
kubectl get all -n databases
# Returns: Empty (namespace exists, no resources)
```

**What you're using instead:**
- ✅ AWS RDS PostgreSQL (external, managed by Terraform)
- ✅ AWS ElastiCache Redis (external, managed by Terraform)
- ❌ No object storage in-cluster (using S3 directly)
- ❌ No vector DB for ML/recommendations
- ❌ No time-series DB for analytics

**To deploy:**
```bash
kubectl apply -f k8s/databases/minio-deployment.yaml
kubectl apply -f k8s/databases/qdrant-deployment.yaml
kubectl apply -f k8s/databases/timescaledb-deployment.yaml
```

---

### 4️⃣ `/k8s/external-secrets/` ❌ NOT DEPLOYED

**Status:** ❌ **NOT in kustomization.yaml**

| Component | File | Deployed | Purpose |
|-----------|------|----------|---------|
| Production Secrets | `production-secrets.yaml` | ❌ No | External Secrets Operator integration |

**What you're using instead:**
- Manual secrets via `secrets/db-secrets.yaml`
- Script-based sync: `update-secrets-from-aws.sh`

**External Secrets Operator would:**
- Automatically sync AWS Secrets Manager → Kubernetes
- Auto-rotate secrets
- No manual script needed

---

### 5️⃣ `/k8s/gdpr/` ❌ NOT DEPLOYED

**Status:** ❌ **NOT in kustomization.yaml**

| Component | File | Deployed | Purpose |
|-----------|------|----------|---------|
| GDPR Deletion Job | `gdpr-deletion-job.yaml` | ❌ No | CronJob for user data deletion (GDPR compliance) |

**To deploy:**
```bash
kubectl apply -f k8s/gdpr/gdpr-deletion-job.yaml
```

---

### 6️⃣ `/k8s/hpa/` ❌ NOT DEPLOYED

**Status:** ❌ **NOT in kustomization.yaml**

| HPA | File | Deployed | Target Service |
|-----|------|----------|----------------|
| Event Ingestion | `event-ingestion-hpa.yaml` | ❌ No | event-ingestion (currently 2 static replicas) |
| Event Processor | `event-processor-hpa.yaml` | ❌ No | event-processor (not deployed) |
| Recommendation Engine | `recommendation-engine-hpa.yaml` | ❌ No | recommendation-engine (not deployed) |

**Current Status:**
```bash
kubectl get hpa -A
# Returns: No resources found
```

**What this means:**
- Services use fixed replica counts (no auto-scaling)
- Manual scaling required: `kubectl scale deployment event-ingestion --replicas=5`

**To enable auto-scaling:**
```bash
kubectl apply -f k8s/hpa/event-ingestion-hpa.yaml
kubectl apply -f k8s/hpa/event-processor-hpa.yaml
kubectl apply -f k8s/hpa/recommendation-engine-hpa.yaml
```

---

### 7️⃣ `/k8s/kafka/` ✅ PARTIALLY DEPLOYED

**Status:** ⚠️ **Base deployed, overlays applied**

| Component | Location | Deployed | Notes |
|-----------|----------|----------|-------|
| Kafka Cluster | `base/kafka.yaml` | ✅ Yes | 1 controller, 1 broker running |
| Topics | `base/topics.yaml` | ✅ Yes | All 8 topics created |
| Node Pools | `base/kafka-node-pools.yaml` | ✅ Yes | Applied |
| Dev Overlay | `overlays/dev/` | ✅ Yes | Applied via `kubectl apply -k` |
| Debezium Connect | `connect/debezium-deployment.yaml` | ❌ No | **Not in kustomization** |
| Schema Registry | `schema-registry/` | ❌ No | **Not in kustomization** |

**What's missing:**
- ❌ Debezium (CDC from PostgreSQL)
- ❌ Schema Registry (Avro schema management)

---

### 8️⃣ `/k8s/kafka-ui/` ✅ DEPLOYED

**Status:** ✅ **Fully Deployed**

| Component | File | Deployed | Status |
|-----------|------|----------|--------|
| Kafka UI | `kafka-ui.yaml` | ✅ Yes | 1 pod running in kafka namespace |

**Access:**
```bash
kubectl port-forward -n kafka svc/kafka-ui 8080:8080
# Open: http://localhost:8080
```

---

### 9️⃣ `/k8s/namespaces/` ✅ DEPLOYED

**Status:** ✅ **Fully Deployed**

All 6 namespaces created:
- ✅ kafka
- ✅ databases (empty)
- ✅ monitoring
- ✅ argocd
- ✅ gamemetrics
- ✅ default

---

### 🔟 `/k8s/network-policies/` ❌ NOT DEPLOYED

**Status:** ❌ **NOT in kustomization.yaml**

| Policy | File | Deployed | Purpose |
|--------|------|----------|---------|
| Default Deny All | `default-deny-all.yaml` | ❌ No | Block all traffic by default (security) |
| GameMetrics Allow | `gamemetrics-allow.yaml` | ❌ No | Allow specific traffic for services |

**Current Network Policies:**
```bash
kubectl get networkpolicies -A
# Shows: Only ArgoCD auto-generated policies (7)
# Shows: Kafka auto-generated policies (2)
```

**Security Impact:**
- ⚠️ No default-deny policy
- ⚠️ All pods can communicate freely
- ⚠️ No network segmentation between services

**To deploy:**
```bash
kubectl apply -f k8s/network-policies/default-deny-all.yaml
kubectl apply -f k8s/network-policies/gamemetrics-allow.yaml
```

---

### 1️⃣1️⃣ `/k8s/observability/` ✅ DEPLOYED

**Status:** ✅ **Fully Deployed**

| Component | File | Deployed | Status |
|-----------|------|----------|--------|
| Prometheus | `prometheus-deployment.yaml` | ✅ Yes | 1 pod running |
| Prometheus Config | `prometheus-config-updated.yaml` | ✅ Yes | ConfigMap created |
| Prometheus RBAC | `prometheus-rbac.yaml` | ✅ Yes | ClusterRole created |
| Alert Rules | `prometheus-alert-rules.yaml` | ✅ Yes | 40+ rules configured |
| Grafana | `grafana-deployment.yaml` | ✅ Yes | 1 pod running |
| Grafana Config | `grafana-config.yaml` | ✅ Yes | Dashboards configured |
| Loki | `loki-deployment.yaml` | ✅ Yes | 1 pod running |
| Loki Config | `loki-config.yaml` | ✅ Yes | 7-day retention |
| AlertManager | `alertmanager-deployment.yaml` | ✅ Yes | 1 pod running |
| AlertManager Config | `alertmanager-config.yaml` | ✅ Yes | Routing configured |
| Promtail | `promtail-daemonset.yaml` | ✅ Yes | 4 pods running (DaemonSet) |
| Promtail Config | `promtail-config.yaml` | ✅ Yes | Log collection configured |

**Subdirectories NOT deployed:**
- ❌ `grafana/dashboards/` - Custom JSON dashboards (6 files)
- ❌ `servicemonitors/` - ServiceMonitor CRDs
- ❌ `tempo/` - Distributed tracing
- ❌ `thanos/` - Long-term Prometheus storage

---

### 1️⃣2️⃣ `/k8s/policies/` ❌ NOT DEPLOYED

**Status:** ❌ **NOT in kustomization.yaml**

| Component | Location | Deployed | Purpose |
|-----------|----------|----------|---------|
| Kyverno Policies | `kyverno/` | ❌ No | Policy enforcement (require labels, limit resources, etc.) |

**What Kyverno would provide:**
- Enforce naming conventions
- Require resource limits
- Validate configurations
- Auto-inject labels/annotations

---

### 1️⃣3️⃣ `/k8s/rollouts/` ❌ NOT DEPLOYED

**Status:** ❌ **NOT in kustomization.yaml**

| Component | File | Deployed | Purpose |
|-----------|------|----------|---------|
| Canary Deployment | `canary-deployment.yaml` | ❌ No | Argo Rollouts canary strategy |

**Current Deployment Strategy:**
- Using standard Kubernetes `RollingUpdate`
- No canary or blue-green deployments
- No progressive delivery

---

### 1️⃣4️⃣ `/k8s/secrets/` ✅ DEPLOYED

**Status:** ✅ **Fully Deployed**

| Secret | File | Deployed | Status |
|--------|------|----------|--------|
| DB Credentials | `db-secrets.yaml` | ✅ Yes | Secret created |
| Kafka Credentials | (generated) | ✅ Yes | Secret created |
| Redis Credentials | (generated) | ✅ Yes | Secret created |

---

### 1️⃣5️⃣ `/k8s/security/` ❌ NOT DEPLOYED

**Status:** ❌ **NOT in kustomization.yaml**

| Component | File | Deployed | Purpose |
|-----------|------|----------|---------|
| Pod Security Standards | `pod-security-standards.yaml` | ❌ No | PSS policies (restricted/baseline) |

**Security Impact:**
- ⚠️ No pod security policies enforced
- ⚠️ Pods can run as root
- ⚠️ Pods can use privileged containers

---

### 1️⃣6️⃣ `/k8s/service-mesh/` ❌ NOT DEPLOYED

**Status:** ❌ **NOT in kustomization.yaml**

| Component | Location | Deployed | Purpose |
|-----------|----------|----------|---------|
| Istio | `istio/` | ❌ No | Service mesh (mTLS, traffic management, observability) |

**Namespace Labels Show Istio Planned:**
```yaml
# From namespaces.yml:
gamemetrics:
  istio-injection: enabled  # But Istio not installed
```

---

### 1️⃣7️⃣ `/k8s/services/` ⚠️ PARTIALLY DEPLOYED

**Status:** ⚠️ **Only 1 of 8 services deployed**

| Service | Directory | Deployed | Status |
|---------|-----------|----------|--------|
| **event-ingestion** | `event-ingestion/` | ✅ Yes | 2 pods running |
| event-processor | `event-processor/` | ❌ No | Not in kustomization |
| recommendation-engine | `recommendation-engine/` | ❌ No | Not in kustomization |
| analytics-api | `analytics-api/` | ❌ No | Not in kustomization |
| user-service | `user-service/` | ❌ No | Not in kustomization |
| notification-service | `notification-service/` | ❌ No | Not in kustomization |
| data-retention-service | `data-retention-service/` | ❌ No | Not in kustomization |
| admin-dashboard | `admin-dashboard/` | ❌ No | Not in kustomization |

**Event Consumers (Python):**
| Consumer | File | Deployed | Purpose |
|----------|------|----------|---------|
| Leaderboard | `event-consumers-deployment.yaml` | ❌ No | Process leaderboard events |
| Logger | `event-consumers-deployment.yaml` | ❌ No | Log events to storage |
| Stats | `event-consumers-deployment.yaml` | ❌ No | Calculate statistics |

**Deployment Coverage:** 12.5% (1 of 8 services)

---

### 1️⃣8️⃣ `/k8s/storage/` ❌ NOT DEPLOYED

**Status:** ❌ **NOT in kustomization.yaml**

| Component | File | Deployed | Purpose |
|-----------|------|----------|---------|
| Storage Classes | `storage-classes.yaml` | ❌ No | Custom storage classes (SSD, HDD, etc.) |

**Current Storage:**
```bash
kubectl get storageclass
# Shows: Only default EKS gp2 (AWS EBS)
```

---

### 1️⃣9️⃣ `/k8s/strimzi/` ✅ DEPLOYED

**Status:** ✅ **Fully Deployed**

Strimzi Kafka Operator deployed and operational.

---

## 📊 Deployment Coverage Summary

### By Category

| Category | Deployed | Total | % | Status |
|----------|----------|-------|---|--------|
| **Core Infrastructure** | 6 | 6 | 100% | ✅ |
| **Kafka** | 1 | 3 | 33% | ⚠️ |
| **Observability** | 12 | 16 | 75% | ⚠️ |
| **Services** | 1 | 8 | 12.5% | ❌ |
| **Databases** | 0 | 3 | 0% | ❌ |
| **Security** | 0 | 4 | 0% | ❌ |
| **Advanced Features** | 0 | 8 | 0% | ❌ |

### Overall Deployment

**Deployed Resources:** 20  
**Available Resources:** 48  
**Coverage:** 41.6%

---

## 🎯 What's Actually Running

### ✅ Deployed & Running (20 components)

1. **Infrastructure (6)**
   - ✅ Namespaces (6)
   - ✅ RBAC & Service Accounts
   - ✅ Secrets (3)

2. **Kafka (1)**
   - ✅ Strimzi Operator
   - ✅ Kafka Cluster (1 controller, 1 broker)
   - ✅ 8 Topics
   - ✅ Kafka UI

3. **Observability (12)**
   - ✅ Prometheus
   - ✅ Grafana
   - ✅ Loki
   - ✅ AlertManager
   - ✅ Promtail (4 pods)
   - ✅ 40+ Alert Rules
   - ✅ RBAC for Prometheus

4. **GitOps (1)**
   - ✅ ArgoCD (7 pods)
   - ✅ 7 Applications (unsynced)

5. **Services (1)**
   - ✅ event-ingestion (2 pods)

---

## ❌ Not Deployed (28 components)

1. **Databases (3)**
   - ❌ MinIO
   - ❌ Qdrant
   - ❌ TimescaleDB

2. **Services (7)**
   - ❌ event-processor
   - ❌ recommendation-engine
   - ❌ analytics-api
   - ❌ user-service
   - ❌ notification-service
   - ❌ data-retention-service
   - ❌ admin-dashboard

3. **Kafka Add-ons (2)**
   - ❌ Debezium CDC
   - ❌ Schema Registry

4. **Security (4)**
   - ❌ Network Policies (default-deny)
   - ❌ Pod Security Standards
   - ❌ Kyverno Policies
   - ❌ Istio Service Mesh

5. **Advanced Features (8)**
   - ❌ HPAs (3)
   - ❌ Velero Backup
   - ❌ External Secrets Operator
   - ❌ GDPR Compliance Job
   - ❌ Argo Rollouts (Canary)
   - ❌ Custom Storage Classes
   - ❌ Tempo (Tracing)
   - ❌ Thanos (Long-term storage)

6. **Observability Add-ons (4)**
   - ❌ Custom Grafana Dashboards (6 JSON files)
   - ❌ ServiceMonitors
   - ❌ Tempo (distributed tracing)
   - ❌ Thanos (Prometheus long-term storage)

---

## 🚀 How to Deploy Missing Components

### Quick Wins (High Value, Low Effort)

```bash
# 1. Enable HPAs for auto-scaling
kubectl apply -f k8s/hpa/event-ingestion-hpa.yaml

# 2. Add network security
kubectl apply -f k8s/network-policies/default-deny-all.yaml
kubectl apply -f k8s/network-policies/gamemetrics-allow.yaml

# 3. Deploy databases
kubectl apply -f k8s/databases/minio-deployment.yaml
kubectl apply -f k8s/databases/qdrant-deployment.yaml
kubectl apply -f k8s/databases/timescaledb-deployment.yaml

# 4. Enable Velero backups
kubectl apply -f k8s/backup/velero-config.yaml

# 5. Add Pod Security Standards
kubectl apply -f k8s/security/pod-security-standards.yaml
```

### Deploy All Services

```bash
# Event Consumers
kubectl apply -f k8s/services/event-consumers-deployment.yaml

# Individual Services
kubectl apply -k k8s/services/event-processor/
kubectl apply -k k8s/services/recommendation-engine/
kubectl apply -k k8s/services/analytics-api/
kubectl apply -k k8s/services/user-service/
kubectl apply -k k8s/services/notification-service/
kubectl apply -k k8s/services/data-retention-service/
kubectl apply -k k8s/services/admin-dashboard/
```

### Enable Advanced Features

```bash
# Kafka Schema Registry
kubectl apply -k k8s/kafka/schema-registry/

# Debezium CDC
kubectl apply -f k8s/kafka/connect/debezium-deployment.yaml

# Argo Rollouts (Canary)
kubectl apply -f k8s/rollouts/canary-deployment.yaml

# Custom Storage Classes
kubectl apply -f k8s/storage/storage-classes.yaml

# GDPR Compliance
kubectl apply -f k8s/gdpr/gdpr-deletion-job.yaml
```

---

## ✅ Conclusion

**What the `production-deploy.sh` script deployed:**
- Core infrastructure (namespaces, RBAC, secrets)
- Kafka cluster with topics
- Full observability stack
- ArgoCD for GitOps
- 1 application service

**What exists in k8s folder but is NOT deployed:**
- 58% of available components
- Most microservices (7 of 8)
- All databases (MinIO, Qdrant, TimescaleDB)
- Security features (network policies, PSS)
- Advanced features (HPA, Velero, Istio, etc.)

**Why?**
The root `k8s/kustomization.yaml` only references a minimal set of resources. Many components exist but are not included in the kustomization file, so they weren't deployed.

**Recommendation:**
Either:
1. Add missing components to `k8s/kustomization.yaml`, or
2. Deploy them manually using the commands above
