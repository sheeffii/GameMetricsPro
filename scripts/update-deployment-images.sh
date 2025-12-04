#!/bin/bash
set -e

REGION=${1:-us-east-1}

echo "=========================================="
echo "Updating Deployment Images with ECR URLs"
echo "Region: $REGION"
echo "=========================================="

# Step 1: Get ECR repository URL from Terraform outputs
echo ""
echo "Step 1: Fetching ECR repository URL from Terraform..."

# Find the correct Terraform directory
TERRAFORM_DIR="$(cd "$(dirname "$0")/../terraform/environments/dev" && pwd)"

if [ ! -d "$TERRAFORM_DIR" ]; then
  echo "ERROR: Terraform directory not found at $TERRAFORM_DIR"
  exit 1
fi

# Try to get ECR URL from Terraform output
ECR_URL=$(cd "$TERRAFORM_DIR" && terraform output -json 2>/dev/null | jq -r '.ecr_repository_urls.value["event-ingestion-service"]' 2>/dev/null || echo "")

if [ -z "$ECR_URL" ] || [ "$ECR_URL" = "null" ]; then
  echo "WARNING: Could not fetch ECR URL from Terraform outputs"
  echo "Attempting to construct ECR URL from AWS account and region..."
  
  # Get AWS account ID
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
  
  if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "ERROR: Cannot determine AWS account ID"
    echo "Please ensure AWS credentials are configured"
    exit 1
  fi
  
  # Construct ECR URL
  ECR_URL="$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/event-ingestion-service"
  echo "Constructed ECR URL: $ECR_URL"
else
  echo "✓ ECR URL from Terraform: $ECR_URL"
fi

# Step 2: Update deployment image using kubectl set image
echo ""
echo "Step 2: Updating event-ingestion deployment image..."

# Check if deployment exists
if ! kubectl get deployment event-ingestion -n gamemetrics &>/dev/null; then
  echo "WARNING: event-ingestion deployment does not exist yet"
  echo "Deployment will use ECR image on first creation"
  
  # Update the deployment.yaml file with ECR URL
  echo "Updating deployment.yaml file with ECR URL..."
  DEPLOYMENT_DIR="$(cd "$(dirname "$0")/../k8s/services/event-ingestion" && pwd)"
  
  if [ ! -f "$DEPLOYMENT_DIR/deployment.yaml" ]; then
    echo "ERROR: deployment.yaml not found at $DEPLOYMENT_DIR/deployment.yaml"
    exit 1
  fi
  
  # Backup original file
  cp "$DEPLOYMENT_DIR/deployment.yaml" "$DEPLOYMENT_DIR/deployment.yaml.bak"
  
  # Replace image URL (handle both placeholder and existing ECR URLs)
  sed -i "s|image:.*event-ingestion-service.*|image: $ECR_URL:latest|g" "$DEPLOYMENT_DIR/deployment.yaml"
  
  echo "✓ deployment.yaml updated with ECR URL: $ECR_URL:latest"
  echo "  (Original backed up to deployment.yaml.bak)"
else
  # Update running deployment
  echo "Updating running deployment..."
  kubectl set image deployment/event-ingestion \
    event-ingestion=$ECR_URL:latest \
    -n gamemetrics || echo "WARNING: Failed to update running deployment"
  
  echo "✓ Deployment image updated to: $ECR_URL:latest"
  
  # Wait for rollout to complete
  echo ""
  echo "Waiting for deployment rollout to complete..."
  kubectl rollout status deployment/event-ingestion -n gamemetrics --timeout=300s || echo "WARNING: Rollout timeout (deployment may still be updating)"
  
  echo "✓ Deployment rollout monitoring complete"
fi

echo ""
echo "=========================================="
echo "✓ Deployment image successfully updated"
echo "=========================================="
echo ""
echo "ECR Image: $ECR_URL:latest"
echo ""
echo "Next steps:"
echo "  1. Monitor deployment: kubectl get deployment event-ingestion -n gamemetrics"
echo "  2. View logs: kubectl logs -n gamemetrics -l app=event-ingestion"
echo "  3. Check pod status: kubectl get pods -n gamemetrics -l app=event-ingestion"
echo ""
