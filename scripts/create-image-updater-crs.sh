#!/bin/bash
#
# Helper script to create ImageUpdater CRs from existing ArgoCD Applications
# This converts annotation-based configs to CRD-based configs for v1.0+
#
# Usage: ./create-image-updater-crs.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/../k8s/argocd/image-updaters"

# Create output directory
mkdir -p "$OUTPUT_DIR"

cat << 'EOF' > "$OUTPUT_DIR/event-ingestion-dev.yaml"
apiVersion: argocd-image-updater.argoproj.io/v1alpha1
kind: ImageUpdater
metadata:
  name: event-ingestion-dev
  namespace: argocd-image-updater-system
spec:
  # Reference to ArgoCD Application
  sourceRef:
    kind: Application
    name: event-ingestion-dev
    namespace: argocd
  
  # Images to track
  images:
    - image: 647523695124.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service
      updateStrategy:
        strategy: latest  # Always use latest tag
      # Alternative: semver constraint
      # updateStrategy:
      #   strategy: semver
      #   constraint: ^1.0.0
  
  # Write-back method: update ArgoCD Application directly
  writeBack:
    method: argocd
EOF

cat << 'EOF' > "$OUTPUT_DIR/notification-service-dev.yaml"
apiVersion: argocd-image-updater.argoproj.io/v1alpha1
kind: ImageUpdater
metadata:
  name: notification-service-dev
  namespace: argocd-image-updater-system
spec:
  # Reference to ArgoCD Application
  sourceRef:
    kind: Application
    name: notification-service-dev
    namespace: argocd
  
  # Images to track
  images:
    - image: 647523695124.dkr.ecr.us-east-1.amazonaws.com/notification-service
      updateStrategy:
        strategy: latest  # Always use latest tag
  
  # Write-back method: update ArgoCD Application directly
  writeBack:
    method: argocd
EOF

cat << 'EOF' > "$OUTPUT_DIR/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: argocd-image-updater-system

resources:
  - event-ingestion-dev.yaml
  - notification-service-dev.yaml
EOF

echo "✅ ImageUpdater CRs created in: $OUTPUT_DIR"
echo ""
echo "To apply:"
echo "  kubectl apply -k $OUTPUT_DIR"
echo ""
echo "To verify:"
echo "  kubectl get imageupdaters -n argocd-image-updater-system"
