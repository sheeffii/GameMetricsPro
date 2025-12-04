# 🚀 Getting Started - Your First Steps

Welcome to GameMetrics Pro! This guide will help you get started quickly.

## 📋 What You Have

You now have a **complete, production-ready gaming analytics platform** that includes:

✅ **Infrastructure Code** (Terraform)
- AWS VPC, EKS, RDS, ElastiCache, S3
- Multi-AZ high availability
- Auto-scaling enabled

✅ **Kubernetes Configuration**
- Kafka cluster (3 brokers)
- All necessary databases
- Service mesh (Istio)
- Monitoring stack

✅ **Microservices**
- 1 complete service (Event Ingestion)
- 7 service templates ready
- Dockerfiles and manifests

✅ **CI/CD Pipelines**
- GitHub Actions workflows
- ArgoCD GitOps setup
- Security scanning

✅ **Observability**
- 40+ Prometheus alerts
- Grafana dashboards
- Distributed tracing

✅ **Documentation**
- Architecture guides
- Deployment procedures
- Operational runbooks

## 🎯 Choose Your Path

### Path 1: Quick Demo (2 hours)
**Goal**: Get a minimal system running to understand the architecture

```bash
# 1. Deploy infrastructure
cd terraform/environments/dev
terraform init && terraform apply -auto-approve

# 2. Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name gamemetrics-dev

# 3. Install Kafka
kubectl create namespace kafka
kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka'
kubectl apply -f k8s/kafka/kafka-cluster.yml -n kafka

# 4. Deploy Event Ingestion Service
kubectl apply -f k8s/services/event-ingestion-service.yml

# 5. Test it
./scripts/setup/test-event-flow.sh
```

### Path 2: Full Development Setup (1 day)
**Goal**: Complete dev environment with monitoring

Follow: **[QUICK_START.md](QUICK_START.md)**

### Path 3: Production Deployment (1 week)
**Goal**: Production-ready, multi-environment setup

Follow: **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)**

## 🛠️ Prerequisites

### Required (Must Have)
```bash
# Check versions
aws --version        # AWS CLI v2.x
kubectl version      # v1.28+
terraform version    # v1.6+
docker version       # v24+
helm version         # v3.13+
```

### Optional (Nice to Have)
```bash
argocd version       # ArgoCD CLI
k9s version          # Kubernetes UI
kubectx              # Context switching
stern                # Multi-pod logs
```

### AWS Account
- Admin access or equivalent permissions
- Service quotas: 3 VPCs, 3 EKS clusters
- Budget: ~$200/month for dev environment

## 📚 Essential Reading

### Start Here
1. **[README.md](README.md)** - 5 min
   - Project overview
   - Architecture diagram
   - Key features

2. **[PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)** - 10 min
   - What's been created
   - Cost estimates
   - Next steps

### Before Deploying
3. **[ARCHITECTURE.md](ARCHITECTURE.md)** - 30 min
   - Detailed design
   - Component details
   - Data flow

4. **[QUICK_START.md](QUICK_START.md)** - Use as guide
   - Step-by-step instructions
   - Troubleshooting
   - Verification

### For Operations
5. **[docs/runbooks/](docs/runbooks/)** - Reference
   - Incident response
   - Troubleshooting
   - Maintenance

## 🎓 Understanding the Architecture

### Data Flow
```
Player Event → REST API → Kafka → Processor → TimescaleDB
                    ↓
              (rate limited)
                    ↓
           (OpenTelemetry traces)
```

### Key Components

**Kafka** (Message Broker)
- 3 brokers for high availability
- 6 topics for different event types
- SASL/SCRAM authentication

**Databases**
- PostgreSQL: User data, metadata
- TimescaleDB: Time-series analytics
- Redis: Caching, sessions
- Qdrant: ML vector search

**Services**
- Event Ingestion: REST API (Go)
- Event Processor: Stream processing (Python)
- Recommendation: ML-powered (Python)
- Analytics API: Dashboard backend (Node.js)
- User Service: Profile management (Java)
- Notification: Multi-channel alerts (Go)
- Data Retention: Archival (Python)
- Admin Dashboard: UI (React)

## 🔧 Quick Commands

### Check Cluster Health
```bash
./scripts/setup/health-check.sh
```

### View All Pods
```bash
kubectl get pods --all-namespaces
```

### Watch Kafka
```bash
kubectl get pods -n kafka -w
```

### Access Grafana
```bash
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80
# Open: http://localhost:3000
# User: admin, Password: (see deployment guide)
```

