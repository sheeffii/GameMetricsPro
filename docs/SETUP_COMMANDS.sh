#!/bin/bash
# Commands to set up ArgoCD + GitHub Actions GitOps Pipeline

echo "🚀 COMPLETE ARGOCD + GITHUB ACTIONS SETUP"
echo "=========================================="

# Step 1: Initialize Terraform and Create Infrastructure
echo -e "\n✅ STEP 1: Create Infrastructure"
echo "cd terraform/environments/dev"
echo "terraform init"
echo "terraform plan"
echo "terraform apply"
echo "# Wait 15-20 minutes for cluster creation"

# Step 2: Connect to Cluster
echo -e "\n✅ STEP 2: Connect to Kubernetes"
echo "aws eks update-kubeconfig --region us-east-1 --name gamemetrics-dev"
echo "kubectl get nodes"

# Step 3: Install ArgoCD using Kustomize (GitOps native approach)
echo -e "\n✅ STEP 3: Install ArgoCD via Kustomize"
echo "# This uses the official ArgoCD manifests"
echo "kubectl apply -k k8s/argocd/base"
echo ""
echo "# Wait for ArgoCD to be ready"
echo "kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd"

# Step 4: Get ArgoCD Initial Password
echo -e "\n✅ STEP 4: Get ArgoCD Access"
echo "# Get initial admin password"
echo "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "# Port forward to access UI"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "# Access: https://localhost:8080"
echo "# Username: admin"
echo "# Password: (from command above)"

# Step 5: Deploy ArgoCD Project
echo -e "\n✅ STEP 5: Create ArgoCD Project"
echo "kubectl apply -f argocd/projects/gamemetrics-project.yml"

# Step 6: Deploy App-of-Apps (manages all applications)
echo -e "\n✅ STEP 6: Deploy App-of-Apps Pattern"
echo "# This will automatically deploy all your applications"
echo "kubectl apply -f argocd/app-of-apps.yml"
echo ""
echo "# Verify applications"
echo "kubectl get applications -n argocd"

# Step 7: Create Namespaces
echo -e "\n✅ STEP 7: Create Application Namespaces"
echo "kubectl create namespace gamemetrics"
echo "kubectl create namespace kafka"
echo "kubectl create namespace monitoring"

# Step 8: Create Database Secret
echo -e "\n✅ STEP 8: Create Database Secret"
echo "RDS_ENDPOINT=\$(cd terraform/environments/dev && terraform output -raw rds_endpoint)"
echo "RDS_PASSWORD=\$(cd terraform/environments/dev && terraform output -raw rds_password)"
echo ""
echo "kubectl create secret generic db-credentials \\"
echo "  --from-literal=DB_HOST=\$RDS_ENDPOINT \\"
echo "  --from-literal=DB_PORT=5432 \\"
echo "  --from-literal=DB_NAME=gamemetrics \\"
echo "  --from-literal=DB_USER=dbadmin \\"
echo "  --from-literal=DB_PASSWORD=\$RDS_PASSWORD \\"
echo "  -n gamemetrics"

# Step 9: Create Kafka Secret
echo -e "\n✅ STEP 9: Create Kafka Secret"
echo "kubectl create secret generic kafka-credentials \\"
echo "  --from-literal=KAFKA_BOOTSTRAP_SERVERS=kafka-cluster-kafka-bootstrap.kafka:9092 \\"
echo "  --from-literal=KAFKA_SECURITY_PROTOCOL=PLAINTEXT \\"
echo "  -n gamemetrics"

# Step 10: Create ECR Secret
echo -e "\n✅ STEP 10: Create ECR Secret"
echo "ECR_REGISTRY=\$(cd terraform/environments/dev && terraform output -raw ecr_registry_url)"
echo ""
echo "aws ecr get-login-password --region us-east-1 | \\"
echo "kubectl create secret docker-registry ecr-secret \\"
echo "  --docker-server=\$ECR_REGISTRY \\"
echo "  --docker-username=AWS \\"
echo "  --docker-password=\$(aws ecr get-login-password --region us-east-1) \\"
echo "  -n gamemetrics"

# Step 11: Sync Applications in ArgoCD
echo -e "\n✅ STEP 11: Sync ArgoCD Applications"
echo "# Login to ArgoCD CLI"
echo "argocd login localhost:8080 --insecure"
echo ""
echo "# Sync all applications"
echo "argocd app sync event-ingestion-service"
echo "argocd app sync kafka-cluster"
echo "argocd app sync monitoring-stack"

# Step 12: Test the Pipeline
echo -e "\n✅ STEP 12: Test End-to-End"
echo "# Make a test change"
echo "echo '# Test' >> services/event-ingestion-service/README.md"
echo "git add services/event-ingestion-service/README.md"
echo "git commit -m 'test: trigger CI/CD'"
echo "git push origin main"
echo ""
echo "# Watch GitHub Actions at: https://github.com/sheeffii/RealtimeGaming/actions"
echo ""
echo "# Verify in ArgoCD:"
echo "argocd app get event-ingestion-service"

# Verification
echo -e "\n✅ VERIFICATION COMMANDS"
echo "kubectl get nodes                                          # Check cluster"
echo "kubectl get pods -n argocd                                # Check ArgoCD"
echo "kubectl get secrets -n gamemetrics                        # Check secrets"
echo "kubectl get applications -n argocd                        # Check ArgoCD apps"
echo "kubectl get pods -n gamemetrics                           # Check deployment"
echo "kubectl logs -n gamemetrics -l app=event-ingestion        # Check logs"
echo ""
echo "=========================================="
echo "🎉 Setup Complete!"
echo "=========================================="
