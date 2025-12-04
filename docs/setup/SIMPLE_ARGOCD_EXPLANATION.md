# ArgoCD + GitHub Actions - Simple Explanation

## The Problem (Simple)

When your app code changes and GitHub Actions builds a new Docker image, how does Kubernetes know to use the new image?

**Answer**: ArgoCD watches Git for changes and deploys them.

---

## The Simple Flow (4 Steps)

### Step 1: Developer Pushes Code
```
Developer edits code → git push → GitHub
```

### Step 2: GitHub Actions Builds New Image
```
GitHub Actions runs:
  ✓ Run tests
  ✓ Build Docker image
  ✓ Push to ECR (Amazon registry)
  ✓ Update Kubernetes manifest with new image
  ✓ Commit to Git
```

### Step 3: ArgoCD Detects Change
```
ArgoCD watches: k8s/services/event-ingestion/deployment.yaml
Sees: New image tag
Status: "OutOfSync" (cluster doesn't match Git)
```

### Step 4: ArgoCD Deploys New Image
```
ArgoCD syncs:
  ✓ Kubernetes uses new image
  ✓ Old pods terminate
  ✓ New pods start
  ✓ Done!
```

---

## Where the Image Comes From - The Code

### 1. GitHub Actions Builds Image

**File**: `.github/workflows/build-event-ingestion.yml`

The workflow:
1. ✅ Builds Docker image
2. ✅ Pushes to ECR (Amazon Container Registry)
3. ✅ Updates deployment.yaml with new image tag
4. ✅ Commits back to Git

**Key Output**: Image URI like `647523695124.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service:main-abc123`

---

### 2. Kubernetes Deployment File (Watches for Image Changes)

**File**: `k8s/services/event-ingestion/deployment.yaml`

```yaml
spec:
  containers:
  - name: event-ingestion
    # THIS IS THE IMAGE THAT CHANGES
    image: 647523695124.dkr.ecr.us-east-1.amazonaws.com/event-ingestion-service:latest
    imagePullPolicy: Always
```

**Key points**:
- `image:` line is what GitHub Actions updates
- ArgoCD watches this file
- When it changes, ArgoCD deploys the new image

---

### 3. ArgoCD Watches & Deploys

**File**: `k8s/argocd/application-event-ingestion-prod.yaml`

```yaml
source:
  repoURL: https://github.com/sheeffii/RealtimeGaming.git
  targetRevision: main
  path: k8s/services/event-ingestion
```

**How it works**:
1. ArgoCD polls: "Did k8s/services/event-ingestion/ change?"
2. If image changed: YES
3. ArgoCD shows: "OutOfSync - New image available"
4. Operator approves: `argocd app sync event-ingestion-prod`
5. ArgoCD syncs deployment to Kubernetes

---

## The Complete Image Flow - Visual

```
┌─────────────────────────────────────────────────────────────┐
│                   YOUR IMAGE JOURNEY                        │
└─────────────────────────────────────────────────────────────┘

1. CODE CHANGES
   Developer edits code
   └─ git push origin main

2. GITHUB ACTIONS BUILDS
   ├─ Runs tests ✓
   ├─ Builds Docker image ✓
   ├─ Pushes to ECR ✓
   └─ Updates deployment.yaml with new image ✓

3. GIT RECEIVES UPDATE
   deployment.yaml changed:
   └─ NEW: image: ...event-ingestion-service:main-abc123

4. ARGOCD DETECTS (every 3 minutes)
   ├─ Watches: k8s/services/event-ingestion/deployment.yaml
   ├─ Sees change: New image tag
   └─ Status: OutOfSync ⚠️

5. OPERATOR APPROVES (manual sync)
   └─ argocd app sync event-ingestion-prod

6. ARGOCD DEPLOYS
   ├─ Kubernetes sees new image
   ├─ Creates new pods with new image
   ├─ Old pods terminate (graceful)
   ├─ Service routes traffic to new pods
   └─ Done! ✓

7. RUNNING
   ├─ New image running in production
   └─ Consumers/producers using new code ✓
```

---

## Where Does ArgoCD Get the New Image?

### Answer: From the deployment.yaml file in Git

**The connection**:
```
1. GitHub Actions updates: k8s/services/event-ingestion/deployment.yaml
   └─ Changes: image: ...event-ingestion-service:main-abc123

2. Commits to Git

3. ArgoCD watches the same file
   └─ Reads: k8s/services/event-ingestion/deployment.yaml
   └─ Sees new image tag
   └─ Syncs to Kubernetes

4. Kubernetes pulls image from ECR
   └─ ECR address: 647523695124.dkr.ecr.us-east-1.amazonaws.com
```

---

## Next Steps

1. **GitHub Actions must update Git** (not deploy directly)
2. **Create Kubernetes secrets** for credentials
3. **Install ArgoCD** in cluster
4. **Deploy ArgoCD applications** to watch Git
5. **Test** end-to-end

See: `docs/COMPLETE_SETUP_GUIDE.md` for detailed steps
