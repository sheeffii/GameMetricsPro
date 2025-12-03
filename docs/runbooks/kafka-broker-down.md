# Runbook: Kafka Broker Down

## Severity: CRITICAL

## Symptoms
- Alert: `KafkaBrokerDown` firing
- Kafka cluster has fewer than 3 brokers
- Producer/consumer errors
- Increased latency or timeouts

## Impact
- Reduced throughput capacity
- Risk of data loss if multiple brokers fail
- Potential service degradation

## Investigation

### 1. Check Broker Status
```bash
# Check all Kafka pods
kubectl get pods -n kafka -l strimzi.io/name=gamemetrics-kafka-kafka

# Expected output: 3 pods in Running state
# NAME                       READY   STATUS    RESTARTS   AGE
# gamemetrics-kafka-kafka-0   1/1     Running   0          24h
# gamemetrics-kafka-kafka-1   1/1     Running   0          24h
# gamemetrics-kafka-kafka-2   1/1     Running   0          24h
```

### 2. Identify Failed Broker
```bash
# Get pod details
kubectl describe pod gamemetrics-kafka-kafka-0 -n kafka

# Check logs
kubectl logs gamemetrics-kafka-kafka-0 -n kafka --tail=100

# Common issues to look for:
# - OutOfMemory errors
# - Disk full errors
# - Network connectivity issues
# - ZooKeeper connection problems
```

### 3. Check Cluster State
```bash
# Check from another broker
kubectl exec -it gamemetrics-kafka-kafka-1 -n kafka -- bash

# Inside pod:
bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# Check under-replicated partitions
bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --under-replicated-partitions
```

## Resolution

### Scenario 1: Pod Crashed (OOMKilled, CrashLoopBackOff)

```bash
# Delete the pod to trigger restart
kubectl delete pod gamemetrics-kafka-kafka-0 -n kafka

# Wait for pod to restart
kubectl wait --for=condition=Ready pod gamemetrics-kafka-kafka-0 -n kafka --timeout=300s

# Verify broker rejoined cluster
kubectl exec -it gamemetrics-kafka-kafka-0 -n kafka -- \
  bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092
```

### Scenario 2: Disk Full

```bash
# Check disk usage
kubectl exec -it gamemetrics-kafka-kafka-0 -n kafka -- df -h

# If disk is full, expand PVC (requires restart)
kubectl edit pvc data-gamemetrics-kafka-kafka-0 -n kafka
# Change size from 100Gi to 200Gi

# Delete pod to apply
kubectl delete pod gamemetrics-kafka-kafka-0 -n kafka
```

### Scenario 3: Network Issues

```bash
# Check pod network
kubectl exec -it gamemetrics-kafka-kafka-0 -n kafka -- ping gamemetrics-kafka-kafka-1.gamemetrics-kafka-kafka-brokers.kafka.svc

# Check DNS
kubectl exec -it gamemetrics-kafka-kafka-0 -n kafka -- nslookup gamemetrics-zookeeper-client.kafka.svc

# Restart pod if network issue is transient
kubectl delete pod gamemetrics-kafka-kafka-0 -n kafka
```

### Scenario 4: ZooKeeper Connection Lost

```bash
# Check ZooKeeper pods
kubectl get pods -n kafka -l strimzi.io/name=gamemetrics-kafka-zookeeper

# Check ZooKeeper logs
kubectl logs gamemetrics-kafka-zookeeper-0 -n kafka --tail=100

# Test ZooKeeper connection from Kafka pod
kubectl exec -it gamemetrics-kafka-kafka-0 -n kafka -- \
  bin/zookeeper-shell.sh gamemetrics-kafka-zookeeper-client.kafka.svc:2181 ls /brokers/ids
```

## Post-Resolution Verification

```bash
# 1. Verify all brokers are up
kubectl get pods -n kafka -l strimzi.io/name=gamemetrics-kafka-kafka

# 2. Check cluster health
kubectl exec -it gamemetrics-kafka-kafka-0 -n kafka -- \
  bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# 3. Verify no under-replicated partitions
kubectl exec -it gamemetrics-kafka-kafka-0 -n kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --under-replicated-partitions

# 4. Check consumer lag (should be recovering)
kubectl exec -it gamemetrics-kafka-kafka-0 -n kafka -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --all-groups

# 5. Test producing/consuming
kubectl exec -it gamemetrics-kafka-kafka-0 -n kafka -- \
  bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic player.events.raw
# Type a test message and Ctrl+C

# 6. Monitor metrics in Grafana
# Open Kafka Health dashboard
# Verify broker metrics are being collected
```

## Prevention

1. **Resource Monitoring**
   - Set up alerts for high memory usage (>80%)
   - Set up alerts for disk usage (>70%)
   - Monitor JVM heap usage

2. **Capacity Planning**
   - Review broker resource requests/limits
   - Plan for growth (add brokers if needed)
   - Implement log retention policies

3. **Regular Maintenance**
   - Rotate logs regularly
   - Clean up old topics
   - Review partition assignments

## Escalation

If issue persists after 30 minutes:
1. Page on-call engineer
2. Consider failing over to DR cluster
3. Notify stakeholders of potential data loss risk

## Related Runbooks
- [Kafka Under-Replicated Partitions](kafka-under-replicated.md)
- [Kafka Consumer Lag](kafka-consumer-lag.md)
- [ZooKeeper Issues](zookeeper-issues.md)

---
**Last Updated**: December 2024  
**Owner**: Platform Team
