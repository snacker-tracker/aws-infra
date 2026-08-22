data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # AWS requires OIDC trust policies to scope on `sub` or
    # `job_workflow_ref` specifically (any other claim is rejected as "not
    # scoped"). `job_workflow_ref` is used here rather than `sub` because
    # orgs with immutable-ID subject claims enabled get a `sub` like
    # "repo:org@ORGID/repo@REPOID:ref:...", not the plain form assumed
    # below. `job_workflow_ref` stays plain either way, and additionally
    # pins to this specific workflow file (not just the branch).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = ["${var.github_repo}/${var.workflow_path}@${var.ref}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.role_name}-permissions"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}
