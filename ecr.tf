# ECR repo for reporter-serverless's Lambda container images (see
# app_role_reporter_serverless.tf — its deploy role already has push
# access to anything under "snacker-tracker-lambda*").

resource "aws_ecr_repository" "snacker_tracker_lambda_append_to_bronze" {
  name                 = "snacker-tracker-lambda/append-to-bronze"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
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
