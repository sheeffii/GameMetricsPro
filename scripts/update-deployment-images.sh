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
cd "$(dirname "$0")/../terraform"

ECR_URL=$(terraform output -json | jq -r '.ecr_repository_urls.value["event-ingestion-service"]' 2>/dev/null || echo "")

if [ -z "$ECR_URL" ] || [ "$ECR_URL" = "null" ]; then
  echo "ERROR: Failed to get ECR repository URL from Terraform outputs"
  echo "Please ensure Terraform has created the ECR repository first"
  exit 1
fi

echo "✓ ECR URL: $ECR_URL"

# Step 2: Update deployment image using kubectl set image
echo ""
echo "Step 2: Updating event-ingestion deployment image..."

# Check if deployment exists
if ! kubectl get deployment event-ingestion -n gamemetrics &>/dev/null; then
  echo "WARNING: event-ingestion deployment does not exist yet"
  echo "Deployment will use ECR image on first creation"
  
  # Update the deployment.yaml file with ECR URL
  echo "Updating deployment.yaml file with ECR URL..."
  cd "$(dirname "$0")/../k8s/services/event-ingestion"
  
  # Backup original file
  cp deployment.yaml deployment.yaml.bak
  
  # Replace image URL (handle both placeholder and existing ECR URLs)
  sed -i "s|image:.*event-ingestion-service.*|image: $ECR_URL:latest|g" deployment.yaml
  
  echo "✓ deployment.yaml updated with ECR URL: $ECR_URL:latest"
  echo "  (Original backed up to deployment.yaml.bak)"
else
  # Update running deployment
  kubectl set image deployment/event-ingestion \
    event-ingestion=$ECR_URL:latest \
    -n gamemetrics
  
  echo "✓ Deployment image updated to: $ECR_URL:latest"
  
  # Wait for rollout to complete
  echo ""
  echo "Waiting for deployment rollout to complete..."
  kubectl rollout status deployment/event-ingestion -n gamemetrics --timeout=300s
  
  echo "✓ Deployment rollout complete"
fi

echo ""
echo "=========================================="
echo "✓ Deployment image successfully updated"
echo "=========================================="
echo ""
echo "ECR Image: $ECR_URL:latest"
echo ""
