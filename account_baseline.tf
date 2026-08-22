# Account-wide baseline settings. These are singleton, account-level
# resources (not tied to any particular app/workload), which is why they
# live at the root of this config rather than in a module.

resource "aws_iam_account_alias" "this" {
  account_alias = var.account_alias
}

resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
