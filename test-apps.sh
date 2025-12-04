#!/bin/bash
# Test ArgoCD Applications deployment

echo "=== DEPLOYING APPLICATIONS FRESH ==="
echo

# Deploy event-ingestion-prod first (simplest)
echo "1. Deploying event-ingestion-prod..."
kubectl apply -f k8s/argocd/application-event-ingestion-prod.yaml
sleep 5
echo "Status:"
kubectl get application event-ingestion-prod -n argocd -o jsonpath='{.spec.source.path} | {.spec.source.targetRevision} | {.status.sync.status}'
echo
echo

# Deploy kafka-prod
echo "2. Deploying kafka-prod..."
kubectl apply -f k8s/argocd/application-kafka-prod.yaml
sleep 5
echo "Status:"
kubectl get application kafka-prod -n argocd -o jsonpath='{.spec.source.path} | {.spec.source.targetRevision} | {.status.sync.status}'
echo
echo

# Deploy event-ingestion-dev
echo "3. Deploying event-ingestion-dev..."
kubectl apply -f k8s/argocd/application-event-ingestion-dev.yaml
sleep 5
echo "Status:"
kubectl get application event-ingestion-dev -n argocd -o jsonpath='{.spec.source.path} | {.spec.source.targetRevision} | {.status.sync.status}'
echo
echo

# Deploy kafka-dev
echo "4. Deploying kafka-dev..."
kubectl apply -f k8s/argocd/application-kafka-dev.yaml
sleep 5
echo "Status:"
kubectl get application kafka-dev -n argocd -o jsonpath='{.spec.source.path} | {.spec.source.targetRevision} | {.status.sync.status}'
echo
echo

# Final summary
echo "=== FINAL STATUS ==="
kubectl get applications -n argocd -o wide
