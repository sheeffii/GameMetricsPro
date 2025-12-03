# AWS EKS GitOps Native Features - December 2024

## Overview
Amazon EKS recently announced **native GitOps and AWS resource management** capabilities that simplify cluster orchestration.

## New Capabilities

### 1. **Native Argo CD Add-on** (EKS Managed)
- **Enable with one click** - No Helm charts or manual installation required
- Fully managed lifecycle (upgrades, security patches)
- Integrated with AWS IAM for authentication
- Pre-configured with best practices

**How to enable:**
```bash
# Via AWS Console: EKS → Cluster → Add-ons → ArgoCD

# Via CLI:
aws eks create-addon \
  --cluster-name gamemetrics-dev \
  --addon-name argo-cd \
  --region us-east-1
```

**Terraform example:**
```hcl
resource "aws_eks_addon" "argocd" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "argo-cd"
  addon_version = "v2.x.x-eksbuild.1"  # Check latest
}
```

### 2. **AWS Controllers for Kubernetes (ACK)** - Native AWS Resource Management
- Manage AWS services (RDS, S3, ElastiCache, ECR, etc.) **directly via Kubernetes API**
- No Terraform needed for AWS resources managed by K8s workloads
- Resources are Kubernetes CRDs (Custom Resource Definitions)

**Example - Create RDS via Kubernetes:**
```yaml
apiVersion: rds.services.k8s.aws/v1alpha1
kind: DBInstance
metadata:
  name: gamemetrics-db
spec:
  dbInstanceClass: db.t3.micro
  engine: postgres
  engineVersion: "15"
  masterUsername: admin
  masterUserPassword:
    namespace: default
    name: db-secret
    key: password
  allocatedStorage: 20
```

**ACK Supported Services:**
- RDS, DynamoDB, S3, ElastiCache, ECR, Lambda, SNS, SQS, API Gateway, ELB, and more

### 3. **Kube Resource Orchestrator (KRO)** - Reusable Abstractions
- Package complex Kubernetes resources into simple, reusable abstractions
- No custom operators or CRDs required
- Define high-level resources (e.g., "WebApp") that expand into Deployments, Services, Ingress, etc.

**Example - Define a "WebApp" resource:**
```yaml
apiVersion: kro.run/v1alpha1
kind: ResourceGroup
metadata:
  name: webapp
spec:
  schema:
    apiVersion: example.com/v1
    kind: WebApp
    spec:
      image: string
      replicas: integer
      domain: string
  resources:
    - apiVersion: apps/v1
      kind: Deployment
      # ... deployment spec using ${spec.image}, ${spec.replicas}
    - apiVersion: v1
      kind: Service
    - apiVersion: networking.k8s.io/v1
      kind: Ingress
```

**Use the abstraction:**
```yaml
apiVersion: example.com/v1
kind: WebApp
metadata:
  name: my-app
spec:
  image: nginx:latest
  replicas: 3
  domain: myapp.example.com
```

## Should We Adopt This?

### **Recommendation: Hybrid Approach**

#### Keep Terraform for:
- ✅ **Infrastructure layer** (VPC, EKS cluster, networking, IAM roles)
- ✅ **Cross-service dependencies** (RDS + EKS + Redis together)
- ✅ **State management** (centralized state, drift detection)
- ✅ **Multi-cloud** (if you expand beyond AWS)

#### Adopt EKS Native for:
- ✅ **ArgoCD** - Use EKS addon instead of Kustomize install (simpler, managed)
- ✅ **Application-owned AWS resources** - RDS databases created/managed by app teams via ACK
- ✅ **GitOps workflow** - ArgoCD manages K8s manifests from Git

#### Use ACK for:
- ⚠️ **Developer-owned resources** - Let app teams create S3 buckets, SQS queues via K8s manifests
- ⚠️ **Per-environment resources** - RDS instances tied to K8s namespaces
- ❌ **Shared infrastructure** - Keep VPC, EKS, shared RDS in Terraform (better for ops teams)

### Migration Path

**Phase 1: ArgoCD Migration (Immediate)**
```hcl
# terraform/environments/dev/main.tf
resource "aws_eks_addon" "argocd" {
  cluster_name  = module.eks.cluster_name
  addon_name    = "argo-cd"
  addon_version = "v2.10.0-eksbuild.1"  # Check latest version
}
```

Remove:
- `k8s/argocd/base/` (no longer needed)
- `scripts/deploy-argocd.sh`

**Phase 2: ACK for Application Resources (Future)**
- Install ACK controllers for RDS, ECR, ElastiCache
- Migrate application-specific resources from Terraform to K8s CRDs
- Keep shared infrastructure in Terraform

**Phase 3: KRO for Abstractions (Optional)**
- Define reusable patterns (e.g., "MicroserviceApp" = Deployment + Service + HPA + PDB)
- Simplify application manifests

## Implementation for GameMetrics

### Current State
- Terraform manages: VPC, EKS, RDS, Redis, S3, ECR
- Kustomize manages: Kafka, Kafka UI, ArgoCD, app services
- Manual kubectl for ArgoCD

### Recommended Next State
```
Terraform:
  ├── VPC, EKS cluster, IAM roles (keep)
  ├── Shared RDS (keep)
  ├── Shared Redis (keep)
  ├── ECR repositories (keep)
  └── EKS ArgoCD Addon (NEW)

ACK (K8s CRDs):
  ├── Per-app S3 buckets (future)
  └── Per-environment RDS instances (future)

ArgoCD (EKS Managed):
  ├── Kafka cluster
  ├── Kafka UI
  ├── App services
  └── Monitoring stack
```

### Cost Considerations
- **EKS Addons**: Free (ArgoCD addon has no additional cost)
- **ACK**: Free (just K8s controllers)
- **Complexity**: Lower (managed lifecycle, integrated auth)

## Conclusion

**For GameMetrics:**
- ✅ **Migrate to EKS-managed ArgoCD** - Simpler, no Helm/Kustomize maintenance
- ⏳ **Evaluate ACK later** - After ArgoCD migration, consider ACK for app-owned resources
- ❌ **Skip KRO for now** - Project not complex enough to justify abstractions

**Next Steps:**
1. Upgrade EKS to 1.29 (in progress)
2. Add `aws_eks_addon.argocd` to Terraform
3. Remove manual ArgoCD Kustomize install
4. Test GitOps workflow with app-of-apps pattern
