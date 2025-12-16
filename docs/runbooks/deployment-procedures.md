# Deployment Procedures Runbook

## Standard Deployment (GitOps)

### Automated Deployment

1. **Push to Git**:
   ```bash
   git add .
   git commit -m "feat: update service"
   git push origin main
   ```

2. **GitHub Actions triggers**:
   - Builds Docker image
   - Pushes to ECR
   - Triggers ArgoCD sync

3. **ArgoCD syncs**:
   - Detects changes
   - Applies to cluster
   - Updates pods

### Manual Deployment

```bash
# 1. Build and push image
docker build -t <ECR_REGISTRY>/service-name:tag .
docker push <ECR_REGISTRY>/service-name:tag

# 2. Update deployment
kubectl set image deployment/service-name service-name=<ECR_REGISTRY>/service-name:tag -n gamemetrics

# 3. Watch rollout
kubectl rollout status deployment/service-name -n gamemetrics
```

## Canary Deployment

### Using ArgoCD Rollouts

```bash
# 1. Update Rollout manifest
vim k8s/rollouts/canary-deployment.yaml

# 2. Apply
kubectl apply -f k8s/rollouts/canary-deployment.yaml

# 3. Monitor canary
kubectl argo rollouts get rollout event-ingestion-service -n gamemetrics

# 4. Promote to 100%
kubectl argo rollouts promote event-ingestion-service -n gamemetrics
```

## Blue-Green Deployment

```bash
# 1. Deploy new version (green)
kubectl apply -f k8s/services/service-name/green-deployment.yaml

# 2. Test green deployment
kubectl port-forward svc/service-name-green 8080:8080

# 3. Switch traffic
kubectl patch service service-name -p '{"spec":{"selector":{"version":"green"}}}'

# 4. Remove blue deployment
kubectl delete deployment service-name-blue
```

## Rollback Procedures

### Quick Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/service-name -n gamemetrics

# Rollback to specific revision
kubectl rollout undo deployment/service-name --to-revision=2 -n gamemetrics
```

### ArgoCD Rollback

```bash
# List revisions
argocd app history service-name-dev

# Rollback to specific revision
argocd app rollback service-name-dev <revision-id>
```

## Pre-Deployment Checklist

- [ ] Code reviewed and approved
- [ ] Tests passing
- [ ] Security scan passed
- [ ] Image built and pushed
- [ ] Deployment manifest updated
- [ ] Backup created (for production)
- [ ] Rollback plan ready

## Post-Deployment Verification

```bash
# 1. Check pods are running
kubectl get pods -n gamemetrics -l app=service-name

# 2. Check service health
curl http://service-name.gamemetrics.svc.cluster.local/health/ready

# 3. Check metrics
curl http://service-name.gamemetrics.svc.cluster.local/metrics

# 4. Monitor logs
kubectl logs -f deployment/service-name -n gamemetrics
```

## Production Deployment

### Steps:

1. **Deploy to Dev** → Test
2. **Deploy to Staging** → Test
3. **Deploy to Production** → Monitor

### Production Safety:

- Use canary deployment
- Monitor error rates
- Have rollback ready
- Deploy during maintenance window



