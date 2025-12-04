# ArgoCD + GitHub Actions - Complete Implementation Checklist

## Pre-Implementation

- [ ] **Understand the Flow**
  - [ ] Read `SIMPLE_ARGOCD_EXPLANATION.md`
  - [ ] Read `IMAGE_UPDATE_FLOW_DIAGRAMS.md`
  - [ ] Understand problem: "GitHub Actions bypasses ArgoCD"
  - [ ] Understand solution: "GitHub Actions updates Git instead"

- [ ] **Prerequisites Check**
  - [ ] AWS account configured locally (`aws configure`)
  - [ ] kubectl installed and in PATH
  - [ ] Helm installed (v3+)
  - [ ] Git configured (`git config user.name`, `git config user.email`)
  - [ ] Access to GitHub repo (sheeffii/RealtimeGaming)
  - [ ] Have push permission to repo

---

## Phase 1: Infrastructure Setup (Terraform)

### 1.1 Initialize Terraform

- [ ] Navigate to workspace:
  ```powershell
  cd c:\Users\Shefqet\Desktop\RealtimeGaming\terraform\environments\dev
  ```

- [ ] Check current state:
  ```powershell
  terraform state list
  ```
  - [ ] Should see resources (if empty, need to apply)

- [ ] Create/Update Terraform:
  ```powershell
  terraform init
  terraform plan
  ```
  - [ ] Review plan (should show EKS, ECR, VPC, etc.)

### 1.2 Apply Infrastructure

- [ ] Apply Terraform:
  ```powershell
  terraform apply
  ```
  - [ ] Confirm with `yes`
  - [ ] Wait 15-20 minutes for EKS cluster creation

- [ ] Get cluster credentials:
  ```powershell
  aws eks update-kubeconfig --region us-east-1 --name gamemetrics-dev
  ```

- [ ] Verify cluster access:
  ```powershell
  kubectl get nodes
  ```
  - [ ] Should show 4 nodes (system, application x2, data)

### 1.3 Get Terraform Outputs

- [ ] Get important values:
  ```powershell
  terraform output -raw rds_endpoint
  # Save: will need for secrets
  
  terraform output -raw rds_password
  # Save: will need for secrets
  
  terraform output -raw ecr_registry_url
  # Save: will need for image pulls
  ```

---

## Phase 2: Kubernetes Setup

### 2.1 Create Namespaces

- [ ] Create application namespace:
  ```bash
  kubectl create namespace gamemetrics
  kubectl label namespace gamemetrics name=gamemetrics
  ```

- [ ] Verify namespaces:
  ```bash
  kubectl get namespaces
  ```
  - [ ] Should see: `argocd`, `gamemetrics`, `kube-*`

### 2.2 Create Secrets

- [ ] Create database secret:
  ```bash
  kubectl create secret generic db-credentials \
    --from-literal=DB_HOST=<RDS-ENDPOINT> \
    --from-literal=DB_PORT=5432 \
    --from-literal=DB_NAME=gamemetrics \
    --from-literal=DB_USER=dbadmin \
    --from-literal=DB_PASSWORD=<RDS-PASSWORD> \
    -n gamemetrics
  ```
  - [ ] Verify: `kubectl get secret db-credentials -n gamemetrics`

- [ ] Create Kafka secret:
  ```bash
  kubectl create secret generic kafka-credentials \
    --from-literal=KAFKA_BOOTSTRAP_SERVERS=kafka-cluster-kafka-bootstrap.kafka:9092 \
    --from-literal=KAFKA_SECURITY_PROTOCOL=PLAINTEXT \
    -n gamemetrics
  ```
  - [ ] Verify: `kubectl get secret kafka-credentials -n gamemetrics`

- [ ] Create ECR pull secret:
  ```bash
  kubectl create secret docker-registry ecr-secret \
    --docker-server=<ECR-REGISTRY-URL> \
    --docker-username=AWS \
    --docker-password=$(aws ecr get-login-password --region us-east-1) \
    -n gamemetrics
  ```
  - [ ] Verify: `kubectl get secret ecr-secret -n gamemetrics`

- [ ] Verify all secrets:
  ```bash
  kubectl get secrets -n gamemetrics
  ```
  - [ ] Should show: `db-credentials`, `kafka-credentials`, `ecr-secret`

---

## Phase 3: Install ArgoCD

### 3.1 Option A: Via Terraform (Recommended)

