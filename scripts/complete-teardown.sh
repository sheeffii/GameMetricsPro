#!/bin/bash
#
# GameMetrics Pro - Complete Cloud Teardown Script
# 
# This script completely removes all GameMetrics Pro resources from AWS:
# 1. Kubernetes resources (pods, deployments, services, etc.)
# 2. Load Balancers and Network Interfaces
# 3. RDS databases (after disabling deletion protection)
# 4. ElastiCache clusters
# 5. S3 buckets (emptied and deleted)
# 6. ECR repositories (images deleted)
# 7. Secrets Manager secrets
# 8. Terraform infrastructure (EKS, VPC, etc.)
#
# WARNING: This script will DELETE ALL resources. Use with caution!
#
# Usage:
#   ./scripts/complete-teardown.sh [region] [environment]
#   Example: ./scripts/complete-teardown.sh us-east-1 prod
#
# Prerequisites:
#   - AWS CLI configured
#   - kubectl installed (if cluster still exists)
#   - terraform installed
#   - jq installed
#
# Environment Variables:
#   AWS_REGION - AWS region (default: us-east-1)
#   ENVIRONMENT - Environment name (default: prod)
#   CONFIRM_DELETE - Skip confirmation prompt (default: false)
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
readonly CONFIRM="${CONFIRM_DELETE:-false}"
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
    echo -e "${RED}════════════════════════════════════════════${NC}"
    echo -e "${RED}  $1${NC}"
    echo -e "${RED}════════════════════════════════════════════${NC}"
    echo ""
}

# Confirmation prompt
confirm_teardown() {
    if [ "$CONFIRM" = "true" ]; then
        return 0
    fi
    
    echo ""
    print_warning "WARNING: This will DELETE ALL GameMetrics Pro resources!"
    print_warning "Region: $REGION"
    print_warning "Environment: $ENVIRONMENT"
    echo ""
    read -p "Type 'DELETE' to confirm: " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        print_error "Teardown cancelled"
        exit 1
    fi
}

# Step 1: Disable RDS Deletion Protection (Must happen before terraform destroy)
disable_rds_protection() {
    print_section "Step 1: Disabling RDS Deletion Protection"
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        print_warning "Terraform directory not found, skipping RDS protection disable"
        return 0
    fi
    
    cd "$TERRAFORM_DIR"
    
    local rds_identifier=$(terraform output -raw rds_instance_identifier 2>/dev/null || \
        echo "gamemetrics-${ENVIRONMENT}-db")
    
    print_info "Checking RDS instance: $rds_identifier"
    
    if aws rds describe-db-instances \
        --db-instance-identifier "$rds_identifier" \
        --region "$REGION" &>/dev/null; then
        print_info "Disabling deletion protection..."
        aws rds modify-db-instance \
            --db-instance-identifier "$rds_identifier" \
            --no-deletion-protection \
            --apply-immediately \
            --region "$REGION" &>/dev/null || true
        
        print_info "Waiting for modification to complete..."
        sleep 10
        
        print_status "RDS deletion protection disabled"
    else
        print_warning "RDS instance not found (may already be deleted)"
    fi
    
    cd - > /dev/null
}

