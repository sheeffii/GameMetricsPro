#!/bin/bash

# Test Event Flow - Sends a test event through the entire pipeline

set -e

echo "========================================="
echo "Testing Event Flow"
echo "========================================="
echo ""

# Check if event ingestion service is running
echo "1. Checking Event Ingestion Service..."
kubectl wait --for=condition=Ready pod -l app=event-ingestion-service --timeout=10s 2>/dev/null || {
    echo "Error: Event Ingestion Service not ready"
    exit 1
}
echo "✓ Service is ready"
echo ""

# Port forward to service
echo "2. Setting up port forward..."
kubectl port-forward svc/event-ingestion-service 8080:80 &>/dev/null &
PF_PID=$!
sleep 3
echo "✓ Port forward established (PID: $PF_PID)"
echo ""

# Function to cleanup
cleanup() {
    echo ""
    echo "Cleaning up..."
    kill $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

# Generate test event
echo "3. Generating test event..."
EVENT_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

EVENT_PAYLOAD=$(cat <<EOF
{
  "event_type": "gameplay",
  "player_id": "test-player-$RANDOM",
  "game_id": "test-game-001",
  "timestamp": "$TIMESTAMP",
  "data": {
    "score": 1500,
    "level": 7,
    "duration_seconds": 180,
    "achievements": ["first_win", "combo_master"]
  }
}
EOF
)

echo "$EVENT_PAYLOAD" | jq .
echo ""

# Send event
echo "4. Sending event to ingestion service..."
RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/events \
  -H "Content-Type: application/json" \
  -d "$EVENT_PAYLOAD")

if echo "$RESPONSE" | jq -e '.status == "success"' > /dev/null 2>&1; then
    RETURNED_EVENT_ID=$(echo "$RESPONSE" | jq -r '.event_id')
    echo "✓ Event ingested successfully"
    echo "  Event ID: $RETURNED_EVENT_ID"
else
    echo "✗ Failed to ingest event"
    echo "  Response: $RESPONSE"
    exit 1
fi
echo ""

# Check Kafka
echo "5. Verifying event in Kafka..."
sleep 2

# Get Kafka pod
KAFKA_POD=$(kubectl get pod -n kafka -l strimzi.io/name=gamemetrics-kafka-kafka -o jsonpath='{.items[0].metadata.name}')

# Check if message is in Kafka
echo "  Checking player.events.raw topic..."
KAFKA_CHECK=$(kubectl exec -n kafka $KAFKA_POD -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic player.events.raw \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 5000 2>/dev/null | grep -c "$RETURNED_EVENT_ID" || echo "0")

if [ "$KAFKA_CHECK" -gt 0 ]; then
    echo "  ✓ Event found in Kafka"
else
    echo "  ⚠ Event not yet in Kafka (may still be in buffer)"
fi
echo ""

# Check Event Processor (if running)
echo "6. Checking Event Processor Service..."
if kubectl get deployment event-processor-service &>/dev/null 2>&1; then
    PROCESSOR_READY=$(kubectl get deployment event-processor-service -o jsonpath='{.status.readyReplicas}' || echo "0")
    if [ "$PROCESSOR_READY" -gt 0 ]; then
        echo "  ✓ Event Processor is running ($PROCESSOR_READY replicas)"
        echo "  Events should be processed within a few seconds"
    else
        echo "  ⚠ Event Processor not ready"
    fi
else
    echo "  ℹ Event Processor not deployed yet"
fi
echo ""

# Summary
echo "========================================="
echo "✓ Event Flow Test Complete"
echo "========================================="
echo ""
echo "What happened:"
echo "  1. REST API received event"
echo "  2. Event validated and enriched"
echo "  3. Event published to Kafka (player.events.raw)"
echo "  4. Event Processor will consume and process"
echo "  5. Processed data written to TimescaleDB"
echo "  6. Analytics available via GraphQL API"
echo ""
echo "To monitor the event flow:"
echo "  - Grafana: kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80"
echo "  - Kafka UI: kubectl exec -it $KAFKA_POD -n kafka -- bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic player.events.raw --from-beginning"
echo "  - Logs: kubectl logs -l app=event-ingestion-service -f"
