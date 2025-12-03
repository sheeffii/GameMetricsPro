variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_id" {
  description = "ElastiCache cluster ID"
  type        = string
}

variable "engine" {
  description = "Cache engine"
  type        = string
  default     = "redis"
}

variable "engine_version" {
  description = "Cache engine version"
  type        = string
  default     = "7.0"
}

variable "node_type" {
  description = "Instance type"
  type        = string
  default     = "cache.r6g.large"
}

variable "num_cache_clusters" {
  description = "Number of cache clusters"
  type        = number
  default     = 3
}

variable "parameter_group_family" {
  description = "Parameter group family"
  type        = string
  default     = "redis7"
}

variable "cluster_mode_enabled" {
  description = "Enable cluster mode"
  type        = bool
  default     = true
}

variable "num_node_groups" {
  description = "Number of node groups (shards)"
  type        = number
  default     = 1
}

variable "replicas_per_node_group" {
  description = "Number of replicas per node group"
  type        = number
  default     = 0
}

variable "automatic_failover_enabled" {
  description = "Enable automatic failover"
  type        = bool
  default     = true
}

variable "multi_az_enabled" {
  description = "Enable Multi-AZ"
  type        = bool
  default     = true
}

variable "at_rest_encryption_enabled" {
  description = "Enable at-rest encryption"
  type        = bool
  default     = true
}

variable "transit_encryption_enabled" {
  description = "Enable in-transit encryption"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs"
  type        = list(string)
  default     = []
}

variable "snapshot_retention_limit" {
  description = "Snapshot retention limit in days"
  type        = number
  default     = 5
}

variable "snapshot_window" {
  description = "Snapshot window"
  type        = string
  default     = "03:00-05:00"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
