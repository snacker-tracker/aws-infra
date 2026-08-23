# Deploy role for github.com/snacker-tracker/reporter-serverless's CI
# pipeline. That pipeline currently authenticates with static AWS access
# keys (a GitHub secret) — this role exists to replace that. The
# reporter-serverless workflow itself still needs updating to use
# aws-actions/configure-aws-credentials with `role-to-assume` set to this
# role's ARN via OIDC, instead of the static keys — see README.md for the
# snippet.
#
# Scoped pragmatically by resource-name prefix per service, matching that
# app's own Terraform naming convention (`${var.api_name}-*-${workspace}`,
# api_name defaulting to "snacker-tracker", workspace being "dev" or
# "prod"). Not scoped to exact ARNs where API Gateway/ACM/Lambda
# event-source-mappings don't support pre-creation resource ARNs at all.

module "reporter_serverless_deploy" {
  source = "./modules/github_actions_role"

  role_name   = "github-actions-reporter-serverless-deploy"
  github_repo = "snacker-tracker/reporter-serverless"
  # No github_org_id/github_repo_id: verified via a live token capture that
  # this repo's `sub` is the plain "repo:org/repo:..." form, unlike
  # aws-infra's (which does embed the numeric IDs) — this is apparently a
  # per-repo GitHub setting, not org-wide. See README's OIDC gotchas.

  # The `test`/`build` jobs run on a plain branch push; `deploy-dev` and
  # `deploy-prod` are gated by GitHub Environments, which replaces the
  # token's subject entirely (environment:NAME instead of ref:...).
  subjects = [
    "ref:refs/heads/master",
    "environment:dev",
    "environment:prod",
  ]

  oidc_provider_arn        = aws_iam_openid_connect_provider.github_actions.arn
  permissions_boundary_arn = aws_iam_policy.app_role_boundary.arn

  policy_json = data.aws_iam_policy_document.reporter_serverless_deploy.json
}

data "aws_iam_policy_document" "reporter_serverless_deploy" {
  statement {
    sid    = "LambdaFunctions"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:DeleteFunction",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:ListTags",
      "lambda:PublishVersion",
      "lambda:ListVersionsByFunction",
      "lambda:CreateAlias",
      "lambda:UpdateAlias",
      "lambda:DeleteAlias",
      "lambda:GetAlias",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetPolicy",
    ]
    resources = ["arn:aws:lambda:*:*:function:snacker-tracker-*"]
  }

  statement {
    sid    = "LambdaEventSourceMappings"
    effect = "Allow"
    actions = [
      "lambda:CreateEventSourceMapping",
      "lambda:UpdateEventSourceMapping",
      "lambda:DeleteEventSourceMapping",
      "lambda:GetEventSourceMapping",
      "lambda:ListEventSourceMappings",
    ]
    # Event source mapping ARNs are UUID-based and unknown pre-creation;
    # IAM doesn't support scoping these to the underlying function/queue.
    resources = ["*"]
  }

  statement {
    sid    = "OwnServiceRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole",
    ]
    # Covers this app's own runtime roles: lambda execution role and
    # api-gateway role (both "${api_name}-*-${workspace}" =>
    # snacker-tracker-*), the firehose delivery role, and the eventbridge
    # delivery role (name_prefix-based, not api_name-prefixed).
    resources = [
      "arn:aws:iam::*:role/snacker-tracker-*",
      "arn:aws:iam::*:role/firehose-delivery-*",
      "arn:aws:iam::*:role/eventbridge_delivery_role*",
    ]
  }

  statement {
    sid    = "OwnStandalonePolicies"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
    ]
    resources = ["arn:aws:iam::*:policy/firehose-*"]
  }

  statement {
    sid       = "ApiGateway"
    effect    = "Allow"
    actions   = ["apigateway:*"]
    resources = ["arn:aws:apigateway:*::/*"]
  }

  statement {
    sid    = "AcmForCustomDomain"
    effect = "Allow"
    actions = [
      "acm:RequestCertificate",
      "acm:DescribeCertificate",
      "acm:DeleteCertificate",
      "acm:ListCertificates",
      "acm:AddTagsToCertificate",
      "acm:ListTagsForCertificate",
    ]
    # No pre-creation ARN to scope to (random cert ID at issue time). Runs
    # via that repo's aws.us-east-1 provider alias — edge-optimized API
    # Gateway custom domains require the cert in us-east-1 specifically.
    resources = ["*"]
  }

  statement {
    sid    = "Route53ForKhanomXyz"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
    ]
    resources = [aws_route53_zone.khanom_xyz.arn]
  }

  statement {
    sid       = "Route53GetChange"
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    sid    = "EventBridge"
    effect = "Allow"
    actions = [
      "events:PutRule",
      "events:DescribeRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:DeleteRule",
      "events:ListTargetsByRule",
      "events:TagResource",
      "events:UntagResource",
      "events:ListTagsForResource",
      "events:CreateEventBus",
      "events:DeleteEventBus",
      "events:DescribeEventBus",
    ]
    resources = [
      "arn:aws:events:*:*:rule/snacker-tracker-*",
      "arn:aws:events:*:*:event-bus/snacker-tracker-*",
    ]
  }

  statement {
    sid    = "Firehose"
    effect = "Allow"
    actions = [
      "firehose:CreateDeliveryStream",
      "firehose:DeleteDeliveryStream",
      "firehose:DescribeDeliveryStream",
      "firehose:UpdateDestination",
      "firehose:TagDeliveryStream",
      "firehose:ListTagsForDeliveryStream",
    ]
    resources = ["arn:aws:firehose:*:*:deliverystream/snacker-tracker-*"]
  }

  statement {
    sid    = "Sqs"
    effect = "Allow"
    actions = [
      "sqs:CreateQueue",
      "sqs:DeleteQueue",
      "sqs:GetQueueAttributes",
      "sqs:SetQueueAttributes",
      "sqs:TagQueue",
      "sqs:UntagQueue",
      "sqs:GetQueueUrl",
      "sqs:ListQueueTags",
    ]
    resources = ["arn:aws:sqs:*:*:snacker-tracker-*"]
  }

  statement {
    sid    = "S3FirehoseDestinationBucket"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:GetBucketPolicy",
      "s3:PutBucketAcl",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    # Exact bucket names (not a "snacker-tracker-*" wildcard): that prefix
    # is shared with this repo's own state bucket
    # (snacker-tracker-aws-infra-tfstate) — a wildcard here would also
    # grant this app's deploy role write/delete access to our Terraform
    # state.
    resources = [
      "arn:aws:s3:::snacker-tracker-dev",
      "arn:aws:s3:::snacker-tracker-dev/*",
      "arn:aws:s3:::snacker-tracker-prod",
      "arn:aws:s3:::snacker-tracker-prod/*",
    ]
  }

  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
    ]
    resources = ["arn:aws:ecr:*:*:repository/snacker-tracker-lambda*"]
  }

  statement {
    sid    = "CloudWatchLogGroups"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DescribeLogGroups",
      "logs:TagResource",
      "logs:ListTagsForResource",
    ]
    resources = [
      "arn:aws:logs:*:*:log-group:/aws/apigateway/*",
      "arn:aws:logs:*:*:log-group:/aws/lambda/snacker-tracker-*",
      "arn:aws:logs:*:*:log-group:API-Gateway-Execution-Logs*",
    ]
  }

  statement {
    sid       = "StsIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}
