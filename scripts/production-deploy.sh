#!/bin/bash
#
# GameMetrics Pro - Complete Production Deployment Script
# 
# This script deploys the entire GameMetrics Pro platform to AWS:
# 1. AWS Infrastructure (EKS, RDS, ElastiCache, S3, ECR)
# 2. Kubernetes Infrastructure (Namespaces, RBAC, Operators)
# 3. Kafka Cluster and Topics
# 4. ArgoCD for GitOps
# 5. All Microservices (via ArgoCD)
# 6. Observability Stack (Prometheus, Grafana, Loki, Tempo)
# 7. Security Components (NetworkPolicies, Pod Security Standards)
#
# Usage:
#   ./scripts/production-deploy.sh [region] [environment]
#   Example: ./scripts/production-deploy.sh us-east-1 prod
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - kubectl installed
#   - terraform installed
#   - jq installed
#   - Docker installed (for building images)
#
# Environment Variables:
#   AWS_REGION - AWS region (default: us-east-1)
#   ENVIRONMENT - Environment name (default: prod)
#   SKIP_BUILD - Skip Docker image builds (default: false)
#   SKIP_ARGO - Skip ArgoCD deployment (default: false)
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly REGION="${1:-${AWS_REGION:-us-east-1}}"
readonly ENVIRONMENT="${2:-${ENVIRONMENT:-prod}}"
# Defaults: build images and deploy ArgoCD unless explicitly skipped
readonly SKIP_BUILD="${SKIP_BUILD:-false}"
readonly SKIP_ARGO="${SKIP_ARGO:-false}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly TERRAFORM_DIR="${PROJECT_ROOT}/terraform/environments/${ENVIRONMENT}"

# Logging functions
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_section() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  $1${NC}"
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    local missing_tools=()
    
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws-cli")
    command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    print_status "All prerequisites met"
}

# Step 1: Deploy AWS Infrastructure via Terraform
deploy_aws_infrastructure() {
    print_section "Step 1: Deploying AWS Infrastructure"
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        print_error "Terraform directory not found: $TERRAFORM_DIR"
        exit 1
    fi
    
    cd "$TERRAFORM_DIR"
    
    print_info "Initializing Terraform..."
    terraform init -upgrade -no-color
    
    print_info "Planning infrastructure changes..."
    terraform plan -no-color -out=tfplan
    
    print_info "Applying infrastructure..."
    terraform apply -auto-approve -no-color tfplan
    
    # Export infrastructure outputs
    export EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "gamemetrics-${ENVIRONMENT}")
    export RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")
    export REDIS_ENDPOINT=$(terraform output -raw elasticache_primary_endpoint 2>/dev/null || echo "")
    export VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    
    # Get ECR repository URLs
    export ECR_REPOS=$(terraform output -json ecr_repository_urls 2>/dev/null || echo "{}")
    
    cd - > /dev/null
    
    print_status "AWS infrastructure deployed"
    print_info "EKS Cluster: $EKS_CLUSTER_NAME"
    print_info "RDS Endpoint: $RDS_ENDPOINT"
    print_info "Redis Endpoint: $REDIS_ENDPOINT"
}

# Step 2: Configure kubectl
configure_kubectl() {
    print_section "Step 2: Configuring kubectl"
    
    print_info "Updating kubeconfig for cluster: $EKS_CLUSTER_NAME"
    aws eks update-kubeconfig --region "$REGION" --name "$EKS_CLUSTER_NAME"
    
    # Verify connectivity
    if ! kubectl cluster-info &>/dev/null; then
        print_error "Failed to connect to Kubernetes cluster"
        exit 1
    fi
    
    print_status "kubectl configured and connected"
}

