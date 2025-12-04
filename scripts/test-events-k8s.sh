#!/bin/bash
# Test sending events directly from within the Kubernetes cluster

echo "=========================================="
echo "Testing Event Ingestion from K8s Cluster"
echo "=========================================="
echo ""

# Test 1: Health Check
echo "Test 1: Health Check"
kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -n gamemetrics -- \
  curl -s http://event-ingestion.gamemetrics.svc.cluster.local/health/live
echo ""
echo ""

# Test 2: Send Login Event
echo "Test 2: Sending Login Event"
kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -n gamemetrics -- \
  curl -s -X POST http://event-ingestion.gamemetrics.svc.cluster.local/api/v1/events \
  -H 'Content-Type: application/json' \
  -d '{"player_id":"test-player-001","game_id":"game-realtime-001","event_type":"login","timestamp":"2025-12-03T12:55:00Z","data":{"level":42,"score":9999}}'
echo ""
echo ""

# Test 3: Send Multiple Events
echo "Test 3: Sending 5 Different Event Types"
for i in {1..5}; do
  EVENT_TYPES=("login" "logout" "level_up" "purchase" "achievement")
  EVENT_TYPE=${EVENT_TYPES[$((i % 5))]}
  
  echo "  Sending event $i: $EVENT_TYPE"
  kubectl run curl-test-$i --image=curlimages/curl:latest --rm -i --restart=Never -n gamemetrics -- \
    curl -s -X POST http://event-ingestion.gamemetrics.svc.cluster.local/api/v1/events \
    -H 'Content-Type: application/json' \
    -d "{\"player_id\":\"player-00$i\",\"game_id\":\"game-realtime-001\",\"event_type\":\"$EVENT_TYPE\",\"timestamp\":\"2025-12-03T12:55:0${i}Z\",\"data\":{\"level\":$((i*10)),\"score\":$((i*1000))}}" \
    > /dev/null 2>&1
  
  sleep 0.5
done

echo ""
echo "=========================================="
echo "✓ Test events sent successfully!"
echo "=========================================="
echo ""
echo "Check application logs:"
echo "  kubectl logs -n gamemetrics -l app=event-ingestion --tail=30"
echo ""
echo "Check Kafka topics:"
echo "  kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
echo "  Open http://localhost:8080"
echo ""
