output "replication_group_id" {
  description = "ElastiCache replication group ID"
  value       = aws_elasticache_replication_group.main.id
}

output "configuration_endpoint" {
  description = "Configuration endpoint (cluster mode)"
  value       = var.cluster_mode_enabled ? aws_elasticache_replication_group.main.configuration_endpoint_address : null
}

output "primary_endpoint" {
  description = "Primary endpoint (non-cluster mode)"
  value       = !var.cluster_mode_enabled ? aws_elasticache_replication_group.main.primary_endpoint_address : null
}

output "reader_endpoint" {
  description = "Reader endpoint"
  value       = aws_elasticache_replication_group.main.reader_endpoint_address
}

output "port" {
  description = "Redis port"
  value       = 6379
}

output "auth_token_secret_arn" {
  description = "ARN of the secret containing Redis auth token"
  value       = aws_secretsmanager_secret.redis_auth.arn
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.redis.id
}
