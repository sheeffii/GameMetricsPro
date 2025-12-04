# Complete Event Processing Pipeline - Testing & Deployment Guide

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                    Your Event Processing Pipeline               │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  HTTP POST /api/v1/events                                       │
│  └─> Go Event Ingestion Service (Port 8080)                     │
│      └─> Kafka Producer (SASL/SCRAM authenticated)              │
│          └─> Topic: player.events.raw                           │
│              └─> Partition by player_id (3 partitions)          │
│                  │                                               │
│                  ├─────────> Python Consumer 1: Logger          │
│                  │           └─> PostgreSQL events table        │
│                  │                                               │
│                  ├─────────> Python Consumer 2: Stats Agg.      │
│                  │           └─> PostgreSQL stats table         │
│                  │           └─> Redis player_stats hash        │
│                  │                                               │
│                  └─────────> Python Consumer 3: Leaderboard     │
│                              └─> PostgreSQL leaderboards table  │
│                              └─> Redis leaderboard sorted sets  │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Database Setup

### Step 1.1: Deploy Database Schema

```bash
# Set environment variables
export DB_HOST="gamemetrics-dev.cwxu6k6ikgjr.us-east-1.rds.amazonaws.com"
export DB_PORT="5432"
export DB_NAME="gamemetrics"
export DB_USER="postgres"
export DB_PASSWORD="your-db-password"

# Run migrations
python scripts/migrate_db.py

# Output should show:
# ✓ Table 'events': exists
# ✓ Table 'player_statistics': exists
# ✓ Table 'leaderboards': exists
# ✓ Table 'dlq_events': exists
```

### Step 1.2: Verify Database Tables

```bash
# Connect to database
psql -h $DB_HOST -U $DB_USER -d $DB_NAME

# Check tables
\dt

# Check event structure
\d+ events

# Expected columns:
# event_id (UUID) | event_type (VARCHAR) | player_id | game_id | 
# event_timestamp | ingested_at | data (JSONB) | created_at
```

---

## Phase 2: Build Consumer Docker Images

### Step 2.1: Build Logger Consumer

```bash
cd services/event-consumer-logger

# Build image
docker build -t event-consumer-logger:latest .

# Tag for ECR
docker tag event-consumer-logger:latest \
  647523695124.dkr.ecr.us-east-1.amazonaws.com/event-consumer-logger:latest

# Push to ECR
docker push 647523695124.dkr.ecr.us-east-1.amazonaws.com/event-consumer-logger:latest
```

**Dockerfile for consumers** (create at `services/event-consumer-logger/Dockerfile`):

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY consumer.py .

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ps aux | grep "consumer.py" | grep -v grep || exit 1

# Run consumer
CMD ["python", "consumer.py"]
```

### Step 2.2: Build Stats Aggregator

```bash
cd services/event-consumer-stats
docker build -t event-consumer-stats:latest .
docker tag event-consumer-stats:latest \
  647523695124.dkr.ecr.us-east-1.amazonaws.com/event-consumer-stats:latest
docker push 647523695124.dkr.ecr.us-east-1.amazonaws.com/event-consumer-stats:latest
```

### Step 2.3: Build Leaderboard Manager

```bash
cd services/event-consumer-leaderboard
docker build -t event-consumer-leaderboard:latest .
docker tag event-consumer-leaderboard:latest \
  647523695124.dkr.ecr.us-east-1.amazonaws.com/event-consumer-leaderboard:latest
docker push 647523695124.dkr.ecr.us-east-1.amazonaws.com/event-consumer-leaderboard:latest
```

---

## Phase 3: Deploy Consumers to Kubernetes

### Step 3.1: Create Kafka Credentials Secret

```bash
# Get Kafka broker details from your cluster
kubectl get kafka -n kafka -o yaml

# Create secret with bootstrap servers and credentials
kubectl create secret generic kafka-credentials \
  --from-literal=bootstrap-servers=gamemetrics-kafka-bootstrap.kafka:9092 \
  --from-literal=username=gamemetrics \
  --from-literal=password=your-kafka-password \
  -n gamemetrics
```

### Step 3.2: Deploy Consumer Services

```bash
# Deploy all consumers
kubectl apply -f k8s/services/event-consumers-deployment.yaml

# Verify deployments
kubectl get deployments -n gamemetrics -l component=consumer

