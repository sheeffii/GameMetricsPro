#!/usr/bin/env bash
set -euo pipefail

REGION=${1:-us-east-1}
REPO_URL=${2:?Usage: build-push-ecr.sh <region> <repo_url> <service_path>}
SERVICE_PATH=${3:-services/event-ingestion-service}

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required" >&2
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_DOMAIN="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Login to ECR
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ECR_DOMAIN}"

# Build image
pushd "${SERVICE_PATH}" >/dev/null
IMAGE_NAME=$(basename "${REPO_URL}")
TAG=${TAG:-latest}
IMAGE_LOCAL_TAG="${IMAGE_NAME}:${TAG}"
IMAGE_REMOTE_TAG="${REPO_URL}:${TAG}"

echo "Building ${IMAGE_LOCAL_TAG} from ${SERVICE_PATH}..."
docker build -t "${IMAGE_LOCAL_TAG}" .

echo "Tagging ${IMAGE_LOCAL_TAG} -> ${IMAGE_REMOTE_TAG}..."
docker tag "${IMAGE_LOCAL_TAG}" "${IMAGE_REMOTE_TAG}"

echo "Pushing ${IMAGE_REMOTE_TAG}..."
docker push "${IMAGE_REMOTE_TAG}"

popd >/dev/null

echo "✔ Pushed ${IMAGE_REMOTE_TAG}"
