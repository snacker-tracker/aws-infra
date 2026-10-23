# Deploy roles for github.com/snacker-tracker/interface, one per environment
# (github-actions-interface-dev, github-actions-interface-prod). They apply
# that repo's infra/main configuration and publish its frontend.
#
# Ported from interface's infra/admin/ci_role.tf (its ADR 0005), which
# created them as snacker-tracker-<env>-ci. The policies are written against
# the names interface's admin configuration and main configuration use, so
# a new permission for interface's CI is now a change here:
# - functions, schedules and log groups snacker-tracker-<env>-*
# - the buckets snacker-tracker-<env>-{site,working,access-logs}
# - the workload roles snacker-tracker-<env>-{build,extraction,scheduler},
#   which interface's admin configuration still creates
# - CloudFront distributions and ACM certificates tagged
#   Project=snacker-tracker
# - the state key env:/<env>/snacker-tracker-interface in this repo's
#   state bucket
#
# The CI role manages only those resources. On IAM it can only read and pass
# its environment's workload roles; it never writes a permission.

locals {
  interface_environments = {
    dev = {
      raw_bucket      = "snacker-tracker-dev"
      hostnames       = ["dev.khanom.xyz"]
      can_push_images = true
      # Pull requests plan in dev only, so they can never assume the prod role.
      subjects = ["environment:dev", "pull_request"]
    }
    prod = {
      raw_bucket      = "snacker-tracker-prod"
      hostnames       = ["khanom.xyz", "www.khanom.xyz"]
      can_push_images = false
      subjects        = ["environment:prod"]
    }
  }

  interface_account          = data.aws_caller_identity.current.account_id
  interface_function_arn     = "arn:aws:lambda:${var.region}:${local.interface_account}:function"
  interface_log_group_arn    = "arn:aws:logs:${var.region}:${local.interface_account}:log-group:/aws/lambda"
  interface_role_arn         = "arn:aws:iam::${local.interface_account}:role"
  interface_log_delivery_arn = "arn:aws:logs:us-east-1:${local.interface_account}"
  interface_raw_buckets      = [for env in values(local.interface_environments) : env.raw_bucket]
  interface_project_tag      = { variable = "Project", value = "snacker-tracker" }

  interface = {
    for env, config in local.interface_environments : env => merge(config, {
      prefix                 = "snacker-tracker-${env}"
      site_bucket_arn        = "arn:aws:s3:::snacker-tracker-${env}-site"
      working_bucket         = "snacker-tracker-${env}-working"
      access_logs_bucket_arn = "arn:aws:s3:::snacker-tracker-${env}-access-logs"
      access_log_group_arn   = "${local.interface_log_delivery_arn}:log-group:/aws/vendedlogs/cloudfront/snacker-tracker-${env}-*"
      main_state_object      = "env:/${env}/snacker-tracker-interface"
      workload_roles = {
        lambda    = ["${local.interface_role_arn}/snacker-tracker-${env}-build", "${local.interface_role_arn}/snacker-tracker-${env}-extraction"]
        scheduler = ["${local.interface_role_arn}/snacker-tracker-${env}-scheduler"]
      }
    })
  }
}

module "interface_deploy" {
  source   = "./modules/github_actions_role"
  for_each = local.interface

  role_name      = "github-actions-interface-${each.key}"
  github_repo    = "snacker-tracker/interface"
  github_org_id  = var.github_org_id
  github_repo_id = "1428184726"
  subjects       = each.value.subjects

  oidc_provider_arn        = aws_iam_openid_connect_provider.github_actions.arn
  permissions_boundary_arn = aws_iam_policy.app_role_boundary.arn

  # Four policies rather than one: together they're too large for a single policy.
  policies = {
    workloads = data.aws_iam_policy_document.interface_workloads[each.key].json
    edge      = data.aws_iam_policy_document.interface_edge[each.key].json
    logs      = data.aws_iam_policy_document.interface_access_logs[each.key].json
    guards    = data.aws_iam_policy_document.interface_guards[each.key].json
  }
}

# --- Functions, schedule, logs, the working bucket, the site's frontend files, the image ---

