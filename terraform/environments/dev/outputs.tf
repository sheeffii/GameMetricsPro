output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "eks_cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_instance_endpoint
}

output "rds_reader_endpoint" {
  description = "RDS reader endpoint"
  value       = module.rds.db_instance_reader_endpoint
}

output "rds_database_name" {
  description = "RDS database name"
  value       = module.rds.db_instance_name
}

output "elasticache_configuration_endpoint" {
  description = "ElastiCache configuration endpoint"
  value       = module.elasticache.configuration_endpoint
}

output "elasticache_primary_endpoint" {
  description = "ElastiCache primary endpoint"
  value       = module.elasticache.primary_endpoint
}

output "s3_backup_bucket" {
  description = "S3 backup bucket name"
  value       = module.s3.bucket_names["backups"]
}

output "s3_logs_bucket" {
  description = "S3 logs bucket name"
  value       = module.s3.bucket_names["logs"]
}

output "s3_velero_bucket" {
  description = "S3 Velero backup bucket name"
  value       = module.s3.bucket_names["velero-backups"]
}

output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = try(module.ecr.repository_urls, {})
}
