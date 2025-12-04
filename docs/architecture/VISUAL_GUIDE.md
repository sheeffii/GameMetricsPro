# Visual Workflow Guide - Your Complete Pipeline

## 1. The Basic Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    BASIC FLOW (5 STEPS)                     │
└─────────────────────────────────────────────────────────────┘

Step 1: Write Code
  ┌────────────────────┐
  │  Developer Local   │
  │  ✎ Edit code       │
  │  ✓ Test locally    │
  │  $ git push        │
  └────────┬───────────┘
           │
           ▼
Step 2: GitHub Actions (CI - Continuous Integration)
  ┌────────────────────┐
  │ GitHub Actions     │
  │ ✓ Run tests        │
  │ ✓ Build image      │
  │ ✓ Push to registry │
  │ ✓ Update YAML      │
  └────────┬───────────┘
           │
           ▼
Step 3: GitHub Webhook (Optional - Real-time)
  ┌────────────────────┐
  │ GitHub Webhook     │
  │ → ArgoCD (notify)  │
  └────────┬───────────┘
           │
           ▼
Step 4: ArgoCD (CD - Continuous Deployment)
  ┌────────────────────┐
  │ ArgoCD             │
  │ ✓ Detect change    │
  │ ✓ Show in UI       │
  │ ? Needs approval?  │
  └────────┬───────────┘
           │
           ├─ YES (Production) → Need operator approval
           │
           ▼
Step 5: Kubernetes
  ┌────────────────────┐
  │ Kubernetes         │
  │ ✓ Deploy pods      │
  │ ✓ Health checks    │
  │ ✓ Ready for traffic│
  └────────────────────┘
```

---

## 2. Detailed Timeline

### Development Branch (develop) - Fast Path

```
Timeline for feature branch → merge to develop

T+0s:   Developer pushes feature branch
        └─ git push origin feature/name

T+5s:   GitHub Actions triggered
        └─ Webhook: "New code detected"

T+60s:  GitHub Actions completes
        ├─ Pytest: 45/45 tests ✓
        ├─ Docker build: Complete ✓
        ├─ Docker push: Complete ✓
        ├─ Manifest updated ✓
        └─ Commit pushed to feature branch ✓

T+65s:  Developer creates PR
        └─ PR: Code review waiting

T+300s: Team approves and merges
        └─ Merge to develop branch

T+305s: GitHub Actions runs again (for develop)
        ├─ Build with develop tag
        └─ Commit to develop branch

T+310s: GitHub webhook notifies ArgoCD
        └─ "Manifest changed in develop branch"

T+315s: ArgoCD detects change
        ├─ Status: OutOfSync
        ├─ Change: New image tag
        └─ Action: Auto-sync (dev has automated: true)

T+320s: ArgoCD syncs to gamemetrics-dev
        ├─ Rolling update starts
        ├─ Old pod terminating
        ├─ New pod starting
        └─ Service routes to new pod

T+380s: New code running in dev!
        └─ Developers can test immediately

TOTAL TIME: ~6 minutes (CI: 60s + PR review: 5min + sync: 5-10s)
```

### Production Branch (main) - Safe Path

```
Timeline for develop → main → production

T+0s:   Team decides: "Ready for production"
        └─ Create PR: develop → main

T+60s:  Team review begins
        ├─ Code review: OK
        ├─ Testing verification: OK
        ├─ Release notes: OK
        └─ Approval: YES ✓

T+120s: Merge to main branch
        └─ git merge develop

T+125s: GitHub Actions runs (production build)
        ├─ Pytest: 45/45 tests ✓
        ├─ Docker build: event-consumer:v20240612-143022
        ├─ Docker push: Complete ✓
        ├─ Manifest update: image: ...v20240612-143022
        └─ Commit to main ✓

T+130s: GitHub webhook notifies ArgoCD
        └─ "Manifest changed in main branch"

T+135s: ArgoCD detects production change
        ├─ Status: OutOfSync ⚠️
        ├─ Change: image v20240611-... → v20240612-143022
        ├─ Manual approval required!
        └─ Shows in UI: "Waiting for operator"