data "aws_iam_policy_document" "interface_workloads" {
  for_each = local.interface

  # No AddPermission or function URLs: those are resource policies, and nothing needs them.
  statement {
    sid = "Functions"
    actions = [
      "lambda:Get*", "lambda:List*",
      "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:PublishVersion",
      "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
      "lambda:PutFunctionConcurrency", "lambda:DeleteFunctionConcurrency",
      "lambda:PutFunctionEventInvokeConfig", "lambda:UpdateFunctionEventInvokeConfig",
      "lambda:DeleteFunctionEventInvokeConfig",
      "lambda:TagResource", "lambda:UntagResource", "lambda:InvokeFunction",
    ]
    resources = ["${local.interface_function_arn}:${each.value.prefix}-*"]
  }

  statement {
    sid       = "ListFunctions"
    actions   = ["lambda:ListFunctions", "scheduler:ListSchedules", "logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid = "Schedule"
    actions = [
      "scheduler:GetSchedule", "scheduler:CreateSchedule",
      "scheduler:UpdateSchedule", "scheduler:DeleteSchedule",
    ]
    resources = ["arn:aws:scheduler:${var.region}:${local.interface_account}:schedule/default/${each.value.prefix}-*"]
  }

  statement {
    sid = "LogGroups"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource",
      "logs:ListTagsForResource", "logs:TagLogGroup", "logs:ListTagsLogGroup",
    ]
    resources = ["${local.interface_log_group_arn}/${each.value.prefix}-*", each.value.access_log_group_arn]
  }

  # Bucket and object policies, ACLs and public access are denied in interface_guards.
  statement {
    sid       = "WorkingBucket"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${each.value.working_bucket}", "arn:aws:s3:::${each.value.working_bucket}/*"]
  }

  statement {
    sid       = "ReadSiteBucket"
    actions   = ["s3:ListBucket", "s3:GetBucket*", "s3:GetEncryptionConfiguration"]
    resources = [each.value.site_bucket_arn]
  }

  # data/* is the build's alone (interface's ADR 0004); the deny is in interface_guards.
  statement {
    sid       = "FrontendFiles"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${each.value.site_bucket_arn}/*"]
  }

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Dev builds the image; prod only reads it (interface's ADR 0006).
  statement {
    sid = "Image"
    actions = concat(
      [
        "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability",
        "ecr:DescribeImages", "ecr:DescribeRepositories",
      ],
      each.value.can_push_images ? [
        "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
      ] : [],
    )
    resources = [aws_ecr_repository.snacker_tracker_lambda_interface.arn]
  }
}

# --- CloudFront, its certificate and DNS records ---

data "aws_iam_policy_document" "interface_edge" {
  for_each = local.interface

  # Creates take no resource ARN (the ID doesn't exist yet), only "*"; the tag scopes them.
  statement {
    sid       = "CreateTaggedDistributions"
    actions   = ["cloudfront:CreateDistribution", "cloudfront:TagResource"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${local.interface_project_tag.variable}"
      values   = [local.interface_project_tag.value]
    }
  }

  statement {
    sid = "ManageTaggedDistributions"
    actions = [
      "cloudfront:GetDistribution", "cloudfront:GetDistributionConfig",
      "cloudfront:UpdateDistribution", "cloudfront:DeleteDistribution",
      "cloudfront:ListTagsForResource", "cloudfront:UntagResource",
      "cloudfront:CreateInvalidation", "cloudfront:GetInvalidation",
    ]
    resources = ["arn:aws:cloudfront::${local.interface_account}:distribution/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.interface_project_tag.variable}"
      values   = [local.interface_project_tag.value]
    }
  }

  # Origin access controls can't carry tags. They grant nothing by themselves: the site
  # bucket's policy decides what CloudFront may read.
  statement {
    sid       = "CreateOriginAccessControls"
    actions   = ["cloudfront:CreateOriginAccessControl"]
    resources = ["*"]
  }

  statement {
    sid = "OriginAccessControls"
    actions = [
      "cloudfront:GetOriginAccessControl", "cloudfront:UpdateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
    ]
    resources = ["arn:aws:cloudfront::${local.interface_account}:origin-access-control/*"]
  }

  statement {
    sid = "ReadCloudFront"
    actions = [
      "cloudfront:ListDistributions", "cloudfront:ListOriginAccessControls",
      "cloudfront:GetCachePolicy", "cloudfront:ListCachePolicies",
      "cloudfront:GetOriginRequestPolicy", "cloudfront:ListOriginRequestPolicies",
      "cloudfront:GetResponseHeadersPolicy", "cloudfront:ListResponseHeadersPolicies",
      "acm:ListCertificates",
    ]
    resources = ["*"]
  }

  # CloudFront certificates live in us-east-1. Requests take no resource ARN, only "*".
  statement {
    sid       = "RequestTaggedCertificates"
    actions   = ["acm:RequestCertificate", "acm:AddTagsToCertificate"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${local.interface_project_tag.variable}"
      values   = [local.interface_project_tag.value]
    }
  }

  statement {
    sid = "ManageTaggedCertificates"
    actions = [
      "acm:DescribeCertificate", "acm:GetCertificate", "acm:DeleteCertificate",
      "acm:ListTagsForCertificate", "acm:RemoveTagsFromCertificate",
    ]
    resources = ["arn:aws:acm:us-east-1:${local.interface_account}:certificate/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.interface_project_tag.variable}"
      values   = [local.interface_project_tag.value]
    }
  }

  statement {
    sid       = "ReadZone"
    actions   = ["route53:GetHostedZone", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
    resources = [aws_route53_zone.khanom_xyz.arn]
  }

  statement {
    sid       = "FindZoneAndChanges"
    actions   = ["route53:ListHostedZones", "route53:ListHostedZonesByName", "route53:GetChange"]
    resources = ["*"]
  }

  # Only this environment's names and their ACM validation records (_<token>.<name>).
  statement {
    sid       = "OwnRecords"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [aws_route53_zone.khanom_xyz.arn]
    condition {
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = flatten([for name in each.value.hostnames : [name, "_*.${name}"]])
    }
  }
}

# --- CloudFront access log delivery (interface's ADR 0010) ---

data "aws_iam_policy_document" "interface_access_logs" {
  for_each = local.interface

  # Lets this account's log delivery read the distribution's logs. It grants no principal access to
  # anything: where the logs may land is still decided by interface's access-log bucket and
  # CloudWatch Logs resource policies.
  statement {
    sid       = "VendDistributionLogs"
    actions   = ["cloudfront:AllowVendedLogDeliveryForResource"]
    resources = ["arn:aws:cloudfront::${local.interface_account}:distribution/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.interface_project_tag.variable}"
      values   = [local.interface_project_tag.value]
    }
  }

  # No delivery destination policies: those are only for cross-account delivery, and are permissions.
  # Delivery IDs are generated, so deliveries can't be scoped by name.
  statement {
    sid = "Deliveries"
    actions = [
      "logs:PutDeliverySource", "logs:GetDeliverySource", "logs:DeleteDeliverySource",
      "logs:PutDeliveryDestination", "logs:GetDeliveryDestination", "logs:DeleteDeliveryDestination",
      "logs:CreateDelivery", "logs:GetDelivery", "logs:DeleteDelivery", "logs:UpdateDeliveryConfiguration",
      "logs:TagResource", "logs:UntagResource", "logs:ListTagsForResource",
    ]
    resources = [
      "${local.interface_log_delivery_arn}:delivery-source:${each.value.prefix}-*",
      "${local.interface_log_delivery_arn}:delivery-destination:${each.value.prefix}-*",
      "${local.interface_log_delivery_arn}:delivery:*",
    ]
  }

  # Delivery reads the destinations' policies to check it may write; it never changes them here.
  statement {
    sid = "ReadDeliveries"
    actions = [
      "logs:DescribeDeliverySources", "logs:DescribeDeliveryDestinations", "logs:DescribeDeliveries",
      "logs:DescribeConfigurationTemplates", "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadAccessLogsBucketPolicy"
    actions   = ["s3:GetBucketPolicy"]
    resources = [each.value.access_logs_bucket_arn]
  }
}

# --- Terraform state, IAM, and the denies that hold whatever the allows above say ---

data "aws_iam_policy_document" "interface_guards" {
  for_each = local.interface

  # The S3 backend lists env:/ to find workspaces, which shows other configurations' key
  # names but none of their contents.
  statement {
    sid       = "ListOwnState"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tf_state.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["env:/", "${each.value.main_state_object}*"]
    }
  }

  statement {
    sid       = "OwnState"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.tf_state.arn}/${each.value.main_state_object}"]
  }

  statement {
    sid       = "OwnStateLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tf_state.arn}/${each.value.main_state_object}.tflock"]
  }

  statement {
    sid       = "ReadWorkloadRoles"
    actions   = ["iam:GetRole"]
    resources = flatten(values(each.value.workload_roles))
  }

  dynamic "statement" {
    for_each = each.value.workload_roles
    content {
      sid       = "PassTo${title(statement.key)}"
      actions   = ["iam:PassRole"]
      resources = statement.value
      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["${statement.key}.amazonaws.com"]
      }
    }
  }

  statement {
    sid       = "NotData"
    effect    = "Deny"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${each.value.site_bucket_arn}/data/*"]
  }

  statement {
    sid       = "NotRawEvents"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = flatten([for bucket in local.interface_raw_buckets : ["arn:aws:s3:::${bucket}", "arn:aws:s3:::${bucket}/*"]])
  }

  statement {
    sid    = "NoBucketPermissions"
    effect = "Deny"
    actions = [
      "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketAcl", "s3:PutObjectAcl",
      "s3:PutBucketPublicAccessBlock", "s3:PutAccountPublicAccessBlock",
      "s3:PutBucketOwnershipControls",
    ]
    resources = ["*"]
  }

  # The project tag is what scopes CloudFront and ACM; removing it would hide a resource.
  statement {
    sid       = "KeepProjectTag"
    effect    = "Deny"
    actions   = ["cloudfront:UntagResource", "acm:RemoveTagsFromCertificate"]
    resources = ["*"]
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "aws:TagKeys"
      values   = [local.interface_project_tag.variable]
    }
  }
}
