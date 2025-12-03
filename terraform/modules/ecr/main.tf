variable "repositories" {
  description = "Map of ECR repositories to create"
  type = map(object({
    image_tag_mutability = optional(string, "MUTABLE")
    scan_on_push         = optional(bool, true)
    lifecycle_policy     = optional(string)
  }))
}

resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name                 = each.key
  image_tag_mutability = each.value.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = each.key
  }
}

# Optional lifecycle policy per repository
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = { for k, v in var.repositories : k => v if try(length(v.lifecycle_policy) > 0, false) }

  repository = aws_ecr_repository.this[each.key].name
  policy     = each.value.lifecycle_policy
}