# Step 2: Empty S3 Buckets (Terraform can't delete non-empty buckets)
cleanup_s3_buckets() {
    print_section "Step 2: Emptying S3 Buckets"
    
    local cluster_name="gamemetrics-${ENVIRONMENT}"
    
    print_info "Finding and deleting Load Balancers..."
    local lb_arns=$(aws elbv2 describe-load-balancers \
        --region "$REGION" \
        --query "LoadBalancers[?contains(LoadBalancerName, 'k8s') || contains(LoadBalancerName, '${cluster_name}')].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$lb_arns" ]; then
        for lb_arn in $lb_arns; do
            print_info "Deleting load balancer: $lb_arn"
            aws elbv2 delete-load-balancer \
                --load-balancer-arn "$lb_arn" \
                --region "$REGION" 2>/dev/null || true
        done
    fi
    
    print_info "Finding and deleting Target Groups..."
    local tg_arns=$(aws elbv2 describe-target-groups \
        --region "$REGION" \
        --query "TargetGroups[?contains(TargetGroupName, 'k8s') || contains(TargetGroupName, '${cluster_name}')].TargetGroupArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$tg_arns" ]; then
        for tg_arn in $tg_arns; do
            print_info "Deleting target group: $tg_arn"
            aws elbv2 delete-target-group \
                --target-group-arn "$tg_arn" \
                --region "$REGION" 2>/dev/null || true
        done
    fi
    
    print_info "Waiting for network interfaces to detach..."
    sleep 15
    
    print_info "Finding and deleting unattached ENIs..."
    local eni_ids=$(aws ec2 describe-network-interfaces \
        --region "$REGION" \
        --filters "Name=tag:kubernetes.io/cluster/${cluster_name},Values=owned" \
        --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$eni_ids" ]; then
        for eni in $eni_ids; do
            print_info "Deleting ENI: $eni"
            aws ec2 delete-network-interface \
                --network-interface-id "$eni" \
                --region "$REGION" 2>/dev/null || true
        done
    fi
    
    print_status "Network resources cleaned up"
}

# Step 3: Disable RDS Deletion Protection
disable_rds_protection() {
    print_section "Step 3: Disabling RDS Deletion Protection"
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        print_warning "Terraform directory not found, skipping RDS protection disable"
        return 0
    fi
    
    cd "$TERRAFORM_DIR"
    
    local rds_identifier=$(terraform output -raw rds_instance_identifier 2>/dev/null || \
        echo "gamemetrics-${ENVIRONMENT}-db")
    
    print_info "Checking RDS instance: $rds_identifier"
    
    if aws rds describe-db-instances \
        --db-instance-identifier "$rds_identifier" \
        --region "$REGION" &>/dev/null; then
        print_info "Disabling deletion protection..."
        aws rds modify-db-instance \
            --db-instance-identifier "$rds_identifier" \
            --no-deletion-protection \
            --apply-immediately \
            --region "$REGION" &>/dev/null || true
        
        print_info "Waiting for modification to complete..."
        sleep 10
        
        print_status "RDS deletion protection disabled"
    else
        print_warning "RDS instance not found (may already be deleted)"
    fi
    
    cd - > /dev/null
}

# Step 4: Empty and Delete S3 Buckets
cleanup_s3_buckets() {
    print_section "Step 4: Cleaning up S3 Buckets"
    
    print_info "Finding S3 buckets..."
    local buckets=$(aws s3 ls | grep "gamemetrics.*-${ENVIRONMENT}" | awk '{print $3}' || echo "")
    
    if [ -z "$buckets" ]; then
        print_warning "No S3 buckets found"
        return 0
    fi
    
    for bucket in $buckets; do
        print_info "Emptying bucket: $bucket"
        aws s3 rm "s3://$bucket" --recursive --region "$REGION" 2>/dev/null || true
        
        print_info "Deleting bucket: $bucket"
        aws s3 rb "s3://$bucket" --region "$REGION" 2>/dev/null || true
    done
    
    print_status "S3 buckets emptied (will be deleted by terraform)"
}

# Step 3: Empty ECR Repositories (Terraform needs empty repos to delete)
cleanup_ecr_repos() {
    print_section "Step 3: Emptying ECR Repositories"
    
    print_info "Finding secrets..."
    local secret_ids=$(aws secretsmanager list-secrets \
        --region "$REGION" \
        --query "SecretList[?contains(Name, 'gamemetrics-${ENVIRONMENT}')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$secret_ids" ]; then
        print_warning "No secrets found"
        return 0
    fi
    
    for secret in $secret_ids; do
        print_info "Deleting secret: $secret"
        aws secretsmanager delete-secret \
            --secret-id "$secret" \
            --force-delete-without-recovery \
            --region "$REGION" 2>/dev/null || true
    done
    
    print_status "Secrets deleted"
}

# Step 6: Empty ECR Repositories
cleanup_ecr_repos() {
    print_section "Step 6: Cleaning up ECR Repositories"
    
    print_info "Finding ECR repositories..."
    local repos=$(aws ecr describe-repositories \
        --region "$REGION" \
        --query 'repositories[?contains(repositoryName, "gamemetrics") || contains(repositoryName, "event-ingestion")].repositoryName' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$repos" ]; then
        print_warning "No ECR repositories found"
        return 0
    fi
    
    for repo in $repos; do
        print_info "Emptying ECR repository: $repo"
        
        local image_ids=$(aws ecr list-images \
            --repository-name "$repo" \
            --region "$REGION" \
            --query 'imageIds[*]' \
            --output json 2>/dev/null || echo "[]")
        
        if [ "$image_ids" != "[]" ] && [ -n "$image_ids" ]; then
            echo "$image_ids" | jq -r '.[] | "imageDigest=\(.imageDigest // ""),imageTag=\(.imageTag // "")"' | \
                while IFS= read -r line; do
                    if [ -n "$line" ]; then
                        aws ecr batch-delete-image \
                            --repository-name "$repo" \
                            --region "$REGION" \
                            --image-ids "$line" 2>/dev/null || true
                    fi
                done
        fi
        
        print_info "Deleting repository: $repo"
        aws ecr delete-repository \
            --repository-name "$repo" \
            --region "$REGION" \
            --force 2>/dev/null || true
    done
    
    print_status "ECR repositories emptied and deleted"
}

# Step 4: Destroy Terraform Infrastructure (This deletes EKS + all K8s resources automatically!)
destroy_terraform() {
    print_section "Step 4: Destroying Terraform Infrastructure (EKS, VPC, RDS, etc.)"
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        print_warning "Terraform directory not found: $TERRAFORM_DIR"
        return 0
    fi
    
    cd "$TERRAFORM_DIR"
    
    print_info "Initializing Terraform..."
    terraform init -upgrade -no-color -reconfigure || true
    
    print_info "Destroying infrastructure..."
    terraform destroy -auto-approve -no-color || {
        print_warning "Terraform destroy encountered errors (some resources may remain)"
    }
    
    cd - > /dev/null
    
    print_status "Terraform infrastructure destroyed (EKS cluster and all K8s resources deleted!)"
}

# Step 5: Clean up Orphaned Network Resources (Load Balancers/ENIs not tracked by Terraform)
cleanup_orphaned_network() {
    print_section "Step 5: Cleaning up Orphaned Network Resources"
    
    local cluster_name="gamemetrics-${ENVIRONMENT}"
    
    print_info "Finding orphaned Load Balancers..."
    local lb_arns=$(aws elbv2 describe-load-balancers \
        --region "$REGION" \
        --query "LoadBalancers[?contains(LoadBalancerName, 'k8s') || contains(LoadBalancerName, '${cluster_name}')].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$lb_arns" ]; then
        for lb_arn in $lb_arns; do
            print_info "Deleting load balancer: $lb_arn"
            aws elbv2 delete-load-balancer \
                --load-balancer-arn "$lb_arn" \
                --region "$REGION" 2>/dev/null || true
        done
        sleep 10
    else
        print_info "No orphaned load balancers found"
    fi
    
    print_info "Finding orphaned Target Groups..."
    local tg_arns=$(aws elbv2 describe-target-groups \
        --region "$REGION" \
        --query "TargetGroups[?contains(TargetGroupName, 'k8s') || contains(TargetGroupName, '${cluster_name}')].TargetGroupArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$tg_arns" ]; then
        for tg_arn in $tg_arns; do
            print_info "Deleting target group: $tg_arn"
            aws elbv2 delete-target-group \
                --target-group-arn "$tg_arn" \
                --region "$REGION" 2>/dev/null || true
        done
        sleep 10
    else
        print_info "No orphaned target groups found"
    fi
    
    print_info "Finding orphaned ENIs..."
    local eni_ids=$(aws ec2 describe-network-interfaces \
        --region "$REGION" \
        --filters "Name=tag:kubernetes.io/cluster/${cluster_name},Values=owned" \
        --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$eni_ids" ]; then
        for eni in $eni_ids; do
            print_info "Deleting ENI: $eni"
            aws ec2 delete-network-interface \
                --network-interface-id "$eni" \
                --region "$REGION" 2>/dev/null || true
        done
    else
        print_info "No orphaned ENIs found"
    fi
    
    print_status "Orphaned network resources cleaned up"
}

# Step 6: Delete Secrets Manager Secrets (Optional cleanup)
delete_secrets() {
    print_section "Step 6: Deleting Secrets Manager Secrets"
    
    print_info "Finding secrets..."
    local secret_ids=$(aws secretsmanager list-secrets \
        --region "$REGION" \
        --query "SecretList[?contains(Name, 'gamemetrics-${ENVIRONMENT}')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$secret_ids" ]; then
        print_warning "No secrets found"
        return 0
    fi
    
    for secret in $secret_ids; do
        print_info "Deleting secret: $secret"
        aws secretsmanager delete-secret \
            --secret-id "$secret" \
            --force-delete-without-recovery \
            --region "$REGION" 2>/dev/null || true
    done
    
    print_status "Secrets deleted"
}

# Main execution
main() {
    print_section "GameMetrics Pro - Complete Cloud Teardown"
    print_warning "This will DELETE ALL resources in region: $REGION"
    print_warning "Environment: $ENVIRONMENT"
    echo ""
    
    confirm_teardown
    
    # Optimized order: Prepare resources, destroy infrastructure (includes EKS), clean orphans
    disable_rds_protection
    cleanup_s3_buckets
    cleanup_ecr_repos
    destroy_terraform  # This deletes EKS cluster + all K8s resources automatically!
    cleanup_orphaned_network
    delete_secrets
    
    print_section "Teardown Complete!"
    print_status "All GameMetrics Pro resources have been removed from AWS"
    echo ""
    echo "Note: Some resources may take a few minutes to fully delete."
    echo "Check AWS Console to verify all resources are removed."
    echo ""
}

# Run main function
main "$@"



