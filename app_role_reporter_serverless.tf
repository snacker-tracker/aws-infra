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

locals {
  reporter_serverless_runtime_roles = [
    "arn:aws:iam::*:role/snacker-tracker-lambda-execution-*",
    "arn:aws:iam::*:role/snacker-tracker-api-gateway-firehose-role-*",
    "arn:aws:iam::*:role/snacker-tracker-eb-delivery-*",
    "arn:aws:iam::*:role/firehose-delivery-*",
  ]
}

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
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:ListTags",
    ]
    # Event source mapping ARNs are UUID-based and unknown pre-creation;
    # IAM doesn't support scoping these to the underlying function/queue.
    resources = ["*"]
  }

  # The app's own runtime roles, by the names its Terraform gives them:
  # "${api_name}-<role>-${workspace}" (api_name defaulting to
  # "snacker-tracker"), or a name_prefix for the Firehose and EventBridge
  # ones. Exact prefixes rather than snacker-tracker-*, which would also
  # cover interface's roles (snacker-tracker-<env>-*).
  statement {
    sid    = "OwnServiceRoles"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:DeleteRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PassRole",
    ]
    resources = local.reporter_serverless_runtime_roles
  }

  # Creating a role, or changing what it may do, only when it carries
  # runtime_role_boundary.tf's boundary: whatever policy the app writes, its
  # roles can never manage IAM. No AttachRolePolicy: the app only uses
  # inline policies, and attaching would allow AWS managed ones such as
  # AdministratorAccess. Detach stays for deleting roles. No
  # DeleteRolePermissionsBoundary, so the boundary can't be taken off.
  statement {
    sid    = "OwnServiceRolePermissions"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = local.reporter_serverless_runtime_roles
    # Either boundary while the app's roles move from the generic one to
    # its own (runtime_role_boundary_reporter_serverless.tf); the generic
    # one goes once both workspaces have moved.
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values = [
        aws_iam_policy.runtime_role_boundary.arn,
        aws_iam_policy.reporter_serverless_runtime_boundary.arn,
      ]
    }
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

  # Edge-optimized API Gateway custom domains provision a CloudFront
  # distribution internally, but API Gateway still checks that the
  # *caller* holds cloudfront:UpdateDistribution before associating a
  # cert with it — confirmed by CreateDomainName's own error message
  # naming this exact permission. Resource "*" because the distribution
  # ID is managed internally by API Gateway, never exposed for scoping.
  statement {
    sid       = "CloudFrontForApiGatewayCustomDomain"
    effect    = "Allow"
    actions   = ["cloudfront:UpdateDistribution"]
    resources = ["*"]
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
      "route53:GetHostedZone",
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
      "s3:GetBucketAcl",
      "s3:PutEncryptionConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:PutBucketTagging",
      "s3:GetBucketTagging",
      "s3:PutBucketVersioning",
      "s3:GetBucketVersioning",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetBucketPublicAccessBlock",
      # The rest of these are never explicitly set by this app's .tf, but
      # aws_s3_bucket's read/refresh cycle checks every sub-configuration
      # a bucket can have regardless (CORS, website, logging, etc.) —
      # missing any one of these fails `plan`/`apply` on this resource.
      "s3:GetBucketCORS",
      "s3:GetBucketWebsite",
      "s3:GetBucketLogging",
      "s3:GetReplicationConfiguration",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketNotification",
      # Not just a read-cycle check: aws_s3_bucket_notification wires this
      # bucket's events to the app's s3-to-lambda SQS queue.
      "s3:PutBucketNotification",
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

  # Lets reporter-serverless store its own Terraform state in THIS repo's
  # state bucket, at the bare key "snacker-tracker-reporter-serverless"
  # (that repo's backend `key` has no "/terraform.tfstate" suffix — it IS
  # the object name), instead of needing its own bucket. Both the bare-key
  # and "/*" forms are listed: a "prefix/*" ARN pattern requires a literal
  # "/" after the prefix to match anything, so it does NOT match an object
  # whose key is exactly the prefix string with nothing after it — this
  # bit us in practice (403s) before these bare-key entries were added.
  # The "/*" forms remain in case that key ever gains a real filename
  # suffix later. Two prefix variants (plain and "env:/<workspace>/...")
  # because that repo uses Terraform *workspaces* (dev/prod), which nests
  # state under a literal "env:/<workspace>/" prefix BEFORE the key.
  statement {
    sid    = "SharedStateBucketForReporterServerless"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "${aws_s3_bucket.tf_state.arn}/snacker-tracker-reporter-serverless",
      "${aws_s3_bucket.tf_state.arn}/snacker-tracker-reporter-serverless/*",
      "${aws_s3_bucket.tf_state.arn}/env:/*/snacker-tracker-reporter-serverless",
      "${aws_s3_bucket.tf_state.arn}/env:/*/snacker-tracker-reporter-serverless/*",
    ]
  }

  statement {
    sid       = "SharedStateBucketListForReporterServerless"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.tf_state.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["snacker-tracker-reporter-serverless/*", "env:/*/snacker-tracker-reporter-serverless/*"]
    }
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
      "ecr:GetDownloadUrlForLayer",
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
      "logs:TagResource",
      "logs:ListTagsForResource",
    ]
    resources = [
      "arn:aws:logs:*:*:log-group:/aws/apigateway/*",
      "arn:aws:logs:*:*:log-group:/aws/lambda/snacker-tracker-*",
      "arn:aws:logs:*:*:log-group:API-Gateway-Execution-Logs*",
    ]
  }

  # DescribeLogGroups is a list operation — AWS doesn't support scoping it
  # to specific log-group ARNs, it always needs Resource "*" (confirmed by
  # the AccessDenied error naming a placeholder ARN, not a real one).
  statement {
    sid       = "CloudWatchLogGroupsDescribe"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid       = "StsIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}
