#!/bin/bash
#
# GameMetrics Pro - System Status Check Script
# 
# This script displays the current status of the GameMetrics Pro platform:
# - AWS Infrastructure (EKS, RDS, Redis endpoints from Terraform)
# - Kubernetes Cluster (nodes, namespaces, pods)
# - Kafka Status (pods, topics, services)
# - Local Tools (AWS CLI, Terraform, kubectl versions)
#
# Usage:
#   ./scripts/check-status.sh
#
# Prerequisites:
#   - kubectl configured (optional, for K8s status)
#   - terraform installed (optional, for infrastructure status)
#   - aws CLI installed (optional, for AWS status)
#

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== GameMetrics System Status ===${NC}"
echo ""

# Check AWS Resources
echo -e "${GREEN}AWS Infrastructure:${NC}"
if command -v terraform &> /dev/null && [ -d "terraform/environments/dev" ]; then
    cd terraform/environments/dev
    echo "EKS Cluster: $(terraform output -raw eks_cluster_name 2>/dev/null || echo 'Not deployed')"
    echo "RDS Endpoint: $(terraform output -raw rds_endpoint 2>/dev/null || echo 'Not deployed')"
    echo "Redis Endpoint: $(terraform output -raw elasticache_primary_endpoint 2>/dev/null || echo 'Not deployed')"
    cd - > /dev/null
else
    echo "Terraform not configured"
fi
echo ""

# Check Kubernetes
echo -e "${GREEN}Kubernetes Cluster:${NC}"
if kubectl cluster-info &> /dev/null; then
    echo "Status: Connected"
    echo "Nodes:"
    kubectl get nodes --no-headers | awk '{print "  - " $1 " (" $2 ")"}'
    echo ""
    
    echo -e "${GREEN}Kafka Namespace:${NC}"
    if kubectl get namespace kafka &> /dev/null; then
        echo "Pods:"
        kubectl get pods -n kafka --no-headers | awk '{print "  - " $1 " (" $3 ")"}'
        echo ""
        
        echo "Topics:"
        kubectl get kafkatopic -n kafka --no-headers 2>/dev/null | awk '{print "  - " $1 " (Partitions: " $3 ")"}'
        echo ""
        
        echo "Services:"
        kubectl get svc -n kafka --no-headers | awk '{print "  - " $1 " (" $2 ")"}'
    else
        echo "Kafka namespace not found"
    fi
else
    echo "Not connected to cluster"
fi
echo ""

# Check local tools
echo -e "${GREEN}Local Tools:${NC}"
command -v aws &> /dev/null && echo "  ✓ AWS CLI: $(aws --version | cut -d' ' -f1)" || echo "  ✗ AWS CLI: Not installed"
command -v terraform &> /dev/null && echo "  ✓ Terraform: $(terraform version -json | grep -o '"terraform_version":"[^"]*' | cut -d'"' -f4)" || echo "  ✗ Terraform: Not installed"
command -v kubectl &> /dev/null && echo "  ✓ kubectl: $(kubectl version --client --short 2>/dev/null | grep 'Client Version' | awk '{print $3}')" || echo "  ✗ kubectl: Not installed"
echo ""

echo -e "${BLUE}Quick Actions:${NC}"
echo "  Deploy:    ./scripts/deploy-infrastructure.sh"
echo "  Teardown:  ./scripts/teardown-infrastructure.sh"
echo "  Kafka UI:  kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