T+180s: Production operator reviews (monitoring)
        ├─ Checks: "What changed?"
        ├─ Checks: "Is it tested?" (Yes, in dev)
        ├─ Decision: "Looks good"
        └─ Approves: argocd app sync event-ingestion-prod

T+185s: ArgoCD syncs to production
        ├─ Rolling update starts
        ├─ Pod 1: Old → Terminating
        ├─ Pod 2: New → Starting, Running
        ├─ Service: Routes to new pod
        ├─ Pod 1: Terminated
        ├─ Pod 3 (if existing): Terminates, updates
        └─ All pods: New version ✓

T+245s: Production updated!
        └─ Feature live for customers

TOTAL TIME: ~4 minutes from merge
  (CI: 60s + operator review: 40-50s + sync: 60s)
```

---

## 3. Tool Usage by File Type

```
What file am I editing?

┌─ Source Code (src/consumer.py, src/producer.py)
│  └─ GitHub Actions: ✓ Builds image
│  └─ ArgoCD: Waits for new image
│  └─ Time: 5-15 minutes to production
│
├─ Application Config (k8s/services/event-ingestion/consumer-deployment.yaml)
│  └─ GitHub Actions: ✗ Skips (no code)
│  └─ ArgoCD: ✓ Detects and deploys
│  └─ Time to prod: 5-30 seconds (+ approval time)
│
├─ Kafka Topics (k8s/kafka/base/topics.yaml)
│  └─ GitHub Actions: ✗ Skips (no code)
│  └─ ArgoCD: ✓ Auto-syncs (no approval!)
│  └─ Time to prod: 5-30 seconds
│
├─ Kafka Broker Config (k8s/kafka/base/kafka.yaml)
│  └─ GitHub Actions: ✗ Skips
│  └─ ArgoCD: ✓ Auto-syncs (no approval!)
│  └─ Time to prod: 5-30 seconds
│
└─ ArgoCD Config (k8s/argocd/)
   └─ GitHub Actions: ✗ Skips
   └─ ArgoCD: ✓ Manages itself
   └─ Time to prod: Immediate
```

---

## 4. Environment Comparison

```
┌──────────────────────────────────────────────────┐
│        DEVELOPMENT ENVIRONMENT                   │
├──────────────────────────────────────────────────┤
│                                                  │
│  Branch: develop                                 │
│  Namespace: gamemetrics-dev                      │
│  ArgoCD Sync: AUTOMATED ✓                        │
│  Approval: None ✗                               │
│  Speed: Fast (immediate)                         │
│  Error tolerance: High                           │
│                                                  │
│  ┌────────────────────────────────────┐          │
│  │ Workflow:                          │          │
│  │ 1. Push to develop                 │          │
│  │ 2. GitHub Actions builds           │          │
│  │ 3. ArgoCD auto-syncs               │          │
│  │ 4. Test (seconds later)            │          │
│  │ 5. Iterate quickly                 │          │
│  └────────────────────────────────────┘          │
│                                                  │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│       PRODUCTION ENVIRONMENT                     │
├──────────────────────────────────────────────────┤
│                                                  │
│  Branch: main                                    │
│  Namespace: gamemetrics                          │
│  ArgoCD Sync: MANUAL ✓ (approval required)       │
│  Approval: Required ✓                            │
│  Speed: Safe (controlled)                        │
│  Error tolerance: None (zero-downtime)           │
│                                                  │
│  ┌────────────────────────────────────┐          │
│  │ Workflow:                          │          │
│  │ 1. Push to main (after PR review)  │          │
│  │ 2. GitHub Actions builds           │          │
│  │ 3. ArgoCD detects change           │          │
│  │ 4. Operator reviews                │          │
│  │ 5. Operator approves               │          │
│  │ 6. Deploy to production            │          │
│  │ 7. Monitor                         │          │
│  └────────────────────────────────────┘          │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

