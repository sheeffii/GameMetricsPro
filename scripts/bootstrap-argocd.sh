#!/bin/bash
#
# Bootstrap script for ArgoCD and ArgoCD Image Updater installation
# This script sets up ArgoCD and Image Updater from scratch in the correct order
#
# Usage: ./bootstrap-argocd.sh [environment]
#   environment: dev, staging, or prod (default: dev)
#

set -e

# Configuration
ENVIRONMENT="${1:-dev}"
ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="v2.9.3"  # Stable version
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    if ! command -v kustomize &> /dev/null; then
        log_warning "kustomize not found. Will use kubectl's built-in kustomize."
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Install ArgoCD
install_argocd() {
    log_info "Installing ArgoCD ${ARGOCD_VERSION}..."
    
    # Create namespace
    if ! kubectl get namespace $ARGOCD_NAMESPACE &> /dev/null; then
        kubectl create namespace $ARGOCD_NAMESPACE
        log_success "Created namespace: $ARGOCD_NAMESPACE"
    else
        log_info "Namespace $ARGOCD_NAMESPACE already exists"
    fi
    
    # Install ArgoCD
    kubectl apply -n $ARGOCD_NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml
    
    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server \
        deployment/argocd-repo-server \
        deployment/argocd-applicationset-controller \
        -n $ARGOCD_NAMESPACE
    
    log_success "ArgoCD installed successfully"
}

# Get ArgoCD admin password
get_argocd_password() {
    log_info "Retrieving ArgoCD admin password..."
    
    PASSWORD=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" | base64 -d)
    
    echo ""
    echo "=========================================="
    echo "ArgoCD Admin Credentials:"
    echo "=========================================="
    echo "Username: admin"
    echo "Password: $PASSWORD"
    echo "=========================================="
    echo ""
    
    # Save to file for reference
    cat > "$PROJECT_ROOT/.argocd-credentials" << EOF
ArgoCD Admin Credentials
Username: admin
Password: $PASSWORD

# Port forward to access:
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Then access at: https://localhost:8080
EOF
    log_info "Credentials saved to .argocd-credentials"
}

# Apply ArgoCD project
apply_argocd_project() {
    log_info "Creating ArgoCD project..."
    
    if [ -f "$PROJECT_ROOT/k8s/argocd/project.yaml" ]; then
        kubectl apply -f "$PROJECT_ROOT/k8s/argocd/project.yaml"
        log_success "ArgoCD project created"
    else
        log_warning "ArgoCD project file not found at k8s/argocd/project.yaml"
    fi
}

# Install ArgoCD Image Updater using Kustomize
install_image_updater() {
    log_info "Installing ArgoCD Image Updater..."
    
    # Check if the kustomization exists
    if [ ! -f "$PROJECT_ROOT/k8s/argocd-image-updater/overlays/$ENVIRONMENT/kustomization.yaml" ]; then
        log_error "Image Updater kustomization not found for environment: $ENVIRONMENT"
        exit 1
    fi
    
    # Apply using kustomize
    kubectl apply -k "$PROJECT_ROOT/k8s/argocd-image-updater/overlays/$ENVIRONMENT"
    
    log_info "Waiting for Image Updater to be ready..."
    sleep 10
    kubectl wait --for=condition=available --timeout=180s \
        deployment/argocd-image-updater-controller \
        -n argocd-image-updater-system || true
    
    log_success "ArgoCD Image Updater installed successfully"
}

# Apply ArgoCD applications
apply_applications() {
    log_info "Applying ArgoCD applications for $ENVIRONMENT environment..."
    
    # Apply root application or app-of-apps if it exists
    if [ -f "$PROJECT_ROOT/k8s/argocd/root-app.yaml" ]; then
        kubectl apply -f "$PROJECT_ROOT/k8s/argocd/root-app.yaml"
        log_success "Root application applied"
    fi
    
    # Apply individual applications
    for app_file in "$PROJECT_ROOT/k8s/argocd/application-"*"-${ENVIRONMENT}.yaml"; do
        if [ -f "$app_file" ]; then
            log_info "Applying $(basename $app_file)..."
            kubectl apply -f "$app_file"
        fi
    done
    
    log_success "ArgoCD applications applied"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    echo ""
    log_info "ArgoCD Pods:"
    kubectl get pods -n $ARGOCD_NAMESPACE
    
    echo ""
    log_info "Image Updater Pods:"
    kubectl get pods -n argocd-image-updater-system
    
    echo ""
    log_info "ArgoCD Applications:"
    kubectl get applications -n $ARGOCD_NAMESPACE
    
    log_success "Installation verification complete"
}

# Display next steps
display_next_steps() {
    echo ""
    echo "=========================================="
    echo "Next Steps:"
    echo "=========================================="
    echo "1. Port-forward ArgoCD UI:"
    echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo ""
    echo "2. Access ArgoCD UI:"
    echo "   https://localhost:8080"
    echo ""
    echo "3. Login with admin credentials (see .argocd-credentials file)"
    echo ""
    echo "4. Monitor Image Updater logs:"
    echo "   kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater -f"
    echo ""
    echo "5. Build and push your service images:"
    echo "   ./scripts/build-push-ecr.sh event-ingestion"
    echo "   ./scripts/build-push-ecr.sh notification-service"
    echo "=========================================="
}

# Main execution
main() {
    log_info "Starting ArgoCD bootstrap for environment: $ENVIRONMENT"
    echo ""
    
    check_prerequisites
    install_argocd
    get_argocd_password
    apply_argocd_project
    install_image_updater
    apply_applications
    verify_installation
    display_next_steps
    
    log_success "ArgoCD bootstrap completed successfully!"
}

# Run main function
main