# Watch logs
kubectl logs -n gamemetrics deployment/event-consumer-logger -f
kubectl logs -n gamemetrics deployment/event-consumer-stats -f
kubectl logs -n gamemetrics deployment/event-consumer-leaderboard -f

# Check pod status
kubectl get pods -n gamemetrics -l component=consumer
```

### Step 3.3: Verify Consumer Health

```bash
# Check pod events
kubectl describe pod -n gamemetrics <pod-name>

# Check consumer group offsets
kubectl exec -n kafka gamemetrics-kafka-0 -- \
  kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group event-logger-group --describe
```

---

## Phase 4: Test Producer → Kafka Flow

### Step 4.1: Port-Forward to Producer

```bash
# In Terminal 1: Forward to ingestion service
kubectl port-forward -n gamemetrics svc/event-ingestion 8080:8080 &

# In Terminal 2: Monitor Kafka topic
kubectl port-forward -n kafka svc/strimzi-kafka-ui 8081:8081 &
```

### Step 4.2: Send Single Test Event

```bash
curl -X POST http://localhost:8080/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "player_level_up",
    "player_id": "player-test-001",
    "game_id": "game-test-001",
    "timestamp": "2024-01-15T10:30:00Z",
    "data": {
      "new_level": 5,
      "experience_gained": 500,
      "achievement": "first_level_5"
    }
  }'

# Expected Response:
# {
#   "status": "success",
#   "event_id": "550e8400-e29b-41d4-a716-446655440000"
# }
```

### Step 4.3: View Event in Kafka UI

```
1. Open http://localhost:8081 in browser
2. Navigate to "Topics" → "player.events.raw"
3. Check "Messages" tab - should see your event
4. Inspect message value - verify all fields present
```

### Step 4.4: Check Producer Metrics

```bash
curl http://localhost:8080/metrics | grep events

# Expected output:
# events_received_total 1
# events_published_total 1
# events_failed_total 0
# http_request_duration_seconds...
```

---

## Phase 5: Verify Consumer Consumption

### Step 5.1: Check Raw Event Logger

```bash
# Monitor logger consumer
kubectl logs -n gamemetrics deployment/event-consumer-logger -f

# Expected output:
# INFO - Kafka consumer initialized
# DEBUG - Event 550e8400-e29b-41d4-a716-446655440000 logged to database
# INFO - Stats - Processed: 100, Failed: 0
```

### Step 5.2: Query Stored Events

```bash
psql -h $DB_HOST -U $DB_USER -d $DB_NAME

# Query raw events
SELECT event_id, event_type, player_id, created_at 
FROM events 
LIMIT 10;

# Query specific player
SELECT * FROM events 
WHERE player_id = 'player-test-001' 
ORDER BY created_at DESC;
```

### Step 5.3: Check Statistics Aggregator

```bash
# Monitor stats consumer
kubectl logs -n gamemetrics deployment/event-consumer-stats -f

# Check Redis statistics
redis-cli -h <redis-endpoint> -p 6379 \
  HGETALL player_stats:player-test-001

# Expected output:
# 1) "total_events"
# 2) "1"
# 3) "event_player_level_up"
# 4) "1"
# 5) "last_event"
# 6) "2024-01-15T10:30:01Z"

# Query aggregated stats in PostgreSQL
SELECT player_id, total_events, event_breakdown 
FROM player_statistics 
WHERE player_id = 'player-test-001';
```

### Step 5.4: Check Leaderboard Manager

```bash
# Send scoring event
curl -X POST http://localhost:8080/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "player_score",
    "player_id": "player-test-001",
    "game_id": "game-test-001",
    "timestamp": "2024-01-15T10:35:00Z",
    "data": {"score": 1500}
  }'

# Check Redis leaderboard (sorted set)
redis-cli -h <redis-endpoint> -p 6379 \
  ZRANGE leaderboard:game-test-001:alltime 0 -1 WITHSCORES REV

# Check PostgreSQL leaderboards
SELECT * FROM leaderboards 
WHERE game_id = 'game-test-001' 
ORDER BY rank LIMIT 10;
```

---

## Phase 6: Load Testing

### Step 6.1: Run Bulk Event Generation

```bash
# Make script executable
chmod +x scripts/load_test_events.sh

# Generate 1000 events at 100 events/sec
./scripts/load_test_events.sh 1000 100