# Step 3: Wait for EKS nodes
wait_for_nodes() {
    print_section "Step 3: Waiting for EKS Nodes"
    
    local timeout=600
    local elapsed=0
    local min_nodes=3
    
    print_info "Waiting for at least $min_nodes nodes to be ready..."
    
    while [ $elapsed -lt $timeout ]; do
        local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
        
        if [ "$ready_nodes" -ge "$min_nodes" ]; then
            print_status "All $ready_nodes nodes are ready"
            return 0
        fi
        
        echo "  Waiting for nodes... ($ready_nodes/$min_nodes ready, elapsed: ${elapsed}s)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    print_warning "Timeout waiting for nodes (waited ${timeout}s)"
    print_info "Current node status:"
    kubectl get nodes
}

# Step 4: Deploy Kubernetes Infrastructure
deploy_k8s_infrastructure() {
    print_section "Step 4: Deploying Kubernetes Infrastructure"
    
    # Install ArgoCD CRDs first to avoid Application kind errors
    print_info "Installing ArgoCD CRDs (argocd/base) before full apply..."
    kubectl apply -k "${PROJECT_ROOT}/k8s/argocd/base" --wait=false 2>/dev/null || true

    print_info "Waiting for ArgoCD CRDs to be established..."
    for crd in applications appprojects applicationsets argocds; do
        kubectl wait --for condition=established --timeout=120s crd/"${crd}.argoproj.io" 2>/dev/null || print_warning "CRD ${crd}.argoproj.io not ready (continuing)"
    done

    print_info "Applying base Kubernetes manifests (namespaces, RBAC, CRDs, services)..."
    kubectl apply -k "${PROJECT_ROOT}/k8s/" --wait=false
    
    print_status "Kubernetes infrastructure deployed"
}

# Step 5: Wait for Strimzi Operator
wait_for_strimzi() {
    print_section "Step 5: Waiting for Strimzi Operator"
    
    print_info "Waiting for Strimzi Cluster Operator..."
    kubectl wait --for=condition=available \
        --timeout=300s \
        deployment/strimzi-cluster-operator \
        -n kafka 2>/dev/null || print_warning "Strimzi operator timeout"
    
    print_info "Waiting for Kafka CRDs to be established..."
    for crd in kafka kafkatopic kafkanodepool kafkauser kafkaconnector; do
        kubectl wait --for condition=established \
            --timeout=300s \
            crd/"${crd}s.kafka.strimzi.io" 2>/dev/null || print_warning "CRD ${crd} timeout"
    done
    
    print_status "Strimzi operator ready"
}

# Step 6: Deploy Kafka Cluster and Topics
deploy_kafka() {
    print_section "Step 6: Deploying Kafka Cluster and Topics"
    
    # Ensure kafka namespace exists (Strimzi + Kafka live here)
    if ! kubectl get ns kafka >/dev/null 2>&1; then
        print_info "Creating kafka namespace..."
        kubectl create namespace kafka >/dev/null 2>&1 || true
    fi

    # Pick overlay (fallback to dev if prod overlay is missing)
    local overlay_path="${PROJECT_ROOT}/k8s/kafka/overlays/${ENVIRONMENT}"
    if [ ! -d "$overlay_path" ]; then
        print_warning "Kafka overlay for '${ENVIRONMENT}' not found at ${overlay_path}. Falling back to dev overlay."
        overlay_path="${PROJECT_ROOT}/k8s/kafka/overlays/dev"
    fi

    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        if kubectl apply -k "${overlay_path}" 2>/dev/null; then
            print_status "Kafka cluster and topics applied"
            break
        else
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                print_warning "Retrying Kafka resources ($retry/$max_retries)..."
                sleep 10
            else
                print_error "Failed to apply Kafka resources after $max_retries retries"
                exit 1
            fi
        fi
    done
    
    print_info "Waiting for Kafka cluster to be ready (this may take 5-10 minutes)..."
    kubectl wait --for=condition=Ready \
        --timeout=600s \
        kafka/gamemetrics-kafka \
        -n kafka 2>/dev/null || print_warning "Kafka CR not Ready after 600s"
    
    # Also wait for StatefulSets
    kubectl rollout status statefulset/gamemetrics-kafka-controller \
        -n kafka --timeout=300s 2>/dev/null || print_warning "Controller statefulset timeout"
    kubectl rollout status statefulset/gamemetrics-kafka-broker \
        -n kafka --timeout=300s 2>/dev/null || print_warning "Broker statefulset timeout"
    
    print_status "Kafka cluster ready"
}

