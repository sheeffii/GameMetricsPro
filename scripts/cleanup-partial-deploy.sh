#!/bin/bash
# Cleanup script for partial/failed deployments
set -e

REGION="${AWS_REGION:-us-east-1}"

echo "=== Cleaning up partial deployment resources ==="
echo ""

# Check for ElastiCache
echo "Checking for ElastiCache cluster..."
if aws elasticache describe-replication-groups --replication-group-id gamemetrics-dev --region "$REGION" 2>/dev/null; then
    echo "Found ElastiCache cluster gamemetrics-dev"
    read -p "Delete it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        aws elasticache delete-replication-group \
            --replication-group-id gamemetrics-dev \
            --region "$REGION" \
            --no-retain-primary-cluster
        echo "✓ ElastiCache cluster deletion initiated"
    fi
else
    echo "✓ No ElastiCache cluster found"
fi

echo ""
echo "Cleanup complete! You can now run deploy-infrastructure.sh"
