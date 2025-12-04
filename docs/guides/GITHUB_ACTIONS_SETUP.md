# GitHub Actions CI + ArgoCD Setup Guide

## Part 1: GitHub Actions Workflow (CI - Continuous Integration)

### What GitHub Actions Will Do:
1. **Run tests** when code is pushed
2. **Build Docker image** with new code
3. **Push image to registry** (Docker Hub, ECR, etc.)
4. **Update Kubernetes manifests** with new image tag
5. **Commit changes back** to Git (triggers ArgoCD)

---

## Create GitHub Actions Workflow

### Step 1: Create Workflow File

```bash
mkdir -p .github/workflows
touch .github/workflows/build-and-deploy.yml
```

### Step 2: Add Workflow Configuration

Create `.github/workflows/build-and-deploy.yml`:

```yaml
name: Build, Test, and Update Manifests

on:
  push:
    branches:
      - main
      - develop
      - 'feature/**'
    paths:
      - 'src/**'           # Only run if source code changes
      - 'requirements.txt' # Or if dependencies change
      - '.github/workflows/build-and-deploy.yml'

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    
    env:
      REGISTRY: docker.io                    # Change if using ECR, GCR, etc.
      IMAGE_NAME_CONSUMER: ${{ secrets.DOCKER_USERNAME }}/event-consumer
      IMAGE_NAME_PRODUCER: ${{ secrets.DOCKER_USERNAME }}/event-producer
    
    steps:
      # Step 1: Checkout code
      - name: Checkout Code
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
      
      # Step 2: Set up Docker Buildx (for faster builds)
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      # Step 3: Log in to Docker Hub
      - name: Log in to Docker Registry
        uses: docker/login-action@v2
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}
      
      # Step 4: Run Tests
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install Dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          pip install pytest pytest-cov
      
      - name: Run Tests
        run: |
          pytest tests/ --cov=src --cov-report=xml
      
      - name: Upload Coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.xml
      
      # Step 5: Generate Image Tag
      - name: Generate Image Tag
        id: meta
        run: |
          # Create tags based on branch
          if [[ "${{ github.ref }}" == "refs/heads/main" ]]; then
            echo "CONSUMER_TAG=${{ env.IMAGE_NAME_CONSUMER }}:latest" >> $GITHUB_OUTPUT
            echo "CONSUMER_VERSION=${{ env.IMAGE_NAME_CONSUMER }}:v$(date +%Y%m%d-%H%M%S)" >> $GITHUB_OUTPUT
            echo "PRODUCER_TAG=${{ env.IMAGE_NAME_PRODUCER }}:latest" >> $GITHUB_OUTPUT
            echo "PRODUCER_VERSION=${{ env.IMAGE_NAME_PRODUCER }}:v$(date +%Y%m%d-%H%M%S)" >> $GITHUB_OUTPUT
            echo "TARGET_BRANCH=main" >> $GITHUB_OUTPUT
          else
            echo "CONSUMER_TAG=${{ env.IMAGE_NAME_CONSUMER }}:${{ github.ref_name }}-${{ github.sha }}" >> $GITHUB_OUTPUT
            echo "CONSUMER_VERSION=${{ env.IMAGE_NAME_CONSUMER }}:${{ github.ref_name }}-${{ github.sha }}" >> $GITHUB_OUTPUT
            echo "PRODUCER_TAG=${{ env.IMAGE_NAME_PRODUCER }}:${{ github.ref_name }}-${{ github.sha }}" >> $GITHUB_OUTPUT
            echo "PRODUCER_VERSION=${{ env.IMAGE_NAME_PRODUCER }}:${{ github.ref_name }}-${{ github.sha }}" >> $GITHUB_OUTPUT
            echo "TARGET_BRANCH=${{ github.ref_name }}" >> $GITHUB_OUTPUT
          fi
      
      # Step 6: Build and Push Consumer Image
      - name: Build and Push Consumer Image
        uses: docker/build-push-action@v4
        with:
          context: ./src/consumer
          push: true
          tags: |
            ${{ steps.meta.outputs.CONSUMER_TAG }}
            ${{ steps.meta.outputs.CONSUMER_VERSION }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
      
      # Step 7: Build and Push Producer Image
      - name: Build and Push Producer Image
        uses: docker/build-push-action@v4
        with:
          context: ./src/producer
          push: true
          tags: |
            ${{ steps.meta.outputs.PRODUCER_TAG }}
            ${{ steps.meta.outputs.PRODUCER_VERSION }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
      
      # Step 8: Update Kubernetes Manifests
      - name: Update Consumer Manifest
        run: |
          # Update image tag in deployment
          sed -i 's|image: .*event-consumer:.*|image: ${{ steps.meta.outputs.CONSUMER_VERSION }}|g' \
            k8s/services/event-ingestion/consumer-deployment.yaml
          
          # Verify change
          grep "image:" k8s/services/event-ingestion/consumer-deployment.yaml
      
      - name: Update Producer Manifest
        run: |
          # Update image tag in deployment
          sed -i 's|image: .*event-producer:.*|image: ${{ steps.meta.outputs.PRODUCER_VERSION }}|g' \
            k8s/services/event-ingestion/producer-deployment.yaml
          
          # Verify change
          grep "image:" k8s/services/event-ingestion/producer-deployment.yaml
      
      # Step 9: Commit and Push Updated Manifests
      - name: Commit Updated Manifests
        run: |
          git config user.email "ci-bot@gamemetrics.io"
          git config user.name "GameMetrics CI Bot"
          git add k8s/services/event-ingestion/
          
          # Only commit if changes exist
          if git diff --cached --quiet; then
            echo "No changes to commit"
          else
            git commit -m "ci: update container images
            
            Consumer: ${{ steps.meta.outputs.CONSUMER_VERSION }}
            Producer: ${{ steps.meta.outputs.PRODUCER_VERSION }}
            
            Commit: ${{ github.sha }}"
            git push origin ${{ steps.meta.outputs.TARGET_BRANCH }}
          fi
      
      # Step 10: Create GitHub Release (for main branch only)
      - name: Create Release
        if: github.ref == 'refs/heads/main'
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ steps.meta.outputs.CONSUMER_VERSION }}
          release_name: Release ${{ steps.meta.outputs.CONSUMER_VERSION }}
          body: |
            ## Changes
            - Consumer: ${{ steps.meta.outputs.CONSUMER_VERSION }}
            - Producer: ${{ steps.meta.outputs.PRODUCER_VERSION }}
            
            ## Docker Images
            - ${{ steps.meta.outputs.CONSUMER_VERSION }}
            - ${{ steps.meta.outputs.PRODUCER_VERSION }}
          draft: false
          prerelease: false

      # Step 11: Notify Slack (Optional)
      - name: Notify Slack
        if: always()
        uses: 8398a7/action-slack@v3
        with:
          status: ${{ job.status }}
          text: 'Build ${{ job.status }}: ${{ github.repository }} - ${{ github.ref }}'
          webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

---

## Part 2: GitHub Secrets Setup

### Required Secrets to Configure

In GitHub UI:
1. Go to: **Settings → Secrets and variables → Actions**
2. Add these secrets:

```
DOCKER_USERNAME     = your-docker-username
DOCKER_PASSWORD     = your-docker-password (or token)
SLACK_WEBHOOK       = https://hooks.slack.com/... (optional)
```

---

## Part 3: GitHub Webhook Setup (Real-time ArgoCD Sync)

### What Webhook Does:
Instead of waiting 3 minutes for ArgoCD to poll, webhook notifies ArgoCD immediately when code is pushed.

### Step 1: Get ArgoCD Webhook URL

```bash
# Port forward to ArgoCD server
kubectl port-forward -n argocd svc/argocd-server 8080:443 &

