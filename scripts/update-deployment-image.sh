#!/usr/bin/env bash
set -euo pipefail

REGION=${1:-us-east-1}
TERRAFORM_DIR=${2:-terraform/environments/dev}
SERVICE_NAME=${3:-event-ingestion-service}
DEPLOYMENT_FILE=${4:-k8s/services/event-ingestion/deployment.yaml}

echo "Fetching ECR repository URL from Terraform..."

cd "${TERRAFORM_DIR}"
ECR_URL=$(terraform output -json ecr_repository_urls | jq -r ".\"${SERVICE_NAME}\"")

if [[ -z "${ECR_URL}" || "${ECR_URL}" == "null" ]]; then
  echo "Error: Could not get ECR URL for ${SERVICE_NAME}" >&2
  exit 1
fi

cd - >/dev/null

echo "ECR URL: ${ECR_URL}:latest"

# Create a temporary file with the updated image
TEMP_FILE=$(mktemp)
sed "s|image:.*${SERVICE_NAME}.*|image: ${ECR_URL}:latest|g" "${DEPLOYMENT_FILE}" > "${TEMP_FILE}"

# Replace the original file
mv "${TEMP_FILE}" "${DEPLOYMENT_FILE}"

echo "✔ Updated ${DEPLOYMENT_FILE} with ECR image URL"
echo ""
echo "To apply changes:"
echo "  kubectl apply -k k8s/services/event-ingestion/"
