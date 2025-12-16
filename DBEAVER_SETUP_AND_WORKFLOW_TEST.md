# DBeaver Setup & Complete Workflow Test Guide

## Part 1: Connect DBeaver to TimescaleDB

### Connection Details:
```
Host: ab125756df3c140d2bff122afd8c5265-bdf6e1f536d2eacb.elb.us-east-1.amazonaws.com
Port: 5432
Database: gamemetrics
Username: dbadmin
Password: [a5&7l*t-jwof44o1FDRzaK8Px5FWKF(
```

### Steps to Connect in DBeaver:

1. **Open DBeaver** → Click **Database** → **New Database Connection**

2. **Select PostgreSQL** (not TimescaleDB, use PostgreSQL driver)
   - Click **Next**

3. **Fill in Connection Settings:**
   - **Server Host:** `ab125756df3c140d2bff122afd8c5265-bdf6e1f536d2eacb.elb.us-east-1.amazonaws.com`
   - **Port:** `5432`
   - **Database:** `gamemetrics`
   - **Username:** `dbadmin`
   - **Password:** `[a5&7l*t-jwof44o1FDRzaK8Px5FWKF(`
   - Check: ✅ Save password locally

4. **Click "Test Connection"** 
   - Should show: `Connected`

5. **Click "Finish"**

6. **Verify:** In DBeaver, expand the connection and navigate:
   - **Schemas** → **public** → **Tables** → You should see **events** table

---

## Part 2: Complete Workflow Test (Producers → Kafka → Consumer → Database)

### Overview:
1. **Producer** sends events → Kafka topic `player.events.raw`
2. **Kafka** stores events (with lz4 compression)
3. **Consumer** (event-consumer-logger) reads from Kafka
4. **Database** receives events in `events` table

### Step 1: Verify Kafka is Ready

```bash
# Check Kafka broker status
kubectl get pods -n kafka -l strimzi.io/cluster=gamemetrics-kafka

# Check Kafka topics
kubectl exec -it gamemetrics-kafka-broker-0 -n kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

**Expected Output:** Should see `player.events.raw` topic

---

### Step 2: Check Database Schema

**In DBeaver:**
1. Right-click on **events** table → **View Table**
2. Should see columns:
   - `event_id` (UUID, Primary Key)
   - `event_type` (VARCHAR)
   - `player_id` (VARCHAR)
   - `game_id` (VARCHAR)
   - `event_timestamp` (TIMESTAMP)
   - `ingested_at` (TIMESTAMP)
   - `data` (JSONB)
   - `created_at` (TIMESTAMP)

---

### Step 3: Run Smoke Test (Producer → Consumer → Database)

```bash
cd /mnt/c/Users/Shefqet/Desktop/RealtimeGaming

# Run the smoke test (produces 10 events, waits for consumer)
CONFIRM_DELETE=true bash scripts/test-kafka-to-db.sh
```

**What This Does:**
1. **Produces** 10 test events to Kafka with unique IDs
2. **Consumer** processes these events in real-time
3. **Database** stores them
4. **Test** verifies all 10 events exist in DB

**Expected Output:**
```
✓ Kafka test events produced
✓ Waiting for consumer to process...
✅ Test PASSED: 10 events found in database
```

---

### Step 4: Query Events in DBeaver

**In DBeaver**, open SQL Editor and run:

```sql
-- View all events
SELECT event_id, event_type, player_id, created_at, data 
FROM events 
ORDER BY created_at DESC 
LIMIT 20;

-- Count events
SELECT COUNT(*) as total_events FROM events;

-- View specific event details
SELECT event_id, event_type, player_id, game_id, data 
FROM events 
WHERE created_at > NOW() - INTERVAL '1 hour' 
ORDER BY created_at DESC;

