# KUSTOMIZATION FLOW EXPLANATION
# GameMetrics Real-time Event Processing

## 🔄 HIERARCHICAL STRUCTURE (Parent → Child)

```
k8s/kustomization.yaml (ROOT - ORCHESTRATOR)
│
├─→ argocd/overlays (PARENT for ArgoCD deployment)
│   ├─→ argocd/base (CHILD - Base ArgoCD install)
│   │   └─→ Official ArgoCD manifests (https://raw.githubusercontent.com/...)
│   ├─→ argocd-server-resources-patch.yaml (Patch applied to base)
│   └─→ github-repo-creds.yaml (Secret added to base)
│
├─→ namespaces/namespaces.yml
│   └─→ Creates: argocd, kafka, gamemetrics, databases, monitoring
│
├─→ secrets/kustomization.yaml
│   └─→ db-secrets.yaml (DB credentials, Redis, Kafka endpoints)
│
├─→ strimzi/base
│   └─→ Kafka operator deployment
│
├─→ kafka/overlays/dev
│   └─→ Kafka cluster configuration (dev environment)
│
├─→ kafka-ui/kustomization.yaml
│   └─→ Kafka UI dashboard
│
└─→ services/event-ingestion
    └─→ Event ingestion service deployment
```

## 🎯 DEPLOYMENT FLOW

### **Option 1: Deploy Everything (Recommended for Production)**
```bash
kubectl apply -k k8s/
```
This runs the ROOT kustomization which automatically:
1. Creates namespaces first
2. Deploys ArgoCD (with overlays = base + patches + secrets)
3. Deploys all infrastructure (Kafka, Strimzi, secrets, etc.)

---

### **Option 2: Deploy Only ArgoCD**
```bash
# Deploy ArgoCD with all customizations (resources + secret)
kubectl apply -k k8s/argocd/overlays/
```
This does NOT require running `argocd/base` separately because:
- `overlays` contains `resources: ../base` in its kustomization.yaml
- It automatically includes and builds the base

---

### **Option 3: Deploy Only Base ArgoCD (Minimal)**
```bash
kubectl apply -k k8s/argocd/base/
```
This deploys only official ArgoCD manifests WITHOUT:
- ❌ Resource limits for argocd-server
- ❌ GitHub credentials secret
- ❌ Not recommended - missing critical configs

---

## 📋 CURRENT DEPLOYMENT STATUS

✅ **Already Deployed:**
- ArgoCD base (official manifests)
- ArgoCD overlays (resource patches + GitHub secret)
- Applications discovered (event-ingestion-dev/prod, kafka-dev)
- All ArgoCD components running (7 pods)

⏳ **Still Need (via ArgoCD):**
- Kafka infrastructure (kafka/base)
- Strimzi operator (strimzi/base)
- Database secrets (secrets/)
- Application deployments

---

## 🔑 KEY KUSTOMIZE CONCEPTS

### **Base vs Overlays**
- **Base**: Original/default configuration (ArgoCD official install)
- **Overlay**: Extends base with customizations (resource limits, patches, secrets)

### **How Overlays Work**
```yaml
# k8s/argocd/overlays/kustomization.yaml
resources:
  - ../base                                    # Include base
  - github-repo-creds.yaml                     # Add secret

patchesStrategicMerge:
  - argocd-server-resources-patch.yaml         # Modify deployment
```

This means:
1. Start with `../base` (all official ArgoCD manifests)
2. Add `github-repo-creds.yaml` secret on top
3. Apply `argocd-server-resources-patch.yaml` patch to modify the argocd-server deployment
4. Result: Complete ArgoCD with resources + credentials

---

## ⚠️ DO NOT RUN BOTH

❌ **WRONG - Causes conflicts:**
```bash
kubectl apply -k k8s/argocd/base/        # Deploy base
kubectl apply -k k8s/argocd/overlays/    # Deploy overlay (includes base again!)
# Result: Duplicate resources, conflicts
```

✅ **RIGHT - Use overlays which includes base:**
```bash
kubectl apply -k k8s/argocd/overlays/    # Deploy overlay (automatically includes base)
# Result: Clean deployment with customizations
```

---

## 🚀 RECOMMENDED DEPLOYMENT STRATEGY

### **For New Cluster:**
```bash
# Option A: Deploy everything at once
kubectl apply -k k8s/

# Option B: Deploy step-by-step
kubectl apply -k k8s/namespaces/
kubectl apply -k k8s/argocd/overlays/
kubectl apply -k k8s/strimzi/base/
# ... etc
```

### **For Updating Existing Cluster:**
```bash
# Update specific component
kubectl apply -k k8s/argocd/overlays/    # Only updates ArgoCD with new resources/secrets

# Or update everything
kubectl apply -k k8s/                     # Root kustomization handles all
```

---

## 📦 WHAT GETS DEPLOYED WHERE

| Component | Namespace | Deployed Via | Status |
|-----------|-----------|--------------|--------|
| ArgoCD | argocd | `k8s/argocd/overlays/` | ✅ Running |
| Kafka | kafka | `k8s/kafka/overlays/dev/` | ⏳ Via ArgoCD |
| Strimzi | kafka | `k8s/strimzi/base/` | ⏳ Via ArgoCD |
| Secrets | gamemetrics | `k8s/secrets/` | ⏳ Via ArgoCD |
| Event-Ingestion | gamemetrics | ArgoCD Application | ⏳ Syncing |

---

## 🎯 ANSWER TO YOUR QUESTIONS

**Q: Do we need to run argocd/base?**
- ❌ NO - Run `argocd/overlays/` instead
- The overlay automatically includes the base
- Base alone lacks resource limits and GitHub credentials

**Q: What is the root?**
- `k8s/kustomization.yaml` - Master orchestrator
- Coordinates all child kustomizations

**Q: What are the children?**
- `argocd/overlays/` - ArgoCD deployment
- `secrets/kustomization.yaml` - Application secrets
- `kafka/overlays/dev/` - Kafka configuration
- `namespaces/namespaces.yml` - Namespace definitions
- `strimzi/base/` - Kafka operator
- `kafka-ui/kustomization.yaml` - UI dashboard
- `services/event-ingestion/` - Event service

**Q: Who is calling who?**
- Root `k8s/kustomization.yaml` calls all children
- `overlays/` calls `base/` and adds customizations
- Order: Namespaces → ArgoCD → Infrastructure → Services

**Q: How does kustomization work?**
1. **Read**: Load kustomization.yaml
2. **Gather**: Collect all resources (base + additions)
3. **Patch**: Apply strategic merge patches
4. **Render**: Generate final Kubernetes manifests
5. **Deploy**: Send to cluster via kubectl apply -k

