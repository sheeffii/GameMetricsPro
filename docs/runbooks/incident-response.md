# Incident Response Runbook

## Overview
This runbook provides procedures for responding to incidents in the GameMetrics Pro platform.

## Severity Levels

### P0 - Critical
- Service completely down
- Data loss or corruption
- Security breach
- **Response Time**: Immediate (< 5 minutes)

### P1 - High
- Service degradation affecting > 50% users
- High error rates (> 10%)
- **Response Time**: < 15 minutes

### P2 - Medium
- Service degradation affecting < 50% users
- Moderate error rates (5-10%)
- **Response Time**: < 1 hour

### P3 - Low
- Minor issues
- Non-critical alerts
- **Response Time**: < 4 hours

## Incident Response Process

### 1. Detection
- Monitor alerts in AlertManager
- Check Grafana dashboards
- Review logs in Loki

### 2. Triage
1. Identify affected service(s)
2. Check service health endpoints
3. Review recent deployments
4. Check Kafka consumer lag
5. Review database connections

### 3. Mitigation
- Scale up services if needed
- Restart failing pods
- Rollback deployment if recent change
- Check resource limits

### 4. Resolution
- Document root cause
- Implement fix
- Verify resolution
- Update runbooks if needed

## Common Incidents

### Kafka Broker Down
**Symptoms**: Consumer lag increasing, producers failing
**Actions**:
1. Check broker status: `kubectl get pods -n kafka`
2. Check logs: `kubectl logs -n kafka <broker-pod>`
3. Restart broker if needed: `kubectl delete pod -n kafka <broker-pod>`
4. Verify replication: Check Kafka UI

### Database Connection Pool Exhausted
**Symptoms**: High error rates, connection timeouts
**Actions**:
1. Check active connections: `SELECT count(*) FROM pg_stat_activity;`
2. Scale up database if needed
3. Increase connection pool size in services
4. Kill idle connections if necessary

### High Consumer Lag
**Symptoms**: Lag > 10k messages
**Actions**:
1. Check consumer status: `kubectl get pods -n gamemetrics -l app=event-processor-service`
2. Scale up consumers: Increase HPA min replicas
3. Check for processing errors in logs
4. Verify Kafka broker health

### Service Out of Memory
**Symptoms**: OOMKilled pods, high memory usage
**Actions**:
1. Check memory limits: `kubectl describe pod <pod-name>`
2. Increase memory limits if needed
3. Check for memory leaks in application logs
4. Scale horizontally if possible

## Escalation
- P0/P1: Page on-call engineer immediately
- P2: Create ticket, notify team
- P3: Create ticket, handle during business hours

## Post-Incident
1. Write incident report
2. Conduct post-mortem meeting
3. Update runbooks
4. Implement preventive measures



