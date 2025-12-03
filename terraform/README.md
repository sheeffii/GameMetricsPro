# Terraform AWS Infrastructure

This directory contains all Terraform configurations for deploying GameMetrics Pro infrastructure on AWS.

## Structure

```
terraform/
├── modules/              # Reusable Terraform modules
│   ├── vpc/             # VPC, subnets, routing
│   ├── eks/             # EKS cluster configuration
│   ├── rds/             # RDS PostgreSQL
│   ├── elasticache/     # Redis cluster
│   └── s3/              # S3 buckets
├── environments/         # Environment-specific configurations
│   ├── dev/
│   ├── staging/
│   └── production/
└── global/              # Global resources (IAM, Route53)
```

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform v1.6+ installed
3. Sufficient AWS service quotas

## Usage

### Deploy Development Environment

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

### Deploy Staging Environment

```bash
cd environments/staging
terraform init
terraform plan
terraform apply
```

### Deploy Production Environment

```bash
cd environments/production
terraform init
terraform plan
terraform apply
```

## State Management

Terraform state is stored in S3 with DynamoDB for locking:
- Bucket: `gamemetrics-terraform-state-<env>`
- DynamoDB Table: `gamemetrics-terraform-locks-<env>`

## Modules Overview

### VPC Module
- Creates VPC with public and private subnets across 3 AZs
- NAT Gateways for private subnets
- VPC Flow Logs to S3
- VPC Endpoints for AWS services

### EKS Module
- EKS cluster with managed node groups
- IRSA (IAM Roles for Service Accounts)
- Cluster autoscaler support
- Multiple node groups (system, application, data)

### RDS Module
- PostgreSQL Multi-AZ deployment
- Automated backups
- Parameter groups optimized for gaming workload
- Read replicas

### ElastiCache Module
- Redis cluster mode enabled
- 3 shards with replication
- Automatic failover
- Parameter groups optimized for caching

### S3 Module
- Buckets for backups, logs, artifacts
- Versioning enabled
- Lifecycle policies
- Encryption at rest

## Estimated Costs

| Environment | Monthly Cost (USD) |
|-------------|-------------------|
| Dev         | $150-200          |
| Staging     | $300-400          |
| Production  | $800-1200         |

Costs include:
- EKS cluster and nodes
- RDS (db.r6g.large Multi-AZ)
- ElastiCache (cache.r6g.large)
- Data transfer
- S3 storage

## Cleanup

To destroy an environment:

```bash
cd environments/<env>
terraform destroy
```

**Warning**: This will delete all resources including databases and backups!
