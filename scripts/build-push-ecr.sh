#!/usr/bin/env bash
#
# GameMetrics Pro - Docker Image Build and Push Script
# 
# This script builds a Docker image for a service and pushes it to AWS ECR:
# 1. Authenticates with AWS ECR
# 2. Auto-detects service name from path or uses provided name
# 3. Creates ECR repository if it doesn't exist
# 4. Builds Docker image from service directory
# 5. Tags image with ECR repository URL
# 6. Pushes image to ECR
#
# Usage:
#   ./scripts/build-push-ecr.sh <service_path> [region] [tag]
#   Example: ./scripts/build-push-ecr.sh services/event-ingestion-service
#   Example: ./scripts/build-push-ecr.sh services/notification-service us-east-1 dev-001
#
# Prerequisites:
#   - AWS CLI configured
#   - Docker installed and running
#

set -euo pipefail

SERVICE_PATH=${1:?Usage: build-push-ecr.sh <service_path> [region] [tag]}
REGION=${2:-us-east-1}
TAG=${3:-latest}

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required" >&2
  exit 1
fi

# Auto-detect service name from path
SERVICE_NAME=$(basename "${SERVICE_PATH}")
echo "Service: ${SERVICE_NAME}"
echo "Path: ${SERVICE_PATH}"
echo "Region: ${REGION}"
echo "Tag: ${TAG}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_DOMAIN="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
REPO_NAME="${SERVICE_NAME}"
REPO_URL="${ECR_DOMAIN}/${REPO_NAME}"

# Create ECR repository if it doesn't exist
echo "Checking ECR repository ${REPO_NAME}..."
if ! aws ecr describe-repositories --region "${REGION}" --repository-names "${REPO_NAME}" >/dev/null 2>&1; then
  echo "Creating ECR repository ${REPO_NAME}..."
  aws ecr create-repository \
    --region "${REGION}" \
    --repository-name "${REPO_NAME}" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256
  echo "✔ Repository ${REPO_NAME} created"
else
  echo "✔ Repository ${REPO_NAME} exists"
fi

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ECR_DOMAIN}"

# Build image
echo "Building Docker image..."
cd "${SERVICE_PATH}"
IMAGE_LOCAL_TAG="${REPO_NAME}:${TAG}"
IMAGE_REMOTE_TAG="${REPO_URL}:${TAG}"

docker build -t "${IMAGE_LOCAL_TAG}" .

echo "Tagging ${IMAGE_LOCAL_TAG} -> ${IMAGE_REMOTE_TAG}..."
docker tag "${IMAGE_LOCAL_TAG}" "${IMAGE_REMOTE_TAG}"

echo "Pushing ${IMAGE_REMOTE_TAG}..."
docker push "${IMAGE_REMOTE_TAG}"

echo ""
echo "════════════════════════════════════════"
echo "✔ Successfully pushed ${IMAGE_REMOTE_TAG}"
echo "════════════════════════════════════════"
echo ""
echo "To use this image in Kubernetes:"
echo "  Update your deployment YAML with:"
echo "    image: ${IMAGE_REMOTE_TAG}"
