#!/bin/bash
set -euo pipefail

# Config (override via env)
NAMESPACE=${NAMESPACE:-gamemetrics}
APP_NAMESPACE=${APP_NAMESPACE:-gamemetrics}
KAFKA_NAMESPACE=${KAFKA_NAMESPACE:-kafka}
TOPIC=${TOPIC:-player.events.raw}
KAFKA_SECRET=${KAFKA_SECRET:-kafka-credentials}
DB_USER=${DB_USER:-postgres}
DB_NAME=${DB_NAME:-gamemetrics}
DB_PUBLIC_SVC=${DB_PUBLIC_SVC:-timescaledb-public}
DB_INTERNAL_HOST=${DB_INTERNAL_HOST:-timescaledb.gamemetrics.svc.cluster.local}
SLEEP_AFTER_PRODUCE=${SLEEP_AFTER_PRODUCE:-12}

# Resolve bootstrap servers and DB password
BOOTSTRAP=$(kubectl get secret "$KAFKA_SECRET" -n "$APP_NAMESPACE" -o jsonpath='{.data.bootstrap-servers}' | base64 -d)
DB_PASSWORD=$(kubectl get secret db-credentials -n "$APP_NAMESPACE" -o go-template='{{.data.password | base64decode}}')

# Use in-cluster TimescaleDB service directly
DB_HOST="timescaledb"
DB_PORT="5432"

# Generate a unique smoke test ID
if command -v uuidgen >/dev/null 2>&1; then
  SMOKE_ID=$(uuidgen)
else
  SMOKE_ID="smoke-$(date +%s)-$RANDOM"
fi

MODE=${MODE:-kafka} # kafka | api

# Message payloads for each mode
MSG_KAFKA="{\"smokeTestId\":\"$SMOKE_ID\",\"event\":\"smoke\",\"ts\":\"$(date -u +%FT%TZ)\"}"
MSG_API_TEMPLATE=$(cat <<EOF
{
  "event_type": "smoke_test",
  "player_id": "smoke_$SMOKE_ID",
  "game_id": "test_game",
  "timestamp": "$(date -u +%FT%TZ)",
  "data": { "smokeTestId": "$SMOKE_ID", "note": "api-path" }
}
EOF
)

echo "Mode: $MODE"
echo "Topic: $TOPIC"
echo "Kafka bootstrap: $BOOTSTRAP"
echo "DB host: $DB_HOST"
echo "SmokeTestId: $SMOKE_ID"

if [ "$MODE" = "api" ]; then
  # Send via event-ingestion HTTP API using an ephemeral curl pod
  SERVICE_HOST=$(kubectl get svc event-ingestion -n "$APP_NAMESPACE" -o jsonpath='{.spec.clusterIP}')
  echo "Sending via API to http://$SERVICE_HOST:8080/api/v1/events"
  kubectl run curl-api-$$ -n "$APP_NAMESPACE" --rm -i --restart=Never --image=radial/busyboxplus:curl --command -- \
    sh -lc "echo '$MSG_API_TEMPLATE' | tee /tmp/payload.json >/dev/null; curl -s -X POST -H 'Content-Type: application/json' --data @/tmp/payload.json http://$SERVICE_HOST:8080/api/v1/events" || {
      echo "Failed to POST event to event-ingestion API"; exit 1;
    }
  echo "Posted event via API. Waiting $SLEEP_AFTER_PRODUCE seconds..."
  sleep "$SLEEP_AFTER_PRODUCE"
else
  # Produce message using a short-lived kcat pod
  kubectl run kcat-producer-$$ \
    -n "$APP_NAMESPACE" \
    --rm -i --restart=Never \
    --image=edenhill/kcat:1.7.1 \
    --command -- sh -c "echo '$MSG_KAFKA' | kcat -P -b '$BOOTSTRAP' -t '$TOPIC'" || {
      echo "Failed to produce message to Kafka"; exit 1;
  }
  echo "Produced message. Waiting $SLEEP_AFTER_PRODUCE seconds for processing..."
  sleep "$SLEEP_AFTER_PRODUCE"
fi

# Check event-ingestion logs for the smoke ID
if kubectl logs -n "$APP_NAMESPACE" -l app=event-ingestion --tail=500 --since=2m 2>/dev/null | grep -q "$SMOKE_ID"; then
  echo "Event-ingestion logs contain the SmokeTestId → Kafka→Service path OK"
  LOG_OK=1
else
  echo "WARNING: SmokeTestId not found in event-ingestion logs (may still be processing or different log format)"
  LOG_OK=0
fi

# Check DB for the smoke ID directly in the events table (use exec for cleaner output)
DB_OK=0
TIMESCALE_POD=$(kubectl get pod -n "$APP_NAMESPACE" -l app=timescaledb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$TIMESCALE_POD" ]; then
  DB_COUNT=$(kubectl exec -i "$TIMESCALE_POD" -n "$APP_NAMESPACE" -- \
    psql -U postgres -d gamemetrics -tA -c "SELECT COUNT(*) FROM events WHERE event_id = '$SMOKE_ID' OR data::text ILIKE '%$SMOKE_ID%';" 2>/dev/null)
  DB_COUNT=${DB_COUNT:-0}
  
  if [ "$DB_COUNT" -gt 0 ] 2>/dev/null; then
    echo "✓ Found SmokeTestId in database (count: $DB_COUNT) → Kafka→Consumer→DB path OK"
    DB_OK=1
  else
    echo "WARNING: Did not find SmokeTestId in DB (may still be processing or async)"
  fi
else
  echo "WARNING: Could not find TimescaleDB pod for verification"
fi

if [ "$LOG_OK" -eq 1 ] && [ "$DB_OK" -eq 1 ]; then
  echo "✅ Kafka→Service→DB smoke test: SUCCESS"
  exit 0
elif [ "$DB_OK" -eq 1 ]; then
  echo "✅ Kafka→Consumer→DB path OK (service logs not checked)"
  exit 0
else
  echo "❌ Kafka→Service→DB smoke test: FAIL"
  exit 1
fi
