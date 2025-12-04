#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TOPIC="${1:-player.events.raw}"
MESSAGE="${2:-{\"playerId\":\"test-123\",\"event\":\"login\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}"

echo -e "${GREEN}=== Kafka Quick Test ===${NC}"
echo ""
echo "Topic: $TOPIC"
echo "Message: $MESSAGE"
echo ""

# Produce message
echo -e "${YELLOW}Producing message...${NC}"
echo "$MESSAGE" | kubectl exec -i -n kafka gamemetrics-kafka-broker-0 -- \
    bin/kafka-console-producer.sh \
    --bootstrap-server localhost:9092 \
    --topic "$TOPIC"

echo -e "${GREEN}✓ Message sent${NC}"
echo ""

# Consume messages
echo -e "${YELLOW}Last 5 messages from topic:${NC}"
kubectl exec -n kafka gamemetrics-kafka-broker-0 -- \
    bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic "$TOPIC" \
    --from-beginning \
    --max-messages 5 \
    --timeout-ms 5000 2>/dev/null || echo "No messages found"

echo ""
echo -e "${GREEN}Test complete!${NC}"
