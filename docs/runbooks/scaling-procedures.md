# Scaling Procedures Runbook

## Horizontal Scaling (HPA)

### Automatic Scaling

HPA is configured for all services. Scaling happens automatically based on:
- CPU utilization > 70%
- Memory utilization > 80%
- Custom metrics (event rate, etc.)

### Manual Scaling

```bash
# Scale specific service
kubectl scale deployment event-ingestion-service --replicas=5 -n gamemetrics

# Scale all services in namespace
kubectl scale deployment --all --replicas=3 -n gamemetrics
```

## Vertical Scaling (VPA)

### Apply VPA Recommendations

```bash
# Get VPA recommendations
kubectl describe vpa event-ingestion-service-vpa -n gamemetrics

# Apply recommendations (manual)
kubectl patch deployment event-ingestion-service -n gamemetrics -p '{"spec":{"template":{"spec":{"containers":[{"name":"event-ingestion","resources":{"requests":{"cpu":"500m","memory":"512Mi"}}}]}}}}'
```

## Cluster Scaling

### Add Nodes

```bash
# EKS: Update node group
aws eks update-nodegroup-config \
  --cluster-name gamemetrics-dev \
  --nodegroup-name workers \
  --scaling-config minSize=3,maxSize=10,desiredSize=5
```

## Database Scaling

### PostgreSQL Scaling

```bash
# RDS: Modify instance
aws rds modify-db-instance \
  --db-instance-identifier gamemetrics-db \
  --db-instance-class db.r5.xlarge \
  --apply-immediately
```

### Redis Scaling

```bash
# ElastiCache: Modify cluster
aws elasticache modify-replication-group \
  --replication-group-id gamemetrics-redis \
  --node-group-configuration NodeGroupId=0001,PrimaryAvailabilityZone=us-east-1a,ReplicaAvailabilityZones=us-east-1b,us-east-1c \
  --apply-immediately
```

## Kafka Scaling

### Add Brokers

```bash
# Update Kafka CR
kubectl patch kafka gamemetrics-kafka -n kafka --type merge -p '{"spec":{"kafka":{"replicas":3}}}'
```

### Scale Topics

```bash
# Increase partitions
kubectl patch kafkatopic player.events.raw -n kafka --type merge -p '{"spec":{"partitions":12}}'
```

## Monitoring Scaling

After scaling, monitor:
- Resource utilization
- Application performance
- Cost impact

```bash
# Check resource usage
kubectl top pods -n gamemetrics

# Check HPA status
kubectl get hpa -n gamemetrics
```



