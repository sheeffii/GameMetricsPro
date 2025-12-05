## Infrastructure Deployment Fixes Applied

### Issues Fixed:

1. **RDS Free Tier Backup Retention Error**
   - Changed backup retention from 7 days → 1 day
   - File: `terraform/modules/rds/variables.tf`
   - AWS free tier only allows 0-1 days backup retention

2. **ElastiCache "Already Exists" Error**
   - Added lifecycle policy to handle existing resources gracefully
   - Added auto-import logic in deploy script
   - File: `terraform/modules/elasticache/main.tf`
   - Script now checks and imports existing ElastiCache clusters

3. **EBS CSI Driver Timeout (20m → DEGRADED)**
   - Increased timeout from 20m → 30m
   - Added explicit dependency on node groups
   - File: `terraform/modules/eks/main.tf`
   - Ensures nodes are ready before installing CSI driver

4. **Deploy Script Enhancements**
   - Added retry logic (2 attempts) for terraform apply
   - Added ElastiCache import check before apply
   - Added extra wait times for Strimzi operator (15s + 10s)
   - File: `scripts/deploy-infrastructure.sh`

### New Script Created:

**cleanup-partial-deploy.sh**
- Cleans up orphaned resources from failed deployments
- Interactive prompts before deletion
- Run this if you get "already exists" errors

### Usage:

**First time or after teardown:**
```bash
wsl bash -c "cd /mnt/c/Users/Shefqet/Desktop/RealtimeGaming && ./scripts/deploy-infrastructure.sh"
```

**If you get "already exists" errors:**
```bash
# Option 1: Let the script auto-import (it will try)
# Option 2: Manual cleanup first
wsl bash -c "cd /mnt/c/Users/Shefqet/Desktop/RealtimeGaming && chmod +x scripts/cleanup-partial-deploy.sh && ./scripts/cleanup-partial-deploy.sh"
# Then re-run deploy-infrastructure.sh
```

### What Changed:

- ✅ RDS backup retention compatible with free tier
- ✅ ElastiCache auto-imports if already exists
- ✅ EBS CSI driver waits for nodes before installing
- ✅ Terraform apply retries on transient failures
- ✅ Better wait times for Strimzi operator readiness
