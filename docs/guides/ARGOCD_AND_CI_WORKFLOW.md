# ArgoCD with Consumer/Producer Apps - Complete Workflow Guide

## Quick Answer to Your Questions

### 1. Do You Need GitHub CI?
**Short Answer**: Yes, but ONLY for building/testing code. **NOT for deployment**.

- **GitHub CI** (GitHub Actions): Builds, tests, pushes Docker images to registry
- **ArgoCD**: Deploys those images to Kubernetes (no CI/CD needed here)
- **Git**: Source of truth for what version runs in each environment

### 2. Is 3 Minutes Too Long?
**Short Answer**: Not really, but we can optimize it to **real-time (~5-30 seconds)** with webhooks.

---

## Full Workflow Explained

### Traditional Deployment (OLD WAY - Don't Do This)

```
Developer Push → CI builds → CI deploys directly to cluster
                                        ▲
                                        │ CI has cluster credentials
                            ⚠️ PROBLEM: Multiple deployment paths
                            ⚠️ PROBLEM: No single source of truth
                            ⚠️ PROBLEM: Manual cluster changes ignored
```

**Problems**:
- ❌ Cluster state ≠ Git state
- ❌ Hard to audit who changed what
- ❌ Hard to rollback
- ❌ Multiple ways to deploy (CI, manual kubectl, etc.)

---

### GitOps Workflow (NEW WAY - What You Have Now)

```
┌──────────────┐
│  Developer   │
│  (local)     │
└──────┬───────┘
       │ git push (code + tests)
       ▼
┌──────────────────────────────────┐
│  GitHub (Main Branch)            │
│  - Source code                   │
│  - Docker manifests              │
│  - Kustomization files           │
│  - App versions (in YAML)        │
└──────┬──────────────────────────┘
       │
       ├─────────────────────────────────────────────┐
       │                                             │
       ▼                                             ▼
┌─────────────────────┐              ┌──────────────────────┐
│  GitHub Actions CI  │              │  ArgoCD (Watches)    │
│  (Optional)         │              │  (Watches every      │
│  - Run tests        │              │   3 min or via       │
│  - Build Docker     │              │   webhook)           │
│  - Push to registry │              │                      │
│  - Update YAML      │              │  • Detects changes   │
│  - Commit back      │              │  • Compares Git vs   │
│    to repo          │              │    cluster           │
└─────────────────────┘              │  • Syncs if different│
       │                              │  • Logs actions      │
       └──────────────┬───────────────┘
                      │
                      ▼
        ┌────────────────────────────┐
        │  Kubernetes Cluster        │
        │  (Single source of truth)  │
        │  ✅ Matches Git exactly    │
        │  ✅ All changes tracked    │
        │  ✅ Easy to rollback       │
        └────────────────────────────┘
```

---

## Complete Example: Event Ingestion App Deployment

### Scenario
You have **consumer** (`event-consumer`) and **producer** (`event-producer`) apps that:
- Consume Kafka messages
- Process events
- Produce results

### File Structure
```
k8s/
├── argocd/
│   ├── app-of-apps.yaml
│   ├── application-kafka-prod.yaml
│   ├── application-event-ingestion-prod.yaml  ← Main app (consumers+producers)
│   └── project-gamemetrics.yaml
│
├── services/
│   └── event-ingestion/
│       ├── kustomization.yaml
│       ├── consumer-deployment.yaml
│       ├── producer-deployment.yaml
│       ├── service.yaml
│       └── configmap.yaml
│
└── kafka/
    └── base/
        ├── kafka.yaml
        ├── topics.yaml
        └── kustomization.yaml
```

---

## Workflow Step-by-Step

### Phase 1: Development (Local)

```bash
# Developer works on consumer code
git checkout -b feature/add-event-filter

# Edit Python code
vim src/consumer.py
# Changes: Add new filter for event type

# Build locally
docker build -t event-consumer:dev .

# Test locally
docker-compose up
# Verify: Consumer works correctly

# Commit code
git add src/consumer.py
git commit -m "feat: add event type filter to consumer"
```

### Phase 2: Push to GitHub (Triggers CI)

```bash
# Push feature branch
git push origin feature/add-event-filter

# GitHub Action automatically triggered:
# ✓ Runs tests (pytest)
# ✓ Builds Docker image
# ✓ Tags: event-consumer:feature-add-event-filter
# ✓ Pushes to Docker Registry
# ✓ Posts results to PR
```

