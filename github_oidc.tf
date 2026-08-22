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
    # scoped"). job_workflow_ref-based matching was tried first (cleaner:
    # no numeric IDs, pins to the specific workflow file) and produced a
    # trust policy confirmed byte-for-byte correct against the token's
    # actual claims, but STS still rejected it with a generic
    # "AccessDenied: An unknown error occurred" every time — apparently
    # broken for this org/account. Matching on `sub` instead (verified
    # working) requires the numeric org/repo IDs because this org has
    # immutable-ID subject claims baked into `sub`
    # ("repo:org@ORGID/repo@REPOID:ref:..."), not the plain form.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${split("/", var.github_repo)[0]}@${var.github_org_id}/${split("/", var.github_repo)[1]}@${var.github_repo_id}:ref:refs/heads/master"]
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