# Or get external IP
kubectl get svc -n argocd argocd-server

# Your webhook URL: https://<argocd-server-ip>/api/webhook
# Example: https://argocd.gamemetrics.io/api/webhook
```

### Step 2: Add Webhook to GitHub

In GitHub UI:
1. Go to: **Settings → Webhooks → Add webhook**
2. Fill in:
   - **Payload URL**: `https://argocd.gamemetrics.io/api/webhook`
   - **Content type**: `application/json`
   - **Events**: Select "Just the push event"
   - **Active**: ✓ Check this
3. Click: **Add webhook**

### Step 3: Test Webhook

```bash
# Make a small change and push
echo "# Test" >> README.md
git add README.md
git commit -m "test: trigger webhook"
git push origin main

# Check webhook delivery in GitHub
# Settings → Webhooks → Your webhook → Recent Deliveries
# Should show green checkmark (200 OK)

# Check ArgoCD sync
kubectl get applications -n argocd -w
# Should show "Syncing" status immediately
```

---

## Part 4: Complete Example Scenario

### Scenario: Add New Event Filter to Consumer

#### Step 1: Developer Makes Change

```bash
# Create feature branch
git checkout -b feature/add-priority-filter

# Edit consumer code
cat >> src/consumer/app.py << 'EOF'
def filter_by_priority(event):
    """Filter low-priority events"""
    return event.get('priority') in ['HIGH', 'CRITICAL']
EOF

# Test locally
pytest tests/test_consumer.py -v

# Commit
git add src/consumer/app.py
git commit -m "feat: add priority filter to event consumer"

# Push feature branch
git push origin feature/add-priority-filter
```

