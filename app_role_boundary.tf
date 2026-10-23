# Permissions boundary attached to every per-app GitHub Actions role (see
# modules/github_actions_role). It doesn't restrict which AWS services an
# app can use — that's controlled by each role's own policy — it hard-blocks
# mutation of the CI/deploy-role layer itself and account-wide IAM settings,
# so no app role can grant itself (or another app's deploy role) more
# access, touch this boundary, or touch the OIDC provider, no matter what
# its own policy says.
#
# This does NOT block apps from creating/managing their OWN runtime IAM
# roles (e.g. a Lambda execution role, a Firehose delivery role) — several
# apps' own Terraform manages IAM resources for services to assume, and a
# blanket IAM deny would break that. Residual risk: since this only
# protects the CI-identity layer BY NAME (github-actions-* roles, this
# boundary, the OIDC provider), an app's deploy role could in principle
# still tamper with a DIFFERENT app's runtime role if it knew its ARN.
# Closing that fully would mean requiring every app's own Terraform to
# attach a runtime-role boundary to whatever it creates — not done here,
# since it requires changes in each app's own repo.

data "aws_iam_policy_document" "app_role_boundary" {
  statement {
    sid       = "AllowEverythingByDefault"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  # Always denied, regardless of resource: account-wide IAM settings and
  # identity-provider/user management. No app deploy role should ever touch
  # these — not scoped to "our" resources specifically because most of
  # these actions aren't resource-scopable in IAM to begin with.
  statement {
    sid    = "DenyAccountWideIamActions"
    effect = "Deny"
    actions = [
      "iam:CreateAccountAlias",
      "iam:DeleteAccountAlias",
      "iam:UpdateAccountPasswordPolicy",
      "iam:DeleteAccountPasswordPolicy",
      "iam:CreateSAMLProvider",
      "iam:UpdateSAMLProvider",
      "iam:DeleteSAMLProvider",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:CreateUser",
      "iam:DeleteUser",
      "iam:CreateAccessKey",
      "iam:UpdateAccessKey",
      "iam:DeleteAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:DeleteLoginProfile",
      "iam:CreateVirtualMFADevice",
      "iam:DeactivateMFADevice",
      "iam:DeleteVirtualMFADevice",
    ]
    resources = ["*"]
  }

  # Denied only when targeting the CI/deploy-role layer specifically: any
  # github-actions-* role (this account's convention for CI identities),
  # this boundary policy itself, or the runtime-role boundaries
  # (runtime_role_boundary*.tf). Mutating a NON-CI-named role/policy (an
  # app's own runtime role) is left to the "allow everything by default"
  # statement above, controlled instead by each app role's own policy.
  statement {
    sid    = "DenyMutatingCiIdentityLayer"
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
    resources = [
      "arn:aws:iam::*:role/github-actions-*",
      "arn:aws:iam::*:policy/app-role-permissions-boundary",
      "arn:aws:iam::*:policy/runtime-role-permissions-boundary",
      "arn:aws:iam::*:policy/reporter-serverless-runtime-boundary",
      "arn:aws:iam::*:oidc-provider/token.actions.githubusercontent.com",
    ]
  }
}

resource "aws_iam_policy" "app_role_boundary" {
  name        = "app-role-permissions-boundary"
  description = "Boundary applied to every per-app GitHub Actions role: blocks IAM self-escalation regardless of the role's own policy"
  policy      = data.aws_iam_policy_document.app_role_boundary.json
}
