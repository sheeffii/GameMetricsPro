# One-Page Quick Reference

## Your Questions - Answers at a Glance

### Q1: "How does ArgoCD work with consumer/producer apps?"
```
Git has manifest → ArgoCD watches → Detects changes → Deploys to K8s
• Dev env: Auto-deploys (no approval)
• Prod env: Shows change, waits for operator approval
Time: 5-30 seconds (with webhook)
```

### Q2: "Do I need GitHub CI?"
```
YES - Different purposes:
• GitHub Actions (CI): Builds images, runs tests, updates manifests
• ArgoCD (CD): Deploys manifests to Kubernetes
Together: Code → Build → Deploy → Running
Separately: Neither alone is sufficient
```

### Q3: "How is workflow different for dev vs production?"
```
DEV:                          PROD:
Branch: develop              Branch: main
Sync: AUTOMATIC              Sync: MANUAL
Approval: NO                 Approval: YES
Time: Seconds               Time: Minutes
Error tolerance: HIGH        Error tolerance: ZERO
```

### Q4: "Is 3 minutes too long?"
```
Current polling: 3 minutes (slow)
Solution: GitHub Webhook
Result: 5-30 seconds (6x faster!)
Setup: 2 minutes in GitHub UI
```

---

## The Complete Flow (One Picture)

```
1. CODE
   Developer edits src/consumer.py

2. PUSH
   git push → GitHub

3. BUILD (GitHub Actions)
   Tests ✓ → Build image ✓ → Push ✓ → Update manifest ✓

4. DETECT (GitHub Webhook)
   GitHub → ArgoCD (notify immediately)

5. SHOW (ArgoCD UI)
   "OutOfSync - consumer image updated"

6. APPROVE (Operator)
   For Dev: Auto ✓
   For Prod: Operator approves

7. DEPLOY (Kubernetes)
   New pods → Old pods terminate → Done ✓

TOTAL: 1-15 minutes
```

---

## Three Environments You Have

```
kafka-dev              gamemetrics-dev         kafka
(Kafka dev)            (App dev)               (Kafka prod)
Auto-sync ✓            Auto-sync ✓             Auto-sync ✓
No approval            No approval             No approval

gamemetrics
(App prod)
Manual approval ✓✓
Operator must approve
```

---

## GitHub Actions vs ArgoCD

| What | GitHub Actions | ArgoCD |
|-----|--------|--------|
| Build | ✓ | ✗ |
| Test | ✓ | ✗ |
| Push Image | ✓ | ✗ |
| Update Manifest | ✓ | ✗ |
| Watch Git | ✗ | ✓ |
| Detect Changes | ✗ | ✓ |
| Deploy | ✗ | ✓ |
| **Job** | **CI** | **CD** |

---

## Sync Speed Comparison

```
WITHOUT Webhook:
Push → 180s wait → Sync → DONE (3 minutes)

WITH Webhook:
Push → 5-30s notify → Sync → DONE (immediate!)

IMPROVEMENT: 6x faster
SETUP TIME: 2 minutes
RECOMMENDATION: Do it!
```

---

## Decision Tree - What to Edit?

```
I want to change...

Source code (src/)
  → GitHub Actions builds it
  → Time: 5-15 min to production

Deployment manifest (k8s/services/)
  → ArgoCD deploys it
  → Dev: Seconds | Prod: After approval

Kafka topics (k8s/kafka/base/topics.yaml)
  → ArgoCD auto-syncs (no approval!)
  → Time: 5-30 seconds to production

Kafka broker config (k8s/kafka/base/kafka.yaml)
  → ArgoCD auto-syncs (no approval!)
  → Time: 5-30 seconds to production
```

---

## Files You Need to Know

```
YOUR CLUSTER:

k8s/argocd/
  ├─ app-of-apps.yaml ← Deploy this first!
  ├─ application-kafka-prod.yaml
  ├─ application-kafka-dev.yaml
  ├─ application-event-ingestion-prod.yaml
  └─ application-event-ingestion-dev.yaml

k8s/kafka/base/
  ├─ kafka.yaml
  └─ topics.yaml

k8s/services/event-ingestion/
  ├─ consumer-deployment.yaml
  └─ producer-deployment.yaml

.github/workflows/
  └─ build-and-deploy.yml (create this)
```

---

## Deploy in 3 Steps

### Step 1: Deploy Root App
```bash
kubectl apply -f k8s/argocd/app-of-apps.yaml -n argocd
```

### Step 2: Verify Apps
```bash
kubectl get applications -n argocd -w
```

### Step 3: Test
```bash
# Edit a file
vim k8s/kafka/base/topics.yaml

# Push to GitHub
git add . && git commit -m "test" && git push

# Watch sync (should happen in 5-30 seconds)
kubectl describe application kafka-prod -n argocd
```

---

## What Happens When You Push?