**GitHub Actions Workflow** (`.github/workflows/ci.yml`):
```yaml
name: CI - Build and Test

on:
  push:
    branches: [main, develop, feature/**]
    paths:
      - 'src/**'
      - '.github/workflows/ci.yml'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run Tests
        run: pytest tests/
      
      - name: Build Docker Image
        run: |
          docker build -t event-consumer:${{ github.sha }} .
          docker tag event-consumer:${{ github.sha }} event-consumer:latest
      
      - name: Push to Registry
        run: |
          docker push event-consumer:${{ github.sha }}
          docker push event-consumer:latest
      
      - name: Update Kubernetes Manifest
        run: |
          sed -i "s|event-consumer:latest|event-consumer:${{ github.sha }}|g" \
            k8s/services/event-ingestion/consumer-deployment.yaml
      
      - name: Commit Updated Manifest
        run: |
          git config user.email "ci@gamemetrics.io"
          git config user.name "GameMetrics CI"
          git add k8s/services/event-ingestion/consumer-deployment.yaml
          git commit -m "ci: update consumer image to ${{ github.sha }}"
          git push origin feature/add-event-filter
```

### Phase 3: Review and Test in DEV

```bash
# Create Pull Request
# Team reviews code changes

# Deploy to dev environment for testing:
# Option 1: Merge to develop branch (ArgoCD watches develop for dev env)
# Option 2: Manually sync from dev app in ArgoCD

# Test in dev environment
# ✓ Consumer connects to Kafka
# ✓ Filters work correctly
# ✓ Producer receives output
```

**Dev App Configuration** (existing):
```yaml
# k8s/argocd/application-event-ingestion-dev.yaml
spec:
  source:
    targetRevision: develop  # Watches develop branch
    path: k8s/services/event-ingestion
  destination:
    namespace: gamemetrics-dev  # Separate namespace
  syncPolicy:
    automated:
      selfHeal: true  # Auto-fixes drift
```

### Phase 4: Approve and Merge to Main

```bash
# Team approves PR
# Merge to main branch
git checkout main
git merge feature/add-event-filter
git push origin main

# GitHub Actions runs again:
# ✓ Tests pass
# ✓ Builds: event-consumer:v1.2.3
# ✓ Pushes image to registry
# ✓ Updates k8s/services/event-ingestion/consumer-deployment.yaml
#   Changes:
#   image: event-consumer:v1.2.3  ← New version
# ✓ Commits and pushes updated manifest to main
```

### Phase 5: ArgoCD Detects Change (Production Deployment)

```
ArgoCD polls main branch every 3 minutes (or immediately via webhook)

DETECTED CHANGES:
  - File: k8s/services/event-ingestion/consumer-deployment.yaml
  - Old: image: event-consumer:v1.2.2
  - New: image: event-consumer:v1.2.3
  - Status: OutOfSync (because manual sync is enabled)

SHOWS IN UI:
  - Application: event-ingestion-prod
  - Status: OutOfSync ⚠️
  - Reason: Updated to commit abc123def456
  - Changes: 1 file modified
```

### Phase 6: Manual Approval (Production Safety)

```bash
# Production operator reviews change in ArgoCD UI
# They see: "Consumer image updated from v1.2.2 → v1.2.3"
# Operator approves:

argocd app sync event-ingestion-prod

# OR via UI: Click "SYNC" button

# ArgoCD executes:
# ✓ Triggers rolling update
# ✓ New pod starts with v1.2.3
# ✓ Old pod stops (graceful shutdown)
# ✓ Service maintains connection
# ✓ Monitors rollout (waits for health check)
```

### Phase 7: Verify in Production

```bash
# Check pod status
kubectl get pods -n gamemetrics -l app=event-consumer

# Verify image version
kubectl get pod -n gamemetrics event-consumer-xxxxx -o yaml | grep image

# Check logs
kubectl logs -n gamemetrics event-consumer-xxxxx -f

# Monitor Kafka
kubectl exec -it gamemetrics-kafka-0 -n kafka -- \
  kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic player.events.processed --max-messages 10
```

---

## Comparison: Dev vs Production

### DEVELOPMENT Environment

**Goal**: Fast iteration, frequent changes