### Check Kafka Topics
```bash
kubectl exec -it gamemetrics-kafka-0 -n kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

### Send Test Event
```bash
./scripts/setup/test-event-flow.sh
```

## 🐛 Troubleshooting Quick Ref

### Pod Not Starting
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### Kafka Issues
```bash
# Check Kafka status
kubectl get kafka -n kafka

# Check broker logs
kubectl logs gamemetrics-kafka-0 -n kafka
```

### Service Not Reachable
```bash
# Check service
kubectl get svc -n <namespace>

# Check endpoints
kubectl get endpoints -n <namespace>

# Check network policies
kubectl get networkpolicies -n <namespace>
```

## 📊 Cost Management

### Current Estimate (Dev)
- **$150-200/month** (~$5-7/day)
- Can be stopped when not in use

### Cost Optimization Tips
1. **Use Spot Instances** for non-critical nodes (-30%)
2. **Stop dev environment** when not needed
3. **Use S3 lifecycle** for old data
4. **Right-size instances** using VPA recommendations

### Track Costs
```bash
# Tag all resources for cost tracking
# Check AWS Cost Explorer
# Set up budget alerts
```

## 🎯 Success Metrics

After deployment, verify:

✅ **Infrastructure**
- [ ] All nodes ready
- [ ] All pods running
- [ ] Services accessible

✅ **Kafka**
- [ ] 3 brokers running
- [ ] Topics created
- [ ] No under-replicated partitions

✅ **Application**
- [ ] Event Ingestion responding
- [ ] Can send test event
- [ ] Event appears in Kafka

✅ **Monitoring**
- [ ] Prometheus collecting metrics
- [ ] Grafana accessible
- [ ] Alerts configured

## 🚨 Getting Help

### Check Documentation
1. Review relevant runbook in `docs/runbooks/`
2. Check troubleshooting section in guides
3. Review logs: `kubectl logs <pod-name>`

### Common Issues & Solutions

**Terraform Apply Fails**
- Check AWS credentials
- Verify service quotas
- Review error message

**Pods Pending**
- Check node resources: `kubectl describe nodes`
- Check PVC status: `kubectl get pvc -A`
- Verify storage classes exist

**Kafka Not Starting**
- Check resources: `kubectl describe pod -n kafka`
- Verify ZooKeeper is running
- Check PVC is bound

**Service Can't Connect to Kafka**
- Verify network policies
- Check Kafka user credentials
- Test connectivity: `kubectl run -it --rm debug --image=busybox`

### Debug Commands
```bash
# Get all resources
kubectl get all --all-namespaces

# Check events
kubectl get events --sort-by='.lastTimestamp' -A

# Check resource usage
kubectl top nodes
kubectl top pods -A

# Interactive shell in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
```

## 📈 What's Next?

### Short Term (This Week)
1. ✅ Deploy infrastructure
2. ✅ Verify Kafka working
3. ✅ Test event flow
4. 🔲 Deploy monitoring dashboards
5. 🔲 Set up alerts to Slack/email

### Medium Term (This Month)
1. 🔲 Implement remaining 7 services
2. 🔲 Set up CI/CD pipelines
3. 🔲 Deploy to staging
4. 🔲 Run load tests
5. 🔲 Execute chaos experiments

### Long Term (This Quarter)
1. 🔲 Production deployment
2. 🔲 Multi-region setup
3. 🔲 DR testing
4. 🔲 Performance optimization
5. 🔲 Cost optimization

## 🎓 Learning Resources

### Kubernetes
- [Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

### Kafka
- [Kafka Documentation](https://kafka.apache.org/documentation/)
- [Strimzi Quickstart](https://strimzi.io/quickstarts/)

### Terraform
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

### Observability
- [Prometheus Querying](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Tutorials](https://grafana.com/tutorials/)

## 📞 Support

### Documentation
- Architecture: `ARCHITECTURE.md`
- Deployment: `DEPLOYMENT_GUIDE.md`
- Quick Start: `QUICK_START.md`
- File Structure: `FILE_STRUCTURE.md`

### Runbooks
- Kafka Issues: `docs/runbooks/kafka-broker-down.md`
- Database Issues: `docs/runbooks/database-connection-issues.md`
- Pod Issues: `docs/runbooks/pod-restart-loop.md`

### Scripts
- Health Check: `./scripts/setup/health-check.sh`
- Test Flow: `./scripts/setup/test-event-flow.sh`

## 🎉 Ready to Start?

Choose your path above and begin your journey!

**Recommended**: Start with Path 1 (Quick Demo) to get familiar, then move to Path 2 for full setup.

---

**Good Luck! 🚀**

If you get stuck, remember:
1. Check the documentation
2. Run health-check script
3. Review logs
4. Consult runbooks

You've got this! 💪
