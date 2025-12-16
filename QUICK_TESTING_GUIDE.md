# 🚀 Quick Testing Guide - 3 Methods

## Summary

**Project Status**: 85% complete ✅  
**MVP Ready**: YES ✅  
**What's Left**: Advanced features (Thanos, Tempo, Kyverno, multi-region)

---

## 1️⃣ **Test Kafka (Send/Receive Messages)**

### Quick Test - Send Event via REST API

```bash
# Step 1: Forward port to event-ingestion service
kubectl port-forward svc/event-ingestion -n gamemetrics 8080:8080 &

# Step 2: Send a test event
curl -X POST http://localhost:8080/events \
  -H "Content-Type: application/json" \
  -d '{
    "player_id": "user_xyz_123",
    "event_type": "game_played",
    "game_id": "poker_001",
    "amount": 250.50,
    "timestamp": "2025-12-08T10:00:00Z"
  }'

# Expected Response:
# {"status":"success","message":"Event queued to Kafka"}

# Step 3: Verify event in Kafka
KAFKA_POD=$(kubectl get pods -n kafka -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $KAFKA_POD -n kafka -- bash -c '
  /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic events \
    --from-beginning \
    --max-messages 5
'

# You should see your JSON event!
```

### Send Multiple Events (Load Test)

```bash
# Send 100 events rapidly
for i in {1..100}; do
  curl -s -X POST http://localhost:8080/events \
    -H "Content-Type: application/json" \
    -d "{
      \"player_id\": \"user_$((RANDOM % 50))\",
      \"event_type\": \"game_played\",
      \"game_id\": \"game_$((RANDOM % 10 + 1))\",
      \"amount\": $((RANDOM % 1000 + 1)).50,
      \"timestamp\": \"2025-12-08T10:00:00Z\"
    }" &
done
wait

echo "✅ Sent 100 events!"
```

---

## 2️⃣ **Test Database (Check Data Stored)**

### Query TimescaleDB

```bash
# Forward port
kubectl port-forward svc/timescaledb -n gamemetrics 5432:5432 &

# Connect to database
psql -h localhost -U postgres -d gamemetrics

# Inside psql, run:

-- List all tables
\dt

-- Count events
SELECT COUNT(*) FROM events;

-- View last 10 events
SELECT player_id, event_type, game_id, amount, timestamp 
FROM events 
ORDER BY timestamp DESC 
LIMIT 10;

-- Aggregated stats by player
SELECT player_id, COUNT(*) as event_count, SUM(amount) as total_spent
FROM events
GROUP BY player_id
ORDER BY total_spent DESC
LIMIT 10;

-- Exit
\q
```

### Check MinIO (Object Storage)

```bash
# Forward ports
kubectl port-forward svc/minio -n gamemetrics 9000:9000 &
kubectl port-forward svc/minio -n gamemetrics 9001:9001 &

# Open MinIO Console
# Browser: http://localhost:9001
# Login: minioadmin / minioadmin

# You'll see:
# - Buckets: gamemetrics-data, gamemetrics-logs, etc.
# - Upload files
# - View stored objects
```

### Check Qdrant (Vector DB)

```bash
# Forward port
kubectl port-forward svc/qdrant -n gamemetrics 6333:6333 &

# Check API
curl http://localhost:6333/health

# List collections
curl http://localhost:6333/collections
```

---

## 3️⃣ **Monitor Data Flow (Real-Time)**

### Watch Logs - All Services

```bash
# Terminal 1: Watch event-ingestion (receives HTTP)
kubectl logs -f deployment/event-ingestion -n gamemetrics --timestamps=true

# Terminal 2: Watch event-processor (consumes Kafka)
kubectl logs -f deployment/event-processor -n gamemetrics --timestamps=true

# Terminal 3: Watch database insertions
kubectl logs -f deployment/event-processor -n gamemetrics | grep -i "insert\|error\|success"
```

### View in Grafana (Dashboard)

```bash
# Forward Grafana
kubectl port-forward svc/grafana -n monitoring 3000:80 &

# Open browser
# http://localhost:3000

# Login: admin / prom-operator

# Go to Dashboards:
# 1. "Platform Overview" - all services status
# 2. "Kafka Health" - topics, messages, consumers
# 3. "Service SLIs" - latency, errors, throughput
# 4. "Database Performance" - queries, connections
# 5. "Business Metrics" - player activity, revenue
```

### View in Kafka UI (Visual)

```bash
# Forward Kafka UI
kubectl port-forward svc/kafka-ui -n kafka 8081:80 &

# Open browser
# http://localhost:8081

# You'll see:
# - Topics list with message counts
# - Messages in each topic (with full payload)
# - Consumer groups and lag
# - Broker health
```

---

## 📊 Complete Data Flow Test (Step-by-Step)

### Step 1: Send Event
```bash
curl -X POST http://localhost:8080/events \
  -H "Content-Type: application/json" \
  -d '{
    "player_id": "test_user_001",
    "event_type": "game_played",
    "game_id": "slots_25",
    "amount": 500.00
  }'
```

### Step 2: See in Kafka
```bash
# Open in another terminal
kubectl exec -it $(kubectl get pods -n kafka -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].metadata.name}') -n kafka -- bash -c '
  /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic events \
    --max-messages 1
'
# Should see: {"player_id":"test_user_001",...}
```

