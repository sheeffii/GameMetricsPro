#!/bin/bash
set -euo pipefail

# Usage:
#   MODE=kafka bash scripts/test-kafka-to-db.sh [name]
#   MODE=api   bash scripts/test-kafka-to-db.sh [name]
#
# Modes:
#   kafka = produce directly to Kafka topic from the broker pod (simple + reliable)
#   api   = send event to the Go event-ingestion API (real app path)

NAME=${1:-smoke}

APP_NAMESPACE=${APP_NAMESPACE:-gamemetrics}
KAFKA_NAMESPACE=${KAFKA_NAMESPACE:-kafka}
TOPIC=${TOPIC:-player.events.raw}
DB_USER=${DB_USER:-postgres}
DB_NAME=${DB_NAME:-gamemetrics}
SLEEP_AFTER_PRODUCE=${SLEEP_AFTER_PRODUCE:-12}
MODE=${MODE:-kafka}

make_uuid() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid; print(uuid.uuid4())'
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    echo "00000000-0000-4000-8000-$(date +%s%N | tail -c 13)" | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/'
  fi
}

EVENT_ID=$(make_uuid)
EVENT_TYPE="smoke_${NAME}"
TS_UTC=$(date -u +%FT%TZ)
PLAYER_ID="smoke_${NAME}"
GAME_ID="test_game"

DB_POD=$(kubectl get pods -n "$APP_NAMESPACE" -l app=timescaledb -o jsonpath='{.items[0].metadata.name}')
KAFKA_BROKER_POD=$(kubectl get pods -n "$KAFKA_NAMESPACE" -l strimzi.io/cluster=gamemetrics-kafka,strimzi.io/broker-role=true -o jsonpath='{.items[0].metadata.name}')

echo "Mode:          $MODE"
echo "Name:          $NAME"
echo "Topic:         $TOPIC"
echo "EventId:       $EVENT_ID"
echo "EventType:     $EVENT_TYPE"
echo "App namespace: $APP_NAMESPACE"
echo "Kafka ns:      $KAFKA_NAMESPACE"
echo "DB pod:        $DB_POD"
echo "Kafka pod:     $KAFKA_BROKER_POD"

if [ -z "$DB_POD" ]; then
  echo "ERROR: Could not find TimescaleDB pod in namespace '$APP_NAMESPACE'"
  exit 1
fi

if [ "$MODE" = "kafka" ] && [ -z "$KAFKA_BROKER_POD" ]; then
  echo "ERROR: Could not find Kafka broker pod in namespace '$KAFKA_NAMESPACE'"
  exit 1
fi

echo ""
echo "DB count before:"
kubectl exec "$DB_POD" -n "$APP_NAMESPACE" -- psql -U "$DB_USER" -d "$DB_NAME" -tA -c "SELECT COUNT(*) FROM events;" | sed 's/^/  /'

EVENT_JSON=$(cat <<EOF
{"event_id":"$EVENT_ID","event_type":"$EVENT_TYPE","player_id":"$PLAYER_ID","game_id":"$GAME_ID","event_timestamp":"$TS_UTC","data":{"smokeTestName":"$NAME","smokeTestId":"$EVENT_ID","path":"$MODE"}}
EOF
)

echo ""
echo "Producing event..."
if [ "$MODE" = "api" ]; then
  SERVICE_HOST=$(kubectl get svc event-ingestion -n "$APP_NAMESPACE" -o jsonpath='{.spec.clusterIP}')
  if [ -z "$SERVICE_HOST" ]; then
    echo "ERROR: Could not resolve event-ingestion service in namespace '$APP_NAMESPACE'"
    exit 1
  fi

  echo "POST http://$SERVICE_HOST:8080/api/v1/events"
  kubectl run curl-api-$$ -n "$APP_NAMESPACE" --rm -i --restart=Never --image=radial/busyboxplus:curl --command -- \
    sh -lc "echo '$EVENT_JSON' > /tmp/payload.json; curl -sS -X POST -H 'Content-Type: application/json' --data @/tmp/payload.json http://$SERVICE_HOST:8080/api/v1/events" >/dev/null
else
  kubectl exec "$KAFKA_BROKER_POD" -n "$KAFKA_NAMESPACE" -- bash -lc "echo '$EVENT_JSON' | bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic '$TOPIC'" >/dev/null
fi

echo "Produced. Waiting $SLEEP_AFTER_PRODUCE seconds for consumer → DB..."
sleep "$SLEEP_AFTER_PRODUCE"

echo ""
echo "DB verification (exact event_id):"
kubectl exec "$DB_POD" -n "$APP_NAMESPACE" -- psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT event_id, event_type, player_id, created_at FROM events WHERE event_id = '$EVENT_ID'::uuid;"

echo ""
echo "Recent matching events (event_type = $EVENT_TYPE):"
kubectl exec "$DB_POD" -n "$APP_NAMESPACE" -- psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT event_id, event_type, player_id, created_at FROM events WHERE event_type = '$EVENT_TYPE' ORDER BY created_at DESC LIMIT 5;"

FOUND=$(kubectl exec "$DB_POD" -n "$APP_NAMESPACE" -- psql -U "$DB_USER" -d "$DB_NAME" -tA -c "SELECT COUNT(*) FROM events WHERE event_id = '$EVENT_ID'::uuid;" | tr -d '[:space:]')
if [ "${FOUND:-0}" = "1" ]; then
  echo ""
  echo "✅ SUCCESS: Event inserted into DB (event_id=$EVENT_ID)"
  exit 0
fi

echo ""
echo "❌ FAIL: Did not find event_id=$EVENT_ID in DB"
echo "Tip: check consumer logs: kubectl logs -n gamemetrics -l app=event-consumer-logger --tail=200"
exit 1