#### Step 2: GitHub Actions Runs (Automatic)

Workflow triggered by push:
```
✓ Checkout code
✓ Run tests (pytest)
  └─ 45 tests passed
✓ Build consumer image: event-consumer:feature-add-priority-filter-abc123
✓ Push to Docker Hub
✓ Update consumer-deployment.yaml with new image tag
✓ Commit changes back to git (feature branch)
```

#### Step 3: Create Pull Request

```bash
# GitHub automatically detects and prompts to create PR

# PR Description:
# Title: Add Priority Filter to Consumer
# Body:
#   - Adds new filter to exclude low-priority events
#   - Tested locally with 45 unit tests ✓
#   - Docker image: event-consumer:feature-add-priority-filter-abc123
#   - Manifest updated: k8s/services/event-ingestion/consumer-deployment.yaml
```

#### Step 4: Team Review and Merge

```bash
# Team reviews code
# Comment: "Looks good! I tested the filter logic."
# Approve ✓
# Merge to main ✓
```

#### Step 5: GitHub Actions Runs Again (for main)

```
✓ Checkout code
✓ Run tests (pytest)
✓ Build consumer image: event-consumer:latest and event-consumer:v20240612-143022
✓ Push to Docker Hub
✓ Update consumer-deployment.yaml: image: event-consumer:v20240612-143022
✓ Commit to main
✓ Create release v20240612-143022
✓ Send Slack notification
```

#### Step 6: GitHub Webhook Notifies ArgoCD (5 seconds)

```
GitHub → Webhook → ArgoCD
↓
ArgoCD fetches main branch
↓
Detects change:
  File: k8s/services/event-ingestion/consumer-deployment.yaml
  Old: image: event-consumer:v20240612-142900
  New: image: event-consumer:v20240612-143022
↓
Status: OutOfSync
```

#### Step 7: ArgoCD UI Shows Change

```
Application: event-ingestion-prod
Status: OutOfSync ⚠️
Message: "Updated to commit abc123 - Consumer image updated"

Changes:
  - consumer-deployment.yaml
    - image: event-consumer:v20240612-142900 → event-consumer:v20240612-143022
```

#### Step 8: Production Operator Reviews

```bash
# Checks in ArgoCD UI:
# - What changed? Consumer image (safe, tested in CI)
# - Why? Added priority filter feature
# - Is it tested? Yes, 45 unit tests passed ✓

# Approves:
argocd app sync event-ingestion-prod
```

#### Step 9: Kubernetes Updates

```bash
# Rolling update starts
kubectl rollout status deployment/event-consumer -n gamemetrics

# Pods update:
# - Old pod: event-consumer:v20240612-142900 (terminating)
# - New pod: event-consumer:v20240612-143022 (starting)
# - New pod: event-consumer:v20240612-143022 (ready)
# - Old pod: (terminated)

# Service maintains connections throughout
```

#### Step 10: Monitor in Production

