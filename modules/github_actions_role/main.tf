locals {
  github_org_name  = split("/", var.github_repo)[0]
  github_repo_name = split("/", var.github_repo)[1]

  # See the variable descriptions for github_org_id/github_repo_id: which
  # form GitHub actually issues is per-repo, verified empirically, not
  # assumed.
  subject_owner_repo = (
    var.github_org_id != null && var.github_repo_id != null
    ? "${local.github_org_name}@${var.github_org_id}/${local.github_repo_name}@${var.github_repo_id}"
    : var.github_repo
  )
}

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
    # account. `sub` is used instead (verified working). Whether `sub`
    # embeds numeric org/repo IDs turned out to be per-repo, not org-wide:
    # see github_org_id/github_repo_id. Multiple values are allowed so one
    # role can serve e.g. both a branch-triggered job and
    # environment-gated deploy jobs.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        for subject in var.subjects :
        "repo:${local.subject_owner_repo}:${subject}"
      ]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn
}

# The inline policy used to be unconditional.
moved {
  from = aws_iam_role_policy.this
  to   = aws_iam_role_policy.this[0]
}

# Counted on policies, not policy_json: policy_json is often unknown until
# apply (it references other resources' ARNs), and count must be known at plan.
resource "aws_iam_role_policy" "this" {
  count  = length(var.policies) == 0 ? 1 : 0
  name   = "${var.role_name}-permissions"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}

# Managed rather than inline: a role's inline policies share one 10,240
# character limit, while each managed policy gets 6,144 of its own.
resource "aws_iam_policy" "this" {
  for_each = var.policies
  name     = "${var.role_name}-${each.key}"
  policy   = each.value
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = aws_iam_policy.this
  role       = aws_iam_role.this.name
  policy_arn = each.value.arn
}
