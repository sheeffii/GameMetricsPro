# 🔄 ArgoCD Workflow Explained - Simple Guide

## 📁 Folder Structure Explained

### Two Different Folders, Two Different Purposes:

```
RealtimeGaming/
├── argocd/                    ← ArgoCD Application Definitions (Git)
│   ├── app-of-apps.yml        ← Root application (points to apps folder)
│   ├── apps/                  ← All service applications
│   │   ├── all-services.yml   ← All 8 microservices defined here
│   │   └── applications.yml   ← Legacy/alternative definitions
│   └── projects/              ← Project configurations
│       └── gamemetrics-project.yml
│
└── k8s/                       ← Kubernetes Manifests (Git)
    └── argocd/                ← ArgoCD Configuration Files
        ├── app-of-apps.yaml   ← Alternative root app definition
        ├── applications/      ← Kustomize applications
        ├── project-gamemetrics.yaml
        └── ...                ← Other ArgoCD configs
```

## 🎯 What Each Folder Does

### 1. `argocd/` Folder (Git Repository)
**Purpose**: Contains ArgoCD Application definitions that ArgoCD reads from Git

**What's Inside**:
- **Application Definitions**: Tells ArgoCD WHAT to deploy
- **App-of-Apps Pattern**: Root application that manages other applications
- **Project Configs**: Security and permissions

**Example Flow**:
```
argocd/app-of-apps.yml
  └─> Points to: argocd/apps/all-services.yml
       └─> Defines: event-ingestion-service-dev
            └─> Points to: k8s/services/event-ingestion (actual K8s manifests)
```

### 2. `k8s/argocd/` Folder (Git Repository)
**Purpose**: Contains ArgoCD configuration files and alternative application definitions

**What's Inside**:
- **Project Definitions**: Security policies, allowed namespaces
- **Application Definitions**: Alternative way to define apps
- **Notifications Config**: Slack/Email alerts
- **Resource Limits**: Free Tier optimizations

## 🔄 How ArgoCD Workflow Works

### Step-by-Step Flow:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. DEVELOPER MAKES CHANGE                                    │
│    - Edits k8s/services/event-ingestion/deployment.yaml    │
│    - Commits and pushes to GitHub                           │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. GITHUB REPOSITORY UPDATED                                │
│    https://github.com/sheeffii/GameMetricsPro.git          │
│    └─> k8s/services/event-ingestion/deployment.yaml        │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. ARGOCD DETECTS CHANGE (Every 3 minutes)                 │
│    ArgoCD polls Git repository                              │
│    Compares Git state vs Kubernetes state                   │
│    Finds: "OutOfSync" - Git has new version                 │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. ARGOCD APPLICATION DEFINITION                            │
│    Reads: argocd/apps/all-services.yml                      │
│    Finds: event-ingestion-service-dev                       │
│    Points to: k8s/services/event-ingestion/                │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. ARGOCD SYNC POLICY                                       │
│    Checks syncPolicy:                                       │
│    - automated: true → Auto-sync                            │
│    - selfHeal: true → Fix drift automatically              │
│    - prune: true → Delete removed resources                │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. ARGOCD APPLIES TO KUBERNETES                             │
│    kubectl apply -f k8s/services/event-ingestion/          │
│    Updates: Deployment, Service, ConfigMap, etc.            │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. KUBERNETES ROLLS OUT UPDATE                              │
│    - Creates new pod with new image                         │
│    - Waits for health check                                 │
│    - Terminates old pod                                     │
│    - Service routes traffic to new pod                      │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. ARGOCD REPORTS STATUS                                    │
│    Status: Synced ✅                                        │
│    Health: Healthy ✅                                       │
│    Sends notification (if configured)                       │
└─────────────────────────────────────────────────────────────┘
```

## 📊 Visual Workflow Diagram

```
┌──────────────┐
│   Developer  │
│   Edits Code │
└──────┬───────┘
       │ git push
       ▼
┌─────────────────────────────────────┐
│   GitHub Repository                 │
│   GameMetricsPro.git                │
│   ├── k8s/services/...              │ ← Actual K8s manifests
│   └── argocd/apps/all-services.yml │ ← ArgoCD app definitions
└──────┬──────────────────────────────┘
       │
       │ ArgoCD polls every 3 min
       ▼
