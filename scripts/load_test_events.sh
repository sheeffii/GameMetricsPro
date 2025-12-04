#!/bin/bash
# Load test script - Generate sample events to test the entire pipeline
# Usage: ./load_test_events.sh <count> <rate_per_second>

set -e

COUNT=${1:-1000}
RATE=${2:-100}

INGESTION_SERVICE_URL=${INGESTION_SERVICE_URL:-"http://localhost:8080"}
ENDPOINT="${INGESTION_SERVICE_URL}/api/v1/events"

# Game and player IDs for testing
GAMES=("game-456" "game-789" "game-123")
PLAYERS=("player-001" "player-002" "player-003" "player-004" "player-005")

# Event types
EVENT_TYPES=("player_level_up" "player_score" "quest_completed" "achievement_unlocked" "boss_defeated")

function generate_event() {
    local game_id=${GAMES[$RANDOM % ${#GAMES[@]}]}
    local player_id=${PLAYERS[$RANDOM % ${#PLAYERS[@]}]}
    local event_type=${EVENT_TYPES[$RANDOM % ${#EVENT_TYPES[@]}]}
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Generate random data based on event type
    case $event_type in
        "player_level_up")
            DATA="{\"level\": $((RANDOM % 100 + 1)), \"experience\": $((RANDOM % 1000))}"
            ;;
        "player_score")
            DATA="{\"score\": $((RANDOM % 10000 + 100))}"
            ;;
        "quest_completed")
            DATA="{\"quest_id\": \"quest-$((RANDOM % 100))\", \"reward_points\": $((RANDOM % 500 + 50))}"
            ;;
        "achievement_unlocked")
            DATA="{\"achievement_id\": \"ach-$((RANDOM % 50))\", \"points\": $((RANDOM % 200 + 10))}"
            ;;
        "boss_defeated")
            DATA="{\"boss_id\": \"boss-$((RANDOM % 20))\", \"difficulty_score\": $((RANDOM % 1000 + 100))}"
            ;;
    esac
    
    cat <<EOF
{
    "event_type": "$event_type",
    "player_id": "$player_id",
    "game_id": "$game_id",
    "timestamp": "$timestamp",
    "data": $DATA
}
EOF
}

echo "🔥 Starting load test..."
echo "  Endpoint: $ENDPOINT"
echo "  Total events: $COUNT"
echo "  Rate: $RATE events/sec"
echo ""

start_time=$(date +%s)
success=0
failed=0

for ((i=1; i<=COUNT; i++)); do
    event=$(generate_event)
    
    response=$(curl -s -X POST "$ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "$event" \
        -w "\n%{http_code}")
    
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" == "200" ]; then
        ((success++))
    else
        ((failed++))
        echo "❌ Event $i failed: HTTP $http_code"
    fi
    
    # Rate limiting
    if [ $((i % RATE)) -eq 0 ]; then
        elapsed=$(($(date +%s) - start_time))
        sleep_time=$((i / RATE - elapsed + 1))
        if [ $sleep_time -gt 0 ]; then
            sleep $sleep_time
        fi
    fi
    
    # Progress every 100 events
    if [ $((i % 100)) -eq 0 ]; then
        echo "  [$i/$COUNT] Success: $success, Failed: $failed"
    fi
done

end_time=$(date +%s)
duration=$((end_time - start_time))

echo ""
echo "✅ Load test completed!"
echo "  Duration: ${duration}s"
echo "  Success: $success"
echo "  Failed: $failed"
echo "  Rate: $(( success / duration )) events/sec"
