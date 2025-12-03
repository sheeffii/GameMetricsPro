output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.main.id
}

output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_address" {
  description = "RDS instance address"
  value       = aws_db_instance.main.address
}

output "db_instance_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

output "db_instance_port" {
  description = "Database port"
  value       = aws_db_instance.main.port
}

output "db_instance_reader_endpoint" {
  description = "RDS reader endpoint"
  value       = var.create_read_replica ? aws_db_instance.replica[0].endpoint : ""
}

output "db_instance_replicas" {
  description = "RDS read replica endpoints"
  value       = var.create_read_replica ? aws_db_instance.replica[*].endpoint : []
}

output "db_password_secret_arn" {
  description = "ARN of the secret containing database password"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.rds.id
}