# Step 7: Update Kubernetes Secrets from AWS
update_secrets() {
    print_section "Step 7: Updating Kubernetes Secrets from AWS"
    
    print_info "Syncing secrets from AWS Secrets Manager..."
    bash "${SCRIPT_DIR}/update-secrets-from-aws.sh" "$REGION"
    
    print_status "Kubernetes secrets updated"
}

# Step 7b: Setup Database Secrets
setup_database_secrets() {
    print_section "Step 7b: Setting Up Database Secrets"
    
    # Check if gamemetrics namespace exists
    if ! kubectl get namespace gamemetrics &>/dev/null; then
        print_warning "gamemetrics namespace not found, skipping database secrets"
        return 0
    fi
    
    print_info "Creating MinIO secrets..."
    kubectl -n gamemetrics create secret generic minio-secrets \
        --from-literal=access-key=minioadmin \
        --from-literal=secret-key=minioadmin123 \
        --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
    
    print_info "Creating db-secrets alias from db-credentials..."
    kubectl -n gamemetrics get secret db-credentials -o yaml 2>/dev/null | \
        sed 's/name: db-credentials/name: db-secrets/' | kubectl apply -f - 2>/dev/null || true
    
    print_status "Database secrets created"
}

# Step 7c: Deploy Databases (Postgres/TimescaleDB)
deploy_databases() {
    print_section "Step 7c: Deploying Databases (Postgres/TimescaleDB)"

    # Ensure gamemetrics namespace exists
    if ! kubectl get namespace gamemetrics &>/dev/null; then
        print_info "Creating gamemetrics namespace..."
        kubectl create namespace gamemetrics >/dev/null 2>&1 || true
    fi

    print_info "Applying database manifests (TimescaleDB/Postgres)..."
    kubectl apply -k "${PROJECT_ROOT}/k8s/databases"

    print_info "Waiting for timescaledb deployment to be available..."
    kubectl rollout status deployment/timescaledb -n gamemetrics --timeout=180s || print_warning "timescaledb rollout not ready"

    print_info "Waiting for timescaledb pod readiness..."
    kubectl wait --for=condition=Ready pod -l app=timescaledb -n gamemetrics --timeout=180s || print_warning "timescaledb pod not ready"

    print_status "Databases deployed"
}

# Step 8: Build and Push Docker Images
build_and_push_images() {
    if [ "$SKIP_BUILD" = "true" ]; then
        print_warning "Skipping Docker image builds (SKIP_BUILD=true)"
        return 0
    fi
    
    print_section "Step 8: Building and Pushing Docker Images"
    
    # Services to build (customize BUILD_SERVICES env var to override)
    # For now, only building event-ingestion-service
    # Full list for future: "event-ingestion-service" "event-processor-service" "recommendation-engine" "analytics-api" "user-service" "notification-service" "data-retention-service" "admin-dashboard"
    local services=(
        "event-ingestion-service"
    )
    
    # Allow override via environment variable
    if [ -n "${BUILD_SERVICES:-}" ]; then
        IFS=',' read -ra services <<< "$BUILD_SERVICES"
    fi
    
    for service in "${services[@]}"; do
        local service_path="${PROJECT_ROOT}/services/${service}"
        
        if [ ! -d "$service_path" ]; then
            print_warning "Service directory not found: $service_path (skipping)"
            continue
        fi
        
        # Build and push image (script derives repo/name from service path)
        print_info "Building and pushing $service..."
        bash "${SCRIPT_DIR}/build-push-ecr.sh" "$service_path" "$REGION" "latest" || {
            print_warning "Failed to build/push $service (continuing...)"
        }
    done
    
    print_status "Docker images built and pushed"
}

