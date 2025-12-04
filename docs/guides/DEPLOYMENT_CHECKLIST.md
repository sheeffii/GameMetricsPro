# ArgoCD Production Deployment Checklist

## Pre-Deployment Verification

- [ ] GitHub repository is `sheeffii/RealtimeGaming` 
- [ ] Main branch exists and contains latest k8s manifests
- [ ] ArgoCD is installed in `argocd` namespace
- [ ] Strimzi Kafka operator is installed in `kafka` namespace
- [ ] All target namespaces exist:
  - [ ] `argocd`
  - [ ] `kafka` 
  - [ ] `gamemetrics`
  - [ ] `monitoring` (if needed)

## Deployment Steps

### Phase 1: Deploy Root Application (app-of-apps)

```bash
# Deploy the root application - this manages all others
kubectl apply -f k8s/argocd/app-of-apps.yaml -n argocd

# Wait for app to appear
kubectl get applications -n argocd
```

**Expected Result**:
```
NAME                        SYNC STATUS   HEALTH STATUS
gamemetrics-app-of-apps     Syncing       Progressing
```

### Phase 2: Verify All Child Applications

```bash
# Wait ~2 minutes for app-of-apps to deploy all child apps
watch kubectl get applications -n argocd

# All should eventually show as "Synced" and "Healthy"
# Example final state:
# NAME                           SYNC STATUS   HEALTH STATUS
# gamemetrics-app-of-apps        Synced        Healthy
# kafka-prod                     Synced        Healthy
# kafka-dev                      Synced        Healthy
# event-ingestion-prod           OutOfSync     Healthy (manual sync - OK)
# event-ingestion-dev            OutOfSync     Healthy (manual sync - OK)
```

### Phase 3: Verify Kafka Deployment

```bash
# Check Kafka broker pods
kubectl get pods -n kafka
# Should see: gamemetrics-kafka-0, gamemetrics-kafka-1 (2 brokers)

# Check Kafka topics
kubectl get kafkatopic -n kafka
# Should see: 8 topics (player.events.raw, etc.)

# Test Kafka connectivity
kubectl exec -it gamemetrics-kafka-0 -n kafka -- \
  kafka-broker-api-versions.sh --bootstrap-server localhost:9092
```

### Phase 4: Verify Event Ingestion Deployment

```bash
# Check event ingestion pods (once manually synced)
kubectl get pods -n gamemetrics
# Should see: event-ingestion-* pods

# Check service endpoints
kubectl get svc -n gamemetrics
# Should see: event-ingestion service
```

## Testing GitOps Sync

### Test 1: Auto-Sync Kafka Topic Change (Should auto-sync)

```bash
# Edit topics file
vim k8s/kafka/base/topics.yaml
# Change player.events.raw retention from 336h to 504h (7→21 days)

# Commit and push
git add k8s/kafka/base/topics.yaml
git commit -m "test: increase retention to 21 days for testing"
git push origin main

# Watch ArgoCD sync (should happen within 3 minutes)
watch kubectl get application kafka-prod -n argocd

# Verify in Kafka
kubectl exec -it gamemetrics-kafka-0 -n kafka -- \
  kafka-configs.sh --bootstrap-server localhost:9092 \
  --describe --entity-type topics --entity-name player.events.raw
# Check: retention should be 1814400000 ms (21 days)

# Rollback change
git revert HEAD
git push origin main
# Watch ArgoCD auto-sync the revert
```

### Test 2: Manual Sync Event Ingestion Change (Requires approval)

```bash
# Edit event ingestion deployment
vim k8s/services/event-ingestion/event-ingestion-deployment.yaml
# Change replicas from 2 to 3

# Commit and push
git add k8s/services/event-ingestion/
git commit -m "test: scale event-ingestion to 3 replicas"
git push origin main

# Watch application status
kubectl describe application event-ingestion-prod -n argocd
# Status should show: OutOfSync (manual approval required)

# Manually approve the sync
argocd app sync event-ingestion-prod
# Or in UI: Navigate to application, click "SYNC" button

# Verify pods scaled
kubectl get pods -n gamemetrics -l app=event-ingestion
# Should see 3 pods instead of 2

# Rollback
git revert HEAD
git push origin main
argocd app sync event-ingestion-prod
```

## Health Checks

### Check 1: ArgoCD Controller Health

```bash
# Controller should be running
kubectl get pods -n argocd | grep application-controller
kubectl logs -n argocd deployment/argocd-application-controller | tail -20
```

### Check 2: All Applications Synced

