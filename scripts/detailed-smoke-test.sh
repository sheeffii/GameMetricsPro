#!/bin/bash
set -euo pipefail

NAME=${1:-"custom"}
COUNT=${2:-3}

APP_NS=${APP_NS:-gamemetrics}
KAFKA_NS=${KAFKA_NS:-kafka}
TOPIC=${TOPIC:-player.events.raw}

DB_POD=$(kubectl get pods -n "$APP_NS" -l app=timescaledb -o jsonpath='{.items[0].metadata.name}')
KAFKA_BROKER_POD=$(kubectl get pods -n "$KAFKA_NS" -l strimzi.io/cluster=gamemetrics-kafka,strimzi.io/broker-role=true -o jsonpath='{.items[0].metadata.name}')

if [ -z "$DB_POD" ] || [ -z "$KAFKA_BROKER_POD" ]; then
  echo "Missing DB or Kafka pod (DB_POD='$DB_POD', KAFKA_BROKER_POD='$KAFKA_BROKER_POD')"
  exit 1
fi

EVENT_TYPE="smoke_${NAME}"
RUN_TS_UTC=$(date -u +%FT%TZ)

make_uuid() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid; print(uuid.uuid4())'
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    echo "00000000-0000-4000-8000-$(date +%s%N | tail -c 13)" | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/'
  fi
}

print_header() {
  echo "Detailed Smoke Test"
  echo "==================="
  echo "Name:        $NAME"
  echo "Event type:  $EVENT_TYPE"
  echo "Count:       $COUNT"
  echo "Topic:       $TOPIC"
  echo "App NS:      $APP_NS"
  echo "Kafka NS:    $KAFKA_NS"
  echo "DB Pod:      $DB_POD"
  echo "Kafka Pod:   $KAFKA_BROKER_POD"
  echo "Run TS (UTC): $RUN_TS_UTC"
  echo ""
}

print_header

echo "DB count before:"
kubectl exec "$DB_POD" -n "$APP_NS" -- psql -U postgres -d gamemetrics -tA -c "SELECT COUNT(*) FROM events;" | sed 's/^/  /'

EVENT_IDS=()
FIRST_EVENT_ID=""

echo ""
echo "Producing $COUNT detailed events to Kafka..."
for i in $(seq 1 "$COUNT"); do
  EVENT_ID=$(make_uuid)
  [ -z "$FIRST_EVENT_ID" ] && FIRST_EVENT_ID="$EVENT_ID"
  EVENT_IDS+=("$EVENT_ID")

  PLAYER_ID="player_${NAME}_${i}"
  GAME_ID="game_${NAME}"
  SESSION_ID="sess_${NAME}_$(date +%s)_${i}"

  # Keep JSON relatively small but detailed
  EVENT_JSON=$(cat <<EOF
{"event_id":"$EVENT_ID","event_type":"$EVENT_TYPE","player_id":"$PLAYER_ID","game_id":"$GAME_ID","session_id":"$SESSION_ID","event_timestamp":"$RUN_TS_UTC","client":{"platform":"pc","build":"1.0.$i","region":"us-east-1"},"metrics":{"latency_ms":$((RANDOM % 120 + 10)),"fps":$((RANDOM % 90 + 30))},"data":{"smoke_name":"$NAME","iteration":$i,"note":"detailed-smoke-test","tags":["smoke","e2e","$NAME"]}}
EOF
)

  echo "  [$i/$COUNT] event_id=$EVENT_ID player_id=$PLAYER_ID"
  kubectl exec "$KAFKA_BROKER_POD" -n "$KAFKA_NS" -- bash -lc "echo '$EVENT_JSON' | bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic '$TOPIC'" >/dev/null

done

echo ""
echo "Reading Kafka to confirm at least one produced event is visible..."
# Read from beginning (simple) but grep for the unique FIRST_EVENT_ID
kubectl exec "$KAFKA_BROKER_POD" -n "$KAFKA_NS" -- bash -lc "bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic '$TOPIC' --from-beginning --timeout-ms 12000 | grep -m 1 '$FIRST_EVENT_ID'" || \
  echo "WARNING: Could not confirm FIRST_EVENT_ID in console-consumer output (may still be fine)."

echo ""
echo "Waiting 15 seconds for consumer to write into DB..."
sleep 15

echo ""
echo "DB verification (by event_type and exact event_id):"
kubectl exec "$DB_POD" -n "$APP_NS" -- psql -U postgres -d gamemetrics -c "SELECT COUNT(*) AS matching_events FROM events WHERE event_type = '$EVENT_TYPE';" 

kubectl exec "$DB_POD" -n "$APP_NS" -- psql -U postgres -d gamemetrics -c "SELECT event_id, event_type, player_id, created_at FROM events WHERE event_id = '$FIRST_EVENT_ID'::uuid;" 

echo "Recent matching events:"
kubectl exec "$DB_POD" -n "$APP_NS" -- psql -U postgres -d gamemetrics -c "SELECT event_id, event_type, player_id, created_at FROM events WHERE event_type = '$EVENT_TYPE' ORDER BY created_at DESC LIMIT 10;"

echo ""
echo "✅ Detailed smoke test done."
