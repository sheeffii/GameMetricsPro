# Random auth token
resource "random_password" "auth_token" {
  length  = 32
  special = false
}

# Store auth token in AWS Secrets Manager
resource "aws_secretsmanager_secret" "redis_auth" {
  name                    = "${var.cluster_id}-auth-token"
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id = aws_secretsmanager_secret.redis_auth.id
  secret_string = jsonencode({
    auth_token = random_password.auth_token.result
    endpoint   = var.cluster_mode_enabled ? aws_elasticache_replication_group.main.configuration_endpoint_address : aws_elasticache_replication_group.main.primary_endpoint_address
    port       = 6379
  })
}

# Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.cluster_id}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = var.tags
}

# Security Group
resource "aws_security_group" "redis" {
  name_prefix = "${var.cluster_id}-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_id}-sg"
    }
  )
}

# Parameter Group
resource "aws_elasticache_parameter_group" "main" {
  name   = "${var.cluster_id}-params"
  family = var.parameter_group_family

  # Optimized for caching workload
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  parameter {
    name  = "tcp-keepalive"
    value = "300"
  }

  parameter {
    name  = "notify-keyspace-events"
    value = "Ex"
  }

  tags = var.tags
}

# ElastiCache Replication Group
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = var.cluster_id
  description          = "Redis cluster for ${var.environment}"

  engine         = var.engine
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = 6379

  lifecycle {
    create_before_destroy = false
  }

  parameter_group_name = aws_elasticache_parameter_group.main.name
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]

  # Cluster mode configuration
  num_node_groups         = var.cluster_mode_enabled ? var.num_node_groups : null
  replicas_per_node_group = var.cluster_mode_enabled ? var.replicas_per_node_group : null
  num_cache_clusters      = var.cluster_mode_enabled ? null : var.num_cache_clusters

  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.multi_az_enabled

  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  transit_encryption_enabled = var.transit_encryption_enabled
  auth_token                 = var.transit_encryption_enabled ? random_password.auth_token.result : null

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window

  maintenance_window = "sun:05:00-sun:06:00"

  notification_topic_arn = aws_sns_topic.redis_events.arn

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.engine_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = merge(
    var.tags,
    {
      Name = var.cluster_id
    }
  )
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "slow_log" {
  name              = "/aws/elasticache/${var.cluster_id}/slow-log"
  retention_in_days = 7

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "engine_log" {
  name              = "/aws/elasticache/${var.cluster_id}/engine-log"
  retention_in_days = 7

  tags = var.tags
}

# SNS Topic for events
resource "aws_sns_topic" "redis_events" {
  name = "${var.cluster_id}-events"

  tags = var.tags
}
