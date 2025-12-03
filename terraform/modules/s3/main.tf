resource "aws_s3_bucket" "main" {
  for_each = var.buckets

  bucket        = each.value.name
  force_destroy = true

  tags = merge(
    var.tags,
    {
      Name = each.value.name
      Type = each.key
    }
  )
}

# Versioning
resource "aws_s3_bucket_versioning" "main" {
  for_each = { for k, v in var.buckets : k => v if try(v.versioning, false) }

  bucket = aws_s3_bucket.main[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  for_each = var.buckets

  bucket = aws_s3_bucket.main[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Public access block
resource "aws_s3_bucket_public_access_block" "main" {
  for_each = var.buckets

  bucket = aws_s3_bucket.main[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rules
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  for_each = { for k, v in var.buckets : k => v if try(length(v.lifecycle_rules), 0) > 0 }

  bucket = aws_s3_bucket.main[each.key].id

  dynamic "rule" {
    for_each = each.value.lifecycle_rules

    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {}

      dynamic "transition" {
        for_each = try(rule.value.transition, [])

        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "expiration" {
        for_each = try([rule.value.expiration], [])

        content {
          days = expiration.value.days
        }
      }
    }
  }
}

# Bucket policy for flow logs
resource "aws_s3_bucket_policy" "flow_logs" {
  for_each = { for k, v in var.buckets : k => v if k == "logs" }

  bucket = aws_s3_bucket.main[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.main[each.key].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.main[each.key].arn
      }
    ]
  })
}

# Bucket logging
resource "aws_s3_bucket_logging" "main" {
  for_each = { for k, v in var.buckets : k => v if k != "logs" }

  bucket = aws_s3_bucket.main[each.key].id

  target_bucket = aws_s3_bucket.main["logs"].id
  target_prefix = "${each.key}/"
}
