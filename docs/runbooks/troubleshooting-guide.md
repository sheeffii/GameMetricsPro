# Troubleshooting Guide - Common Issues

## Pod Issues

### Pod Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n gamemetrics

# Check logs
kubectl logs <pod-name> -n gamemetrics

# Common causes:
# - Image pull errors → Check ECR access
# - Resource limits → Check resource requests
# - ConfigMap/Secret missing → Check secrets exist
```

### Pod CrashLooping

```bash
# Check crash reason
kubectl describe pod <pod-name> -n gamemetrics | grep -A 10 "Last State"

# Common causes:
# - Application error → Check application logs
# - OOMKilled → Increase memory limits
# - Health check failing → Check health endpoint
```

## Service Issues

### Service Not Accessible

```bash
# Check service endpoints
kubectl get endpoints <service-name> -n gamemetrics

# Check service selector
kubectl get svc <service-name> -n gamemetrics -o yaml

# Verify pods have correct labels
kubectl get pods -n gamemetrics --show-labels
```

## Kafka Issues

### Consumer Lag High

```bash
# Check consumer lag
kubectl exec -n kafka <kafka-pod> -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group <group-id>

# Solutions:
# - Scale up consumers
# - Check for processing errors
# - Verify Kafka broker health
```

### Topic Not Found

```bash
# List topics
kubectl get kafkatopics -n kafka

# Create topic if missing
kubectl apply -f k8s/kafka/base/topics.yaml
```

## Database Issues

### Connection Refused

```bash
# Check database endpoint
kubectl get secret db-secrets -n gamemetrics -o jsonpath='{.data.host}' | base64 -d

# Test connection
kubectl run -it --rm test-db --image=postgres:15 --restart=Never -- \
  psql -h <db-host> -U postgres -d gamemetrics

# Common causes:
# - Security group blocking
# - Wrong endpoint
# - Credentials incorrect
```

## ArgoCD Issues

### Application OutOfSync

```bash
# Check sync status
argocd app get <app-name>

# Force sync
argocd app sync <app-name>

# Check Git repository
argocd repo get <repo-url>
```

### Sync Failed

```bash
# Check sync logs
argocd app logs <app-name> --tail=100

# Common causes:
# - Git repository not accessible
# - Kubernetes manifest invalid
# - Resource conflicts
```

## Network Issues

### Pods Can't Communicate

```bash
# Check NetworkPolicies
kubectl get networkpolicies -n gamemetrics

# Test connectivity
kubectl run -it --rm test-pod --image=busybox --restart=Never -- \
  wget -O- http://service-name.gamemetrics.svc.cluster.local:8080/health/live
```

## Performance Issues

### High CPU Usage

```bash
# Check CPU usage
kubectl top pods -n gamemetrics

# Scale up
kubectl scale deployment <deployment-name> --replicas=5 -n gamemetrics
```

### High Memory Usage

```bash
# Check memory usage
kubectl top pods -n gamemetrics

# Increase memory limits
kubectl patch deployment <deployment-name> -n gamemetrics -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"<container>","resources":{"limits":{"memory":"2Gi"}}}]}}}}'
```

## Quick Diagnostic Commands

```bash
# Overall health check
kubectl get pods -A | grep -v Running

# Check all services
kubectl get svc -A

# Check events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Check resource usage
kubectl top nodes
kubectl top pods -A
```



