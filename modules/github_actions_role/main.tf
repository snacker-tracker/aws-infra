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
    # scoped"). job_workflow_ref-based matching (cleaner: no numeric IDs,
    # pins to a specific workflow file) was tried for the admin role in
    # github_oidc.tf first, produced a trust policy confirmed correct
    # against the token's actual claims, and STS still rejected it with a
    # generic "AccessDenied" every time — apparently broken for this
    # account. `sub` is used instead (verified working), which requires
    # the numeric org/repo IDs because this org has immutable-ID subject
    # claims baked into `sub` ("repo:org@ORGID/repo@REPOID:ref:..."), not
    # the plain form. Note this only scopes to repo+ref, not a specific
    # workflow file (job_workflow_ref would have, but doesn't work here).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${split("/", var.github_repo)[0]}@${var.github_org_id}/${split("/", var.github_repo)[1]}@${var.github_repo_id}:ref:${var.ref}"]
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