## 5. Decision Tree

```
I want to make a change...

├─ Edit source code (consumer.py, producer.py)
│  ├─ Which branch?
│  │  ├─ develop? YES → Auto-deploy to dev (fast)
│  │  └─ main? YES → Auto-deploy to prod (after approval)
│  ├─ GitHub Actions runs?
│  │  └─ YES ✓ (builds Docker images)
│  └─ Approval needed?
│     ├─ Dev? NO
│     └─ Prod? YES (manual sync)
│
├─ Edit Kubernetes manifest (deployment)
│  ├─ GitHub Actions runs?
│  │  └─ NO ✗ (already built)
│  ├─ ArgoCD deploys?
│  │  └─ YES ✓ (watches Git)
│  └─ Approval needed?
│     ├─ Dev? NO (auto-sync)
│     └─ Prod? YES (manual sync)
│
├─ Edit Kafka config (topics, broker)
│  ├─ GitHub Actions runs?
│  │  └─ NO ✗ (no code)
│  ├─ ArgoCD deploys?
│  │  └─ YES ✓ (watches Git)
│  └─ Approval needed?
│     ├─ Dev? NO
│     └─ Prod? NO (auto-sync for infrastructure!)
│
└─ Need faster deployment?
   ├─ Set up GitHub Webhook
   │  └─ Reduces: 3 min → 5-30 sec
   │  └─ Setup: 2 minutes
   └─ Result: Real-time notifications!
```

---

## 6. Sync Speed Comparison

```
SCENARIO: Changes pushed to main branch

┌──────────────────────────────────────────┐
│ WITHOUT Webhook (polling)                │
├──────────────────────────────────────────┤
│ T+0s:   Push to GitHub                   │
│ T+180s: ArgoCD polls (3-minute interval) │
│ T+185s: Detects change                   │
│ T+190s: Deploys                          │
│ ─────────────────────────────────────    │
│ TOTAL: ~3-4 minutes                      │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│ WITH Webhook (real-time)                 │
├──────────────────────────────────────────┤
│ T+0s:   Push to GitHub                   │
│ T+5s:   Webhook notifies ArgoCD          │
│ T+10s:  Detects change                   │
│ T+15s:  Deploys                          │
│ ─────────────────────────────────────    │
│ TOTAL: ~5-30 seconds                     │
│ FASTER: 6x improvement!                  │
└──────────────────────────────────────────┘
```

---

## 7. Your Three Environments

```
┌─────────────────────────────────────────────────────────┐
│              YOUR K8S CLUSTER                           │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ NAMESPACE: kafka-dev                             │  │
│  │ PURPOSE: Kafka for development                   │  │
│  │ MANAGED BY: ArgoCD (app: kafka-dev)              │  │
│  │ AUTO-SYNC: YES                                   │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ NAMESPACE: gamemetrics-dev                       │  │
│  │ PURPOSE: Consumer/Producer development           │  │
│  │ MANAGED BY: ArgoCD (app: event-ingestion-dev)    │  │
│  │ AUTO-SYNC: YES                                   │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ NAMESPACE: kafka (shared)                        │  │
│  │ PURPOSE: Kafka for production (2 brokers)        │  │
│  │ MANAGED BY: ArgoCD (app: kafka-prod)             │  │
│  │ AUTO-SYNC: YES                                   │  │
│  │ PRUNE: NO (protect data!)                        │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ NAMESPACE: gamemetrics (production)              │  │
│  │ PURPOSE: Consumer/Producer production            │  │
│  │ MANAGED BY: ArgoCD (app: event-ingestion-prod)   │  │
│  │ AUTO-SYNC: NO (manual approval required!)        │  │
│  │ APPROVAL: Operator must sync                     │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 8. Who Does What?

```
┌────────────────────────────────────────────────┐
│ Developer                                      │
├────────────────────────────────────────────────┤
│ ✓ Writes code                                  │
│ ✓ Tests locally                                │
│ ✓ Commits to Git                               │
│ ✓ Creates Pull Request                         │
│ ✗ Deploys anything (that's ArgoCD's job)      │
└────────────────────────────────────────────────┘

