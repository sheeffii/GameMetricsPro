terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  # Using local backend for initial deployment
  # Uncomment S3 backend after infrastructure is created
  # backend "s3" {
  #   bucket         = "gamemetrics-terraform-state-dev"
  #   key            = "dev/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "gamemetrics-terraform-locks-dev"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "GameMetrics Pro"
      ManagedBy   = "Terraform"
      Owner       = "DevOps Team"
    }
  }
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_flow_logs = true
  flow_logs_bucket = module.s3.flow_logs_bucket_id

  tags = var.tags
}

# EKS Cluster Module
module "eks" {
  source = "../../modules/eks"

  environment     = var.environment
  cluster_name    = "gamemetrics-${var.environment}"
  cluster_version = var.eks_cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Node groups
  node_groups = {
    system = {
      desired_size = 1
      min_size     = 1
      max_size     = 2

      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND"

      labels = {
        role = "system"
      }

      taints = [{
        key    = "dedicated"
        value  = "system"
        effect = "NO_SCHEDULE"
      }]
    }

    application = {
      desired_size = 2
      min_size     = 2
      max_size     = 4

      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND"

      labels = {
        role = "application"
      }
    }

    data = {
      desired_size = 1
      min_size     = 1
      max_size     = 2

      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND"

      labels = {
        role = "data"
      }
    }
  }

  # Enable IRSA
  enable_irsa = true

  # Cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # Enable cluster logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = var.tags
}

# RDS PostgreSQL Module
module "rds" {
  source = "../../modules/rds"

  environment = var.environment
  identifier  = "gamemetrics-${var.environment}"

  engine         = "postgres"
  engine_version = "15"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 20
  storage_encrypted     = false

  database_name = "gamemetrics"
  username      = "dbadmin"
  port          = 5432

  multi_az                = false
  backup_retention_period = 0
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.eks.cluster_security_group_id]

  # Performance Insights
  performance_insights_enabled          = false
  performance_insights_retention_period = 0

  # Enhanced Monitoring
  monitoring_interval = 0

  # Read Replicas
  replica_count  = 0

  tags = var.tags
}

# ElastiCache Redis Module
module "elasticache" {
  source = "../../modules/elasticache"

  environment = var.environment
  cluster_id  = "gamemetrics-${var.environment}"

  engine         = "redis"
  engine_version = "7.0"
  node_type      = "cache.t3.micro"

  num_cache_clusters     = 1
  parameter_group_family = "redis7"

  # Cluster mode disabled for free tier
  cluster_mode_enabled    = false
  num_node_groups         = 1
  replicas_per_node_group = 0

  automatic_failover_enabled = false
  multi_az_enabled           = false

  at_rest_encryption_enabled = false
  transit_encryption_enabled = false

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  security_group_ids = [module.eks.cluster_security_group_id]

  # Backup
  snapshot_retention_limit = 5
  snapshot_window          = "03:00-05:00"

  tags = var.tags
}

# S3 Buckets Module
module "s3" {
  source = "../../modules/s3"

  environment = var.environment

  buckets = {
    backups = {
      name       = "gamemetrics-backups-${var.environment}"
      versioning = true
      lifecycle_rules = [
        {
          id      = "archive-old-backups"
          enabled = true

          transition = [
            {
              days          = 30
              storage_class = "STANDARD_IA"
            },
            {
              days          = 90
              storage_class = "GLACIER"
            }
          ]

          expiration = {
            days = 365
          }
        }
      ]
    }

    logs = {
      name       = "gamemetrics-logs-${var.environment}"
      versioning = true
      lifecycle_rules = [
        {
          id      = "expire-old-logs"
          enabled = true

          expiration = {
            days = 90
          }
        }
      ]
    }

    artifacts = {
      name       = "gamemetrics-artifacts-${var.environment}"
      versioning = true
    }

    velero-backups = {
      name       = "gamemetrics-velero-${var.environment}"
      versioning = true
      lifecycle_rules = [
        {
          id      = "expire-old-velero-backups"
          enabled = true

          expiration = {
            days = 30
          }
        }
      ]
    }
  }

  tags = var.tags
}

# ECR Repositories
module "ecr" {
  source = "../../modules/ecr"

  repositories = {
    "event-ingestion-service" = {
      image_tag_mutability = "MUTABLE"
      scan_on_push         = true
      lifecycle_policy     = jsonencode({
        rules = [
          {
            rulePriority = 1
            description  = "Keep last 10 images"
            selection = {
              tagStatus     = "any"
              countType     = "imageCountMoreThan"
              countNumber   = 10
            }
            action = { type = "expire" }
          }
        ]
      })
    }
  }
}

# Optionally build and push Docker images locally (temporary until CI/CD is in place)
# Disabled by default - enable with: TF_VAR_enable_local_ecr_build_push=true terraform apply
resource "null_resource" "build_and_push_ecr" {
  count = var.enable_local_ecr_build_push ? 1 : 0

  # Rebuild when ECR repo changes
  triggers = {
    repo_url = module.ecr.repository_urls["event-ingestion-service"]
    region   = var.aws_region
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/../../scripts"
    command     = "./build-push-ecr.sh ${var.aws_region} ${module.ecr.repository_urls["event-ingestion-service"]} ../services/event-ingestion-service"
  }
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "rds-monitoring-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Kubernetes and Helm providers are configured in providers.tf and require the EKS cluster
