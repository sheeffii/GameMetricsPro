variable "environment" {
  description = "Environment name"
  type        = string
}

variable "buckets" {
  description = "Map of bucket configurations"
  type        = any
  default     = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