```bash
# Every app should show Synced status
kubectl get applications -n argocd -o wide

# Check for any OutOfSync issues
kubectl get applications -n argocd | grep -v "Synced\|OutOfSync"
```

### Check 3: Kafka Cluster Health

```bash
# All brokers should be Running
kubectl get statefulset -n kafka
kubectl get pods -n kafka

# Check broker logs for errors
kubectl logs -n kafka gamemetrics-kafka-0 | tail -20 | grep -i error

# Check entity operator (manages topics)
kubectl get pod -n kafka | grep entity-operator
```

### Check 4: Verify Git Tracking

```bash
# Check current source repo
kubectl get application kafka-prod -n argocd -o yaml | grep repoURL

# Should be: https://github.com/sheeffii/RealtimeGaming.git
# Should NOT be: YOUR-USERNAME
```

## Troubleshooting

### Application Not Syncing

```bash
# Check application status
kubectl describe application kafka-prod -n argocd

# Check last sync time and errors
kubectl get event -n argocd | grep kafka-prod

# Force manual sync (if needed)
argocd app sync kafka-prod --hard

# Check controller logs for sync errors
kubectl logs -f -n argocd deployment/argocd-application-controller | grep kafka-prod
```

### Kafka Cluster Not Starting

```bash
# Check pod status
kubectl get pod -n kafka -o wide

# Check pod events
kubectl describe pod gamemetrics-kafka-0 -n kafka

# Check pod logs
kubectl logs -n kafka gamemetrics-kafka-0 | tail -50

# Check Strimzi operator logs
kubectl logs -n kafka -l app.kubernetes.io/name=strimzi-cluster-operator
```

### Git Changes Not Appearing in Cluster

```bash
# Check if ArgoCD is watching the right branch
kubectl get application kafka-prod -n argocd -o yaml | grep targetRevision
# Should be: main

# Force ArgoCD to refresh from Git
argocd app diff kafka-prod

# Check git sync time settings
kubectl describe application kafka-prod -n argocd | grep -A 5 "Sync Request"

# Manually trigger refresh (if polling interval is long)
argocd app get kafka-prod
```

## Post-Deployment Verification

- [ ] All applications show "Synced" status: `kubectl get applications -n argocd`
- [ ] Kafka brokers are running: `kubectl get statefulset -n kafka`
- [ ] All Kafka topics exist: `kubectl get kafkatopic -n kafka`
- [ ] Event ingestion pods are running: `kubectl get pods -n gamemetrics`
- [ ] ArgoCD can connect to Git: `kubectl describe application kafka-prod -n argocd | grep "Sync Error"`
- [ ] Git changes auto-sync to Kafka within 3 minutes (tested)
- [ ] Event ingestion manual sync works (tested)

## Production Sign-Off

- [ ] All health checks pass
- [ ] Testing procedures successful
- [ ] No errors in ArgoCD controller logs
- [ ] Repository credentials working
- [ ] Team trained on GitOps workflow
- [ ] Documentation provided to team

## Rollback Plan (If Issues)

If something goes wrong after deployment:

### Option 1: Quick Rollback (Remove app-of-apps)
```bash
# Delete root application (all child apps go with it)
kubectl delete application gamemetrics-app-of-apps -n argocd

# Manual restore from backup (if available)
kubectl apply -f kafka-backup.yaml -n kafka
```

### Option 2: Git Revert
```bash
# Revert bad change in Git
git log --oneline
git revert <commit-hash>
git push origin main

# ArgoCD will auto-sync the revert
```

### Option 3: Cluster Reset
```bash
# Delete all ArgoCD applications
kubectl delete applications -n argocd --all

# Delete all managed resources
kubectl delete all -n kafka
kubectl delete all -n gamemetrics
kubectl delete kafkatopic -n kafka --all

# Restart deployment
kubectl apply -f k8s/argocd/app-of-apps.yaml -n argocd
```

---

## Helpful Commands Reference

```bash
# Monitor sync in real-time
watch 'kubectl get applications -n argocd && echo "---" && kubectl get pods -n kafka && echo "---" && kubectl get pods -n gamemetrics'

# Access ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Get ArgoCD admin password
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Check all namespaces for issues
kubectl get all -n argocd && kubectl get all -n kafka && kubectl get all -n gamemetrics

# Describe all applications
for app in $(kubectl get applications -n argocd -o name); do
  echo "=== $app ==="
  kubectl describe $app -n argocd | grep -E "Sync Status|Health Status|Condition"
done
```

---

**Ready for deployment!** Follow this checklist step-by-step. 🚀
