#!/bin/bash
#
# Complete End-to-End Workflow Test
# Tests: Producer → Kafka → Consumer → TimescaleDB
#
# Usage: bash test-complete-workflow.sh [num_events]
# Example: bash test-complete-workflow.sh 20
#

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Configuration
NUM_EVENTS="${1:-10}"
NAMESPACE_GAMEMETRICS="gamemetrics"
NAMESPACE_KAFKA="kafka"
DB_POD="timescaledb-589bf95b9d-p2vsx"
KAFKA_BROKER="gamemetrics-kafka-broker-0"
TOPIC="player.events.raw"

# Helper functions
print_section() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo ""
}

print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Step 1: Verify Infrastructure
verify_infrastructure() {
    print_section "Step 1: Verifying Infrastructure"
    
    print_info "Checking Kubernetes pods..."
    
    # Check gamemetrics pods
    local gamemetrics_pods=$(kubectl get pods -n $NAMESPACE_GAMEMETRICS --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$gamemetrics_pods" -gt 0 ]; then
        print_status "gamemetrics namespace has $gamemetrics_pods running pods"
    else
        print_error "No pods running in gamemetrics namespace"
        exit 1
    fi
    
    # Check Kafka
    local kafka_brokers=$(kubectl get pods -n $NAMESPACE_KAFKA -l strimzi.io/cluster=gamemetrics-kafka --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$kafka_brokers" -gt 0 ]; then
        print_status "Kafka cluster has $kafka_brokers brokers running"
    else
        print_error "Kafka brokers not running"
        exit 1
    fi
    
    # Check consumer
    local consumer_pods=$(kubectl get pods -n $NAMESPACE_GAMEMETRICS -l app=event-consumer-logger --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$consumer_pods" -gt 0 ]; then
        print_status "Event consumer has $consumer_pods pods running"
    else
        print_warning "Event consumer not running (will be deployed during test)"
    fi
    
    # Check database
    local db_pods=$(kubectl get pods -n $NAMESPACE_GAMEMETRICS -l app=timescaledb --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$db_pods" -gt 0 ]; then
        print_status "TimescaleDB has $db_pods pods running"
    else
        print_error "TimescaleDB not running"
        exit 1
    fi
}

# Step 2: Check Database Schema
check_database_schema() {
    print_section "Step 2: Checking Database Schema"
    
    print_info "Verifying events table exists..."
    
    local table_exists=$(kubectl exec -it $DB_POD -n $NAMESPACE_GAMEMETRICS -- \
        psql -U dbadmin -d gamemetrics -tc \
        "SELECT EXISTS(SELECT FROM information_schema.tables WHERE table_name='events');" 2>/dev/null | xargs)
    
    if [ "$table_exists" = "t" ]; then
        print_status "events table exists"
        
        # Show schema
        print_info "Table schema:"
        kubectl exec -it $DB_POD -n $NAMESPACE_GAMEMETRICS -- \
            psql -U dbadmin -d gamemetrics -c "\d events" 2>/dev/null | sed 's/^/  /'
    else
        print_error "events table does not exist"
        exit 1
    fi
}

# Step 3: Get Initial Event Count
get_event_count() {
    local count=$(kubectl exec -it $DB_POD -n $NAMESPACE_GAMEMETRICS -- \
        psql -U dbadmin -d gamemetrics -tc "SELECT COUNT(*) FROM events;" 2>/dev/null | xargs)
    echo "$count"
}

# Step 4: Produce Test Events
produce_events() {
    print_section "Step 4: Producing $NUM_EVENTS Test Events"
    
    print_info "Sending events to Kafka topic: $TOPIC"
    
    for i in $(seq 1 $NUM_EVENTS); do
        # Generate unique event ID
        EVENT_ID="test-event-$(date +%s%N)-$i"
        EVENT_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        
        # Create event JSON
        EVENT=$(cat <<EOF
{"event_id":"$EVENT_ID","event_type":"test_event","player_id":"player_test_$i","game_id":"game_test_$i","event_timestamp":"$EVENT_TIMESTAMP","data":{"test":true,"iteration":$i}}
EOF
)
        
        # Send to Kafka
        echo "$EVENT" | kubectl exec -i $KAFKA_BROKER -n $NAMESPACE_KAFKA -- \
            bin/kafka-console-producer.sh \
                --broker-list localhost:9092 \
                --topic $TOPIC \
                --property "parse.key=false" 2>/dev/null
        
        if [ $((i % 5)) -eq 0 ]; then
            echo "  Produced events $i/$NUM_EVENTS"
        fi
    done
    
    print_status "All $NUM_EVENTS events produced"
}

# Step 5: Wait for Consumer to Process
wait_for_consumer() {
    print_section "Step 5: Waiting for Consumer to Process Events"
    
    print_info "Giving consumer time to process events..."
    
    local timeout=60
    local elapsed=0
    local check_interval=5
    
    while [ $elapsed -lt $timeout ]; do
        local current_count=$(get_event_count)
        echo "  Events in DB: $current_count (elapsed: ${elapsed}s)"
        
        if [ "$current_count" -gt "$COUNT_BEFORE" ]; then
            local processed=$((current_count - COUNT_BEFORE))
            if [ "$processed" -ge "$NUM_EVENTS" ]; then
                print_status "All events consumed and processed!"
                return 0
            fi
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    print_warning "Timeout: Consumer may still be processing"
}

# Step 6: Verify Events in Database
verify_events() {
    print_section "Step 6: Verifying Events in Database"
    
    local count_after=$(get_event_count)
    local events_added=$((count_after - COUNT_BEFORE))
    
    print_info "Event counts:"
    echo "  Before test: $COUNT_BEFORE"
    echo "  After test:  $count_after"
    echo "  Added:       $events_added"
    
    if [ "$events_added" -ge "$NUM_EVENTS" ]; then
        print_status "✅ TEST PASSED: All $NUM_EVENTS events stored in database!"
        echo ""
        echo "  Complete flow verified:"
        echo "    Producer → Kafka → Consumer → Database ✓"
        return 0
    elif [ "$events_added" -gt 0 ]; then
        print_warning "PARTIAL SUCCESS: Only $events_added of $NUM_EVENTS events received"
        echo ""
        echo "  Possible issues:"
        echo "    1. Consumer processing slower than expected"
        echo "    2. Check consumer logs: kubectl logs -n $NAMESPACE_GAMEMETRICS deployment/event-consumer-logger -f"
        echo "    3. Check Kafka: kubectl logs -n $NAMESPACE_KAFKA deployment/strimzi-cluster-operator"
        return 1
    else
        print_error "TEST FAILED: No events received in database"
        echo ""
        echo "  Troubleshooting:"
        echo "    1. Check consumer: kubectl get pods -n $NAMESPACE_GAMEMETRICS"
        echo "    2. Check logs: kubectl logs -n $NAMESPACE_GAMEMETRICS deployment/event-consumer-logger --tail=50"
        echo "    3. Check Kafka: kubectl exec -it $KAFKA_BROKER -n $NAMESPACE_KAFKA -- bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic $TOPIC --max-messages 5"
        return 1
    fi
}

# Step 7: Display Recent Events
show_recent_events() {
    print_section "Step 7: Recent Events in Database"
    
    print_info "Last 5 events inserted:"
    echo ""
    kubectl exec -it $DB_POD -n $NAMESPACE_GAMEMETRICS -- \
        psql -U dbadmin -d gamemetrics -c \
        "SELECT event_id, event_type, player_id, created_at FROM events ORDER BY created_at DESC LIMIT 5;" 2>/dev/null
}

# Step 8: Display Statistics
show_statistics() {
    print_section "Step 8: Pipeline Statistics"
    
    print_info "Event distribution by type:"
    kubectl exec -it $DB_POD -n $NAMESPACE_GAMEMETRICS -- \
        psql -U dbadmin -d gamemetrics -c \
        "SELECT event_type, COUNT(*) as count FROM events GROUP BY event_type ORDER BY count DESC;" 2>/dev/null
    
    echo ""
    print_info "Total events in database:"
    local total=$(get_event_count)
    echo "  $total events"
    
    echo ""
    print_info "Consumer group status:"
    kubectl exec -it $KAFKA_BROKER -n $NAMESPACE_KAFKA -- \
        bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group event-logger-group --describe 2>/dev/null || echo "  Consumer group not yet created"
}

# Main execution
main() {
    print_section "Complete End-to-End Workflow Test"
    echo "Testing: Producer → Kafka → Consumer → TimescaleDB"
    echo "Number of events: $NUM_EVENTS"
    
    verify_infrastructure
    check_database_schema
    
    # Get initial count
    COUNT_BEFORE=$(get_event_count)
    print_info "Initial event count: $COUNT_BEFORE"
    
    produce_events
    wait_for_consumer
    
    if verify_events; then
        show_recent_events
        show_statistics
        print_section "Test Completed Successfully ✅"
        exit 0
    else
        print_section "Test Completed with Issues ⚠️"
        exit 1
    fi
}

# Run main
main "$@"