```yaml
# k8s/argocd/application-event-ingestion-dev.yaml
spec:
  source:
    targetRevision: develop  # Separate branch
    path: k8s/services/event-ingestion
  destination:
    namespace: gamemetrics-dev
  syncPolicy:
    automated:
      selfHeal: true        # ✅ Auto-sync enabled
      prune: true           # ✅ Auto-delete outdated
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 3              # ✅ Fewer retries OK
```

**Workflow**:
```
1. Push to develop branch
2. ArgoCD auto-syncs immediately (no approval needed)
3. New pods start in dev namespace
4. Developers test
5. If broken, fix and push again (fast loop)
```

**Kafka for Dev**:
```yaml
# k8s/argocd/application-kafka-dev.yaml
spec:
  source:
    targetRevision: main
    path: k8s/kafka/base
  destination:
    namespace: kafka-dev
  syncPolicy:
    automated:
      selfHeal: true
      prune: false          # ✅ Don't delete data
```

---

### PRODUCTION Environment

**Goal**: Stability, safety, approval workflow

```yaml
# k8s/argocd/application-event-ingestion-prod.yaml
spec:
  source:
    targetRevision: main    # Only main for prod
    path: k8s/services/event-ingestion
  destination:
    namespace: gamemetrics  # Production namespace
  syncPolicy:
    automated:
      selfHeal: false       # ❌ NO auto-sync
      prune: false          # ❌ NO auto-delete
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5              # ✅ More retries for stability
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

**Workflow**:
```
1. Push to main branch
2. ArgoCD detects change (shows OutOfSync)
3. Production operator reviews in UI
4. Operator approves: argocd app sync event-ingestion-prod
5. Pods update with approval
6. Monitors health before considering sync complete
```

**Kafka for Prod**:
```yaml
# k8s/argocd/application-kafka-prod.yaml
spec:
  source:
    targetRevision: main
    path: k8s/kafka/base
  destination:
    namespace: kafka
  syncPolicy:
    automated:
      selfHeal: true        # ✅ Auto-fix config drift
      prune: false          # ✅ Protect data
    retry:
      limit: 5              # ✅ Stable retries
```

---

## Addressing the 3-Minute Delay

### Problem
ArgoCD polls every ~3 minutes by default. For production, this might feel slow.

### Solution 1: GitHub Webhook (Recommended - Real-time)

**Setup**: Configure webhook so GitHub notifies ArgoCD immediately

```bash
# 1. Get ArgoCD Webhook URL
# Use: <argocd-server>/api/webhook

# 2. In GitHub repo settings:
# Add Webhook:
#   URL: https://argocd.yourcluster.com/api/webhook
#   Events: Push events
#   Active: ✓

# Result: Changes sync within 5-30 seconds of push
```

**How it works**:
```
Git Push → GitHub → Webhook → ArgoCD (immediate notification)
                                    ↓
                            Checks Git for changes
                                    ↓
                            Syncs immediately (5-30 sec)
```

### Solution 2: Reduce Polling Interval

```yaml
# k8s/argocd/argocd-server/argocd-server-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd
data:
  # Default: 180 seconds (3 min)
  # New: 30 seconds (fast but higher load)
  application.instanceLabelKey: argocd.argoproj.io/instance
  application.resourceTrackingMethod: annotation
  repo.server: argocd-repo-server:8081
  
  # Polling settings
  server.disable.auth: "false"
  application.instanceLabelKey: argocd.argoproj.io/instance
  
  # Check for new commits every 30 seconds
  reposerver.autoreload: "true"
```

Then restart ArgoCD:
```bash
kubectl rollout restart deployment argocd-application-controller -n argocd
```

**Trade-offs**:
| Setting | Speed | Load | Cost |
|---------|-------|------|------|
| 3 min polling | Slow | Low | Low |
| 30 sec polling | Fast | Medium | Medium |
| Webhook | Real-time (5-30s) | Low | Low |

**Recommendation**: Use **Webhook** (best balance)

---

## Complete CI/CD to ArgoCD Flow

### Your Current Apps

**Event Ingestion App**:
- **Consumer** pods: Process incoming Kafka events
- **Producer** pods: Send processed events to output topics

```yaml
# k8s/services/event-ingestion/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - consumer-deployment.yaml
  - producer-deployment.yaml
  - service.yaml
  - configmap.yaml

images:
  - name: event-consumer
    newTag: latest  # GitHub CI updates this
  - name: event-producer
    newTag: latest  # GitHub CI updates this
