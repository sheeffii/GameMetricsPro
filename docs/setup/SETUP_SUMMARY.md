# ArgoCD + GitHub Actions - Complete Setup Guide

## 📋 What You Have vs What You Need

### Current State (What You Have)
✅ GitHub Actions workflow (`build-event-ingestion.yml`)
✅ Deployment manifest (`deployment.yaml`)  
✅ ArgoCD applications (`application-*.yaml`)
✅ Terraform infrastructure modules

❌ **BUT**: GitHub Actions bypasses ArgoCD (uses kubectl directly)
❌ **BUT**: ArgoCD never sees image updates
❌ **BUT**: ArgoCD not installed in cluster
❌ **BUT**: Secrets not created
❌ **BUT**: Cluster not created (or is it?)

---

## 🎯 The Simple Problem & Solution

### Problem
When you push code:
1. GitHub Actions builds image ✓
2. GitHub Actions directly updates Kubernetes ❌
3. ArgoCD watches Git but sees nothing changed ❌
4. Conflict: GitHub Actions and ArgoCD fighting over deployment

### Solution
When you push code:
1. GitHub Actions builds image ✓
2. GitHub Actions **updates deployment manifest in Git** ✓
3. ArgoCD sees Git change ✓
4. ArgoCD syncs to Kubernetes ✓
5. Harmony: Single source of truth is Git

---

## 📊 Architecture After Fix

```
┌─────────────────────────────────────────────────────────────────┐
│                        YOUR COMPLETE WORKFLOW                   │
└─────────────────────────────────────────────────────────────────┘

DEVELOPER'S LAPTOP
├─ Edits: services/event-ingestion-service/main.go
└─ git push origin main

        ↓

GITHUB (sheeffii/RealtimeGaming.git)
├─ Receives push
└─ Triggers: .github/workflows/build-event-ingestion.yml

        ↓

GITHUB ACTIONS (Runner)
├─ Step 1: Build Docker image
│  └─ Creates: event-ingestion-service:main-abc123
│
├─ Step 2: Push to ECR
│  └─ Pushes to: 647523695124.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service:main-abc123
│
└─ Step 3: Update Git (GitOps!)
   ├─ Updates: k8s/services/event-ingestion/deployment.yaml
   ├─ Changes image: ...event-ingestion-service:main-abc123
   └─ Commits back to: main branch

        ↓

GITHUB (Git receives update)
├─ Sees: deployment.yaml changed
└─ ArgoCD polling detects this

        ↓

ARGOCD (in Kubernetes cluster)
├─ Polls: "Did k8s/services/event-ingestion/ change?"
├─ Sees: Yes! New image tag
├─ Status: OutOfSync ⚠️
└─ Shows in UI: "New image version available"

        ↓

OPERATOR (You/DevOps)
├─ Reviews in ArgoCD UI
├─ Approves: "argocd app sync event-ingestion-prod"
└─ Sends sync command

        ↓

KUBERNETES (EKS cluster)
├─ Old deployment: event-ingestion with old image
├─ New deployment: event-ingestion with new image
├─ Old pods: Graceful shutdown
├─ New pods: Start with new image
└─ Service: Routes traffic to new pods

        ↓

✓ COMPLETE
  Running new code in production!
```

---

## 🚀 Quick Start (Step by Step)

### Step 1: Verify Terraform Ran
```powershell
cd c:\Users\Shefqet\Desktop\RealtimeGaming\terraform\environments\dev

# Check if resources exist
terraform state list

# Should show resources like:
# aws_eks_cluster.main
# aws_ecr_repository.repo
# etc.

# If nothing, run:
terraform apply
```

### Step 2: Connect to Cluster
```bash
aws eks update-kubeconfig --region us-east-1 --name gamemetrics-dev
kubectl get nodes
```

### Step 3: Create Namespaces
```bash
kubectl create namespace gamemetrics
kubectl create namespace argocd
```

### Step 4: Set Up Secrets
```bash
# Database
kubectl create secret generic db-credentials \
  --from-literal=DB_HOST=<RDS-endpoint> \
  --from-literal=DB_PORT=5432 \
  --from-literal=DB_NAME=gamemetrics \
  --from-literal=DB_USER=dbadmin \
  --from-literal=DB_PASSWORD=<password> \
  -n gamemetrics

# Kafka
kubectl create secret generic kafka-credentials \
  --from-literal=KAFKA_BOOTSTRAP_SERVERS=kafka-cluster-kafka-bootstrap.kafka:9092 \
  -n gamemetrics

# ECR
kubectl create secret docker-registry ecr-secret \
  --docker-server=<ECR-registry> \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-east-1) \
  -n gamemetrics
```

### Step 5: Install ArgoCD
```bash
# Option A: Helm (recommended)
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd

# Option B: Direct YAML
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Step 6: Fix GitHub Actions
Edit `.github/workflows/build-event-ingestion.yml`:
- Replace `deploy-to-prod` job to update Git (not kubectl)
- Replace `deploy-to-dev` job to update Git (not kubectl)
- See `EXACT_CODE_CHANGES.md` for exact code

### Step 7: Deploy ArgoCD Applications
```bash
kubectl apply -f k8s/argocd/application-event-ingestion-prod.yaml
kubectl apply -f k8s/argocd/application-event-ingestion-dev.yaml
```

### Step 8: Test End-to-End
```bash
# Make a test commit
echo "# Test" >> services/event-ingestion-service/README.md
git add services/event-ingestion-service/README.md
git commit -m "test: trigger CI/CD"
git push origin main

