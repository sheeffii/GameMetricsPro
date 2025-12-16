#!/bin/bash
#
# GameMetrics Pro - Partial Deployment Cleanup Script
# 
# This script helps clean up resources from failed or partial deployments.
# Currently handles ElastiCache clusters that may prevent new deployments.
#
# Usage:
#   ./scripts/cleanup-partial-deploy.sh
#
# Environment Variables:
#   AWS_REGION - AWS region (default: us-east-1)
#
# Note: This script prompts for confirmation before deleting resources.
#

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
