output "bucket_ids" {
  description = "Map of bucket IDs"
  value       = { for k, v in aws_s3_bucket.main : k => v.id }
}

output "bucket_arns" {
  description = "Map of bucket ARNs"
  value       = { for k, v in aws_s3_bucket.main : k => v.arn }
}

output "bucket_names" {
  description = "Map of bucket names"
  value       = { for k, v in aws_s3_bucket.main : k => v.bucket }
}

output "flow_logs_bucket_id" {
  description = "Flow logs bucket ARN"
  value       = try(aws_s3_bucket.main["logs"].arn, "")
}
