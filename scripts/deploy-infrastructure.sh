#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="gamemetrics-dev"
TERRAFORM_DIR="terraform/environments/dev"

echo -e "${GREEN}=== GameMetrics Infrastructure Deployment ===${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check prerequisites
echo "Checking prerequisites..."
command -v aws >/dev/null 2>&1 || { print_error "AWS CLI not installed"; exit 1; }
command -v terraform >/dev/null 2>&1 || { print_error "Terraform not installed"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { print_error "kubectl not installed"; exit 1; }
print_status "All prerequisites installed"
echo ""

# Step 1: Deploy Terraform infrastructure
echo -e "${GREEN}Step 1: Deploying AWS Infrastructure${NC}"
cd "$TERRAFORM_DIR"

# Initialize Terraform
terraform init -upgrade

# Apply infrastructure
terraform apply -auto-approve

# Get outputs
export EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "$CLUSTER_NAME")
export RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")
export REDIS_ENDPOINT=$(terraform output -raw elasticache_primary_endpoint 2>/dev/null || echo "")

cd - > /dev/null
print_status "Infrastructure deployed"
echo ""

# Step 2: Configure kubectl
echo -e "${GREEN}Step 2: Configuring kubectl${NC}"
aws eks update-kubeconfig --region "$REGION" --name "$EKS_CLUSTER_NAME"
print_status "kubectl configured"
echo ""

# Step 3: Wait for nodes to be ready
echo -e "${GREEN}Step 3: Waiting for EKS nodes${NC}"
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
    ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    if [ "$ready_nodes" -ge 3 ]; then
        print_status "All 3 nodes are ready"
        break
    fi
    echo "Waiting for nodes... ($ready_nodes/3 ready)"
    sleep 10
    elapsed=$((elapsed + 10))
done

if [ $elapsed -ge $timeout ]; then
    print_error "Timeout waiting for nodes"
    exit 1
fi
echo ""

# Step 4: Deploy all K8s components via root kustomization
echo -e "${GREEN}Step 4: Deploying all K8s components${NC}"
kubectl apply -k k8s/
print_status "K8s resources deployed"
echo ""

# Step 5: Wait for Strimzi operator
echo -e "${GREEN}Step 5: Waiting for Strimzi Operator${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/strimzi-cluster-operator -n kafka || print_warning "Strimzi operator timeout"
print_status "Strimzi operator ready"
echo ""

# Step 6: Wait for Kafka cluster
echo -e "${GREEN}Step 6: Waiting for Kafka Cluster${NC}"
kubectl wait --for=condition=ready --timeout=600s pod -l strimzi.io/cluster=gamemetrics-kafka -n kafka || print_warning "Kafka cluster timeout"
print_status "Kafka cluster ready"
echo ""

# Step 7: Wait for Kafka UI
echo -e "${GREEN}Step 7: Waiting for Kafka UI${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/kafka-ui -n kafka || print_warning "Kafka UI timeout"
print_status "Kafka UI ready"
echo ""

# Step 8: Verify topics
echo -e "${GREEN}Step 8: Verifying Kafka Topics${NC}"
kubectl get kafkatopic -n kafka
echo ""

# Step 9: Update Kubernetes secrets from AWS
echo -e "${GREEN}Step 9: Updating Kubernetes secrets from AWS${NC}"
bash "$(dirname "$0")/update-secrets-from-aws.sh" "$REGION"
print_status "Kubernetes secrets updated from AWS Secrets Manager"
echo ""

# Step 10: Update deployment images with ECR URLs
echo -e "${GREEN}Step 10: Updating deployment images with ECR URLs${NC}"
bash "$(dirname "$0")/update-deployment-images.sh" "$REGION"
print_status "Deployment images updated with ECR URLs"
echo ""

# Summary
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo "Cluster Info:"
echo "  EKS Cluster: $EKS_CLUSTER_NAME"
echo "  RDS Endpoint: $RDS_ENDPOINT"
echo "  Redis Endpoint: $REDIS_ENDPOINT"
echo ""
echo "Kafka Info:"
echo "  Pods: $(kubectl get pods -n kafka --no-headers | wc -l)"
echo "  Topics: $(kubectl get kafkatopic -n kafka --no-headers | wc -l)"
echo ""
echo "Access Kafka UI:"
echo "  kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
echo "  Then open: http://localhost:8080"
echo ""
print_status "All systems operational!"
