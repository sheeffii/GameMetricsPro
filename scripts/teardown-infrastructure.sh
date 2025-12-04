#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

REGION="${AWS_REGION:-us-east-1}"
TERRAFORM_DIR="terraform/environments/dev"

echo -e "${YELLOW}=== GameMetrics Infrastructure Teardown ===${NC}"
echo ""

print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Step 1: Delete Kubernetes resources
echo -e "${YELLOW}Step 1: Deleting Kubernetes resources${NC}"
if kubectl get namespace kafka &> /dev/null; then
    echo "Deleting all applications..."
    kubectl delete deployment --all -n gamemetrics --timeout=60s --ignore-not-found=true
    kubectl delete deployment --all -n kafka --timeout=60s --ignore-not-found=true
    
    echo "Waiting for pods to terminate..."
    sleep 10
    
    echo "Deleting Kafka cluster..."
    kubectl delete kafka --all -n kafka --timeout=120s --ignore-not-found=true
    
    echo "Deleting Strimzi operator..."
    kubectl delete deployment strimzi-cluster-operator -n kafka --timeout=60s --ignore-not-found=true
    
    echo "Deleting ArgoCD..."
    kubectl delete namespace argocd --timeout=60s --ignore-not-found=true
    
    echo "Waiting for all pods to terminate..."
    sleep 20
    
    print_status "Kubernetes resources deleted"
else
    print_warning "Kafka namespace not found, skipping K8s cleanup"
fi
echo ""

# Step 1.5: Clean up ENIs and Load Balancers
echo -e "${YELLOW}Step 1.5: Cleaning up network interfaces and load balancers${NC}"
CLUSTER_NAME=$(cd "$TERRAFORM_DIR" && terraform output -raw eks_cluster_name 2>/dev/null || echo "gamemetrics-dev")

# Delete Load Balancers tagged with cluster
echo "Finding load balancers for cluster: $CLUSTER_NAME"
LB_ARNS=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?contains(LoadBalancerName, 'k8s')].LoadBalancerArn" --output text 2>/dev/null || true)
for lb_arn in $LB_ARNS; do
    echo "Deleting load balancer: $lb_arn"
    aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" --region "$REGION" 2>/dev/null || true
done

# Delete target groups
TG_ARNS=$(aws elbv2 describe-target-groups --region "$REGION" --query "TargetGroups[?contains(TargetGroupName, 'k8s')].TargetGroupArn" --output text 2>/dev/null || true)
for tg_arn in $TG_ARNS; do
    echo "Deleting target group: $tg_arn"
    aws elbv2 delete-target-group --target-group-arn "$tg_arn" --region "$REGION" 2>/dev/null || true
done

# Delete unattached ENIs
echo "Finding and deleting unattached ENIs..."
sleep 10
ENI_IDS=$(aws ec2 describe-network-interfaces --region "$REGION" --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' --output text 2>/dev/null || true)
for eni in $ENI_IDS; do
    echo "Deleting ENI: $eni"
    aws ec2 delete-network-interface --network-interface-id "$eni" --region "$REGION" 2>/dev/null || true
done

print_status "Network cleanup complete"
echo ""

# Step 2: Disable RDS deletion protection
echo -e "${YELLOW}Step 2: Disabling RDS deletion protection${NC}"
cd "$TERRAFORM_DIR"
RDS_IDENTIFIER=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "gamemetrics-dev")

if aws rds describe-db-instances --db-instance-identifier "$RDS_IDENTIFIER" --region "$REGION" &> /dev/null; then
    aws rds modify-db-instance \
        --db-instance-identifier "$RDS_IDENTIFIER" \
        --no-deletion-protection \
        --apply-immediately \
        --region "$REGION" &> /dev/null || true
    print_status "RDS deletion protection disabled"
    sleep 5
else
    print_warning "RDS instance not found"
fi
echo ""

# Step 3: Empty S3 buckets
echo -e "${YELLOW}Step 3: Emptying S3 buckets${NC}"
BUCKETS=$(aws s3 ls | grep "gamemetrics.*-dev" | awk '{print $3}' || true)
for bucket in $BUCKETS; do
    echo "Emptying bucket: $bucket"
    aws s3 rm "s3://$bucket" --recursive --region "$REGION" 2>/dev/null || true
done
print_status "S3 buckets emptied"
echo ""

# Step 4: Force delete secrets
echo -e "${YELLOW}Step 4: Deleting Secrets Manager secrets${NC}"
SECRET_IDS=$(aws secretsmanager list-secrets --region "$REGION" --query 'SecretList[?contains(Name, `gamemetrics-dev`)].Name' --output text || true)
for secret in $SECRET_IDS; do
    echo "Deleting secret: $secret"
    aws secretsmanager delete-secret \
        --secret-id "$secret" \
        --force-delete-without-recovery \
        --region "$REGION" 2>/dev/null || true
done
print_status "Secrets deleted"
echo ""

# Step 4.5: Empty ECR repositories
echo -e "${YELLOW}Step 4.5: Emptying ECR repositories${NC}"
ECR_REPOS=$(aws ecr describe-repositories --region "$REGION" --query 'repositories[?contains(repositoryName, `event-ingestion`)].repositoryName' --output text 2>/dev/null || true)
for repo in $ECR_REPOS; do
    echo "Emptying ECR repository: $repo"
    IMAGE_IDS=$(aws ecr list-images --repository-name "$repo" --region "$REGION" --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
    if [ "$IMAGE_IDS" != "[]" ]; then
        aws ecr batch-delete-image --repository-name "$repo" --region "$REGION" --image-ids "$IMAGE_IDS" 2>/dev/null || true
    fi
done
print_status "ECR repositories emptied"
echo ""

# Step 5: Destroy Terraform infrastructure
echo -e "${YELLOW}Step 5: Destroying Terraform infrastructure${NC}"
terraform destroy -auto-approve

cd - > /dev/null
print_status "Infrastructure destroyed"
echo ""

echo -e "${GREEN}=== Teardown Complete ===${NC}"
echo ""
print_status "All resources have been cleaned up!"