┌─────────────────────────────────────┐
│   ArgoCD Server (in Kubernetes)     │
│   ├── Reads: argocd/apps/...        │ ← What to deploy
│   ├── Reads: k8s/services/...       │ ← How to deploy
│   └── Compares Git vs K8s state     │
└──────┬──────────────────────────────┘
       │
       │ If different → Sync
       ▼
┌─────────────────────────────────────┐
│   Kubernetes Cluster                │
│   ├── Namespace: gamemetrics         │
│   ├── Deployment: event-ingestion    │
│   ├── Service: event-ingestion      │
│   └── Pods: Running ✅              │
└─────────────────────────────────────┘
```

## 🔑 Key Concepts

### App-of-Apps Pattern
```
Root Application (app-of-apps.yml)
    │
    ├─> Points to: argocd/apps/all-services.yml
    │
    └─> This file contains 8 child applications:
        ├─> event-ingestion-service-dev
        ├─> event-processor-service-dev
        ├─> recommendation-engine-dev
        ├─> analytics-api-dev
        ├─> user-service-dev
        ├─> notification-service-dev
        ├─> data-retention-service-dev
        └─> admin-dashboard-dev
```

### Why Two Folders?

**`argocd/` folder**:
- Contains ArgoCD-specific definitions
- Tells ArgoCD WHAT applications exist
- Managed by ArgoCD Application Controller

**`k8s/argocd/` folder**:
- Contains ArgoCD configuration
- Project definitions (security)
- Resource limits
- Notifications config
- Can also contain application definitions (alternative approach)

## 🎯 Real Example

### Scenario: Update Event Ingestion Service

1. **Developer edits**:
   ```yaml
   # File: k8s/services/event-ingestion/deployment.yaml
   image: my-ecr/event-ingestion-service:v1.2.3
   ```

2. **Commits and pushes**:
   ```bash
   git add k8s/services/event-ingestion/deployment.yaml
   git commit -m "Update event ingestion to v1.2.3"
   git push origin main
   ```

3. **ArgoCD detects** (within 3 minutes):
   - Reads: `argocd/apps/all-services.yml`
   - Finds: `event-ingestion-service-dev`
   - Sees it points to: `k8s/services/event-ingestion`
   - Compares Git vs Kubernetes
   - Finds: Image version different → OutOfSync

4. **ArgoCD syncs** (if automated):
   - Applies: `kubectl apply -k k8s/services/event-ingestion`
   - Updates deployment
   - Kubernetes rolls out new version

5. **Result**:
   - New pod with v1.2.3 running
   - Old pod terminated
   - Status: Synced ✅

## 🔧 Configuration Files Explained

### `argocd/app-of-apps.yml`
```yaml
# Root application - manages other applications
source:
  path: argocd/apps  # Points to folder with all app definitions
```

### `argocd/apps/all-services.yml`
```yaml
# Defines all 8 microservices
# Each application points to actual K8s manifests
source:
  path: k8s/services/event-ingestion  # Actual deployment files
```

### `k8s/services/event-ingestion/deployment.yaml`
```yaml
# Actual Kubernetes deployment manifest
# This is what gets applied to cluster
apiVersion: apps/v1
kind: Deployment
metadata:
  name: event-ingestion-service
spec:
  containers:
    - image: my-ecr/event-ingestion-service:latest
```

## 🚀 How to Use

### Option 1: Use `argocd/` folder (Recommended)
```bash
# Deploy root application
kubectl apply -f argocd/app-of-apps.yml

# This will automatically create all 8 service applications
```

### Option 2: Use `k8s/argocd/` folder
```bash
# Deploy project first
kubectl apply -f k8s/argocd/project-gamemetrics.yaml

# Then deploy app-of-apps
kubectl apply -f k8s/argocd/app-of-apps.yaml
```

## 📝 Summary

**Simple Answer**:
- **`argocd/`** = ArgoCD application definitions (WHAT to deploy)
- **`k8s/argocd/`** = ArgoCD configuration (HOW ArgoCD works)
- **`k8s/services/`** = Actual Kubernetes manifests (WHAT gets deployed)

**Workflow**:
1. Edit K8s manifests in `k8s/services/`
2. Push to GitHub
3. ArgoCD detects change
4. ArgoCD reads app definition from `argocd/apps/`
5. ArgoCD applies manifests from `k8s/services/`
6. Kubernetes updates running pods

**Key Point**: ArgoCD is the "bridge" between Git (source of truth) and Kubernetes (running cluster).