┌────────────────────────────────────────────────┐
│ GitHub Actions (Robot)                         │
├────────────────────────────────────────────────┤
│ ✓ Runs tests automatically                     │
│ ✓ Builds Docker images                         │
│ ✓ Pushes to registry                           │
│ ✓ Updates Kubernetes manifests                 │
│ ✗ Doesn't deploy (ArgoCD does)                │
└────────────────────────────────────────────────┘

┌────────────────────────────────────────────────┐
│ ArgoCD (Robot)                                 │
├────────────────────────────────────────────────┤
│ ✓ Watches Git for changes                      │
│ ✓ Shows what changed in UI                     │
│ ✓ Auto-deploys infrastructure                  │
│ ✓ Waits for approval for apps                  │
│ ✓ Deploys after approval                       │
│ ✗ Doesn't build anything                       │
└────────────────────────────────────────────────┘

┌────────────────────────────────────────────────┐
│ Operations / Production Operator               │
├────────────────────────────────────────────────┤
│ ✓ Reviews changes in ArgoCD UI                 │
│ ✓ Approves deployment to production            │
│ ✓ Monitors production health                   │
│ ✓ Handles rollbacks if needed                  │
│ ✗ Makes manual changes (breaks GitOps!)       │
└────────────────────────────────────────────────┘
```

---

## 9. What Happens on Push?

```
Developer: git push origin main

                    ↓

GitHub: "New commits detected"
  ├─ Trigger GitHub Actions workflow
  └─ Trigger GitHub Webhook

                    ↓

GitHub Actions (CI):
  ├─ Checkout code
  ├─ Run tests (pytest)
  ├─ Build Docker images
  ├─ Push to Docker Hub
  ├─ Update k8s/services/event-ingestion/consumer-deployment.yaml
  │  └─ image: event-consumer:new_tag
  ├─ Commit to Git
  └─ Push to main branch

                    ↓

GitHub Webhook:
  └─ Notify ArgoCD: "Manifest changed in main!"

                    ↓

ArgoCD:
  ├─ Fetch latest from Git
  ├─ Compare: Git vs Cluster
  ├─ Found difference! Status: OutOfSync
  ├─ Show in UI: "Update consumer image"
  ├─ For Kafka: Auto-sync immediately
  ├─ For Apps: Wait for operator approval
  └─ After approval: Deploy to Kubernetes

                    ↓

Kubernetes:
  ├─ Terminate old pods (graceful)
  ├─ Start new pods (with new image)
  ├─ Monitor health (readiness probes)
  ├─ Route traffic to new pods
  └─ Done! ✓
```

---

## 10. Quick Status Check

```
Want to see if everything is syncing?

Run these commands:

✓ Check applications:
  kubectl get applications -n argocd

✓ Expected output:
  NAME                        SYNC STATUS   HEALTH
  gamemetrics-app-of-apps     Synced        Healthy
  kafka-prod                  Synced        Healthy
  event-ingestion-prod        OutOfSync     Healthy  (waiting approval)

✓ Watch for changes:
  kubectl get applications -n argocd -w

✓ See detailed status:
  kubectl describe application event-ingestion-prod -n argocd

✓ Check pods:
  kubectl get pods -n gamemetrics -l app=event-consumer

✓ View logs:
  kubectl logs -n gamemetrics -l app=event-consumer -f
```

---

## 🎯 Key Takeaways

1. **GitHub Actions**: Builds & tests code (CI)
2. **ArgoCD**: Deploys to Kubernetes (CD/GitOps)
3. **Webhook**: Speeds up sync from 3 min to 5-30 sec
4. **Dev**: Auto-syncs, no approval, fast iteration
5. **Prod**: Manual approval, safety first
6. **Git**: Single source of truth for everything
7. **No manual kubectl**: All changes through Git

---

**You're ready to deploy!** 🚀
