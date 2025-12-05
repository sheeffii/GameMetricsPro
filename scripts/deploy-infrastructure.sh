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
# Toggle Kafka apply (set APPLY_KAFKA=false to skip Kafka resources)
APPLY_KAFKA="${APPLY_KAFKA:-true}"

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

# Check for existing resources and import if needed
echo "Checking for existing resources..."
set +e
EXISTING_ELASTICACHE=$(aws elasticache describe-replication-groups --replication-group-id gamemetrics-dev --region "$REGION" 2>/dev/null)
if [ $? -eq 0 ]; then
    print_warning "ElastiCache cluster already exists, importing..."
    terraform import 'module.elasticache.aws_elasticache_replication_group.main' gamemetrics-dev 2>/dev/null || true
fi
set -e

# Apply infrastructure with retry on specific errors
echo "Applying infrastructure..."
MAX_RETRIES=2
for i in $(seq 1 $MAX_RETRIES); do
    if terraform apply -auto-approve; then
        break
    else
        EXIT_CODE=$?
        if [ $i -lt $MAX_RETRIES ]; then
            print_warning "Terraform apply failed (attempt $i/$MAX_RETRIES), retrying..."
            sleep 10
        else
            print_error "Terraform apply failed after $MAX_RETRIES attempts"
            exit $EXIT_CODE
        fi
    fi
done

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

# Step 5: Wait for Strimzi operator to be ready
echo -e "${GREEN}Step 5: Waiting for Strimzi Operator to register CRDs${NC}"
# Give extra time for operator to fully initialize
sleep 15
kubectl wait --for=condition=available --timeout=300s deployment/strimzi-cluster-operator -n kafka 2>/dev/null || print_warning "Strimzi operator timeout"
print_status "Strimzi operator ready"

# Wait for CRDs to be established
echo "Waiting for Kafka CRDs to be established..."
sleep 10
for crd in kafka kafkatopic kafkanodepool; do
  kubectl wait --for condition=established --timeout=300s crd/"${crd}s.kafka.strimzi.io" 2>/dev/null || print_warning "CRD ${crd} timeout"
done
print_status "All Kafka CRDs established"
echo ""

if [ "$APPLY_KAFKA" = "true" ]; then
    # Step 6: Apply Kafka resources (with retry logic)
    echo -e "${GREEN}Step 6: Applying Kafka cluster and topics${NC}"
    max_retries=3
    retry=0
    while [ $retry -lt $max_retries ]; do
        if kubectl apply -k k8s/kafka/overlays/dev 2>/dev/null; then
            print_status "Kafka cluster and topics applied"
            break
        else
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                echo "Retrying Kafka resources ($retry/$max_retries)..."
                sleep 10
            else
                print_warning "Failed to apply Kafka resources after $max_retries retries"
            fi
        fi
    done
    echo ""

    # Step 7: Wait for Kafka cluster (CR Ready + statefulsets)
    echo -e "${GREEN}Step 7: Waiting for Kafka Cluster${NC}"
    if ! kubectl wait --for=condition=Ready --timeout=600s kafka/gamemetrics-kafka -n kafka 2>/dev/null; then
        print_warning "Kafka CR not Ready after 600s; checking statefulsets"
    fi
    kubectl rollout status statefulset/gamemetrics-kafka-controller -n kafka --timeout=300s 2>/dev/null || print_warning "Controller statefulset not ready"
    kubectl rollout status statefulset/gamemetrics-kafka-broker -n kafka --timeout=300s 2>/dev/null || print_warning "Broker statefulset not ready"
    echo ""

    # Step 8: Wait for Kafka UI
    echo -e "${GREEN}Step 8: Waiting for Kafka UI${NC}"
    kubectl wait --for=condition=available --timeout=300s deployment/kafka-ui -n kafka 2>/dev/null || print_warning "Kafka UI timeout"
    print_status "Kafka UI ready"
    echo ""

    # Step 9: Verify topics
    echo -e "${GREEN}Step 9: Verifying Kafka Topics${NC}"
    kubectl get kafkatopic -n kafka 2>/dev/null || echo "Topics not yet available"
    echo ""
else
    print_warning "Kafka apply skipped (APPLY_KAFKA=false)."
fi

# Step 10: Update Kubernetes secrets from AWS
echo -e "${GREEN}Step 10: Updating Kubernetes secrets from AWS${NC}"
bash "$(dirname "$0")/update-secrets-from-aws.sh" "$REGION"
print_status "Kubernetes secrets updated from AWS Secrets Manager"
echo ""

# Step 11: Update deployment images with ECR URLs
echo -e "${GREEN}Step 11: Updating deployment images with ECR URLs${NC}"
bash "$(dirname "$0")/update-deployment-images.sh" "$REGION"
print_status "Deployment images updated with ECR URLs"

echo ""
echo "Cluster Info:"
echo "  EKS Cluster: $EKS_CLUSTER_NAME"
echo "  RDS Endpoint: $RDS_ENDPOINT"
echo "  Redis Endpoint: $REDIS_ENDPOINT"
echo ""
echo "Kafka Info:"
echo "  Operator: $(kubectl get pods -n kafka -l app.kubernetes.io/name=strimzi-cluster-operator --no-headers 2>/dev/null | wc -l) running"
echo "  Brokers: $(kubectl get pods -n kafka -l strimzi.io/cluster=gamemetrics-kafka --no-headers 2>/dev/null | wc -l) running"
echo "  Topics: $(kubectl get kafkatopic -n kafka --no-headers 2>/dev/null | wc -l) configured"
echo ""
echo "Access Kafka UI:"
echo "  kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
echo "  Then open: http://localhost:8080"
echo ""
echo "Event Ingestion Service:"
echo "  kubectl get deployment -n gamemetrics event-ingestion"
echo "  kubectl logs -n gamemetrics -l app=event-ingestion"
echo ""
print_status "All systems operational!"
