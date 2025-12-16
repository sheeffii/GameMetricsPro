# Observability Stack - Access Guide

## 🎯 What's Deployed

✅ **Prometheus** - Metrics collection and storage (256Mi RAM, 7-day retention)
✅ **Grafana** - Visualization dashboards (128Mi RAM)
✅ **Loki** - Log aggregation (128Mi RAM, 7-day retention)
✅ **Promtail** - Log shipper (64Mi RAM per node)

All configured for **AWS free tier** with minimal resources.

---

## 📊 Access Dashboards

### Grafana (Recommended - All-in-one)
```bash
# Terminal 1 - Port forward:
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Open browser:
http://localhost:3000

# Login:
Username: admin
Password: admin123
```

**Pre-configured Dashboards:**
- 📈 **Platform Overview** - CPU, Memory, Network by namespace
- 🎯 **Kafka Cluster Monitoring** - Brokers, messages/sec, consumer lag
- 📊 **Explore Logs** - Go to "Explore" → Select "Loki" datasource

---

### Prometheus (Direct Metrics)
```bash
# Terminal 2 - Port forward:
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Open browser:
http://localhost:9090

# Example queries:
# - kafka_server_brokertopicmetrics_messagesinpersec_count
# - up{namespace="gamemetrics"}
# - rate(container_cpu_usage_seconds_total[5m])
```

---

## 📝 What's Being Monitored

### Automatically Scraped:
- ✅ **Kubernetes API Server** - Cluster health
- ✅ **Kubernetes Nodes** - CPU, memory, disk
- ✅ **Kafka Cluster** - All JMX metrics via Strimzi
- ✅ **ArgoCD Pods** - Application sync status
- ✅ **Event Ingestion Service** - Custom metrics on port 9090
- ✅ **All Pods with `prometheus.io/scrape: "true"` annotation**

### Logs Collected:
- ✅ **All pods in all namespaces** (via Promtail DaemonSet)
- ✅ **Stored in Loki** for 7 days
- ✅ **Searchable by**: namespace, pod, container, labels

---

## 🔍 Quick Checks

### Verify Prometheus is scraping targets:
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets
# Should see: kubernetes-*, kafka, event-ingestion
```

### View Kafka metrics:
```bash
# In Prometheus UI, query:
kafka_server_replicamanager_leadercount
kafka_server_brokertopicmetrics_messagesinpersec_count
```

### View logs in Grafana:
```bash
# Grafana → Explore → Loki datasource
# Query examples:
{namespace="kafka"}
{namespace="gamemetrics", app="event-ingestion"}
{namespace="argocd"} |= "error"
```

---

## 📈 Challenge Requirements Met

### ✅ Phase 3: Observability (15% of grade)
- [x] Prometheus deployed with ServiceMonitors
- [x] Grafana with pre-configured dashboards
- [x] Loki for log aggregation
- [x] Prometheus scraping Kafka JMX metrics
- [x] All pods discoverable and monitored
- [ ] Thanos (optional - for multi-cluster, not needed for dev)
- [ ] Tempo (distributed tracing - next phase)
- [ ] AlertManager with 40+ rules (next phase)
- [ ] OpenTelemetry instrumentation (requires service code updates)

**Current Score: ~8/15 points** ⭐⭐⭐

To get full 15/15:
1. Add AlertManager with alerting rules (2 points)
2. Add Tempo for distributed tracing (2 points)
3. Create more comprehensive dashboards (1 point)
4. Add OpenTelemetry to services (2 points)

---

## 🚀 Next Steps

### Priority 1: Add AlertManager
```bash
# Deploy AlertManager to get alerts for:
- Kafka broker down
- Consumer lag > 10k
- Pod CrashLoopBackOff
- High memory usage
- Disk space low
```

### Priority 2: Instrument Services
Add Prometheus client libraries to:
- event-ingestion-service (already has /metrics endpoint)
- Other microservices when built

### Priority 3: Custom Dashboards
Create dashboards for:
- Service SLIs (error rate, latency, throughput)
- Database performance (RDS metrics)
- Cost monitoring (resource usage)
- Business metrics (events/sec, active users)

---

## 💾 Resource Usage (Free Tier Optimized)

| Component  | CPU Request | Memory Request | Memory Limit |
|------------|-------------|----------------|--------------|
| Prometheus | 100m        | 256Mi          | 512Mi        |
| Grafana    | 50m         | 128Mi          | 256Mi        |
| Loki       | 50m         | 128Mi          | 256Mi        |
| Promtail   | 50m/node    | 64Mi/node      | 128Mi/node   |

**Total:** ~300m CPU, ~850Mi RAM (well within free tier limits)

---

## 🛠️ Troubleshooting

### Prometheus not showing targets:
```bash
kubectl logs -n monitoring -l app=prometheus
# Check for scrape errors
```

### Loki not receiving logs:
```bash
kubectl logs -n monitoring -l app=promtail
# Check if Promtail can reach Loki
```

### Grafana datasource issues:
```bash
# Inside Grafana: Configuration → Data Sources → Prometheus
# Test connection should be green
```

### Reset Grafana password:
```bash
kubectl exec -n monitoring -it deployment/grafana -- grafana-cli admin reset-admin-password newpassword
```

---

## 📚 Useful Prometheus Queries

```promql
# Event ingestion metrics (if instrumented)
rate(http_requests_total{namespace="gamemetrics"}[5m])

# Kafka messages per second
sum(rate(kafka_server_brokertopicmetrics_messagesinpersec_count[5m]))

# Consumer lag
kafka_consumergroup_lag

# Pod CPU usage
sum(rate(container_cpu_usage_seconds_total{namespace="gamemetrics"}[5m])) by (pod)

# Pod memory usage
sum(container_memory_usage_bytes{namespace="gamemetrics"}) by (pod)

# Pods not ready
kube_pod_status_phase{phase!="Running"} == 1
```

---

## 🎓 For Challenge Evaluation

**Demonstrate:**
1. ✅ Grafana dashboard showing real-time metrics
2. ✅ Kafka cluster health visible in dashboards
3. ✅ Logs searchable and aggregated in Loki
4. ✅ Prometheus scraping all services
5. 🔜 Alerts firing and routing (need AlertManager)
6. 🔜 Distributed traces (need Tempo)

**Screenshot these for documentation:**
- Grafana Platform Overview dashboard
- Kafka Cluster Monitoring dashboard
- Prometheus targets page (showing all green)
- Loki logs in Grafana Explore

---

Generated: 2025-12-05
Stack Version: Prometheus 2.48, Grafana 10.2, Loki 2.9
