# Permissions boundary attached to every per-app GitHub Actions role (see
# modules/github_actions_role). It doesn't restrict which AWS services an
# app can use — that's controlled by each role's own policy — it only
# hard-blocks IAM-mutating actions, so no app role can grant itself (or any
# other role) more access, touch this boundary, or touch the OIDC provider,
# no matter what its own policy says.

data "aws_iam_policy_document" "app_role_boundary" {
  statement {
    sid       = "AllowEverythingByDefault"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyIamMutation"
    effect = "Deny"
    actions = [
      "iam:Add*",
      "iam:Attach*",
      "iam:Create*",
      "iam:Delete*",
      "iam:Detach*",
      "iam:Put*",
      "iam:Remove*",
      "iam:Set*",
      "iam:Update*",
    ]
    # Verb-prefix based (not an enumerated action list) so it also covers
    # any new IAM mutating action AWS adds later. iam:PassRole, iam:Get*,
    # iam:List*, iam:Simulate* etc. are untouched by this.
    resources = ["*"]
  }
}

resource "aws_iam_policy" "app_role_boundary" {
  name        = "app-role-permissions-boundary"
  description = "Boundary applied to every per-app GitHub Actions role: blocks IAM self-escalation regardless of the role's own policy"
  policy      = data.aws_iam_policy_document.app_role_boundary.json
}