### Step 3: Check Database (wait 5 seconds)
```bash
psql -h localhost -U postgres -d gamemetrics -c "
  SELECT * FROM events WHERE player_id = 'test_user_001';
"
```

### Step 4: View in Grafana
```bash
# Open http://localhost:3000
# Go to "Platform Overview" dashboard
# Look at "Events Received" metric - should increase
```

### Step 5: Query Analytics API
```bash
kubectl port-forward svc/analytics-api -n gamemetrics 3000:3000 &

curl -X POST http://localhost:3000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{
      events(playerId: \"test_user_001\", limit: 5) {
        id
        playerId
        eventType
        amount
        timestamp
      }
    }"
  }'
```

---

## 🔍 Troubleshooting Tests

### Issue: No events in database after sending

**Diagnose**:
```bash
# 1. Check if Kafka has the message
KAFKA_POD=$(kubectl get pods -n kafka -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $KAFKA_POD -n kafka -- bash -c '
  /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic events --max-messages 5
'

# 2. Check event-processor logs
kubectl logs deployment/event-processor -n gamemetrics | tail -50

# 3. Check database connectivity
kubectl exec -it deployment/event-processor -n gamemetrics -- bash
# Inside: psql -h timescaledb -U postgres -d gamemetrics -c "SELECT 1"
```

### Issue: Services not responding

**Diagnose**:
```bash
# Check all pods
kubectl get pods -n gamemetrics

# Check one pod
kubectl describe pod <pod-name> -n gamemetrics

# Check logs
kubectl logs <pod-name> -n gamemetrics
```

### Issue: Kafka messages piling up (not consumed)

**Diagnose**:
```bash
# Check consumer lag
KAFKA_POD=$(kubectl get pods -n kafka -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $KAFKA_POD -n kafka -- bash -c '
  /opt/kafka/bin/kafka-consumer-groups.sh \
    --bootstrap-server localhost:9092 \
    --group event-processor \
    --describe
'

# Fix: Restart event-processor
kubectl rollout restart deployment/event-processor -n gamemetrics
```

---

## ✅ Testing Checklist

```
DATA FLOW TEST:
☐ Send event via REST API
☐ Event appears in Kafka (kafka-console-consumer)
☐ event-processor consuming logs show "processing..."
☐ Data appears in TimescaleDB
☐ Grafana dashboard shows metrics increasing
☐ Can query via GraphQL API

LOAD TEST:
☐ Send 100 events in loop
☐ No errors (HTTP 200s)
☐ All events consumed by processor
☐ All events in database
☐ Grafana shows throughput increasing

MONITORING TEST:
☐ Grafana dashboards load
☐ Prometheus scraping metrics
☐ Loki has logs
☐ Kafka UI shows topics/messages
☐ Alerts firing (if load high)

DATABASE TEST:
☐ TimescaleDB responding
☐ MinIO console accessible
☐ Qdrant API responsive
☐ Redis responding
```

---

## 🎯 Key Endpoints Reference

| Service | Port | Command |
|---------|------|---------|
| Event-Ingestion API | 8080 | `kubectl port-forward svc/event-ingestion -n gamemetrics 8080:8080` |
| Kafka UI | 8081 | `kubectl port-forward svc/kafka-ui -n kafka 8081:80` |
| Grafana | 3000 | `kubectl port-forward svc/grafana -n monitoring 3000:80` |
| Prometheus | 9090 | `kubectl port-forward svc/prometheus -n monitoring 9090:9090` |
| MinIO Console | 9001 | `kubectl port-forward svc/minio -n gamemetrics 9001:9001` |
| Qdrant API | 6333 | `kubectl port-forward svc/qdrant -n gamemetrics 6333:6333` |
| TimescaleDB | 5432 | `kubectl port-forward svc/timescaledb -n gamemetrics 5432:5432` |
| Analytics API | 3000 | `kubectl port-forward svc/analytics-api -n gamemetrics 3000:3000` |

---

## 🚀 Start Everything at Once

```bash
# Open multiple terminals or use tmux/screen

# Terminal 1: Forward all services
kubectl port-forward svc/event-ingestion -n gamemetrics 8080:8080 &
kubectl port-forward svc/kafka-ui -n kafka 8081:80 &
kubectl port-forward svc/grafana -n monitoring 3000:80 &
kubectl port-forward svc/timescaledb -n gamemetrics 5432:5432 &
kubectl port-forward svc/minio -n gamemetrics 9001:9001 &

# Terminal 2: Send test events in loop
watch -n 1 'curl -s -X POST http://localhost:8080/events -H "Content-Type: application/json" -d "{\"player_id\":\"test_$(date +%s)\",\"event_type\":\"game_played\",\"game_id\":\"poker_01\",\"amount\":100}"'

# Terminal 3: Watch logs
kubectl logs -f deployment/event-processor -n gamemetrics --timestamps=true

# Open Browsers:
# - http://localhost:8081 (Kafka UI - see messages)
# - http://localhost:3000 (Grafana - see metrics)
# - psql -h localhost -U postgres -d gamemetrics (query database)
```

---

**Everything is ready to test! Start with the Quick Test section above.** ✅