```

### GitHub Actions Updates This File

```bash
# GitHub CI script updates image tags:
sed -i "s|event-consumer:.*|event-consumer:$NEW_TAG|g" \
  k8s/services/event-ingestion/consumer-deployment.yaml
```

### ArgoCD Watches and Deploys

```yaml
# k8s/argocd/application-event-ingestion-prod.yaml
spec:
  source:
    path: k8s/services/event-ingestion  # ArgoCD watches this
  syncPolicy:
    automated:
      selfHeal: false  # Manual for prod apps
```

---

## Do You Still Need GitHub CI?

### Yes, Here's Why:

| Task | GitHub CI | ArgoCD | Where? |
|------|-----------|--------|--------|
| Run tests | ✅ YES | ❌ No | GitHub Actions |
| Build Docker image | ✅ YES | ❌ No | GitHub Actions |
| Push to registry | ✅ YES | ❌ No | GitHub Actions |
| Update YAML | ✅ YES | ❌ No | GitHub Actions |
| Deploy to cluster | ❌ No | ✅ YES | ArgoCD |
| Manage Kubernetes | ❌ No | ✅ YES | ArgoCD |

### The Split of Responsibilities:

```
GitHub Actions (CI):
├── Run unit tests
├── Run integration tests
├── Build Docker images
├── Push to Docker Hub/ECR
├── Update K8s manifests with new image tag
└── Commit updated manifests back to Git

ArgoCD (CD/GitOps):
├── Watch Git for changes
├── Detect new manifest versions
├── Show what changed in UI
├── Require approval (for prod)
└── Deploy to Kubernetes cluster
```

---

## Real Production Example

### Your Scenario: Event Consumer Fix

```
1. BUG FOUND: Consumer crashes on malformed JSON
   └─ Impact: Losing 10% of events

2. DEVELOPER FIXES:
   └─ git checkout -b fix/json-parsing
   └─ vim src/consumer.py (add try/catch)
   └─ git commit -m "fix: handle malformed JSON gracefully"
   └─ git push origin fix/json-parsing

3. GITHUB ACTIONS RUNS (automatic):
   ├─ Runs pytest tests/ ✓ All pass
   ├─ Builds Docker image ✓
   ├─ Pushes event-consumer:abc123def ✓
   ├─ Updates consumer-deployment.yaml:
   │  image: event-consumer:abc123def
   └─ Commits to git ✓

4. PULL REQUEST CREATED:
   ├─ Code review
   ├─ Comment: "Tested in dev, looking good"
   ├─ Approval ✓
   └─ Merge to main

5. ARGOCD DETECTS CHANGE (via webhook ~5 sec):
   ├─ Reads updated consumer-deployment.yaml
   ├─ Sees new image: event-consumer:abc123def
   ├─ Status: OutOfSync
   └─ Shows in UI: "Update consumer from old → abc123def"

6. PRODUCTION OPERATOR REVIEWS:
   ├─ Checks: "Fix for JSON parsing, tested in dev"
   ├─ Runs: argocd app sync event-ingestion-prod
   └─ Result: ✓ Synced

7. KUBERNETES UPDATES:
   ├─ Terminates old pods (graceful)
   ├─ Starts new pods with abc123def
   ├─ Monitors readiness (5-10 sec)
   └─ Service traffic switches to new pods

8. MONITORING:
   ├─ Error rate drops from 10% → 0.5%
   ├─ Events now processed correctly
   └─ Problem solved! ✓

TOTAL TIME: ~5-15 minutes from code push to production fix
```

---

## Do You Need Both GitHub CI and ArgoCD?

**YES, they work together**:

```
GitHub CI = "Is the code correct?"
ArgoCD = "Is the cluster correct?"

GitHub CI handles:
  • Code quality
  • Tests
  • Building images
  • Storing versions

ArgoCD handles:
  • Deploying images
  • Managing Kubernetes resources
  • Ensuring cluster matches Git
  • Handling rollbacks
  • Audit trail
