variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.29"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "GameMetrics Pro"
    ManagedBy   = "Terraform"
  }
}

variable "enable_local_ecr_build_push" {
  description = "Enable running local Docker build and push to ECR during Terraform apply (uses local-exec)."
  type        = bool
  default     = false
}

variable "ecr_repositories" {
  description = "ECR repositories to create"
  type = map(object({
    image_tag_mutability = optional(string, "MUTABLE")
    scan_on_push         = optional(bool, true)
    lifecycle_policy     = optional(string)
  }))
  default = {
    "event-ingestion-service" = {
      image_tag_mutability = "MUTABLE"
      scan_on_push         = true
      lifecycle_policy     = null  # Set in main.tf or pass JSON string
    }
  }
}
