# Random password for master user
resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_lower        = 6
  min_upper        = 6
  min_numeric      = 6
  min_special      = 2

  # Force regeneration if the allowed special set changes
  keepers = {
    allowed_specials = "!#$%&*()-_=+[]{}<>:?"
  }
}

# Store password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.identifier}-master-password"
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.username
    password = random_password.master.result
    engine   = var.engine
    host     = aws_db_instance.main.address
    port     = var.port
    dbname   = var.database_name
  })
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.identifier}-subnet-group"
    }
  )
}

# Security Group
resource "aws_security_group" "rds" {
  name_prefix = "${var.identifier}-sg"
  description = "Security group for RDS instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.port
    to_port         = var.port
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
      Name = "${var.identifier}-sg"
    }
  )
}

# Parameter Group
resource "aws_db_parameter_group" "main" {
  name   = "${var.identifier}-params"
  family = "${var.engine}15"

  # Optimized for gaming workload
  parameter {
    name         = "shared_buffers"
    value        = "{DBInstanceClassMemory/4096}"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_connections"
    value        = "500"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "work_mem"
    value        = "16384"
    apply_method = "immediate"
  }

  parameter {
    name         = "maintenance_work_mem"
    value        = "524288"
    apply_method = "immediate"
  }

  parameter {
    name         = "effective_cache_size"
    value        = "{DBInstanceClassMemory/2048}"
    apply_method = "immediate"
  }

  parameter {
    name         = "checkpoint_completion_target"
    value        = "0.9"
    apply_method = "immediate"
  }

  parameter {
    name         = "wal_buffers"
    value        = "2048"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "random_page_cost"
    value        = "1.1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_statement"
    value        = "ddl"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  tags = var.tags
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier     = var.identifier
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = var.storage_encrypted

  db_name  = var.database_name
  username = var.username
  password = random_password.master.result
  port     = var.port

  # Apply modifications like password rotation immediately without waiting
  apply_immediately = true

  multi_az = var.multi_az

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_role_arn

  deletion_protection       = false
  skip_final_snapshot       = true
  final_snapshot_identifier = "${var.identifier}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  copy_tags_to_snapshot = true

  tags = merge(
    var.tags,
    {
      Name = var.identifier
    }
  )
}

# Read Replicas
resource "aws_db_instance" "replica" {
  count = var.replica_count

  identifier          = "${var.identifier}-replica-${count.index + 1}"
  replicate_source_db = aws_db_instance.main.identifier
  instance_class      = var.instance_class

  storage_encrypted = var.storage_encrypted

  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_role_arn

  skip_final_snapshot = true

  tags = merge(
    var.tags,
    {
      Name = "${var.identifier}-replica-${count.index + 1}"
    }
  )
}
