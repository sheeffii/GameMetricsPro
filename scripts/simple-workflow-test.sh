#!/bin/bash

echo "Simple Workflow Test"
echo "==================="
echo ""

# Get pod names
DB_POD=$(kubectl get pods -n gamemetrics -l app=timescaledb -o jsonpath='{.items[0].metadata.name}')
KAFKA_POD=$(kubectl get pods -n kafka -l strimzi.io/cluster=gamemetrics-kafka -o jsonpath='{.items[0].metadata.name}')

echo "DB Pod: $DB_POD"
echo "Kafka Pod: $KAFKA_POD"
echo ""

# Test 1: Check DB is working
echo "Test 1: Checking database..."
kubectl exec $DB_POD -n gamemetrics -- psql -U postgres -d gamemetrics -c "SELECT COUNT(*) as events FROM events;" || exit 1

# Test 2: Send event to Kafka
echo ""
echo "Test 2: Sending test event to Kafka..."
kubectl exec $KAFKA_POD -n kafka -- bash -c 'echo "{\"event_id\":\"test-123\",\"event_type\":\"login\",\"player_id\":\"player1\"}" | bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic player.events.raw' || exit 1

# Test 3: Check if message is in Kafka
echo ""
echo "Test 3: Checking Kafka topic..."
kubectl exec $KAFKA_POD -n kafka -- bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic player.events.raw --from-beginning --max-messages 1 --timeout-ms 5000 || echo "No messages yet"

# Test 4: Wait and check DB again
echo ""
echo "Test 4: Waiting 10 seconds for consumer to process..."
sleep 10

echo "Checking database for events..."
kubectl exec $DB_POD -n gamemetrics -- psql -U postgres -d gamemetrics -c "SELECT COUNT(*) as total_events FROM events; SELECT event_id, event_type FROM events ORDER BY created_at DESC LIMIT 3;"

echo ""
echo "✅ Test complete!"
