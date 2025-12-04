# ArgoCD GitOps Setup - Production Ready

## Overview
Your Kubernetes cluster is now configured for GitOps with ArgoCD. All infrastructure and application changes are version-controlled in GitHub and automatically synchronized to your cluster.

## Architecture

```
GitHub (sheeffii/RealtimeGaming)
    ↓
    ├── k8s/argocd/
    │   ├── app-of-apps.yaml ........................ ROOT application (entry point)
    │   ├── application-kafka-prod.yaml ............ Kafka cluster (automated sync, no prune)
    │   ├── application-kafka-dev.yaml ............ Kafka dev cluster
    │   ├── application-event-ingestion-prod.yaml . Event ingestion service (manual sync)
    │   ├── application-event-ingestion-dev.yaml .. Event ingestion dev
    │   └── project-gamemetrics.yaml .............. RBAC and resource policies
    │
    ├── k8s/kafka/base/
    │   ├── kafka.yaml ............................ Strimzi Kafka cluster (2 replicas, free tier optimized)
    │   └── topics.yaml ........................... Kafka topics as CRDs (managed by KafkaTopic operator)
    │
    └── k8s/services/
        └── event-ingestion/ ....................... Event ingestion deployment
```

## Sync Policies Explained

### 1. **Kafka Production** (k8s/argocd/application-kafka-prod.yaml)
- **Sync Mode**: Automated (selfHeal: true)
- **Prune**: false (prevents accidental deletion of stateful sets)
- **Behavior**: ArgoCD automatically syncs Git changes to cluster, but won't delete resources
- **Best For**: Infrastructure that must always match Git state

### 2. **Event Ingestion Production** (k8s/argocd/application-event-ingestion-prod.yaml)
- **Sync Mode**: Manual (selfHeal: false, automated: false)
- **Prune**: false
- **Behavior**: ArgoCD detects drift but requires manual approval to sync
- **Best For**: Production applications requiring change approval before deployment

### 3. **App-of-Apps** (k8s/argocd/app-of-apps.yaml)
- **Sync Mode**: Automated (selfHeal: true)
- **Prune**: true
- **Behavior**: Manages all ArgoCD applications, auto-syncs and auto-deletes orphaned apps
- **Best For**: Central management of all applications

---

## Testing GitOps Sync

### Step 1: Deploy Root Application (First Time Only)

```bash
# Apply the app-of-apps as the entry point
kubectl apply -f k8s/argocd/app-of-apps.yaml -n argocd
```

### Step 2: Verify Applications are Syncing

```bash
# Watch all applications in ArgoCD namespace
kubectl get applications -n argocd -w

# Expected output:
# NAME                        SYNC STATUS   HEALTH STATUS
# gamemetrics-app-of-apps     Synced        Healthy
# kafka-prod                  Synced        Healthy
# kafka-dev                   Synced        Healthy
# event-ingestion-prod        OutOfSync     Healthy (manual sync - wait for approval)
```

### Step 3: View Application Details

```bash
# See detailed status of Kafka production
kubectl describe application kafka-prod -n argocd

# See detailed status of event ingestion
kubectl describe application event-ingestion-prod -n argocd
```

### Step 4: Test Auto-Sync with Kafka Topics

1. **Make a change locally**:
   ```bash
   # Edit a topic (e.g., increase retention for player.events.raw)
   # File: k8s/kafka/base/topics.yaml
   ```

2. **Commit and push to GitHub**:
   ```bash
   git add k8s/kafka/base/topics.yaml
   git commit -m "chore: increase player.events.raw retention to 14 days"
   git push origin main
   ```

3. **Watch ArgoCD sync (within 3 minutes)**:
   ```bash
   kubectl get applications kafka-prod -n argocd -w
   # Status should change: OutOfSync → Syncing → Synced
   ```

4. **Verify in Kafka**:
   ```bash
   # Check if topic config was updated
   kubectl exec -it gamemetrics-kafka-0 -n kafka -- \
     kafka-configs.sh --bootstrap-server localhost:9092 \
     --describe --entity-type topics --entity-name player.events.raw
   ```

### Step 5: Test Manual Sync for Application Changes

1. **Make a change to event-ingestion**:
   ```bash
   # Modify deployment (e.g., update replica count)
   # File: k8s/services/event-ingestion/event-ingestion-deployment.yaml
   ```

2. **Commit and push**:
   ```bash
   git add k8s/services/event-ingestion/
   git commit -m "feat: scale event-ingestion to 3 replicas"
   git push origin main
   ```

3. **Check sync status in ArgoCD**:
   ```bash
   kubectl describe application event-ingestion-prod -n argocd
   # Status: OutOfSync (because manual sync is enabled)
   ```

