#!/usr/bin/env bash
#
# GameMetrics Pro - Application Test Suite Script
# 
# This script runs basic health checks and functional tests:
# 1. Liveness probe test
# 2. Readiness probe test
# 3. Event ingestion test
# 4. Pod logs inspection
#
# Usage:
#   ./scripts/test-application.sh
#
# Prerequisites:
#   - kubectl configured and connected
#   - event-ingestion service deployed and running
#   - Port 8081 available (for port-forwarding)
#
# Note: This is a basic test script. For comprehensive testing, use
# the integration test suite in tests/integration/.
#

set -euo pipefail

echo "==================================================================="
echo "  GameMetrics - Application Test Suite"
echo "==================================================================="
echo ""

# Check if port-forward is running
PORT_FORWARD_PID=$(lsof -ti:8081 2>/dev/null || true)

if [ -z "${PORT_FORWARD_PID}" ]; then
    echo "⚠️  Port-forward not detected on port 8081"
    echo "Starting port-forward in background..."
    kubectl port-forward -n gamemetrics svc/event-ingestion 8081:80 > /dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    sleep 3
    echo "✅ Port-forward started (PID: ${PORT_FORWARD_PID})"
    echo ""
else
    echo "✅ Port-forward already running on port 8081"
    echo ""
fi

# Test 1: Liveness probe
echo "1️⃣  Testing liveness probe..."
LIVENESS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/health/live || echo "000")
if [ "${LIVENESS}" = "200" ]; then
    echo "   ✅ Liveness: OK (HTTP ${LIVENESS})"
else
    echo "   ❌ Liveness: FAILED (HTTP ${LIVENESS})"
fi

# Test 2: Readiness probe
echo "2️⃣  Testing readiness probe..."
READINESS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/health/ready || echo "000")
if [ "${READINESS}" = "200" ]; then
    echo "   ✅ Readiness: OK (HTTP ${READINESS})"
else
    echo "   ❌ Readiness: FAILED (HTTP ${READINESS})"
fi

# Test 3: Send test event
echo "3️⃣  Sending test event..."
TEST_EVENT=$(cat <<EOF
{
    "playerId": "player-$(date +%s)",
    "eventType": "login",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "metadata": {
        "platform": "web",
        "version": "1.0.0"
    }
}
EOF
)

EVENT_RESPONSE=$(curl -s -X POST http://localhost:8081/api/v1/events \
    -H "Content-Type: application/json" \
    -d "${TEST_EVENT}" || echo "ERROR")

if echo "${EVENT_RESPONSE}" | grep -q '"status":"success"\|"success":true'; then
    echo "   ✅ Event ingestion: OK"
    echo "   Response: ${EVENT_RESPONSE}"
else
    echo "   ❌ Event ingestion: FAILED"
    echo "   Response: ${EVENT_RESPONSE}"
fi

# Test 4: Check pod logs
echo ""
echo "4️⃣  Recent pod logs (last 10 lines):"
kubectl logs -n gamemetrics -l app=event-ingestion --tail=10 | grep -v "caller=" || true

echo ""
echo "==================================================================="
echo "  Test Summary"
echo "==================================================================="
echo ""
echo "To view Kafka topics:"
echo "  kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
echo "  Open: http://localhost:8080"
echo ""
echo "To check database:"
echo "  kubectl port-forward -n databases svc/postgresql 5432:5432"
echo "  psql -h localhost -U dbadmin -d gamemetrics"
echo ""
