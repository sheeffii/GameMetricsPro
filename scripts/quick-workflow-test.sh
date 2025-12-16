#!/bin/bash

echo "Testing Producer → Kafka → Consumer → Database workflow"
echo ""

# Get DB pod
DB_POD=$(kubectl get pods -n gamemetrics -l app=timescaledb -o jsonpath='{.items[0].metadata.name}')
KAFKA_BROKER=$(kubectl get pods -n kafka -l strimzi.io/cluster=gamemetrics-kafka -o jsonpath='{.items[0].metadata.name}')

echo "✓ Database pod: $DB_POD"
echo "✓ Kafka broker: $KAFKA_BROKER"
echo ""

# Get initial count
COUNT_BEFORE=$(kubectl exec $DB_POD -n gamemetrics -- psql -U postgres -d gamemetrics -tc "SELECT COUNT(*) FROM events;" 2>/dev/null | xargs)
echo "Events before: $COUNT_BEFORE"
echo ""

# Send 5 test events
echo "Producing 5 test events to Kafka..."
for i in {1..5}; do
  TS=$(date +%s%N)
  EVENT="{\"event_id\":\"test-$i-$TS\",\"event_type\":\"test_event\",\"player_id\":\"player_$i\",\"game_id\":\"game_$i\",\"event_timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"data\":{\"test\":true}}"
  echo "$EVENT" | kubectl exec -i $KAFKA_BROKER -n kafka -- bin/kafka-console-producer.sh --broker-list localhost:9092 --topic player.events.raw 2>/dev/null
  echo "  Event $i sent"
done

echo ""
echo "Waiting 20 seconds for consumer to process..."
sleep 20

# Get final count
COUNT_AFTER=$(kubectl exec $DB_POD -n gamemetrics -- psql -U postgres -d gamemetrics -tc "SELECT COUNT(*) FROM events;" 2>/dev/null | xargs)
ADDED=$((COUNT_AFTER - COUNT_BEFORE))

echo "Events after: $COUNT_AFTER"
echo "Events added: $ADDED"
echo ""

if [ $ADDED -ge 5 ]; then
  echo "✅ SUCCESS: All events stored in database!"
  echo ""
  echo "Sample events:"
  kubectl exec $DB_POD -n gamemetrics -- psql -U postgres -d gamemetrics -c "SELECT event_id, event_type, player_id, created_at FROM events ORDER BY created_at DESC LIMIT 3;"
else
  echo "⚠️ Only $ADDED events received. Consumer may still be processing."
  echo ""
  echo "Check consumer logs: kubectl logs -n gamemetrics deployment/event-consumer-logger -f"
fi