-- Check event types distribution
SELECT event_type, COUNT(*) 
FROM events 
GROUP BY event_type 
ORDER BY COUNT(*) DESC;
```

---

### Step 5: Real-Time Monitoring

#### Option A: Watch Events in Real-Time (DBeaver)

1. Run the test script again
2. In DBeaver, **F5** to refresh the SQL results
3. Watch the **COUNT(*)** increase in real-time

#### Option B: Monitor via Kafka UI

```bash
# Port-forward Kafka UI
kubectl port-forward -n kafka svc/kafka-ui 8080:8080
```

Open browser: http://localhost:8080
- See `player.events.raw` topic
- Watch messages flowing in real-time
- View Consumer Groups: `event-logger-group`

#### Option C: Monitor Consumer Logs

```bash
# Watch event-consumer-logger processing events
kubectl logs -n gamemetrics deployment/event-consumer-logger -f
```

---

### Step 6: Test Event Flow with Custom Data

**Option 1: Send events via Kubernetes Pod**

```bash
# Get inside Kafka broker pod
kubectl exec -it gamemetrics-kafka-broker-0 -n kafka -- bash

# Create a test producer
cat > /tmp/test-event.json << 'EOF'
{
  "event_id": "custom-event-001",
  "event_type": "player_login",
  "player_id": "player_123",
  "game_id": "game_456",
  "event_timestamp": "2025-12-16T10:30:00Z",
  "data": {
    "device": "mobile",
    "location": "US",
    "session_id": "sess_789"
  }
}
EOF

# Send to Kafka
echo '{"event_id":"custom-event-001","event_type":"player_login","player_id":"player_123","game_id":"game_456","event_timestamp":"2025-12-16T10:30:00Z","data":{"device":"mobile"}}' | \
  bin/kafka-console-producer.sh \
    --broker-list localhost:9092 \
    --topic player.events.raw \
    --property "parse.key=false"

exit
```

**Option 2: Use kcat (simpler)**

```bash
# If kcat is installed locally
kcat -b <kafka-bootstrap-server>:9092 \
  -t player.events.raw \
  -P << 'EOF'
{"event_id":"test-001","event_type":"player_logout","player_id":"player_999"}
EOF
```

---

### Step 7: Monitor Complete Pipeline

#### Terminal 1: Watch Database Changes
```bash
# Keep refreshing database query
watch -n 2 'kubectl exec -it timescaledb-589bf95b9d-p2vsx -n gamemetrics -- \
  psql -U dbadmin -d gamemetrics -c "SELECT COUNT(*) FROM events;"'
```

#### Terminal 2: Watch Consumer Processing
```bash
# Follow consumer logs
kubectl logs -n gamemetrics deployment/event-consumer-logger -f --timestamps
```

#### Terminal 3: Send Test Events
```bash
# Send 20 rapid events
for i in {1..20}; do
  echo "{\"event_id\":\"bulk-$i\",\"event_type\":\"test_event\",\"player_id\":\"player_$i\"}" | \
    kubectl exec -i gamemetrics-kafka-broker-0 -n kafka -- \
    bin/kafka-console-producer.sh --broker-list localhost:9092 --topic player.events.raw
done
```

---

## Part 3: Troubleshooting Workflow

### Issue: No events appearing in database

**Check Consumer Status:**
```bash
# Check if consumer is running
kubectl get pods -n gamemetrics -l app=event-consumer-logger

# Check consumer logs for errors
kubectl logs -n gamemetrics deployment/event-consumer-logger --tail=50
```

**Check Kafka Topic:**
```bash
# Verify topic exists and has messages
kubectl exec -it gamemetrics-kafka-broker-0 -n kafka -- \
  bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic player.events.raw \
    --from-beginning \
    --max-messages 5
```

**Check Database Connection:**
```bash
# Test DB connection from consumer pod
kubectl exec -it deployment/event-consumer-logger -n gamemetrics -- \
  python -c "import psycopg2; conn=psycopg2.connect('host=timescaledb user=dbadmin password=<pwd> dbname=gamemetrics'); print('✓ Connected')"
```

### Issue: Consumer crashes with "UnsupportedCodecError"

**Solution:** Ensure lz4 is installed
```bash
# Check consumer image includes lz4
kubectl exec -it deployment/event-consumer-logger -n gamemetrics -- \
  python -c "import lz4; print('✓ lz4 installed')"
```

### Issue: DBeaver connection timeout

**Solution:** Check security groups allow 5432
```bash
# Verify load balancer is accessible
kubectl get service timescaledb-public -n gamemetrics -o wide
```

---

## Quick Commands Reference

```bash
# Get all endpoints
kubectl get all -n gamemetrics

