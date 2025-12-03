#!/usr/bin/env bash
set -euo pipefail

REGION=${1:-us-east-1}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==================================================================="
echo "  GameMetrics - Complete Application Deployment"
echo "==================================================================="
echo ""

cd "${PROJECT_ROOT}"

# Step 1: Update secrets from AWS
echo "1️⃣  Updating Kubernetes secrets from AWS Secrets Manager..."
bash scripts/update-secrets.sh "${REGION}"
echo ""

# Step 2: Get ECR URL and update deployment
echo "2️⃣  Updating deployment with ECR image URL..."
bash scripts/update-deployment-image.sh "${REGION}"
echo ""

# Step 3: Build and push Docker image
echo "3️⃣  Building and pushing Docker image to ECR..."
ECR_URL=$(cd terraform/environments/dev && terraform output -json ecr_repository_urls | jq -r '.["event-ingestion-service"]')
bash scripts/build-push-ecr.sh "${REGION}" "${ECR_URL}" services/event-ingestion-service
echo ""

# Step 4: Deploy application
echo "4️⃣  Deploying application to Kubernetes..."
kubectl apply -k k8s/services/event-ingestion/
echo ""

# Step 5: Wait for deployment
echo "5️⃣  Waiting for deployment to be ready..."
kubectl rollout status deployment/event-ingestion -n gamemetrics --timeout=120s
echo ""

# Step 6: Show status
echo "==================================================================="
echo "  Deployment Complete!"
echo "==================================================================="
echo ""
echo "Pod Status:"
kubectl get pods -n gamemetrics -l app=event-ingestion
echo ""
echo "Service Endpoints:"
echo "  Event Ingestion API: kubectl port-forward -n gamemetrics svc/event-ingestion 8081:80"
echo "  Kafka UI:            kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
echo "  ArgoCD:              kubectl port-forward -n argocd svc/argocd-server 8082:80"
echo ""
echo "ArgoCD Credentials:"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "N/A")
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "Test Commands:"
echo "  curl http://localhost:8081/health/live"
echo "  curl http://localhost:8081/health/ready"
echo ""
