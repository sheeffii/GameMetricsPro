#!/bin/bash
set -e

# Configuration
NAMESPACE="gamemetrics"
SERVICE="event-ingestion"
PORT=8080
NUM_EVENTS=${1:-10}

echo "=========================================="
echo "Sending Test Events to Event Ingestion API"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Service: $SERVICE"
echo "  Number of events: $NUM_EVENTS"
echo ""

# Check if service exists
if ! kubectl get service $SERVICE -n $NAMESPACE &>/dev/null; then
  echo "ERROR: Service $SERVICE not found in namespace $NAMESPACE"
  exit 1
fi

# Get service endpoint
SERVICE_IP=$(kubectl get service $SERVICE -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
echo "Service IP: $SERVICE_IP"
echo ""

# Port forward in background
echo "Setting up port-forward..."
kubectl port-forward -n $NAMESPACE svc/$SERVICE $PORT:80 &
PF_PID=$!
echo "Port-forward PID: $PF_PID"
sleep 3
echo ""

# Function to cleanup on exit
cleanup() {
  echo ""
  echo "Cleaning up..."
  kill $PF_PID 2>/dev/null || true
  echo "Port-forward stopped"
}
trap cleanup EXIT

# Test health endpoints
echo "Testing health endpoints..."
echo -n "  Live: "
curl -s http://localhost:$PORT/health/live | jq -r '.status' || echo "FAILED"
echo -n "  Ready: "
curl -s http://localhost:$PORT/health/ready | jq -r '.status' || echo "FAILED"
echo ""

# Event types to rotate through
EVENT_TYPES=("login" "logout" "level_up" "purchase" "achievement" "game_start" "game_end")
PLAYER_IDS=("player-001" "player-002" "player-003" "player-004" "player-005")

echo "Sending $NUM_EVENTS test events..."
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for i in $(seq 1 $NUM_EVENTS); do
  # Rotate through event types and player IDs
  EVENT_TYPE=${EVENT_TYPES[$((i % ${#EVENT_TYPES[@]}))]}
  PLAYER_ID=${PLAYER_IDS[$((i % ${#PLAYER_IDS[@]}))]}
  
  # Generate timestamp
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Create event payload
  PAYLOAD=$(cat <<EOF
{
  "playerId": "$PLAYER_ID",
  "eventType": "$EVENT_TYPE",
  "timestamp": "$TIMESTAMP",
  "metadata": {
    "level": $((RANDOM % 100 + 1)),
    "score": $((RANDOM % 10000)),
    "session_id": "session-$((RANDOM % 1000))"
  }
}
EOF
)
  
  # Send event
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:$PORT/api/v1/events \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  RESPONSE_BODY=$(echo "$RESPONSE" | head -n-1)
  
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    echo "✓ Event $i: $EVENT_TYPE for $PLAYER_ID (HTTP $HTTP_CODE)"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "✗ Event $i: $EVENT_TYPE for $PLAYER_ID (HTTP $HTTP_CODE)"
    echo "  Response: $RESPONSE_BODY"
  fi
  
  # Small delay between events
  sleep 0.1
done

echo ""
echo "=========================================="
echo "Test Results:"
echo "  Total events: $NUM_EVENTS"
echo "  Successful: $SUCCESS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo "=========================================="
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
  echo "✓ All events sent successfully!"
  echo ""
  echo "Next steps:"
  echo "  1. Check Kafka topics:"
  echo "     kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
  echo "     Open http://localhost:8080"
  echo ""
  echo "  2. Check application logs:"
  echo "     kubectl logs -n $NAMESPACE -l app=event-ingestion --tail=50"
else
  echo "⚠ Some events failed. Check application logs:"
  echo "  kubectl logs -n $NAMESPACE -l app=event-ingestion --tail=50"
fi
echo ""
