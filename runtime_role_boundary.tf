# Permissions boundary for the runtime roles apps create for themselves
# (Lambda execution roles, Firehose/EventBridge/API Gateway delivery roles,
# ...). app_role_boundary.tf limits what an app's deploy role can do, but
# not what the roles it creates can do: without this, a deploy role allowed
# to create and attach policies to its own runtime roles can create one
# with AdministratorAccess and assume it.
#
# This closes that once app deploy roles may only create, or change the
# permissions of, roles carrying this boundary (an iam:PermissionsBoundary
# condition on their IAM statements). Runtime roles never need IAM, so
# denying it outright costs them nothing, and nothing a runtime role does
# can widen any role's permissions, its own included.
#
# Attaching it to a role constrains that role only; it has no effect until
# an app's Terraform sets it as `permissions_boundary` on its roles.

data "aws_iam_policy_document" "runtime_role_boundary" {
  statement {
    sid       = "AllowEverythingByDefault"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyIdentityAndAccountManagement"
    effect = "Deny"
    actions = [
      "iam:*",
      "organizations:*",
      "account:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "runtime_role_boundary" {
  name        = "runtime-role-permissions-boundary"
  description = "Boundary required on every app runtime role: no IAM, Organizations or account management, whatever the role's own policy says"
  policy      = data.aws_iam_policy_document.runtime_role_boundary.json
}
