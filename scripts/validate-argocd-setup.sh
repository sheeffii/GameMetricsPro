#!/bin/bash
#
# Validation script to test ArgoCD and Image Updater installation
# Run this after bootstrap to ensure everything is working correctly
#
# Usage: ./validate-argocd-setup.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; PASSED=$((PASSED + 1)); }
log_fail() { echo -e "${RED}[✗]${NC} $1"; FAILED=$((FAILED + 1)); }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

echo "=========================================="
echo "ArgoCD Setup Validation"
echo "=========================================="
echo ""

# Test 1: kubectl connectivity
log_info "Checking kubectl connectivity..."
if kubectl cluster-info &> /dev/null; then
    log_success "kubectl can connect to cluster"
else
    log_fail "kubectl cannot connect to cluster"
fi

# Test 2: ArgoCD namespace exists
log_info "Checking ArgoCD namespace..."
if kubectl get namespace argocd &> /dev/null; then
    log_success "ArgoCD namespace exists"
else
    log_fail "ArgoCD namespace not found"
fi

# Test 3: ArgoCD pods running
log_info "Checking ArgoCD pods..."
ARGOCD_PODS=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
ARGOCD_RUNNING=$(kubectl get pods -n argocd --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$ARGOCD_PODS" -gt 0 ] && [ "$ARGOCD_RUNNING" -eq "$ARGOCD_PODS" ]; then
    log_success "All ArgoCD pods are running ($ARGOCD_RUNNING/$ARGOCD_PODS)"
else
    log_fail "ArgoCD pods not all running ($ARGOCD_RUNNING/$ARGOCD_PODS)"
    kubectl get pods -n argocd
fi

# Test 4: ArgoCD server deployment
log_info "Checking ArgoCD server deployment..."
if kubectl get deployment argocd-server -n argocd &> /dev/null; then
    REPLICAS=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.availableReplicas}')
    if [ "$REPLICAS" -gt 0 ]; then
        log_success "ArgoCD server is available"
    else
        log_fail "ArgoCD server is not available"
    fi
else
    log_fail "ArgoCD server deployment not found"
fi

# Test 5: ArgoCD admin secret exists
log_info "Checking ArgoCD admin secret..."
if kubectl get secret argocd-initial-admin-secret -n argocd &> /dev/null; then
    log_success "ArgoCD admin secret exists"
else
    log_warning "ArgoCD admin secret not found (may have been deleted)"
fi

# Test 6: Image Updater namespace
log_info "Checking Image Updater namespace..."
if kubectl get namespace argocd-image-updater-system &> /dev/null; then
    log_success "Image Updater namespace exists"
else
    log_fail "Image Updater namespace not found"
fi

