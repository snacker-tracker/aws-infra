# ECR repo for reporter-serverless's Lambda container images (see
# app_role_reporter_serverless.tf — its deploy role already has push
# access to anything under "snacker-tracker-lambda*").

resource "aws_ecr_repository" "snacker_tracker_lambda_append_to_bronze" {
  name                 = "snacker-tracker-lambda/append-to-bronze"
  image_tag_mutability = "MUTABLE"

  tags = {
    Component = "reporter-serverless"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

data "aws_caller_identity" "current" {}

# Required for Lambda functions backed by this image: Lambda pulls the
# image using its own service identity (not the caller's), which needs
# this resource-based grant regardless of the deploy role's own IAM
# permissions — a separate mechanism from identity-based policies.
resource "aws_ecr_repository_policy" "snacker_tracker_lambda_append_to_bronze" {
  repository = aws_ecr_repository.snacker_tracker_lambda_append_to_bronze.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowLambdaPull"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_ecr_repository" "snacker_tracker_lambda_interface" {
  name                 = "snacker-tracker-lambda/interface"
  image_tag_mutability = "IMMUTABLE"

  tags = {
    Component = "interface"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Same grant as for append-to-bronze, but scoped to snacker-tracker-*
# functions rather than the whole account (kept as interface defined it).
resource "aws_ecr_repository_policy" "snacker_tracker_lambda_interface" {
  repository = aws_ecr_repository.snacker_tracker_lambda_interface.name
  policy     = data.aws_iam_policy_document.snacker_tracker_lambda_interface_pull.json
}

data "aws_iam_policy_document" "snacker_tracker_lambda_interface_pull" {
  statement {
    sid     = "LambdaPulls"
    actions = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:snacker-tracker-*"]
    }
  }
}

# Untagged only: images are tagged by commit SHA and prod may run an older
# one than dev, so tagged images are never expired automatically.
resource "aws_ecr_lifecycle_policy" "snacker_tracker_lambda_interface" {
  repository = aws_ecr_repository.snacker_tracker_lambda_interface.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "snacker_tracker_lambda_append_to_bronze" {
  repository = aws_ecr_repository.snacker_tracker_lambda_append_to_bronze.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
