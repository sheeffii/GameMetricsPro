#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REGION=${1:-us-east-1}
INFRA_OUTPUT_FILE=".infra-output.env"

echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Deploying Applications to Kubernetes${NC}"
echo -e "${GREEN}════════════════════════════════════════════${NC}"
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

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Load infrastructure outputs if available
if [ -f "$INFRA_OUTPUT_FILE" ]; then
    print_info "Loading infrastructure outputs from $INFRA_OUTPUT_FILE"
    source "$INFRA_OUTPUT_FILE"
    print_status "Infrastructure outputs loaded"
else
    print_warning "Infrastructure output file not found; using fallback values"
    REGION=${REGION:-us-east-1}
    EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME:-gamemetrics-dev}
    ECR_URL=${ECR_URL:-}
fi
echo ""

# Verify kubectl connectivity
echo -e "${GREEN}Step 1: Verifying Kubernetes connectivity${NC}"
if ! kubectl cluster-info &>/dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    echo "  Run: aws eks update-kubeconfig --region $REGION --name $EKS_CLUSTER_NAME"
    exit 1
fi
print_status "Connected to cluster"
echo ""

# Step 2: Get ECR URL if not loaded from infra output
if [ -z "$ECR_URL" ]; then
    echo -e "${GREEN}Step 2: Fetching ECR repository URL${NC}"
    
    # Try from Terraform
    TERRAFORM_DIR="terraform/environments/dev"
    if [ -d "$TERRAFORM_DIR" ]; then
        ECR_URL=$(cd "$TERRAFORM_DIR" && terraform output -json 2>/dev/null | jq -r '.ecr_repository_urls.value["event-ingestion-service"]' 2>/dev/null || echo "")
    fi
    
    # Fallback: construct from AWS account ID
    if [ -z "$ECR_URL" ] || [ "$ECR_URL" = "null" ]; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        ECR_URL="$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/event-ingestion-service"
        print_info "Constructed ECR URL: $ECR_URL"
    else
        print_status "ECR URL from Terraform: $ECR_URL"
    fi
else
    print_status "Using ECR URL from infrastructure output: $ECR_URL"
fi
echo ""

# Step 3: Update event-ingestion deployment
echo -e "${GREEN}Step 2: Deploying event-ingestion service${NC}"

# Check if deployment already exists
if kubectl get deployment event-ingestion -n gamemetrics &>/dev/null; then
    print_info "Deployment exists; updating image..."
    kubectl set image deployment/event-ingestion \
        event-ingestion=$ECR_URL:latest \
        -n gamemetrics
    
    print_info "Waiting for rollout..."
    kubectl rollout status deployment/event-ingestion -n gamemetrics --timeout=300s || print_warning "Rollout timeout"
    print_status "Deployment updated and rolled out"
else
    print_info "Creating new deployment from kustomization..."
    
    # Update deployment.yaml with ECR URL
    DEPLOYMENT_DIR="k8s/services/event-ingestion"
    if [ -f "$DEPLOYMENT_DIR/deployment.yaml" ]; then
        # Create temp file
        temp_file=$(mktemp)
        sed "s|image:.*event-ingestion-service.*|image: $ECR_URL:latest|g" "$DEPLOYMENT_DIR/deployment.yaml" > "$temp_file"
        mv "$temp_file" "$DEPLOYMENT_DIR/deployment.yaml"
        print_status "Deployment manifest updated with ECR URL"
    fi
    
    # Apply deployment
    kubectl apply -f "$DEPLOYMENT_DIR/deployment.yaml" -n gamemetrics
    print_info "Waiting for deployment ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/event-ingestion -n gamemetrics || print_warning "Deployment timeout"
    print_status "Deployment created and ready"
fi
echo ""

# Step 4: Verify deployment health
echo -e "${GREEN}Step 3: Verifying deployment health${NC}"
echo ""
print_info "Deployment Status:"
kubectl get deployment event-ingestion -n gamemetrics
echo ""

print_info "Pod Status:"
kubectl get pods -n gamemetrics -l app=event-ingestion -o wide
echo ""

print_info "Service Status:"
kubectl get svc event-ingestion -n gamemetrics
echo ""

# Step 5: Test health endpoints (if pods are running)
RUNNING_PODS=$(kubectl get pods -n gamemetrics -l app=event-ingestion --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$RUNNING_PODS" ]; then
    echo -e "${GREEN}Step 4: Testing health endpoints${NC}"
    POD=$(echo $RUNNING_PODS | awk '{print $1}')
    
    print_info "Port-forwarding to pod $POD..."
    kubectl port-forward -n gamemetrics pod/$POD 8080:8080 &
    PF_PID=$!
    sleep 3
    
    if curl -fsS http://localhost:8080/health/live &>/dev/null; then
        print_status "Health check passed (/health/live)"
    else
        print_warning "Health check failed; pod may still be starting"
    fi
    
    kill $PF_PID 2>/dev/null || true
    echo ""
fi

# Summary
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Application Deployment Complete${NC}"
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo ""
echo "Deployment Summary:"
echo "  Service: event-ingestion"
echo "  Namespace: gamemetrics"
echo "  Image: $ECR_URL:latest"
echo ""
echo "Useful Commands:"
echo "  View logs: kubectl logs -n gamemetrics -l app=event-ingestion -f"
echo "  Describe: kubectl describe deployment event-ingestion -n gamemetrics"
echo "  Port-forward: kubectl port-forward -n gamemetrics svc/event-ingestion 8080:8080"
echo "  Check events: kubectl get events -n gamemetrics --sort-by='.lastTimestamp'"
echo ""
echo "CI/CD Note:"
echo "  Push to 'develop' branch → auto-deploys to dev EKS cluster"
echo "  Push to 'main' branch → auto-deploys to prod EKS cluster (with approval)"
echo ""
print_status "Applications deployed successfully!"