# Test 7: Image Updater pods
log_info "Checking Image Updater pods..."
IU_PODS=$(kubectl get pods -n argocd-image-updater-system --no-headers 2>/dev/null | wc -l)
IU_RUNNING=$(kubectl get pods -n argocd-image-updater-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$IU_PODS" -gt 0 ] && [ "$IU_RUNNING" -eq "$IU_PODS" ]; then
    log_success "Image Updater pod is running ($IU_RUNNING/$IU_PODS)"
else
    log_fail "Image Updater pod not running ($IU_RUNNING/$IU_PODS)"
    kubectl get pods -n argocd-image-updater-system
fi

# Test 8: Image Updater CRD
log_info "Checking ImageUpdater CRD..."
if kubectl get crd imageupdaters.argocd-image-updater.argoproj.io &> /dev/null; then
    log_success "ImageUpdater CRD is installed"
else
    log_fail "ImageUpdater CRD not found"
fi

# Test 9: Image Updater ConfigMap
log_info "Checking Image Updater configuration..."
if kubectl get configmap argocd-image-updater-config -n argocd-image-updater-system &> /dev/null; then
    log_success "Image Updater ConfigMap exists"
    
    # Check for ECR config
    if kubectl get configmap argocd-image-updater-config -n argocd-image-updater-system -o yaml | grep -q "647523695124.dkr.ecr"; then
        log_success "ECR registry configured"
    else
        log_warning "ECR registry may not be configured"
    fi
else
    log_fail "Image Updater ConfigMap not found"
fi

# Test 10: ArgoCD Applications
log_info "Checking ArgoCD Applications..."
APP_COUNT=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
if [ "$APP_COUNT" -gt 0 ]; then
    log_success "Found $APP_COUNT ArgoCD Application(s)"
    kubectl get applications -n argocd --no-headers | while read -r line; do
        APP_NAME=$(echo "$line" | awk '{print $1}')
        SYNC_STATUS=$(echo "$line" | awk '{print $2}')
        HEALTH_STATUS=$(echo "$line" | awk '{print $3}')
        echo "  - $APP_NAME: Sync=$SYNC_STATUS, Health=$HEALTH_STATUS"
    done
else
    log_warning "No ArgoCD Applications found (this may be expected)"
fi

# Test 11: ArgoCD project
log_info "Checking ArgoCD project..."
if kubectl get appproject gamemetrics -n argocd &> /dev/null; then
    log_success "ArgoCD project 'gamemetrics' exists"
else
    log_warning "ArgoCD project 'gamemetrics' not found"
fi

# Test 12: RBAC for Image Updater
log_info "Checking Image Updater RBAC..."
if kubectl get clusterrole argocd-image-updater-manager-role &> /dev/null; then
    log_success "Image Updater ClusterRole exists"
else
    log_fail "Image Updater ClusterRole not found"
fi

if kubectl get clusterrolebinding argocd-image-updater-manager-rolebinding &> /dev/null; then
    log_success "Image Updater ClusterRoleBinding exists"
else
    log_fail "Image Updater ClusterRoleBinding not found"
fi

# Test 13: Check Image Updater logs for errors
log_info "Checking Image Updater logs for errors..."
if kubectl get pods -n argocd-image-updater-system --no-headers &> /dev/null; then
    ERROR_COUNT=$(kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater --tail=100 2>/dev/null | grep -i "error\|fatal\|panic" | wc -l)
    if [ "$ERROR_COUNT" -eq 0 ]; then
        log_success "No errors in Image Updater logs"
    else
        log_warning "Found $ERROR_COUNT error lines in Image Updater logs"
    fi
fi

# Test 14: Service connectivity
log_info "Checking ArgoCD server service..."
if kubectl get service argocd-server -n argocd &> /dev/null; then
    log_success "ArgoCD server service exists"
else
    log_fail "ArgoCD server service not found"
fi

# Test 15: Check if gamemetrics namespace exists (for apps)
log_info "Checking application namespace..."
if kubectl get namespace gamemetrics &> /dev/null; then
    log_success "Application namespace 'gamemetrics' exists"
    
    # Check deployments in gamemetrics
    DEPLOY_COUNT=$(kubectl get deployments -n gamemetrics --no-headers 2>/dev/null | wc -l)
    if [ "$DEPLOY_COUNT" -gt 0 ]; then
        log_success "Found $DEPLOY_COUNT deployment(s) in gamemetrics namespace"
    else
        log_info "No deployments in gamemetrics namespace yet"
    fi
else
    log_info "Application namespace 'gamemetrics' not found yet (will be created by ArgoCD)"
fi

# Summary
echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo -e "${GREEN}Passed: $PASSED${NC}"
if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
fi
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! ArgoCD setup looks good.${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Access ArgoCD UI:"
    echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "   Open: https://localhost:8080"
    echo ""
    echo "2. Get admin password:"
    echo "   cat .argocd-credentials"
    echo ""
    echo "3. Build and push an image:"
    echo "   ./scripts/build-push-ecr.sh notification-service"
    echo ""
    echo "4. Monitor Image Updater:"
    echo "   kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater -f"
    exit 0
else
    echo -e "${RED}✗ Some checks failed. Review the output above.${NC}"
    echo ""
    echo "Common fixes:"
    echo "- Wait a few minutes for pods to become ready"
    echo "- Check pod logs: kubectl logs -n <namespace> <pod-name>"
    echo "- Verify cluster has sufficient resources"
    echo "- Re-run bootstrap: ./scripts/bootstrap-argocd.sh dev"
    exit 1
fi