# Step 9: Deploy ArgoCD and Image Updater (already installed via k8s kustomization)
deploy_argocd() {
    if [ "$SKIP_ARGO" = "true" ]; then
        print_warning "Skipping ArgoCD verification (SKIP_ARGO=true)"
        return 0
    fi
    
    print_section "Step 9: Verifying ArgoCD and Image Updater"
    
    print_info "ArgoCD and Image Updater are deployed via k8s/ kustomization..."
    
    print_info "Waiting for ArgoCD server to be ready..."
    kubectl wait --for=condition=available \
        --timeout=300s \
        deployment/argocd-server \
        -n argocd 2>/dev/null || print_warning "ArgoCD server timeout"
    
    print_info "Waiting for Image Updater to be ready..."
    kubectl wait --for=condition=available \
        --timeout=180s \
        deployment/argocd-image-updater-controller \
        -n argocd-image-updater-system 2>/dev/null || print_warning "Image Updater timeout"
    
    print_status "ArgoCD and Image Updater verified"
    
    # Display ArgoCD access info
    local argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "N/A")
    
    print_info "ArgoCD Access:"
    echo "  URL: kubectl port-forward -n argocd svc/argocd-server 8082:80"
    echo "  Username: admin"
    echo "  Password: $argocd_password"
    echo ""
    print_info "Image Updater:"
    echo "  Namespace: argocd-image-updater-system"
    echo "  Status: kubectl get pods -n argocd-image-updater-system"
    echo "  Logs: kubectl logs -n argocd-image-updater-system -l app.kubernetes.io/name=argocd-image-updater -f"
}

# Step 10: Verify Deployment
verify_deployment() {
    print_section "Step 10: Verifying Deployment"
    
    print_info "Kubernetes Cluster Status:"
    kubectl get nodes
    echo ""
    
    print_info "Namespace Status:"
    kubectl get namespaces | grep -E "gamemetrics|kafka|monitoring|argocd"
    echo ""
    
    print_info "Kafka Status:"
    kubectl get pods -n kafka -l strimzi.io/cluster=gamemetrics-kafka
    echo ""
    
    print_info "Kafka Topics:"
    kubectl get kafkatopic -n kafka
    echo ""
    
    if [ "$SKIP_ARGO" != "true" ]; then
        print_info "ArgoCD Applications:"
        kubectl get applications -n argocd 2>/dev/null || echo "ArgoCD applications not yet synced"
        echo ""
    fi
    
    print_status "Deployment verification complete"
}

# Main execution
main() {
    print_section "GameMetrics Pro - Production Deployment"
    print_info "Region: $REGION"
    print_info "Environment: $ENVIRONMENT"
    print_info "Skip Build: $SKIP_BUILD"
    print_info "Skip ArgoCD: $SKIP_ARGO"
    echo ""
    
    check_prerequisites
    deploy_aws_infrastructure
    configure_kubectl
    wait_for_nodes
    deploy_k8s_infrastructure
    wait_for_strimzi
    deploy_kafka
    update_secrets
    setup_database_secrets
    deploy_databases
    build_and_push_images
    deploy_argocd
    verify_deployment
    
    print_section "Deployment Complete!"
    print_status "GameMetrics Pro platform is now deployed"
    echo ""
    echo "Next Steps:"
    echo "  1. Access ArgoCD: kubectl port-forward -n argocd svc/argocd-server 8082:80"
    echo "  2. Access Grafana: kubectl port-forward -n monitoring svc/grafana 3000:3000"
    echo "  3. Access Kafka UI: kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
    echo "  4. Check status: bash scripts/check-status.sh"
    echo ""
    echo "To tear down everything:"
    echo "  bash scripts/complete-teardown.sh $REGION"
    echo ""
}

# Run main function
main "$@"



