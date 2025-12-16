# QUICK REFERENCE: Kustomization Call Flow

## 📊 WHO CALLS WHO (Parent → Child Direction)

```
┌─────────────────────────────────────────────────────────┐
│  ROOT: k8s/kustomization.yaml                           │
│  "I orchestrate everything"                             │
└──────────────────┬──────────────────────────────────────┘
                   │
        ┌──────────┼──────────┬──────────┬──────────┐
        ▼          ▼          ▼          ▼          ▼
    ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
    │argocd/ │ │secrets/│ │strimzi/│ │kafka/  │ │kafka-ui│
    │overlays│ │kustomization
    │        │ │        │ │base    │ │overlays│ │kustomization
    └──┬─────┘ └────────┘ └────────┘ └────────┘ └────────┘
       │
       │ "includes me"
       ▼
    ┌──────────────┐
    │argocd/base   │
    │(Official)    │
    └──────────────┘
```

## 🔄 DETAILED FLOW FOR ARGOCD

```
kubectl apply -k k8s/argocd/overlays/
                    │
                    ▼
        ┌─────────────────────────────┐
        │ Read overlays/kustomization.yaml
        └─────────────────────────────┘
                    │
        ┌───────────┴────────────┐
        ▼                        ▼
    Include base/          Add secrets &
    kustomization.yaml      patches
        │                        │
        ▼                        ▼
    Load official         + github-repo-creds.yaml
    ArgoCD manifests      + argocd-server-resources-patch.yaml
        │
        └───────────┬────────────┘
                    ▼
        ┌─────────────────────────────┐
        │ Render final manifests      │
        │ (combined + patched)        │
        └─────────────────────────────┘
                    │
                    ▼
        ┌─────────────────────────────┐
        │ kubectl apply to cluster    │
        └─────────────────────────────┘
```

## ✅ CURRENT STATE

```
Deployed (via kubectl apply -k k8s/argocd/overlays/):
✅ ArgoCD base (official manifests)
✅ ArgoCD server (with 500m CPU, 512Mi memory limits)
✅ GitHub credentials secret
✅ All ArgoCD components (7 pods running)

NOT YET deployed:
❌ Kafka infrastructure
❌ Application services
❌ Database secrets
```

## 🚀 CORRECT DEPLOYMENT ORDER

```
Step 1: kubectl apply -k k8s/namespaces/
        └─→ Creates all namespaces

Step 2: kubectl apply -k k8s/argocd/overlays/
        └─→ Deploys ArgoCD with customizations

Step 3: kubectl apply -k k8s/
        └─→ Deploys everything else
            (Kafka, secrets, services, etc.)
```

## ⚡ QUICK ANSWER

**Do we need to run argocd/base?**
- ❌ NO. Run `overlays/` which includes base automatically.

**What calls what?**
- Root calls children
- Overlays call base
- Order matters: namespaces first, then argocd, then infrastructure

**Can I run both base and overlays?**
- ❌ NO. That's duplication. Use overlays (it includes base).

**What's deployed right now?**
- ✅ ArgoCD is ready
- ⏳ Everything else via ArgoCD GitOps