```
Scenario: You push to main branch

Timeline:
T+0s:   Push to GitHub
T+5s:   Webhook notifies ArgoCD
T+10s:  ArgoCD detects change
        - For Kafka: Auto-syncs
        - For Apps: Shows "OutOfSync", waits approval
T+15s:  (If auto-sync) Kubernetes updates
T+60s:  (If auto-sync) Rolling update complete
T+Xmin: (If manual) Operator approves
T+Xmin+15s: (After approval) Kubernetes updates

Result: Change is live!
```

---

## 13 Guides You Have

```
1. QUICKSTART.md - 30-second overview
2. QUICK_DECISIONS.md - When to use what
3. ARGOCD_AND_CI_WORKFLOW.md - Complete explanation
4. GITHUB_ACTIONS_SETUP.md - How to set up CI
5. DEV_VS_PROD.md - Environment differences
6. COMPLETE_WORKFLOW.md - Full workflow example
7. VISUAL_GUIDE.md - Diagrams and flowcharts
8. GITOPS_GUIDE.md - GitOps principles
9. DEPLOYMENT_CHECKLIST.md - Deploy step-by-step
10. DOCUMENTATION_INDEX.md - Navigation guide
11. SETUP_COMPLETE.md - Summary
12. ARGOCD_CHANGES.md - What was changed
13. ALL_QUESTIONS_ANSWERED.md - FAQ
```

---

## Your Questions - In One Table

| Q | A | Reference | Setup Time |
|---|---|-----------|-----------|
| How does ArgoCD work? | Watches Git → Deploys | ARGOCD_AND_CI_WORKFLOW.md | 0 min |
| Do I need CI? | YES (for building) | ARGOCD_AND_CI_WORKFLOW.md | 15 min |
| Dev vs Prod? | Different branches + approval | DEV_VS_PROD.md | 0 min |
| Too slow (3 min)? | Use webhook (5-30 sec) | GITHUB_ACTIONS_SETUP.md | 2 min |

---

## Key Metrics

```
Dev deployment:          ~1 minute (auto)
Prod deployment:         ~5-15 minutes (with approval)
Kafka topic deployment:  ~5-30 seconds (auto)
Time to reduce 3→0.5min: 2 minutes (webhook setup)
Total doc reading:       ~2 hours (optional, can skip)
To start using:          5 minutes (deploy root app)
```

---

## Status Check Commands

```bash
# See all applications
kubectl get applications -n argocd

# Watch for changes
kubectl get applications -n argocd -w

# See detailed status
kubectl describe application kafka-prod -n argocd

# Check pods
kubectl get pods -n gamemetrics

# View logs
kubectl logs -n gamemetrics -l app=event-consumer -f

# Check sync events
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

---

## Do's and Don'ts

```
✅ DO:
• Commit all manifests to Git
• Use GitHub Actions to build images
• Use ArgoCD to deploy
• Set up GitHub Webhook
• Push to Git for changes

❌ DON'T:
• Make manual kubectl changes
• Build images in ArgoCD
• Deploy directly from GitHub Actions
• Skip testing
• Use 'latest' image tags
```

---

## Architecture at a Glance

```
LOCAL         GITHUB        CI/CD         KUBERNETES
┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐
│Developer├──→│Repo    │    │Actions │    │Cluster │
│(code)  │    │(source)├───→│Webhook │─→┌─┤  (run) │
└────────┘    │(main)  │    │ArgoCD  │   │ └────────┘
              │(develop)    └────────┘   │
              └────────┘                 │
                                         V
                                    Kubernetes
                                    (deployed)
```

---

## Next 5 Minutes

```
1. Read this file (2 min)
2. Open QUICKSTART.md (2 min)
3. Run: kubectl apply -f k8s/argocd/app-of-apps.yaml (1 min)
Done!
```

---

## Next Hour

```
1. Read QUICKSTART.md (5 min)
2. Read ARGOCD_AND_CI_WORKFLOW.md (20 min)
3. Read QUICK_DECISIONS.md (10 min)
4. Deploy root app (2 min)
5. Test deployment (10 min)
6. Set up webhook (2 min)
7. Read DEV_VS_PROD.md (10 min)
Done - you're an expert!
```

---

## Your Complete Setup ✅

```
✅ ArgoCD installed
✅ Kafka cluster configured (2 replicas, free tier)
✅ Repository URLs fixed (sheeffii)
✅ Production Kafka app created
✅ App-of-apps created
✅ Manual approval for prod apps
✅ Auto-sync for infrastructure
✅ 13 comprehensive guides
✅ Webhook setup instructions
✅ GitHub Actions templates
✅ Decision trees provided
✅ Troubleshooting guides included

READY TO DEPLOY? YES! ✅
```

---

## One Command to Get Started

```bash
kubectl apply -f k8s/argocd/app-of-apps.yaml -n argocd
```

Then watch:
```bash
kubectl get applications -n argocd -w
```

---

**Start with QUICKSTART.md → Then deploy → You're done!** 🚀