4. **Approve and sync manually**:
   ```bash
   # Using ArgoCD CLI
   argocd app sync event-ingestion-prod
   
   # Or via UI: Log into ArgoCD and click "SYNC" button
   ```

---

## ArgoCD UI Access

### Port Forward to Access Web UI

```bash
# Forward ArgoCD UI to localhost:8080
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Access: https://localhost:8080
# Username: admin
# Password: (get with command below)
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### What to Look For:
- **App Health**: Shows if resources are in desired state
- **Sync Status**: Shows if Git and cluster are in sync
- **Resource Tree**: Shows all K8s resources created
- **Sync Policy**: Shows whether auto-sync is enabled

---

## Monitoring Sync Events

### View ArgoCD Controller Logs

```bash
# Watch for sync events
kubectl logs -f -n argocd deployment/argocd-application-controller | grep -i sync

# Example sync log:
# time="2024-01-15T10:23:45Z" level=info msg="synced" app=kafka-prod
```

### View Application Sync History

```bash
# Get recent sync operations
kubectl get events -n argocd --sort-by='.lastTimestamp' | grep -i sync
```

---

## Rollback Procedures

### Automatic Rollback (Kafka Infrastructure)

```bash
# If a bad change syncs to Kafka cluster:
# 1. Git will have the change committed
# 2. Revert the commit locally:
git revert HEAD
git push origin main

# 3. ArgoCD will auto-sync the reverted state within 3 minutes
kubectl get applications kafka-prod -n argocd -w
```

### Manual Rollback (Event Ingestion)

```bash
# For manual-sync applications:
# 1. Revert Git change
git revert HEAD
git push origin main

# 2. Manually approve the rollback
argocd app sync event-ingestion-prod

# Or check sync history:
kubectl describe application event-ingestion-prod -n argocd
```

---

## Troubleshooting

### Application Out of Sync

```bash
# Check what's different between Git and cluster
kubectl diff -f k8s/kafka/base/kafka.yaml

# Force immediate sync (for automated apps)
kubectl patch application kafka-prod -n argocd \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'
```

### Sync Failures

```bash
# Check ArgoCD controller logs
kubectl logs -n argocd deployment/argocd-application-controller

# Check application status details
kubectl get application kafka-prod -n argocd -o yaml | grep -A 20 conditions
```

### Repository Access Issues

```bash
# Verify GitHub credentials are configured
kubectl get secrets -n argocd | grep github

# Check if repository is accessible
kubectl get repo -n argocd
```

---

## Best Practices

### ✅ DO:
- **Commit to `main` branch** - This is what ArgoCD watches
- **Use descriptive commit messages** - "feat:", "fix:", "chore:" prefixes
- **Test changes in dev first** - Edit kafka-dev or event-ingestion-dev before prod
- **Review diffs before push** - Use `git diff` to see what will sync
- **Monitor sync status** - Check `kubectl get applications` regularly

### ❌ DON'T:
- **Make manual changes in cluster** - They'll be overwritten by ArgoCD sync
- **Disable prune on stateless apps** - Wastes resources
- **Use manual sync for infrastructure** - Should be automated for consistency
- **Store sensitive data in YAML** - Use ExternalSecrets instead
- **Force push to main** - Breaks GitOps audit trail

---

## Configuration Files Location

| File | Purpose | Sync Mode |
|------|---------|-----------|
| `k8s/argocd/app-of-apps.yaml` | Root application manager | Automated |
| `k8s/argocd/application-kafka-prod.yaml` | Kafka cluster | Automated (no prune) |
| `k8s/argocd/application-kafka-dev.yaml` | Kafka dev | Automated (no prune) |
| `k8s/argocd/application-event-ingestion-prod.yaml` | App deployment | Manual |
| `k8s/argocd/project-gamemetrics.yaml` | RBAC policies | N/A |
| `k8s/kafka/base/kafka.yaml` | Kafka config | Via app |
| `k8s/kafka/base/topics.yaml` | Kafka topics | Via app |
| `k8s/services/event-ingestion/` | App code | Via app |

---

## Next Steps

1. ✅ **Deploy app-of-apps**: `kubectl apply -f k8s/argocd/app-of-apps.yaml -n argocd`
2. ✅ **Verify sync**: Run `kubectl get applications -n argocd -w`
3. ✅ **Test GitOps**: Make a change to Kafka topics, commit, and watch it sync
4. ✅ **Configure notifications** (Optional): Set up Slack/Teams webhooks for sync events
5. ✅ **Document in team wiki**: Share this guide with your team

---

## Support Resources

- **ArgoCD Docs**: https://argo-cd.readthedocs.io/
- **Strimzi Docs**: https://strimzi.io/docs/
- **Kubernetes GitOps**: https://www.gitops.tech/
