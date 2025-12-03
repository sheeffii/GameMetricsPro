# System Architecture - GameMetrics Pro

## Overview

GameMetrics Pro is a distributed, event-driven gaming analytics platform designed to process 50,000+ events per second with 99.9% uptime. The system leverages AWS services, Kubernetes orchestration, and microservices architecture to provide real-time player insights, recommendations, and analytics.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Cloud (Multi-AZ)                      │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Amazon EKS Cluster                       │ │
│  │                                                              │ │
│  │  ┌──────────────┐    ┌──────────────┐   ┌──────────────┐  │ │
│  │  │   Istio      │───▶│   Event      │──▶│    Kafka     │  │ │
│  │  │   Gateway    │    │  Ingestion   │   │  (3 brokers) │  │ │
│  │  │              │    │   Service    │   │              │  │ │
│  │  │ (Rate Limit) │    │    (Go)      │   │ Strimzi Ops  │  │ │
│  │  └──────────────┘    └──────────────┘   └──────┬───────┘  │ │
│  │                                                  │          │ │
│  │  ┌──────────────────────────────────────────────┼────────┐ │ │
│  │  │          Stream Processing Layer             │        │ │ │
│  │  │                                               ▼        │ │ │
│  │  │  ┌──────────────┐   ┌──────────────┐  ┌────────────┐│ │ │
│  │  │  │   Event      │   │Recommendation│  │Notification││ │ │
│  │  │  │  Processor   │   │   Engine     │  │  Service   ││ │ │
│  │  │  │  (Python)    │   │  (Python/ML) │  │    (Go)    ││ │ │
│  │  │  └──────┬───────┘   └──────┬───────┘  └────────────┘│ │ │
│  │  └─────────┼──────────────────┼─────────────────────────┘ │ │
│  │            │                  │                            │ │
│  │  ┌─────────▼──────────────────▼─────────────────────────┐ │ │
│  │  │              Data & Storage Layer                     │ │ │
│  │  │                                                        │ │ │
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────────┐ │ │ │
│  │  │  │PostgreSQL  │  │TimescaleDB │  │  Redis Cluster │ │ │ │
│  │  │  │ (Multi-AZ) │  │(Time-Series│  │   (Cache/Sess) │ │ │ │
│  │  │  └────────────┘  └────────────┘  └────────────────┘ │ │ │
│  │  │                                                        │ │ │
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────────┐ │ │ │
│  │  │  │  Qdrant    │  │   MinIO    │  │      S3        │ │ │ │
│  │  │  │  (Vector)  │  │ (S3-compat)│  │  (Backups)     │ │ │ │
│  │  │  └────────────┘  └────────────┘  └────────────────┘ │ │ │
│  │  └────────────────────────────────────────────────────┘ │ │
│  │                                                            │ │
│  │  ┌────────────────────────────────────────────────────┐  │ │
│  │  │            API & Application Layer                  │  │ │
│  │  │                                                      │  │ │
│  │  │  ┌────────────┐  ┌────────────┐  ┌──────────────┐ │  │ │
│  │  │  │ Analytics  │  │   User     │  │    Admin     │ │  │ │
│  │  │  │API (GraphQL│  │  Service   │  │  Dashboard   │ │  │ │
│  │  │  │  Node.js)  │  │  (Java)    │  │   (React)    │ │  │ │
│  │  │  └────────────┘  └────────────┘  └──────────────┘ │  │ │
│  │  └────────────────────────────────────────────────────┘  │ │
│  │                                                            │ │
│  │  ┌────────────────────────────────────────────────────┐  │ │
│  │  │         Observability Stack                         │  │ │
│  │  │  Prometheus │ Grafana │ Loki │ Tempo │ AlertMgr   │  │ │
│  │  └────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐ │
│  │    VPC     │  │   RDS      │  │    ElastiCache         │ │
│  │ (Multi-AZ) │  │(PostgreSQL)│  │      (Redis)           │ │
│  └────────────┘  └────────────┘  └────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Event Ingestion Layer

**Event Ingestion Service (Go)**
- **Purpose**: High-performance REST API for receiving player events
- **Technology**: Go 1.21, Gin web framework, Kafka producer
- **Capacity**: 50,000+ events/second
- **Features**:
  - Rate limiting (10,000 req/sec per instance)
  - Request validation and sanitization
  - Prometheus metrics export
  - OpenTelemetry distributed tracing
  - Health checks (liveness/readiness)
  - Graceful shutdown with connection draining
- **Scaling**: HPA (3-20 replicas based on CPU/memory)
- **Security**: TLS termination, SASL/SCRAM for Kafka

**API Endpoints**:
```
POST /api/v1/events         - Submit player events
GET  /health/live           - Liveness probe
GET  /health/ready          - Readiness probe (checks Kafka)
GET  /metrics               - Prometheus metrics
```

### 2. Message Broker Layer

**Apache Kafka (via Strimzi)**
- **Version**: 3.6.0
- **Deployment**: 3 brokers with rack awareness
- **Configuration**:
  - Replication factor: 3
  - Min in-sync replicas: 2
  - Retention: 7-30 days (topic-dependent)
  - Partitions: 6-12 per topic
- **Authentication**: SASL/SCRAM-SHA-512
- **Authorization**: ACL-based (per service user)
- **Monitoring**: JMX metrics, Prometheus exporter
- **Storage**: JBOD with 100Gi per broker

**Topics**:
1. `player.events.raw` - Raw ingested events (12 partitions, 7d retention)
2. `player.events.processed` - Processed events (6 partitions, 30d, compacted)
3. `recommendations.generated` - ML recommendations (6 partitions, 1d)
4. `user.actions` - User interactions (6 partitions, 30d)
5. `notifications` - Notification requests (3 partitions, 3d)
6. `dlq.events` - Dead letter queue (3 partitions, 7d)

### 3. Stream Processing Layer

**Event Processor Service (Python)**
- **Purpose**: Process raw events, enrich, validate, store
- **Technology**: Python 3.11, Kafka consumer, asyncio
- **Processing**:
  - Consume from `player.events.raw`
  - Validate and enrich events
  - Write to TimescaleDB (time-series storage)
  - Publish to `player.events.processed`
- **Features**:
  - Configurable batch processing
  - Error handling with DLQ
  - Idempotency via deduplication
  - State management
- **Scaling**: Consumer group with 6-12 instances

**Recommendation Engine (Python/FastAPI)**
- **Purpose**: Generate personalized game recommendations
- **Technology**: Python 3.11, FastAPI, scikit-learn/TensorFlow
- **Processing**:
  - Consume processed events
  - Feature extraction
  - ML model inference (collaborative filtering)
  - Vector similarity search (Qdrant)
  - Cache results in Redis
- **Models**:
  - User behavior clustering
  - Item similarity (cosine similarity)
  - Real-time scoring
- **Scaling**: Multiple replicas with model sharding

**Notification Service (Go)**
- **Purpose**: Multi-channel notification delivery
- **Technology**: Go 1.21, worker pool pattern
- **Channels**:
  - In-app push notifications
  - Email (via AWS SES)
  - SMS (via AWS SNS)
  - Webhook callbacks
- **Features**:
  - Priority queuing
  - Retry with exponential backoff
  - Rate limiting per channel
  - Delivery tracking
- **Scaling**: Worker pool (10-100 workers per instance)

### 4. Data Storage Layer

**Amazon RDS PostgreSQL 15**
- **Instance**: db.r6g.large (Multi-AZ)
- **Storage**: 500GB gp3 (auto-scaling enabled)
- **Configuration**:
  - Read replicas: 2 (for analytics queries)
  - Automated backups: 7-day retention
  - Performance Insights enabled
  - Enhanced Monitoring (1-minute intervals)
- **Schemas**:
  - `users`: User profiles, authentication
  - `games`: Game metadata, configurations
  - `sessions`: Gaming sessions
  - `achievements`: Player achievements
- **Connection Pooling**: PgBouncer (500 max connections)

**TimescaleDB (Hypertables)**
- **Purpose**: High-performance time-series storage
- **Deployment**: On Kubernetes with persistent volumes
- **Configuration**:
  - Chunk time interval: 1 day
  - Retention policy: 90 days online, archive to S3
  - Compression: After 7 days
  - Continuous aggregates: hourly, daily rollups
- **Tables**:
  - `player_events`: All processed events
  - `performance_metrics`: Game performance data
  - `engagement_metrics`: Player engagement scores

**Amazon ElastiCache Redis**
- **Cluster**: cache.r6g.large (Cluster mode enabled)
- **Configuration**:
  - 3 shards with 1 replica each
  - Encryption at rest and in transit
  - Auth token enabled
  - Automatic failover
- **Use Cases**:
  - Session storage (TTL: 24h)
  - API response caching (TTL: 5-60min)
  - Real-time leaderboards (sorted sets)
  - Rate limiting counters
  - Feature flags
- **Eviction**: LRU policy

**Qdrant Vector Database**
- **Purpose**: Similarity search for recommendations
- **Deployment**: StatefulSet with persistent volumes
- **Configuration**:
  - Vector dimension: 128
  - Distance metric: Cosine similarity
  - Indexing: HNSW (Hierarchical Navigable Small World)
- **Collections**:
  - `user_embeddings`: User behavior vectors
  - `game_embeddings`: Game feature vectors
  - `session_embeddings`: Session patterns

**MinIO (S3-Compatible)**
- **Purpose**: Object storage for ML models, exports
- **Deployment**: Distributed mode (4 nodes)
- **Buckets**:
  - `ml-models`: Trained model artifacts
  - `data-exports`: Analytics exports
  - `user-uploads`: User-generated content

**Amazon S3**
- **Buckets**:
  - `gamemetrics-backups`: Velero backups, DB dumps
  - `gamemetrics-logs`: Long-term log storage (Loki)
  - `gamemetrics-traces`: Archived traces (Tempo)
  - `gamemetrics-vpc-logs`: VPC Flow Logs
- **Lifecycle Policies**:
  - Standard → Standard-IA (30 days)
  - Standard-IA → Glacier (90 days)
  - Glacier → Glacier Deep Archive (365 days)

### 5. API & Application Layer

**Analytics API (Node.js/GraphQL)**
- **Purpose**: Unified API for dashboard and external consumers
- **Technology**: Node.js 18, Apollo Server, TypeScript
- **Features**:
  - GraphQL API with subscriptions (WebSocket)
  - Real-time data streaming
  - Caching with DataLoader
  - Query complexity limiting
  - Rate limiting per API key
- **Endpoints**:
  - Player statistics
  - Game analytics
  - Recommendation queries
  - Real-time event streams
- **Scaling**: Horizontal with session affinity

**User Service (Java/Spring Boot)**
- **Purpose**: User management, authentication, authorization
- **Technology**: Java 17, Spring Boot 3, Spring Security
- **Features**:
  - OAuth2/OIDC integration
  - JWT token management
  - Role-based access control (RBAC)
  - User profile management
  - Multi-factor authentication
- **Database**: PostgreSQL (RDS)
- **Caching**: Redis for sessions

**Data Retention Service (Python)**
- **Purpose**: Automated data archival and cleanup
- **Technology**: Python 3.11, Celery, Kubernetes CronJob
- **Tasks**:
  - Archive old events to S3 (>90 days)
  - Delete archived data from TimescaleDB
  - Prune Kafka topics
  - Clean up temporary files
  - Generate compliance reports
- **Schedule**: Daily at 2 AM UTC

**Admin Dashboard (React/Next.js)**
- **Purpose**: Internal operations dashboard
- **Technology**: React 18, Next.js 14, TypeScript, Material-UI
- **Features**:
  - Real-time metrics visualization
  - Service health monitoring
  - User management interface
  - Configuration management
  - Alert acknowledgment
  - Deployment status
- **Authentication**: OAuth2 with role-based views

### 6. Service Mesh Layer

**Istio 1.20.0**
- **Components**:
  - Istiod (control plane)
  - Ingress Gateway (external traffic)
  - Egress Gateway (external calls)
- **Features**:
  - mTLS between services (STRICT mode)
  - Traffic management (canary, blue-green)
  - Circuit breaking
  - Retry policies
  - Timeout management
  - Request routing
- **Observability**:
  - Distributed tracing (Jaeger/Tempo)
  - Metrics collection (Prometheus)
  - Access logs (Loki)

### 7. Observability Stack

**Prometheus**
- **Configuration**: Federation setup with Thanos
- **Retention**: 30 days local, unlimited in S3 (via Thanos)
- **Scrape Interval**: 15 seconds
- **Targets**:
  - Kubernetes metrics (kube-state-metrics)
  - Node metrics (node-exporter)
  - Kafka metrics (JMX exporter)
  - Application metrics (custom exporters)
  - Istio metrics
- **Alert Rules**: 40+ rules (see monitoring/prometheus/)

**Grafana**
- **Dashboards**: 15 pre-configured dashboards
  1. Platform Overview
  2. Kafka Health
  3. Service SLIs
  4. Database Performance
  5. Redis Monitoring
  6. Network Traffic
  7. Cost Dashboard
  8. Business Metrics
  9. Security Events
  10. Kubernetes Resources
  11. Node Status
  12. Application Logs
  13. Trace Analysis
  14. Alert Status
  15. Capacity Planning
- **Data Sources**: Prometheus, Loki, Tempo, PostgreSQL

**Loki**
- **Storage**: S3 backend
- **Retention**: 30 days
- **Ingestion**: Promtail daemonset
- **Indexing**: Per-stream indexes
- **Query**: LogQL

**Tempo**
- **Storage**: S3 backend
- **Retention**: 7 days
- **Ingestion**: OpenTelemetry collector
- **Sampling**: 10% (configurable)

**AlertManager**
- **Receivers**:
  - Slack (critical/warning)
  - PagerDuty (critical)
  - Email (warning/info)
  - Webhook (custom integrations)
- **Grouping**: By service and severity
- **Throttling**: Max 1 alert per 5 minutes

## Data Flow

### Event Ingestion Flow
```
1. Player → [HTTPS] → Istio Gateway → Event Ingestion Service
2. Event Ingestion → [SASL/SCRAM] → Kafka (player.events.raw)
3. Event Processor → [Consume] → Kafka (player.events.raw)
4. Event Processor → [Write] → TimescaleDB
5. Event Processor → [Produce] → Kafka (player.events.processed)
6. Recommendation Engine → [Consume] → Kafka (player.events.processed)
7. Recommendation Engine → [ML Inference] → Qdrant (similarity search)
8. Recommendation Engine → [Cache] → Redis
9. Recommendation Engine → [Produce] → Kafka (recommendations.generated)
```

### Query Flow
```
1. Dashboard → [GraphQL] → Analytics API
2. Analytics API → [Query] → Redis (cache check)
3. Cache Miss → [Query] → TimescaleDB
4. Analytics API → [Subscribe] → Kafka (real-time updates)
5. Analytics API → [Return] → Dashboard
```

### Notification Flow
```
1. Service → [Produce] → Kafka (notifications)
2. Notification Service → [Consume] → Kafka (notifications)
3. Notification Service → [Dispatch] → AWS SES/SNS/Push
4. Notification Service → [Track] → PostgreSQL (delivery status)
```

## Scaling Strategy

### Horizontal Pod Autoscaling (HPA)
- **Event Ingestion**: 3-20 replicas (CPU 70%, Memory 80%)
- **Event Processor**: 6-12 replicas (Kafka lag <10k)
- **Recommendation Engine**: 3-10 replicas (CPU 75%)
- **Analytics API**: 3-15 replicas (CPU 70%)
- **Notification Service**: 2-8 replicas (CPU 70%)

### Vertical Pod Autoscaling (VPA)
- Enabled for all services in recommendation mode
- Updates every 12 hours during low-traffic windows

### Cluster Autoscaling
- **Node Groups**:
  - System: 3-6 nodes (t3.large)
  - Application: 6-20 nodes (c6g.2xlarge)
  - Data: 3-10 nodes (r6g.xlarge)
- **Scale-up**: When CPU/Memory >70% for 3 minutes
- **Scale-down**: When CPU/Memory <40% for 10 minutes
- **Buffer**: Always maintain 20% spare capacity

### Database Scaling
- **Read Replicas**: Automatic addition when CPU >70%
- **Storage**: Auto-scaling enabled (max 1TB)
- **Connection Pooling**: Dynamic pool size based on load

### Kafka Scaling
- **Brokers**: Manual scaling (3→5→7 brokers)
- **Partitions**: Pre-allocated for expected growth
- **Consumer Groups**: Auto-rebalancing

## High Availability

### Multi-AZ Deployment
- All services deployed across 3 availability zones
- Kafka rack awareness enabled
- Database Multi-AZ automatic failover
- Load balancing across AZs

### Replication
- **Kafka**: Replication factor 3, min ISR 2
- **PostgreSQL**: Multi-AZ with 2 read replicas
- **Redis**: 3 shards with 1 replica each
- **TimescaleDB**: Replicated via persistent volumes

### Pod Disruption Budgets
- Event Ingestion: minAvailable 2
- Event Processor: minAvailable 3
- Kafka: maxUnavailable 1
- Critical services: Always maintain majority

### Circuit Breaking
- Istio circuit breaker on all services
- Max connections: 1000
- Max pending requests: 100
- Consecutive errors: 5 (trip circuit)
- Recovery time: 30 seconds

## Security Architecture

### Network Security
- **VPC**: Isolated VPC with public/private subnets
- **Security Groups**: Least-privilege rules
- **Network Policies**: Default deny-all, explicit allow
- **NAT Gateways**: 3 (one per AZ)
- **VPC Endpoints**: S3, ECR (no internet routing)

### Identity & Access
- **IAM**: IRSA (IAM Roles for Service Accounts)
- **RBAC**: Kubernetes role-based access control
- **ServiceAccounts**: One per service with minimal permissions
- **Secrets**: External Secrets Operator (AWS Secrets Manager)
- **Encryption**: Secrets encrypted at rest (KMS)

### Communication Security
- **Istio mTLS**: STRICT mode between services
- **Kafka SASL**: SASL/SCRAM-SHA-512
- **Database TLS**: Encrypted connections (RDS/Redis)
- **API TLS**: TLS 1.3 at Istio Gateway
- **Certificate Management**: cert-manager with Let's Encrypt

### Data Security
- **Encryption at Rest**: All storage (EBS, S3, RDS, Redis)
- **Encryption in Transit**: TLS for all communications
- **Data Masking**: PII masked in logs
- **Access Logging**: All API calls logged
- **Audit Logs**: Kubernetes audit logs to S3

### Pod Security
- **Pod Security Standards**: Restricted mode
- **Non-root**: All containers run as non-root
- **Read-only filesystem**: Except for temp directories
- **No privileged**: Privileged containers forbidden
- **Seccomp**: Enabled with default profile
- **AppArmor**: Enabled where supported

## Disaster Recovery

### Backup Strategy
- **Velero**: Kubernetes resource backups
  - Full backup: Daily at 1 AM UTC
  - Incremental: Every 6 hours
  - Retention: 30 days
- **Database Backups**: Automated via AWS RDS
  - Automated: Daily, 7-day retention
  - Manual snapshots: Before major changes
  - Point-in-time recovery: 5-minute RPO
- **Kafka Backups**: MirrorMaker2 to secondary cluster
  - Real-time replication
  - Separate region (us-west-2)

### Recovery Objectives
- **RTO (Recovery Time Objective)**: 15 minutes
- **RPO (Recovery Point Objective)**: 5 minutes
- **Service Tier SLAs**:
  - Tier 1 (Critical): 99.9% (43m downtime/month)
  - Tier 2 (Important): 99.5% (3.6h downtime/month)
  - Tier 3 (Normal): 99% (7.2h downtime/month)

### Disaster Scenarios
1. **AZ Failure**: Automatic failover, no data loss
2. **Region Failure**: Manual failover to DR region, <5min data loss
3. **Database Corruption**: Restore from snapshot, <1h RPO
4. **Kafka Cluster Failure**: Switch to DR cluster, real-time sync
5. **Complete AWS Outage**: Multi-cloud DR (future)

### Recovery Procedures
- Documented runbooks for each scenario
- Automated failover for common issues
- Regular DR drills (monthly)
- Recovery testing (quarterly)

## Cost Optimization

### Production Environment Estimate ($800-1200/month)

**Compute (EKS)**: $450-700/month
- 3 t3.large (system): $150/month
- 6-12 c6g.2xlarge (app): $200-450/month
- 3-5 r6g.xlarge (data): $100-250/month

**Database (RDS PostgreSQL)**: $200-300/month
- db.r6g.large Multi-AZ: $200/month
- 2 read replicas: $100/month
- Storage (500GB): $50/month

**ElastiCache (Redis)**: $150-200/month
- 3x cache.r6g.large: $150/month
- Data transfer: $20/month

**Storage (S3/EBS)**: $100-150/month
- S3 (5TB): $100/month
- EBS (2TB): $200/month
- Backups (3TB): $50/month

**Networking**: $100-150/month
- NAT Gateways (3): $100/month
- Data transfer: $50/month

**Observability**: $50-100/month
- CloudWatch: $30/month
- Grafana Cloud (optional): $50/month

### Cost Optimization Strategies
1. **Use Spot Instances**: 30-50% savings on non-critical workloads
2. **Right-size Instances**: Use VPA recommendations
3. **Reserved Instances**: 40% savings on predictable workloads
4. **S3 Lifecycle Policies**: Auto-tier to cheaper storage
5. **Autoscaling**: Scale down during off-peak hours
6. **Graviton Instances**: 20% cost reduction (ARM-based)
7. **CloudWatch Logs**: Aggressive retention policies
8. **Unused Resources**: Regular cleanup of orphaned resources

### Cost Monitoring
- AWS Cost Explorer dashboards
- Grafana cost dashboard
- Budget alerts at 80%, 100%, 120%
- Monthly cost review meetings
- Cost allocation tags on all resources

## Performance Optimization

### Application Performance
- **Response Time**: P99 <500ms
- **Throughput**: 50,000 events/sec
- **Error Rate**: <0.1%
- **Availability**: 99.9%

### Database Performance
- **Query Optimization**: Indexes on all foreign keys
- **Connection Pooling**: PgBouncer with transaction mode
- **Read Replicas**: Separate analytics queries
- **Caching**: Redis for frequent queries (80% hit rate)
- **Partitioning**: TimescaleDB hypertables

### Kafka Performance
- **Producer**: Batch size 100KB, linger 10ms
- **Consumer**: Fetch min 50KB, max wait 500ms
- **Compression**: Snappy (good balance)
- **Partitioning Strategy**: Hash by user ID
- **Consumer Groups**: Balanced partition assignment

### API Performance
- **Caching**: Multi-layer (CDN, Redis, in-memory)
- **Query Optimization**: DataLoader for N+1 queries
- **Pagination**: Cursor-based for large datasets
- **Rate Limiting**: Token bucket algorithm
- **Compression**: Gzip for responses >1KB

## Compliance & Governance

### Data Privacy
- **GDPR Compliance**: Right to erasure, data portability
- **Data Residency**: Region-locked storage
- **PII Handling**: Encrypted, access-controlled
- **Data Retention**: Configurable per data type
- **Consent Management**: Tracked in database

### Audit & Compliance
- **Audit Logs**: All access logged (CloudTrail, K8s audit)
- **Change Tracking**: Git history, ArgoCD sync logs
- **Access Reviews**: Quarterly IAM/RBAC reviews
- **Compliance Reports**: Automated generation
- **Penetration Testing**: Annual third-party audit

### Monitoring & Alerting
- **SLO Monitoring**: Track service level objectives
- **Error Budget**: 0.1% error budget per service
- **Alert Fatigue**: Max 3 pages per week per engineer
- **Incident Response**: Documented playbooks
- **Post-Mortems**: Required for all major incidents

## Future Enhancements

### Short Term (Q1 2026)
- [ ] Multi-region deployment
- [ ] Advanced ML models (deep learning)
- [ ] Real-time stream analytics (Apache Flink)
- [ ] Mobile SDK for direct integration

### Medium Term (Q2-Q3 2026)
- [ ] Edge computing for low-latency regions
- [ ] Predictive autoscaling with ML
- [ ] Advanced anomaly detection
- [ ] Player churn prediction

### Long Term (Q4 2026+)
- [ ] Multi-cloud deployment (GCP/Azure)
- [ ] Blockchain integration for achievements
- [ ] Advanced anti-cheat detection
- [ ] Real-time player matching algorithms

## References

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kafka Optimization Guide](https://kafka.apache.org/documentation/#configuration)
- [Istio Security Best Practices](https://istio.io/latest/docs/ops/best-practices/security/)
- [Kubernetes Production Best Practices](https://kubernetes.io/docs/setup/best-practices/)
- [TimescaleDB Performance Tuning](https://docs.timescale.com/timescaledb/latest/how-to-guides/configuration/)

---

**Document Version**: 1.0  
**Last Updated**: December 1, 2025  
**Owner**: Platform Engineering Team
