#!/bin/bash

# GameMetrics Pro - Health Check Script
# This script performs comprehensive health checks on all components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "GameMetrics Pro - Health Check"
echo "========================================="
echo ""

# Function to check if a resource is ready
check_pods() {
    local namespace=$1
    local label=$2
    local name=$3
    
    echo -n "Checking $name... "
    
    local ready_pods=$(kubectl get pods -n $namespace -l $label -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | tr ' ' '\n' | grep -c "True" || true)
    local total_pods=$(kubectl get pods -n $namespace -l $label --no-headers | wc -l)
    
    if [ "$ready_pods" -eq "$total_pods" ] && [ "$total_pods" -gt 0 ]; then
        echo -e "${GREEN}✓ OK${NC} ($ready_pods/$total_pods pods ready)"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC} ($ready_pods/$total_pods pods ready)"
        return 1
    fi
}

# Function to check service endpoint
check_service() {
    local namespace=$1
    local service=$2
    local name=$3
    
    echo -n "Checking $name service... "
    
    local endpoint=$(kubectl get svc -n $namespace $service -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
    
    if [ -n "$endpoint" ]; then
        echo -e "${GREEN}✓ OK${NC} ($endpoint)"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC} (Service not found)"
        return 1
    fi
}

failures=0

# Check Kafka
echo ""
echo "=== Kafka Cluster ==="
check_pods "kafka" "strimzi.io/name=gamemetrics-kafka-kafka" "Kafka Brokers" || ((failures++))
check_pods "kafka" "strimzi.io/name=gamemetrics-kafka-zookeeper" "ZooKeeper" || ((failures++))
check_service "kafka" "gamemetrics-kafka-bootstrap" "Kafka Bootstrap" || ((failures++))

# Check if Kafka is ready
echo -n "Checking Kafka cluster status... "
kafka_status=$(kubectl get kafka gamemetrics-kafka -n kafka -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
if [ "$kafka_status" == "True" ]; then
    echo -e "${GREEN}✓ Ready${NC}"
else
    echo -e "${RED}✗ Not Ready${NC}"
    ((failures++))
fi

# Check Kafka topics
echo -n "Checking Kafka topics... "
topic_count=$(kubectl get kafkatopics -n kafka --no-headers 2>/dev/null | wc -l)
if [ "$topic_count" -ge 5 ]; then
    echo -e "${GREEN}✓ OK${NC} ($topic_count topics)"
else
    echo -e "${YELLOW}⚠ WARNING${NC} ($topic_count topics, expected 6+)"
fi

# Check Databases
echo ""
echo "=== Databases ==="
check_pods "databases" "app=postgresql" "PostgreSQL" || ((failures++))
check_pods "databases" "app=redis" "Redis" || ((failures++))
check_pods "databases" "app=timescaledb" "TimescaleDB" || ((failures++))
check_pods "databases" "app=qdrant" "Qdrant" || ((failures++))

# Check Application Services
echo ""
echo "=== Application Services ==="
check_pods "default" "app=event-ingestion-service" "Event Ingestion" || ((failures++))
check_service "default" "event-ingestion-service" "Event Ingestion" || ((failures++))

# Check for other services if they exist
services=("event-processor-service" "recommendation-engine" "analytics-api" "user-service" "notification-service" "data-retention-service" "admin-dashboard")
for svc in "${services[@]}"; do
    if kubectl get deployment $svc -n default &>/dev/null; then
        check_pods "default" "app=$svc" "$svc" || ((failures++))
    fi
done

# Check Monitoring Stack
echo ""
echo "=== Monitoring ==="
check_pods "monitoring" "app.kubernetes.io/name=prometheus" "Prometheus" || ((failures++))
check_pods "monitoring" "app.kubernetes.io/name=grafana" "Grafana" || ((failures++))

if kubectl get pods -n monitoring -l app=loki &>/dev/null 2>&1; then
    check_pods "monitoring" "app=loki" "Loki" || ((failures++))
fi

if kubectl get pods -n monitoring -l app=tempo &>/dev/null 2>&1; then
    check_pods "monitoring" "app=tempo" "Tempo" || ((failures++))
fi

# Check ArgoCD
echo ""
echo "=== ArgoCD ==="
check_pods "argocd" "app.kubernetes.io/name=argocd-server" "ArgoCD Server" || ((failures++))
check_service "argocd" "argocd-server" "ArgoCD" || ((failures++))

# Check ArgoCD applications
echo -n "Checking ArgoCD applications... "
if kubectl get applications -n argocd &>/dev/null 2>&1; then
    app_count=$(kubectl get applications -n argocd --no-headers | wc -l)
    synced_count=$(kubectl get applications -n argocd -o jsonpath='{.items[*].status.sync.status}' | tr ' ' '\n' | grep -c "Synced" || true)
    echo -e "${GREEN}$synced_count/$app_count synced${NC}"
else
    echo -e "${YELLOW}⚠ Not installed${NC}"
fi

# Check Istio
echo ""
echo "=== Istio Service Mesh ==="
check_pods "istio-system" "app=istiod" "Istio Control Plane" || ((failures++))
check_pods "istio-system" "app=istio-ingressgateway" "Istio Ingress Gateway" || ((failures++))

# Check Node Health
echo ""
echo "=== Kubernetes Nodes ==="
echo -n "Checking node status... "
ready_nodes=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | tr ' ' '\n' | grep -c "True" || true)
total_nodes=$(kubectl get nodes --no-headers | wc -l)
if [ "$ready_nodes" -eq "$total_nodes" ]; then
    echo -e "${GREEN}✓ All nodes ready${NC} ($ready_nodes/$total_nodes)"
else
    echo -e "${RED}✗ Some nodes not ready${NC} ($ready_nodes/$total_nodes)"
    ((failures++))
fi

# Check for node pressure
echo -n "Checking node pressure... "
pressure_nodes=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="MemoryPressure")].status}' | tr ' ' '\n' | grep -c "True" || true)
if [ "$pressure_nodes" -eq 0 ]; then
    echo -e "${GREEN}✓ No pressure${NC}"
else
    echo -e "${YELLOW}⚠ $pressure_nodes nodes under pressure${NC}"
fi

# Check PVC Status
echo ""
echo "=== Persistent Volumes ==="
echo -n "Checking PVCs... "
unbound_pvcs=$(kubectl get pvc --all-namespaces -o jsonpath='{.items[?(@.status.phase!="Bound")].metadata.name}' | wc -w)
if [ "$unbound_pvcs" -eq 0 ]; then
    echo -e "${GREEN}✓ All PVCs bound${NC}"
else
    echo -e "${RED}✗ $unbound_pvcs PVCs not bound${NC}"
    ((failures++))
fi

# Final Summary
echo ""
echo "========================================="
if [ $failures -eq 0 ]; then
    echo -e "${GREEN}✓ All health checks passed!${NC}"
    echo "========================================="
    exit 0
else
    echo -e "${RED}✗ $failures health check(s) failed${NC}"
    echo "========================================="
    echo ""
    echo "To investigate failures, run:"
    echo "  kubectl get pods --all-namespaces"
    echo "  kubectl get events --sort-by='.lastTimestamp'"
    echo "  kubectl logs <pod-name> -n <namespace>"
    exit 1
fi
