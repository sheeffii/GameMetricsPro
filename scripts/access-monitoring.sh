#!/bin/bash
#
# GameMetrics Pro - Monitoring Access Script
# 
# This script provides quick access to observability tools via port-forwarding:
# - Grafana (dashboards, metrics, logs)
# - Prometheus (direct metrics queries)
# - Kafka UI (Kafka cluster management)
#
# Usage:
#   ./scripts/access-monitoring.sh [grafana|prometheus|kafka-ui|all]
#   Example: ./scripts/access-monitoring.sh grafana
#
# Prerequisites:
#   - kubectl configured and connected
#   - Monitoring namespace must exist (deployed via production-deploy.sh)
#   - Kafka namespace must exist (for Kafka UI)
#
# Note: Port-forwarding runs in foreground. Use Ctrl+C to stop.
#

set -e

COMPONENT=${1:-all}

echo "🔍 GameMetrics Pro - Monitoring Access"
echo "======================================"
echo ""

function access_grafana() {
    echo "📊 Starting Grafana port-forward..."
    echo "   URL: http://localhost:3000"
    echo "   Username: admin"
    echo "   Password: admin123"
    echo ""
    echo "   Dashboards:"
    echo "   - Platform Overview"
    echo "   - Kafka Cluster Monitoring"
    echo "   - Explore → Loki (for logs)"
    echo ""
    kubectl port-forward -n monitoring svc/grafana 3000:3000
}

function access_prometheus() {
    echo "📈 Starting Prometheus port-forward..."
    echo "   URL: http://localhost:9090"
    echo ""
    echo "   Example queries:"
    echo "   - kafka_server_brokertopicmetrics_messagesinpersec_count"
    echo "   - up{namespace=\"gamemetrics\"}"
    echo "   - rate(container_cpu_usage_seconds_total[5m])"
    echo ""
    kubectl port-forward -n monitoring svc/prometheus 9090:9090
}

function access_kafka_ui() {
    echo "🎯 Starting Kafka UI port-forward..."
    echo "   URL: http://localhost:8080"
    echo ""
    kubectl port-forward -n kafka svc/kafka-ui 8080:8080
}

case $COMPONENT in
    grafana)
        access_grafana
        ;;
    prometheus)
        access_prometheus
        ;;
    kafka-ui)
        access_kafka_ui
        ;;
    all)
        echo "Select component to access:"
        echo "1) Grafana (Recommended - All-in-one)"
        echo "2) Prometheus (Direct metrics)"
        echo "3) Kafka UI"
        echo ""
        read -p "Enter choice [1-3]: " choice
        
        case $choice in
            1)
                access_grafana
                ;;
            2)
                access_prometheus
                ;;
            3)
                access_kafka_ui
                ;;
            *)
                echo "Invalid choice"
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Usage: $0 [grafana|prometheus|kafka-ui|all]"
        exit 1
        ;;
esac
