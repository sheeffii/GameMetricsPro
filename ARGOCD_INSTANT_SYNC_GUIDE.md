# ⚡ ArgoCD Instant Sync Guide - No More 3-Minute Wait!

## Problem: ArgoCD Polling Delay

**Default Behavior**:
- ArgoCD polls Git every **3 minutes**
- You push code → Wait up to 3 minutes → ArgoCD detects → Syncs
- **Total wait time**: Up to 3 minutes + sync time

## Solution: GitHub Actions Webhook Integration

**New Behavior**:
- You push code → GitHub Actions triggers → ArgoCD syncs **immediately**
- **Total wait time**: ~30 seconds (GitHub Actions startup + sync)

---

## 🚀 Method 1: GitHub Actions → ArgoCD CLI (Recommended)

### How It Works:

```
┌─────────────┐
│ Git Push    │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│ GitHub Actions      │
│ Triggered           │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ ArgoCD CLI          │
│ - Login             │
│ - Detect Changes    │
│ - Sync Apps         │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ ArgoCD Syncs        │
│ Instantly! ⚡       │
└─────────────────────┘
```

### Setup Steps:

1. **Workflow is already created**: `.github/workflows/argocd-sync-webhook.yml`

2. **Configure GitHub Secrets** (if not already done):
   ```bash
   # In GitHub: Settings → Secrets → Actions
   AWS_ACCESS_KEY_ID=your-key
   AWS_SECRET_ACCESS_KEY=your-secret
   SLACK_WEBHOOK_URL=your-webhook (optional)
   ```

3. **Test it**:
   ```bash
   # Make a change
   echo "# Test" >> k8s/services/event-ingestion/deployment.yaml
   git add .
   git commit -m "test: trigger ArgoCD sync"
   git push origin main
   
   # Watch GitHub Actions
   # ArgoCD will sync within 30 seconds!
   ```

### Features:

✅ **Instant Sync** - No 3-minute wait  
✅ **Smart Detection** - Only syncs changed applications  
✅ **Notifications** - Slack alerts on success/failure  
✅ **Manual Trigger** - Can trigger manually via GitHub UI  
✅ **Environment Support** - Dev/Staging/Prod  

---

## 🔧 Method 2: ArgoCD Webhook (Alternative)

### How It Works:

```
┌─────────────┐
│ Git Push    │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│ GitHub Webhook     │
│ Sends POST to      │
│ ArgoCD Webhook     │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ ArgoCD Webhook      │
│ Receives event      │
│ Syncs automatically │
└─────────────────────┘
```

### Setup Steps:

1. **Expose ArgoCD Webhook**:
   ```bash
   kubectl apply -f k8s/argocd/argocd-webhook-config.yaml
   ```

2. **Get Webhook URL**:
   ```bash
   # Port-forward to test locally
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   
   # Webhook URL: https://localhost:8080/api/webhook
   ```

3. **Configure GitHub Webhook**:
   - Go to: GitHub Repo → Settings → Webhooks → Add webhook
   - Payload URL: `https://argocd-webhook.yourdomain.com/api/webhook`
   - Content type: `application/json`
   - Events: `Just the push event`
   - Secret: (optional, for security)

4. **Add Secret to GitHub**:
   ```bash
   # In GitHub: Settings → Secrets → Actions
   ARGOCD_WEBHOOK_URL=https://argocd-webhook.yourdomain.com/api/webhook
   ```

---

## 📊 Comparison

| Method | Speed | Setup Complexity | Reliability |
|--------|-------|------------------|-------------|
| **Default Polling** | 3 min delay | ✅ Easy | ✅ Very reliable |
| **GitHub Actions → CLI** | ~30 sec | ⚠️ Medium | ✅ Reliable |
| **GitHub Webhook → ArgoCD** | ~10 sec | ⚠️ Complex | ⚠️ Depends on network |

---

## 🎯 Recommended Approach

**Use Method 1 (GitHub Actions → ArgoCD CLI)** because:
- ✅ Already implemented
- ✅ Works immediately
- ✅ No additional infrastructure needed
- ✅ Can add custom logic (notifications, conditions)
- ✅ Works with existing ArgoCD setup

---

## 🔍 How the Workflow Works

### Step-by-Step:

1. **Push to Git**:
   ```bash
   git push origin main
   ```

2. **GitHub Actions Triggers**:
   - Detects push to `main` branch
   - Detects changes in `k8s/` or `argocd/` folders
   - Starts workflow

3. **Workflow Executes**:
   - Connects to EKS cluster
   - Installs ArgoCD CLI
   - Port-forwards to ArgoCD server
   - Logs in to ArgoCD

4. **Detects Changed Applications**:
   - Analyzes changed files
   - Maps to ArgoCD applications
   - Example: `k8s/services/event-ingestion/` → `event-ingestion-service-dev`

5. **Syncs Applications**:
   - Runs `argocd app sync <app-name>`
   - Waits for sync completion
   - Reports status

6. **Notifications**:
   - Sends Slack notification (if configured)
   - Shows status in GitHub Actions

---

## 🛠️ Customization

### Sync Only Specific Applications:

```yaml
# In workflow_dispatch, specify application:
application: event-ingestion-service-dev
```

### Sync Only on Main Branch:

```yaml
# Already configured:
on:
  push:
    branches:
      - main  # Only main branch
```

### Add Conditions:

```yaml
# Only sync if tests pass
if: github.event_name == 'push' && github.ref == 'refs/heads/main'
```

---

## 📝 Configuration

### Reduce ArgoCD Polling Interval (Optional):

Even with webhook, you can reduce polling as backup:

```yaml
# k8s/argocd/argocd-cmd-params-cm.yaml
data:
  timeout.reconciliation: "60s"  # Poll every 60 seconds instead of 3 minutes
```

### Disable Auto-Sync (Use Webhook Only):

```yaml
# In ArgoCD Application
syncPolicy:
  automated: false  # Disable auto-sync
  # Webhook will trigger manual sync
```

---

## ✅ Benefits

1. **Instant Deployment**: No 3-minute wait
2. **Faster Feedback**: Know immediately if deployment works
3. **Better CI/CD**: Integrates with GitHub Actions
4. **Notifications**: Get alerts on success/failure
5. **Selective Sync**: Only syncs changed applications

---

## 🚨 Troubleshooting

### Workflow Not Triggering:

1. Check GitHub Actions tab
2. Verify file paths match workflow triggers
3. Check branch name matches

### ArgoCD Sync Failing:

1. Check ArgoCD server is running: `kubectl get pods -n argocd`
2. Verify kubeconfig is correct
3. Check ArgoCD application exists: `argocd app list`

### Port-Forward Issues:

1. Ensure port 8080 is not in use
2. Check ArgoCD service exists: `kubectl get svc -n argocd`

---

## 📚 Summary

**Before**: Push → Wait 3 minutes → ArgoCD syncs  
**After**: Push → GitHub Actions → ArgoCD syncs instantly (~30 seconds)

**File Created**: `.github/workflows/argocd-sync-webhook.yml`

**Status**: ✅ Ready to use! Just push code and watch it sync instantly!