# Watch GitHub Actions (should update deployment.yaml)
# Watch ArgoCD (should show OutOfSync)
# Manually sync (should deploy to cluster)
```

---

## 🔧 Key Concepts

### What is GitOps?
Git is the source of truth. Everything needed to run your app is in Git.

**Good GitOps**:
- Code in Git ✓
- Kubernetes manifests in Git ✓
- When manifest changes, ArgoCD deploys ✓

**Bad GitOps**:
- Manual kubectl commands ❌
- Using kubectl set image ❌
- ArgoCD confused about what's deployed ❌

### What is ArgoCD?
ArgoCD watches Git and keeps Kubernetes in sync.

**Example**:
```
Git has: image: v1.2.3
Kubernetes has: image: v1.2.0
ArgoCD sees mismatch and updates Kubernetes to v1.2.3
```

### Why Manual Approval for Production?
- Safe! No automatic deploys
- Operator reviews before deploying
- Team awareness of what's being deployed

### Why Auto-Sync for Development?
- Fast feedback
- Good for testing
- Acceptable risk in dev

---

## 📁 File Organization

```
RealtimeGaming/
├─ .github/
│  └─ workflows/
│     └─ build-event-ingestion.yml  ← UPDATE THIS (remove kubectl, add Git update)
│
├─ k8s/
│  ├─ services/
│  │  └─ event-ingestion/
│  │     ├─ deployment.yaml         ← ADD ECR pull secret
│  │     └─ kustomization.yaml
│  │
│  └─ argocd/
│     ├─ application-event-ingestion-prod.yaml    ← VERIFY THIS EXISTS
│     ├─ application-event-ingestion-dev.yaml     ← VERIFY THIS EXISTS
│     └─ app-of-apps.yaml
│
├─ terraform/
│  └─ environments/
│     └─ dev/
│        ├─ main.tf                ← Uses EKS, ECR, RDS modules
│        ├─ argocd.tf              ← UPDATE THIS (add ArgoCD Helm)
│        └─ providers.tf
│
└─ SIMPLE_ARGOCD_EXPLANATION.md          ← NEW (read this first!)
   COMPLETE_NEXT_STEPS.md                ← NEW (detailed steps)
   EXACT_CODE_CHANGES.md                 ← NEW (exact code to copy)
```

---

## ⚠️ Common Mistakes

### Mistake 1: Keeping kubectl deployment in GitHub Actions
❌ **Don't**: Have both GitHub Actions deploying AND ArgoCD
✅ **Do**: Let GitHub Actions update Git, let ArgoCD deploy

### Mistake 2: Forgetting to create secrets
❌ **Don't**: Assume secrets exist
✅ **Do**: Create db-credentials and kafka-credentials secrets

### Mistake 3: Hardcoding AWS account ID
❌ **Don't**: Keep `647523695124` in deployment.yaml
✅ **Do**: GitHub Actions will update it dynamically

### Mistake 4: Auto-syncing production
❌ **Don't**: Set `automated: true` for production
✅ **Do**: Manual approval for production, auto for dev

### Mistake 5: Not waiting for ArgoCD to detect changes
❌ **Don't**: Expect instant deployment (ArgoCD polls every 3 min)
✅ **Do**: Configure webhooks for instant detection or just wait

---

## ✅ Verification Checklist

- [ ] Terraform created EKS cluster
- [ ] Can connect to cluster: `kubectl get nodes`
- [ ] Namespaces created: `kubectl get ns`
- [ ] Secrets created: `kubectl get secret -n gamemetrics`
- [ ] ArgoCD installed: `kubectl get pods -n argocd`
- [ ] ArgoCD applications exist: `kubectl get app -n argocd`
- [ ] Deployment manifest has ECR secret reference
- [ ] GitHub Actions workflow fixed (no direct kubectl)
- [ ] GitHub Actions can commit to Git
- [ ] Test push triggers workflow
- [ ] Workflow updates deployment.yaml in Git
- [ ] ArgoCD shows OutOfSync
- [ ] Manual sync deploys to cluster
- [ ] Pods running with new image

---

## 🆘 Troubleshooting Quick Links

| Problem | Check |
|---------|-------|
| Pods won't start | `kubectl describe pod` - check image, secrets |
| Image pull fails | ECR secret created? Permission to pull? |
| ArgoCD shows OutOfSync but can't sync | ArgoCD can access GitHub repo? SSH key? |
| GitHub Actions fails | GITHUB_TOKEN has `contents: write`? |
| Manifest not updating | Did workflow actually run? Check logs |
| ArgoCD not detecting changes | Configure webhook or just wait 3 min |

---

## 📞 Key People/Contacts

- **ArgoCD Questions**: https://github.com/argoproj/argo-cd/discussions
- **GitHub Actions Help**: https://github.community/t/github-actions/
- **Kubernetes Issues**: https://kubernetes.io/docs/

---

## Next Actions in Order

1. **Read**: `SIMPLE_ARGOCD_EXPLANATION.md` (understanding)
2. **Read**: `COMPLETE_NEXT_STEPS.md` (detailed steps)
3. **Read**: `EXACT_CODE_CHANGES.md` (exact code)
4. **Do**: Follow the steps in `COMPLETE_NEXT_STEPS.md`
5. **Test**: Verify everything works
6. **Deploy**: Push to production

---

## Summary

Your setup will work, but needs these fixes:

1. **GitHub Actions** → Fix to update Git instead of using kubectl
2. **Kubernetes** → Create secrets
3. **ArgoCD** → Install in cluster
4. **Terraform** → Add ArgoCD Helm chart

Once fixed:
- Developer commits code
- GitHub Actions builds and updates manifest in Git
- ArgoCD sees change and syncs
- Kubernetes runs new image
- ✓ Complete GitOps pipeline

**Estimated time to complete**: 30-60 minutes