```bash
# Check new pods
kubectl get pods -n gamemetrics -l app=event-consumer

# View logs for new feature
kubectl logs -n gamemetrics event-consumer-xxxxx -f | grep "priority"

# Check metrics
# - Event rate ✓
# - Error rate ✓ (should be lower with filter)
- Processing latency ✓
```

**Total time**: 5-15 minutes from PR merge to production

---

## Workflow Visualization

```
┌─────────────────────────────────────────────────────────────┐
│                 COMPLETE CI/CD WITH WEBHOOK                 │
└─────────────────────────────────────────────────────────────┘

Developer (5 sec)
└─ git push

┌──────────────────────────────────────────┐
│ GitHub Actions (3-5 min)                 │
├──────────────────────────────────────────┤
│ ✓ Run tests                              │
│ ✓ Build Docker images                    │
│ ✓ Push to registry                       │
│ ✓ Update K8s manifests                   │
│ ✓ Commit back to git                     │
└──────────────────────────────────────────┘
           │
           │ git push (updated manifests)
           ▼
┌──────────────────────────────────────────┐
│ GitHub Webhook (5 sec)                   │
├──────────────────────────────────────────┤
│ ✓ Notifies ArgoCD                        │
└──────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────┐
│ ArgoCD (10 sec)                          │
├──────────────────────────────────────────┤
│ ✓ Fetches Git changes                    │
│ ✓ Shows in UI (OutOfSync)                │
│ ✓ Waits for manual approval              │
└──────────────────────────────────────────┘
           │
           │ Operator approves
           ▼
┌──────────────────────────────────────────┐
│ Kubernetes (30-60 sec)                   │
├──────────────────────────────────────────┤
│ ✓ Rolling update starts                  │
│ ✓ New pods deploy                        │
│ ✓ Old pods terminate                     │
│ ✓ Ready for traffic                      │
└──────────────────────────────────────────┘

TOTAL: ~5-15 minutes from push to production
```

---

## Troubleshooting

### Issue 1: GitHub Actions Doesn't Run

```bash
# Check workflow file syntax
# Ensure .github/workflows/build-and-deploy.yml is valid YAML

# Verify workflow is enabled
# Settings → Actions → Workflows → Check status

# View workflow runs
# Actions tab → Select workflow → View logs
```

### Issue 2: Docker Images Not Pushing

```bash
# Verify Docker credentials are correct
# Settings → Secrets → Check DOCKER_USERNAME and DOCKER_PASSWORD

# Test locally
docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
docker push $DOCKER_USERNAME/event-consumer:test
```

### Issue 3: Manifests Not Updating

```bash
# Check sed command syntax in workflow
# Make sure file path is correct: k8s/services/event-ingestion/consumer-deployment.yaml

# Verify deployment YAML format
cat k8s/services/event-ingestion/consumer-deployment.yaml | grep "image:"
```

### Issue 4: Webhook Not Triggering ArgoCD

```bash
# Verify webhook URL is correct
# Test in GitHub UI: Settings → Webhooks → Recent Deliveries

# Check ArgoCD logs for webhook errors
kubectl logs -n argocd deployment/argocd-server | grep webhook

# Manually test webhook
curl -X POST https://argocd.gamemetrics.io/api/webhook \
  -H "Content-Type: application/json" \
  -d '{"repository": {"name": "RealtimeGaming"}}'
```

---

## Best Practices

✅ **DO:**
- Commit all manifests to Git
- Use branch protection rules (require PR review)
- Run tests before building images
- Tag images with commit SHA or version
- Set up webhook for real-time sync
- Monitor GitHub Actions runs

❌ **DON'T:**
- Build images directly in ArgoCD
- Skip tests in CI
- Use `latest` tag in production (hard to track)
- Push manifests without committing to Git
- Deploy directly from GitHub Actions to K8s

---

## Next Steps

1. **Copy `.github/workflows/build-and-deploy.yml`** to your repo
2. **Add Docker credentials** to GitHub Secrets
3. **Set up GitHub Webhook** → ArgoCD
4. **Test the workflow**:
   - Push a small change
   - Watch GitHub Actions build
   - Check ArgoCD detects change
   - Approve and deploy
5. **Monitor production** for successful update

You now have **complete CI/CD automation**! 🚀
