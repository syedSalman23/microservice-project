# Define the 12 repository names
locals {
  repo_names = [
    "frontend", "cartservice", "productcatalogservice",
    "currencyservice", "paymentservice", "shippingservice", "emailservice",
    "checkoutservice", "recommendationservice", "adservice", "redis-cart",
    "loadgenerator","shoppingassistantservice"
  ]
}

resource "aws_ecr_repository" "k8s-repositories" {
  for_each             = toset(local.repo_names)
  name                 = each.key
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = each.key
  }
}

resource "aws_ecr_lifecycle_policy" "repo_policy" {
  for_each   = aws_ecr_repository.k8s-repositories
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}