# Disaster Recovery Runbook

## Overview
This runbook provides procedures for disaster recovery scenarios.

## Recovery Objectives

- **RPO (Recovery Point Objective)**: 5 minutes
- **RTO (Recovery Time Objective)**: 15 minutes

## Backup Locations

- **Velero Backups**: S3 bucket `gamemetrics-velero-backups`
- **PostgreSQL Backups**: S3 bucket `gamemetrics-db-backups`
- **Kafka Backups**: S3 bucket `gamemetrics-kafka-backups`

## Recovery Procedures

### 1. Full Cluster Recovery

```bash
# 1. Restore from Velero backup
velero restore create --from-backup <backup-name> --wait

# 2. Verify all pods are running
kubectl get pods -A

# 3. Check application health
kubectl get applications -n argocd
```

### 2. Database Recovery

```bash
# 1. Restore PostgreSQL from backup
aws s3 cp s3://gamemetrics-db-backups/latest/dump.sql .

# 2. Restore to database
psql -h <RDS_ENDPOINT> -U postgres -d gamemetrics < dump.sql

# 3. Verify data
psql -h <RDS_ENDPOINT> -U postgres -d gamemetrics -c "SELECT COUNT(*) FROM player_events;"
```

### 3. Kafka Recovery

```bash
# 1. Restore Kafka topics from backup
kubectl apply -f k8s/kafka/base/topics.yaml

# 2. Verify topics
kubectl get kafkatopics -n kafka

# 3. Check consumer groups
kubectl exec -n kafka <kafka-pod> -- kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list
```

## Multi-Region Failover

### Active-Passive Setup

1. **Primary Region**: us-east-1 (Active)
2. **DR Region**: us-west-2 (Passive)

### Failover Steps

```bash
# 1. Promote DR region to active
kubectl config use-context <dr-cluster-context>

# 2. Update DNS to point to DR region
aws route53 change-resource-record-sets --hosted-zone-id <zone-id> --change-batch file://dns-failover.json

# 3. Scale up services in DR region
kubectl scale deployment --all --replicas=3 -n gamemetrics

# 4. Verify services are healthy
kubectl get pods -n gamemetrics
```

## Testing

### Monthly DR Test

1. Create test backup
2. Restore to test cluster
3. Verify all services work
4. Document results

## Contacts

- **On-Call Engineer**: [Contact Info]
- **Database Team**: [Contact Info]
- **Infrastructure Team**: [Contact Info]