# Scale consumer replicas
kubectl scale deployment event-consumer-logger -n gamemetrics --replicas=3

# Restart consumer
kubectl rollout restart deployment event-consumer-logger -n gamemetrics

# View database size
kubectl exec timescaledb-589bf95b9d-p2vsx -n gamemetrics -- \
  psql -U dbadmin -d gamemetrics -c "SELECT pg_size_pretty(pg_database_size('gamemetrics'));"

# Backup database
kubectl exec timescaledb-589bf95b9d-p2vsx -n gamemetrics -- \
  pg_dump -U dbadmin gamemetrics > gamemetrics_backup.sql
```

---

## Complete End-to-End Test Script

Save this as `test-complete-workflow.sh`:

```bash
#!/bin/bash

echo "═══════════════════════════════════════════"
echo "Complete Workflow Test: Producer → Kafka → Consumer → DB"
echo "═══════════════════════════════════════════"
echo ""

# Step 1: Verify infrastructure
echo "✓ Step 1: Verifying infrastructure..."
kubectl get pods -n gamemetrics,kafka --no-headers | grep -E "Running|Ready" > /dev/null && echo "  ✓ All pods running" || echo "  ✗ Some pods not ready"

# Step 2: Clear old test data (optional)
echo ""
echo "✓ Step 2: Checking database..."
COUNT_BEFORE=$(kubectl exec -it timescaledb-589bf95b9d-p2vsx -n gamemetrics -- psql -U dbadmin -d gamemetrics -tc "SELECT COUNT(*) FROM events;" 2>/dev/null | xargs)
echo "  Events before test: $COUNT_BEFORE"

# Step 3: Produce events
echo ""
echo "✓ Step 3: Producing 10 test events to Kafka..."
for i in {1..10}; do
  EVENT_ID=$(uuidgen 2>/dev/null || echo "test-$i-$(date +%s%N)")
  EVENT='{"event_id":"'$EVENT_ID'","event_type":"test_event_'$i'","player_id":"player_test_'$i'","game_id":"game_'$i'","event_timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","data":{"test":true}}'
  echo "$EVENT" | kubectl exec -i gamemetrics-kafka-broker-0 -n kafka -- \
    bin/kafka-console-producer.sh --broker-list localhost:9092 --topic player.events.raw 2>/dev/null
  echo "  Produced event #$i"
done

# Step 4: Wait for consumer
echo ""
echo "✓ Step 4: Waiting for consumer to process events (30 seconds)..."
sleep 30

# Step 5: Verify in database
echo ""
echo "✓ Step 5: Verifying events in database..."
COUNT_AFTER=$(kubectl exec -it timescaledb-589bf95b9d-p2vsx -n gamemetrics -- psql -U dbadmin -d gamemetrics -tc "SELECT COUNT(*) FROM events;" 2>/dev/null | xargs)
EVENTS_ADDED=$((COUNT_AFTER - COUNT_BEFORE))
echo "  Events after test: $COUNT_AFTER"
echo "  Events added: $EVENTS_ADDED"

if [ "$EVENTS_ADDED" -ge 10 ]; then
  echo ""
  echo "✅ TEST PASSED: Workflow working correctly!"
  echo "   Producer → Kafka → Consumer → Database ✓"
else
  echo ""
  echo "⚠️  TEST INCOMPLETE: Only $EVENTS_ADDED of 10 events received"
  echo "   Check consumer logs: kubectl logs -n gamemetrics deployment/event-consumer-logger -f"
fi

# Step 6: Show recent events
echo ""
echo "✓ Step 6: Recent events in database:"
kubectl exec -it timescaledb-589bf95b9d-p2vsx -n gamemetrics -- \
  psql -U dbadmin -d gamemetrics -c "SELECT event_id, event_type, player_id, created_at FROM events ORDER BY created_at DESC LIMIT 5;" 2>/dev/null

echo ""
echo "═══════════════════════════════════════════"
echo "Test Complete!"
echo "═══════════════════════════════════════════"
```

Run it:
```bash
bash test-complete-workflow.sh
```
