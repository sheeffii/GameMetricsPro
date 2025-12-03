# Kubernetes Resources

This directory contains all Kubernetes manifests organized with Kustomize.

## Quick Deploy - Single Command

Deploy everything at once:

```bash
kubectl apply -k k8s/
```

This single command deploys:
- **Namespaces** (kafka, databases, monitoring, argocd, default)
- **ArgoCD** (GitOps platform)
- **Secrets** (Database, Redis, Kafka credentials)
- **Strimzi Operator** (Kafka management)
- **Kafka Cluster** (KRaft mode with broker + controller)
- **Kafka UI** (Web interface)
- **Application Services** (event-ingestion, etc.)

## Structure

```
k8s/
├── kustomization.yaml          # Root - deploys everything
├── namespaces/
│   └── namespaces.yml          # All namespaces
├── argocd/
│   └── base/
│       ├── kustomization.yaml  # ArgoCD installation
│       └── namespace.yaml
├── secrets/
│   └── db-secrets.yaml         # Credentials
├── strimzi/
│   └── base/
│       └── kustomization.yaml  # Strimzi operator
├── kafka/
│   ├── base/
│   │   ├── kafka-node-pools.yaml    # KRaft broker & controller
│   │   ├── kafka.yaml               # Kafka cluster CR
│   │   ├── topics.yaml              # KafkaTopic CRs
│   │   └── kustomization.yaml
│   └── overlays/
│       └── dev/
│           ├── kafka-patch.yaml     # Environment-specific config
│           └── kustomization.yaml
├── kafka-ui/
│   ├── kafka-ui.yaml           # UI deployment & service
│   └── kustomization.yaml
└── services/
    └── event-ingestion/
        ├── deployment.yaml
        ├── service.yaml
        └── kustomization.yaml
```

## Deploy Everything

```bash
# From project root - single command deploys all components
kubectl apply -k k8s/

# From project root - single command deploys all components
kubectl apply -k k8s/

# Components deployed in order:
# 1. Namespaces
# 2. ArgoCD (optional - if you want GitOps)
# 3. Secrets
# 4. Strimzi operator
# 5. Kafka cluster
# 6. Kafka UI
# 7. Application services
```

## Selective Deployment

Deploy individual components if needed:

```bash
kubectl apply -k k8s/argocd/base/              # ArgoCD only
kubectl apply -k k8s/strimzi/base/             # Strimzi operator only
kubectl apply -k k8s/kafka/overlays/dev/       # Kafka cluster only
kubectl apply -k k8s/kafka-ui/                 # Kafka UI only
kubectl apply -k k8s/services/event-ingestion/ # App services only
```

## Adding New Components

1. Create your component directory under `k8s/`
2. Add a `kustomization.yaml` in that directory
3. Reference it in the root `k8s/kustomization.yaml`:

```yaml
resources:
  - your-new-component/
```

## GitOps with ArgoCD

Once ArgoCD is deployed:

1. Update `argocd/app-of-apps.yml` with your GitHub repo URL
2. Apply: `kubectl apply -f argocd/app-of-apps.yml`
3. ArgoCD automatically syncs all resources from Git

Access ArgoCD UI:
```bash
kubectl -n argocd port-forward svc/argocd-server 8082:80
# Get admin password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

## Verify Deployment

```bash
# Check all pods
kubectl get pods -n kafka

# Check Kafka cluster status
kubectl get kafka -n kafka

# Check topics
kubectl get kafkatopic -n kafka

# List topics inside Kafka
kubectl -n kafka exec gamemetrics-kafka-broker-0 -- \
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

## Access Kafka UI

```bash
# Port-forward to access UI
kubectl -n kafka port-forward svc/kafka-ui 8080:80

# Open http://localhost:8080 in browser
```

## Configuration

### Kafka Cluster
- **Mode**: KRaft (no ZooKeeper)
- **Broker**: 1 replica, 512Mi RAM, ephemeral storage
- **Controller**: 1 replica, 512Mi RAM, ephemeral storage
- **Listeners**: Plain (9092), TLS (9093)
- **Bootstrap**: `gamemetrics-kafka-kafka-bootstrap.kafka.svc:9092`

### Topics
All topics have `replicas: 1` and `min.insync.replicas: 1` for free-tier compatibility:
- `player.events.raw` (3 partitions)
- `player.events.processed` (3 partitions)
- `recommendations.generated` (2 partitions)
- `user.actions` (3 partitions)
- `notifications` (2 partitions)
- `dlq.events` (2 partitions)

### Environment Overlays
Override configs per environment in `kafka/overlays/{env}/kafka-patch.yaml`

## Update/Modify

```bash
# Edit any manifest in k8s/
# Then reapply:
kubectl apply -k k8s/

# Kustomize will handle diffs and update only changed resources
```

## Teardown

```bash
# Delete everything
kubectl delete -k k8s/

# Or just Kafka namespace
kubectl delete ns kafka
```

## Production Considerations

For production, update `kafka/overlays/prod/`:
- Increase replicas (3+ brokers, 3+ controllers)
- Use persistent storage (PVC instead of ephemeral)
- Adjust resource limits
- Enable authentication (SCRAM/mTLS)
- Set replication factors to 3
- Configure backups and monitoring
