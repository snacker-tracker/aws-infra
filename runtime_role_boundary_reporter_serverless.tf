# Permissions boundary for reporter-serverless's runtime roles: the most any
# of them may ever do, whatever policy or trust that app's deploy role gives
# them. Unlike runtime_role_boundary.tf it allows only what those roles use,
# so a role the pipeline rewrote and assumed would still reach nothing but
# the app's own resources:
#
# - Lambda (append/rebuild/compact-bronze): its bucket, the S3-to-Lambda
#   queue (through the event source mapping), its functions' log groups
# - Firehose: writes the bucket
# - API Gateway: puts events on the bus
# - EventBridge: puts records on the stream, dead letters on the DLQ
#
# Names are listed exactly per workspace, never snacker-tracker-*: that
# would also match interface's buckets and log groups, and this repo's state
# bucket. Narrower scoping (raw/* vs bronze/*) is the roles' own policies' job.
#
# Not allowed, though the roles' policies grant it: logs:* on "*" for the
# Firehose and EventBridge roles (the stream has no logging configured, and
# EventBridge targets don't log).

locals {
  reporter_serverless_workspaces = ["dev", "prod"]
  reporter_serverless_account    = data.aws_caller_identity.current.account_id

  reporter_serverless_buckets = [for ws in local.reporter_serverless_workspaces : "arn:aws:s3:::snacker-tracker-${ws}"]
  reporter_serverless_streams = [for ws in local.reporter_serverless_workspaces : "arn:aws:firehose:${var.region}:${local.reporter_serverless_account}:deliverystream/snacker-tracker-${ws}"]
  reporter_serverless_buses   = [for ws in local.reporter_serverless_workspaces : "arn:aws:events:${var.region}:${local.reporter_serverless_account}:event-bus/snacker-tracker-${ws}"]
  reporter_serverless_queues  = [for ws in local.reporter_serverless_workspaces : "arn:aws:sqs:${var.region}:${local.reporter_serverless_account}:snacker-tracker-s3-to-lambda-${ws}"]
  reporter_serverless_dlqs    = [for ws in local.reporter_serverless_workspaces : "arn:aws:sqs:${var.region}:${local.reporter_serverless_account}:snacker-tracker-eventbridge-dlq-${ws}"]
  reporter_serverless_log_groups = flatten([
    for ws in local.reporter_serverless_workspaces : [
      for function in ["append-to-bronze", "rebuild-bronze", "compact-bronze"] :
      "arn:aws:logs:${var.region}:${local.reporter_serverless_account}:log-group:/aws/lambda/snacker-tracker-${function}-${ws}"
    ]
  ])
}

data "aws_iam_policy_document" "reporter_serverless_runtime_boundary" {
  statement {
    sid = "Bucket"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
    ]
    resources = local.reporter_serverless_buckets
  }

  statement {
    sid = "Objects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
    ]
    resources = [for bucket in local.reporter_serverless_buckets : "${bucket}/*"]
  }

  statement {
    sid       = "PutRecords"
    actions   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
    resources = local.reporter_serverless_streams
  }

  statement {
    sid       = "PutEvents"
    actions   = ["events:PutEvents"]
    resources = local.reporter_serverless_buses
  }

  statement {
    sid = "ConsumeQueue"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = local.reporter_serverless_queues
  }

  statement {
    sid       = "DeadLetters"
    actions   = ["sqs:SendMessage"]
    resources = local.reporter_serverless_dlqs
  }

  # CreateLogGroup is authorized against the group, the others against its streams.
  statement {
    sid = "FunctionLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = concat(
      local.reporter_serverless_log_groups,
      [for group in local.reporter_serverless_log_groups : "${group}:*"],
    )
  }
}

resource "aws_iam_policy" "reporter_serverless_runtime_boundary" {
  name        = "reporter-serverless-runtime-boundary"
  description = "Boundary required on reporter-serverless's runtime roles: only that app's own bucket, stream, event bus, queues and log groups"
  policy      = data.aws_iam_policy_document.reporter_serverless_runtime_boundary.json
}
