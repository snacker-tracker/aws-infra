# Lets GitHub Actions in this repo assume an admin role via OIDC, with no
# long-lived AWS keys stored as GitHub secrets. Bootstrap note: this has to
# be applied from a local run (with your own profile) first — CI can't
# create the trust relationship that lets CI itself authenticate.

data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  # AWS validates GitHub's OIDC certificate chain against its own trusted
  # root CAs rather than this value, but the resource schema still requires
  # it. Computed from the live cert chain (root CA, last in the list)
  # instead of hardcoded, so it can't go stale if GitHub ever rotates it.
  thumbprint_list = [
    data.tls_certificate.github_actions.certificates[
      length(data.tls_certificate.github_actions.certificates) - 1
    ].sha1_fingerprint,
  ]
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # AWS requires OIDC trust policies to scope on `sub` or
    # `job_workflow_ref` specifically (any other claim is rejected as "not
    # scoped"). `job_workflow_ref` is used here rather than `sub` because
    # this org has immutable-ID subject claims enabled, making `sub` look
    # like "repo:org@ORGID/repo@REPOID:ref:...", not the plain form assumed
    # below. `job_workflow_ref` stays plain either way, and additionally
    # pins to this specific workflow file (not just the branch).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = ["${var.github_repo}/.github/workflows/terraform.yml@refs/heads/master"]
    }
  }
}

resource "aws_iam_role" "github_actions_admin" {
  name               = "github-actions-admin"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