- [ ] Update `terraform/environments/dev/argocd.tf`:
  - [ ] Copy content from `EXACT_CODE_CHANGES.md` (Fix #5)
  - [ ] Replace empty file with Helm installation
  - [ ] File should have `kubernetes_namespace`, `helm_release`, `random_password`

- [ ] Apply Terraform:
  ```powershell
  terraform apply
  ```
  - [ ] Wait for ArgoCD to be installed

- [ ] Get ArgoCD admin password:
  ```powershell
  terraform output -raw argocd_admin_password
  ```
  - [ ] Save this! You'll need it to login

### 3.2 Option B: Via Helm (Alternative)

- [ ] Add Helm repo:
  ```bash
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  ```

- [ ] Install ArgoCD:
  ```bash
  helm install argocd argo/argo-cd \
    -n argocd \
    --create-namespace \
    --set server.service.type=LoadBalancer
  ```

- [ ] Wait for deployment:
  ```bash
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
  ```

### 3.3 Verify ArgoCD Installation

- [ ] Check pods:
  ```bash
  kubectl get pods -n argocd
  ```
  - [ ] Should see: `argocd-server`, `argocd-controller`, `argocd-repo-server`, etc.

- [ ] Get ArgoCD server endpoint:
  ```bash
  kubectl get svc argocd-server -n argocd
  ```
  - [ ] Note the external IP/DNS name

- [ ] Access ArgoCD UI:
  - [ ] Forward port (temporary):
    ```bash
    kubectl port-forward svc/argocd-server -n argocd 8080:443
    ```
  - [ ] Open: https://localhost:8080
  - [ ] Login: admin / <password>
  - [ ] Accept self-signed cert warning

---

## Phase 4: Deploy ArgoCD Applications

### 4.1 Create Project (if not exists)

- [ ] Check if project exists:
  ```bash
  kubectl get AppProject -n argocd
  ```

- [ ] If not, create project:
  ```bash
  kubectl apply -f k8s/argocd/project-gamemetrics.yaml
  ```

### 4.2 Deploy Applications

- [ ] Deploy production application:
  ```bash
  kubectl apply -f k8s/argocd/application-event-ingestion-prod.yaml
  ```
  - [ ] Verify: `kubectl get Application -n argocd`
  - [ ] Should show: `event-ingestion-prod` in ArgoCD UI

- [ ] Deploy development application:
  ```bash
  kubectl apply -f k8s/argocd/application-event-ingestion-dev.yaml
  ```
  - [ ] Verify: `kubectl get Application -n argocd`

### 4.3 Check Application Status

- [ ] In ArgoCD UI:
  - [ ] Click on `event-ingestion-prod`
  - [ ] Should show status: "Synced" (might be "OutOfSync" initially, that's OK)

---

## Phase 5: Fix GitHub Actions Workflow

### 5.1 Update Workflow File

- [ ] Open `.github/workflows/build-event-ingestion.yml`

- [ ] Replace `deploy-to-prod` job:
  - [ ] Copy from `EXACT_CODE_CHANGES.md` (Fix #1)
  - [ ] Remove: kubectl deployment commands
  - [ ] Add: Git manifest update commands
  - [ ] Ensure: `permissions: contents: write`

- [ ] Replace `deploy-to-dev` job:
  - [ ] Copy from `EXACT_CODE_CHANGES.md` (Fix #1)
  - [ ] Similar changes: Git update instead of kubectl

- [ ] Verify workflow file:
  - [ ] Should NOT have `kubectl set image`
  - [ ] SHOULD have `sed -i` to update deployment.yaml
  - [ ] SHOULD have `git commit` and `git push`

### 5.2 Test Workflow Syntax

- [ ] Check GitHub Actions syntax:
  ```bash
  # GitHub automatically validates on push
  # Or manually check using online validator
  # https://github.com/rhysd/actionlint
  ```

### 5.3 Update Deployment Manifest

- [ ] Open `k8s/services/event-ingestion/deployment.yaml`

- [ ] Add ECR pull secret:
  - [ ] Add `imagePullSecrets:` section (see `EXACT_CODE_CHANGES.md`)
  - [ ] Should reference: `ecr-secret`

- [ ] Verify environment variables:
  - [ ] All database vars from `db-credentials` secret
  - [ ] All Kafka vars from `kafka-credentials` secret

### 5.4 Commit Changes to Git

- [ ] Stage files:
  ```bash
  git add .github/workflows/build-event-ingestion.yml
  git add k8s/services/event-ingestion/deployment.yaml
  ```

- [ ] Commit:
  ```bash
  git commit -m "feat: fix GitHub Actions to use GitOps

  - Remove direct kubectl deployment
  - Add Git manifest update mechanism
  - GitHub Actions now updates deployment.yaml
  - ArgoCD will handle Kubernetes deployment"
  ```

- [ ] Push:
  ```bash
  git push origin main
  ```

- [ ] Verify push:
  - [ ] Go to GitHub repo
  - [ ] Should see commit on `main` branch

---

## Phase 6: End-to-End Testing

### 6.1 Trigger Workflow

- [ ] Make a test change:
  ```bash
  echo "# Test" >> services/event-ingestion-service/README.md
  git add services/event-ingestion-service/README.md
  git commit -m "test: trigger CI/CD pipeline"
  git push origin main
  ```

- [ ] Watch GitHub Actions:
  - [ ] Go to: https://github.com/sheeffii/RealtimeGaming/actions
  - [ ] Should see workflow running
  - [ ] Wait for completion

- [ ] Check workflow output:
  - [ ] ✅ build-and-push job succeeds
  - [ ] ✅ deploy-to-prod job succeeds
  - [ ] ✅ Should NOT see kubectl error (since we removed it)

### 6.2 Verify Git Manifest Updated

- [ ] Check deployment.yaml in Git:
  ```bash
  git log --oneline k8s/services/event-ingestion/deployment.yaml
  ```
  - [ ] Should see recent commit from "GitHub Actions Bot"
  - [ ] Commit message: "ci: bump event-ingestion image to..."

- [ ] Check the actual change:
  ```bash
  git show HEAD:k8s/services/event-ingestion/deployment.yaml | grep image
  ```
  - [ ] Should show NEW image tag (not old "latest")

### 6.3 Check ArgoCD Detected Change

- [ ] In ArgoCD UI:
  - [ ] Go to `event-ingestion-prod` application
  - [ ] Check status: should be "OutOfSync" ⚠️
  - [ ] Shows diff: old image vs new image
  - [ ] This means ArgoCD sees the Git change! ✅

### 6.4 Manual Sync

- [ ] In ArgoCD UI:
  - [ ] Click [SYNC] button
  - [ ] Confirm sync
  - [ ] Watch sync progress

- [ ] Via CLI:
  ```bash
  argocd app sync event-ingestion-prod
  ```

- [ ] Check sync status:
  ```bash
  kubectl get Application event-ingestion-prod -n argocd
  ```
  - [ ] Should show: "Synced" status

### 6.5 Verify Deployment Rolled Out

- [ ] Check deployment:
  ```bash
  kubectl get deployment event-ingestion -n gamemetrics
  ```
  - [ ] Replicas: 2/2
  - [ ] Updated: 2
  - [ ] Available: 2

- [ ] Check pods:
  ```bash
  kubectl get pods -n gamemetrics -l app=event-ingestion
  ```
  - [ ] Should show 2 pods
  - [ ] Status: Running
  - [ ] Age: recent (within last minute)

- [ ] Check image running:
  ```bash
  kubectl get deployment event-ingestion -n gamemetrics \
    -o jsonpath='{.spec.template.spec.containers[0].image}'
  ```
  - [ ] Should show NEW image tag (not "latest")

- [ ] Check logs:
  ```bash
  kubectl logs -n gamemetrics -l app=event-ingestion --tail=20
  ```
  - [ ] Should see app starting logs
  - [ ] No errors

### 6.6 Verify Service Health

- [ ] Port-forward to service:
  ```bash
  kubectl port-forward svc/event-ingestion -n gamemetrics 8080:8080
  ```

- [ ] Test health endpoint:
  ```bash
  curl http://localhost:8080/health/live
  ```
  - [ ] Should return: `{"status":"UP"}`

- [ ] Test metrics endpoint:
  ```bash
  curl http://localhost:8080/metrics
  ```
  - [ ] Should return Prometheus metrics

---

## Phase 7: Verify All Components

### 7.1 Cluster Components

- [ ] EKS cluster:
  ```bash
  kubectl get nodes
  ```
  - [ ] ✅ 4 nodes running

- [ ] Namespaces:
  ```bash
  kubectl get ns
  ```
  - [ ] ✅ `gamemetrics` exists
  - [ ] ✅ `argocd` exists

- [ ] Secrets:
  ```bash
  kubectl get secrets -n gamemetrics
  ```
  - [ ] ✅ `db-credentials`
  - [ ] ✅ `kafka-credentials`
  - [ ] ✅ `ecr-secret`

### 7.2 ArgoCD Components

- [ ] ArgoCD pods:
  ```bash
  kubectl get pods -n argocd
  ```
  - [ ] ✅ All pods Running

- [ ] ArgoCD applications:
  ```bash
  kubectl get apps -n argocd
  ```
  - [ ] ✅ `event-ingestion-prod` exists
  - [ ] ✅ `event-ingestion-dev` exists

- [ ] ArgoCD UI:
  - [ ] ✅ Can login
  - [ ] ✅ Can see applications
  - [ ] ✅ Can see sync status

### 7.3 Application Components

- [ ] Deployment:
  ```bash
  kubectl get deployment -n gamemetrics
  ```
  - [ ] ✅ `event-ingestion` ready

- [ ] Pods:
  ```bash
  kubectl get pods -n gamemetrics
  ```
  - [ ] ✅ 2 pods running with new image

- [ ] Service:
  ```bash
  kubectl get svc -n gamemetrics
  ```
  - [ ] ✅ `event-ingestion` service exists

---

## Post-Implementation

### Ongoing Maintenance

- [ ] **Monitor ArgoCD**:
  - [ ] Check UI for sync status
  - [ ] Set up notifications for OutOfSync alerts
  - [ ] Review application health regularly

- [ ] **Monitor Kubernetes**:
  - [ ] Check pod logs: `kubectl logs -f -n gamemetrics ...`
  - [ ] Monitor resource usage: `kubectl top nodes`
  - [ ] Check events: `kubectl get events -n gamemetrics`

- [ ] **Monitor GitHub Actions**:
  - [ ] Check workflow runs
  - [ ] Review any failures
  - [ ] Ensure commits are being made

- [ ] **Documentation**:
  - [ ] Document any issues found
  - [ ] Update runbooks
  - [ ] Share knowledge with team

### Next Steps After Verification

1. **Set up production safeguards**:
   - [ ] Enable GitOps pull requests for production
   - [ ] Require code review before merge
   - [ ] Set up protection rules on main branch

2. **Add more services**:
   - [ ] Create GitHub Actions for other services
   - [ ] Create ArgoCD applications for each
   - [ ] Test CI/CD pipeline for each

3. **Set up monitoring**:
   - [ ] Prometheus for metrics
   - [ ] Grafana for dashboards
   - [ ] Alerts for pod failures

4. **Set up logging**:
   - [ ] ELK stack or similar
   - [ ] Centralized log collection
   - [ ] Log aggregation and search

---

## Troubleshooting Reference

| Issue | Check | Fix |
|-------|-------|-----|
| Workflow fails | GitHub Actions logs | Check permissions, secrets, network |
| ArgoCD shows OutOfSync | Git diff | Manual sync or check webhook |
| Pods won't start | `kubectl describe pod` | Missing secrets, image pull errors |
| Image pull fails | ECR permissions | Verify `ecr-secret`, credentials valid |
| Service unreachable | `kubectl port-forward` | Check pod health, service selector |
| ArgoCD can't access repo | GitHub deploy key | Add public key to repo settings |

---

## Success Criteria

✅ **All of these should be true**:

- [ ] GitHub Actions workflow runs successfully
- [ ] Workflow updates deployment.yaml in Git
- [ ] Commit appears in git log
- [ ] ArgoCD detects change (OutOfSync)
- [ ] Operator can sync in ArgoCD UI
- [ ] Kubernetes deployment updates
- [ ] New image runs in pods
- [ ] Service is healthy
- [ ] Logs show no errors
- [ ] Complete GitOps pipeline works end-to-end

---

## Final Notes

**Remember**:
- Git is the source of truth
- GitHub Actions updates Git
- ArgoCD watches Git
- Kubernetes runs what's in Git

**When something goes wrong**:
1. Check Git: Is deployment.yaml correct?
2. Check ArgoCD: Does it see the change?
3. Check Kubernetes: Are the resources applied?
4. Check logs: What errors are reported?

**For questions**:
- ArgoCD docs: https://argocd.io/docs/
- GitHub Actions docs: https://docs.github.com/actions
- Kubernetes docs: https://kubernetes.io/docs/