# Output:
# 🔥 Starting load test...
# [100/1000] Success: 100, Failed: 0
# ✅ Load test completed!
#    Duration: 10s
#    Success: 1000
#    Failed: 0
#    Rate: 100 events/sec
```

### Step 6.2: Monitor Pipeline During Load

```bash
# Terminal 1: Watch consumer logs
kubectl logs -n gamemetrics -f \
  --all-containers deployment/event-consumer-logger \
  deployment/event-consumer-stats \
  deployment/event-consumer-leaderboard

# Terminal 2: Monitor database growth
watch -n 1 "psql -h $DB_HOST -U $DB_USER -d $DB_NAME \
  -c 'SELECT COUNT(*) as events FROM events; \
      SELECT COUNT(*) as stats FROM player_statistics; \
      SELECT COUNT(*) as leaderboard FROM leaderboards;'"

# Terminal 3: Monitor Kafka topics
kubectl exec -n kafka gamemetrics-kafka-0 -- \
  kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group event-logger-group --describe
```

### Step 6.3: Performance Validation

```bash
# After load test completes:

# 1. Verify total events
psql -h $DB_HOST -U $DB_USER -d $DB_NAME \
  -c "SELECT COUNT(*) FROM events;"
# Should show: 1000+

# 2. Check statistics aggregation
psql -h $DB_HOST -U $DB_USER -d $DB_NAME \
  -c "SELECT COUNT(*) FROM player_statistics;"
# Should show: ~5 (5 test players)

# 3. Validate leaderboards
psql -h $DB_HOST -U $DB_USER -d $DB_NAME \
  -c "SELECT COUNT(*) FROM leaderboards WHERE period='alltime';"

# 4. Check Kafka lag
kubectl exec -n kafka gamemetrics-kafka-0 -- \
  kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group event-logger-group --describe
# LAG should be 0 (all messages consumed)
```

---

## Phase 7: Monitor & Troubleshoot

### Troubleshooting Guide

| Issue | Symptom | Solution |
|-------|---------|----------|
| **Events not reaching Kafka** | `events_received_total` increases but `events_published_total` doesn't | Check Kafka credentials, verify bootstrap servers accessible |
| **Consumers not processing** | Logs show no events consumed | Check consumer group offset: `kafka-consumer-groups` |
| **Database insert failures** | `psycopg2.Error` in logs | Verify DB credentials, check database connectivity, run `migrate_db.py` |
| **Redis connection failed** | `redis.ConnectionError` in stats/leaderboard logs | Check Redis endpoint, verify security group allows traffic |
| **High latency** | Events delayed reaching database | Increase consumer replicas, check Kafka partition count |
| **Memory issues** | Pod OOMKilled | Increase resource limits in deployment |

### Useful Commands

```bash
# Check all services running
kubectl get all -n gamemetrics

# View producer metrics
kubectl port-forward -n gamemetrics svc/event-ingestion 9090:9090
# Then: curl http://localhost:9090/metrics

# Check Kafka topics
kubectl exec -n kafka gamemetrics-kafka-0 -- \
  kafka-topics.sh --bootstrap-server localhost:9092 --list

# Monitor consumer lag in real-time
watch -n 5 'kubectl exec -n kafka gamemetrics-kafka-0 -- \
  kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group event-logger-group --describe'

# Stream logs from all consumers
kubectl logs -n gamemetrics -f -l component=consumer --tail=50 --all-containers

# Check resource usage
kubectl top pods -n gamemetrics
```

---

## Phase 8: Production Checklist

- [ ] Database schema migrated and verified
- [ ] Consumer Docker images built and pushed to ECR
- [ ] Kafka credentials configured in Kubernetes
- [ ] Consumer deployments running (check pod status)
- [ ] Producer → Kafka connection verified
- [ ] Raw events appearing in PostgreSQL `events` table
- [ ] Statistics aggregating in `player_statistics` table
- [ ] Leaderboards updating in Redis and PostgreSQL
- [ ] Load test completed with 0% failure rate
- [ ] Consumer lag is 0 (all messages consumed)
- [ ] Monitoring dashboards configured
- [ ] Error handling (DLQ) verified

---

## Next Steps

1. **API Gateway** - Add authentication/rate limiting for `/api/v1/events`
2. **Dashboards** - Create Grafana dashboards for real-time monitoring
3. **Alerts** - Configure alerts for high latency, consumer lag, failures
4. **Backup** - Set up automated PostgreSQL backups
5. **Scaling** - Monitor metrics and auto-scale consumers based on Kafka lag

