# Quick Reference: Event Processing System

## File Structure

```
services/
├── event-ingestion-service/           ← Go Producer (Already Built ✓)
│   ├── cmd/main.go
│   └── ...
├── event-consumer-logger/              ← Python Consumer 1 (NEW)
│   ├── consumer.py
│   ├── requirements.txt
│   └── Dockerfile
├── event-consumer-stats/               ← Python Consumer 2 (NEW)
│   ├── consumer.py
│   ├── requirements.txt
│   └── Dockerfile
└── event-consumer-leaderboard/         ← Python Consumer 3 (NEW)
    ├── consumer.py
    ├── requirements.txt
    └── Dockerfile

k8s/services/
├── event-ingestion/                    ← Producer Deployment (Already Running ✓)
│   └── deployment.yaml
└── event-consumers-deployment.yaml      ← Consumer Deployments (NEW)

scripts/
├── load_test_events.sh                 ← Load Testing Tool (NEW)
└── migrate_db.py                       ← Database Setup (NEW)

Guides/
├── EVENT_PROCESSING_GUIDE.md           ← Architecture & Code Examples (NEW)
├── TESTING_DEPLOYMENT_GUIDE.md         ← Step-by-Step Testing (NEW)
└── QUICK_REFERENCE.md                  ← This File
```

## Environment Variables

### Producer (Already Running)
```
KAFKA_BOOTSTRAP_SERVERS=gamemetrics-kafka-bootstrap.kafka:9092
KAFKA_USERNAME=gamemetrics
KAFKA_PASSWORD=<from-secrets>
KAFKA_TOPIC_PLAYER_EVENTS=player.events.raw
PORT=8080
```

### Consumers (Deploy)
```
KAFKA_BOOTSTRAP_SERVERS=gamemetrics-kafka-bootstrap.kafka:9092
KAFKA_USERNAME=gamemetrics
KAFKA_PASSWORD=<from-secrets>
DB_HOST=gamemetrics-dev.cwxu6k6ikgjr.us-east-1.rds.amazonaws.com
DB_PORT=5432
DB_NAME=gamemetrics
DB_USER=postgres
DB_PASSWORD=<from-secrets>
REDIS_HOST=<redis-endpoint>
REDIS_PORT=6379
```

## Quick Start (TL;DR)

```bash
# 1. Set up database
export DB_HOST="..." DB_PORT="5432" DB_NAME="gamemetrics" DB_USER="postgres" DB_PASSWORD="..."
python scripts/migrate_db.py

# 2. Build consumer images
for dir in event-consumer-*; do
  cd services/$dir
  docker build -t $dir:latest .
  docker tag $dir:latest 647523695124.dkr.ecr.us-east-1.amazonaws.com/$dir:latest
  docker push 647523695124.dkr.ecr.us-east-1.amazonaws.com/$dir:latest
  cd ../..
done

# 3. Deploy consumers
kubectl apply -f k8s/services/event-consumers-deployment.yaml

# 4. Test producer
curl -X POST http://localhost:8080/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "player_level_up",
    "player_id": "test-player",
    "game_id": "test-game",
    "timestamp": "2024-01-15T10:30:00Z",
    "data": {"level": 5}
  }'

# 5. Verify in database
psql -h $DB_HOST -U $DB_USER -d $DB_NAME \
  -c "SELECT COUNT(*) FROM events;"

# 6. Run load test
./scripts/load_test_events.sh 1000 100
```

## Kafka Topics

| Topic | Purpose | Consumers |
|-------|---------|-----------|
| `player.events.raw` | Raw incoming events | All 3 consumers |
| `player.events.processed` | Validated events | (future) |
| `system.dlq` | Dead letter queue | Manual review |

## Database Tables

| Table | Columns | Consumer |
|-------|---------|----------|
| `events` | event_id, event_type, player_id, game_id, event_timestamp, ingested_at, data | Logger |
| `player_statistics` | player_id, total_events, event_breakdown, updated_at | Stats Aggregator |
| `leaderboards` | game_id, player_id, rank, score, period | Leaderboard Manager |
| `dlq_events` | original_event, error_message, consumer_service | DLQ Handler |

## Event Types Supported

```
Generic: player_level_up, player_score, quest_completed, achievement_unlocked, boss_defeated
Custom: Any event_type with matching JSON data structure
```

## Monitoring URLs

```
Kafka UI:           http://localhost:8081     (after port-forward)
Producer Metrics:   http://localhost:8080/metrics
Prometheus:         http://localhost:9090     (after port-forward)
Grafana:            http://localhost:3000     (if deployed)
```

## Key Commands

```bash
# View producer health
kubectl get svc -n gamemetrics event-ingestion
kubectl logs -n gamemetrics deployment/event-ingestion

# View consumers
kubectl get pods -n gamemetrics -l component=consumer
kubectl logs -n gamemetrics deployment/event-consumer-logger -f

# Check Kafka connectivity
kubectl exec -n kafka gamemetrics-kafka-0 -- \
  kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# Check consumer groups
kubectl exec -n kafka gamemetrics-kafka-0 -- \
  kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list

# View database
psql -h $DB_HOST -U $DB_USER -d $DB_NAME

# View Redis
redis-cli -h <redis-endpoint> -p 6379
```

## Common Issues & Fixes

| Problem | Fix |
|---------|-----|
| Consumer pod CrashLoopBackOff | Check logs: `kubectl logs <pod>` - usually Kafka/DB connection |
| Kafka authentication fails | Verify `kafka-credentials` secret exists in namespace |
| Database migration fails | Ensure DB user has CREATE TABLE permissions |
| Events not appearing in database | Check consumer lag, verify DB table exists |
| Redis not updating | Check REDIS_HOST/PORT env vars, verify Redis pod running |
| High memory usage | Increase container limits, reduce BUFFER_SIZE |

## Next Phase Tasks

1. **Deploy Consumers** - Use Phase 3-7 from TESTING_DEPLOYMENT_GUIDE.md
2. **Verify Pipeline** - Run load test with 1000+ events
3. **Set Up Monitoring** - Create Grafana dashboards for:
   - Events/sec ingestion rate
   - Consumer lag per group
   - Database write latency
   - Error rates per consumer
4. **Scale Consumers** - Increase replicas if lag grows
5. **Custom Event Types** - Add application-specific events to EVENT_TYPES

## File References

- **Architecture Details**: `EVENT_PROCESSING_GUIDE.md`
- **Step-by-Step Deployment**: `TESTING_DEPLOYMENT_GUIDE.md`
- **Producer Code**: `services/event-ingestion-service/cmd/main.go`
- **Consumer Templates**: `services/event-consumer-{logger,stats,leaderboard}/consumer.py`
- **K8s Manifests**: `k8s/services/event-consumers-deployment.yaml`

---

**Status**: ✅ All code examples created | 🔧 Ready to deploy | 📊 Production-ready patterns

