# Bootstraps the bucket that will hold this config's own remote state.
#
# Chicken-and-egg: this must be created via a *local*-state apply first.
# Once it exists, uncomment the `backend "s3"` block in versions.tf and run
# `terraform init -migrate-state` to move state into this bucket.

resource "aws_s3_bucket" "tf_state" {
  bucket = "${var.account_alias}-aws-infra-tfstate"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