```

**Without GitHub CI** (Bad):
- ❌ No tests
- ❌ Can deploy broken code
- ❌ No version tracking
- ❌ No reproducibility

**Without ArgoCD** (Also Bad):
- ❌ No single source of truth
- ❌ Hard to track who changed what
- ❌ Manual deployments (error-prone)
- ❌ Hard to rollback

**With Both** (Perfect):
- ✅ Tests before deploying
- ✅ Automatic image building
- ✅ GitOps for all changes
- ✅ Easy rollbacks
- ✅ Clear audit trail

---

## Reducing Sync Time from 3 Minutes

### Option 1: Add GitHub Webhook (RECOMMENDED)

```bash
# Get ArgoCD webhook URL
kubectl get svc -n argocd argocd-server
# Use: https://<argocd-ip>/api/webhook

# In GitHub:
# Settings → Webhooks → Add webhook
# URL: https://your-argocd.com/api/webhook
# Events: Push events
# Active: ✓
```

**Result**: Syncs in 5-30 seconds after push

### Option 2: Faster Polling (Alternative)

```bash
# Edit ArgoCD config
kubectl edit configmap argocd-cmd-params-cm -n argocd

# Add/modify:
# server.repo.server.timeout.seconds: 30
# (from default 60)

# Restart controller
kubectl rollout restart deployment argocd-application-controller -n argocd
```

**Result**: Checks every 30-60 seconds (faster than 3 min)

### Option 3: Hybrid (Best)

```
Setup webhook (5-30 sec) + faster polling (1 min fallback)
= Real-time when connected, fallback if webhook fails
```

---

## Summary: Your Updated Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    PRODUCTION WORKFLOW                      │
└─────────────────────────────────────────────────────────────┘

Developer
  ├─ Edit code (consumer.py, producer.py)
  ├─ Push to feature branch
  └─ Create PR

GitHub Actions (CI)
  ├─ Run tests ✅
  ├─ Build Docker images ✅
  ├─ Push to registry ✅
  └─ Update k8s/services/event-ingestion/*.yaml ✅

Team Review
  └─ Approve PR ✅

Merge to Main
  └─ GitHub Actions runs again ✅

GitHub Webhook (OPTIONAL - Real-time)
  └─ Notifies ArgoCD immediately ✅

ArgoCD (GitOps - CD)
  ├─ Detects changes in k8s/services/
  ├─ Shows "OutOfSync" in UI
  ├─ Waits for manual approval
  └─ Syncs to production cluster ✅

Kubernetes
  ├─ Rolling update starts
  ├─ New consumer pods deployed
  ├─ Old pods gracefully terminate
  ├─ Service maintains connections
  └─ Done! ✅

Monitoring
  └─ Check metrics/logs ✅
```

---

## DO's and DON'Ts

### ✅ DO:

- **Commit all K8s manifests to Git** (source of truth)
- **Use GitHub Actions to build/test** (CI)
- **Use ArgoCD to deploy** (CD)
- **Make manual changes only in Git** (never kubectl apply directly)
- **Review changes before production** (approval workflow)
- **Set up webhooks** (real-time sync)

### ❌ DON'T:

- ❌ Build Docker images in ArgoCD
- ❌ Run tests in ArgoCD
- ❌ Deploy directly from GitHub Actions to K8s
- ❌ Make manual kubectl changes in production
- ❌ Mix CI and CD pipelines in one tool

---

## Questions Answered

### Q1: "Do I need GitHub CI?"
**A**: Yes! GitHub CI builds/tests code. ArgoCD deploys it. Different jobs, same pipeline.

### Q2: "Is 3 minutes too slow?"
**A**: Not really, but setup a webhook to make it ~5-30 seconds (much better).

### Q3: "How does it work for prod vs dev?"
**A**: 
- **Dev**: Auto-syncs from `develop` branch, manual approval disabled
- **Prod**: Watches `main` branch, requires manual approval

### Q4: "What's the exact workflow?"
**A**: Code → GitHub CI builds image → Updates YAML → ArgoCD detects → Shows in UI → Operator approves → Deploys to K8s

---

## Next Steps

1. **Set up GitHub Webhook** (optional but recommended):
   ```bash
   # Get URL: kubectl get svc -n argocd argocd-server
   # Add to GitHub Settings → Webhooks
   ```

2. **Create GitHub Actions CI** (.github/workflows/ci.yml):
   - Build Docker images
   - Run tests
   - Update K8s manifests
   - Commit back to git

3. **Test end-to-end**:
   - Push code → Watch CI build → Watch ArgoCD deploy

4. **Document for team**:
   - Share this guide
   - Train on approval process

You're all set! 🚀
