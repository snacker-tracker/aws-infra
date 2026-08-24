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

# AWS requires OIDC trust policies to scope on `sub` or `job_workflow_ref`
# specifically (any other claim is rejected as "not scoped").
# job_workflow_ref-based matching was tried first (cleaner: no numeric
# IDs, pins to the specific workflow file) and produced a trust policy
# confirmed byte-for-byte correct against the token's actual claims, but
# STS still rejected it with a generic "AccessDenied: An unknown error
# occurred" every time — apparently broken for this org/account. Matching
# on `sub` instead (verified working) requires the numeric org/repo IDs
# because this org has immutable-ID subject claims baked into `sub`
# ("repo:org@ORGID/repo@REPOID:ref:..."), not the plain form.
locals {
  github_actions_subject_prefix = "repo:${split("/", var.github_repo)[0]}@${var.github_org_id}/${split("/", var.github_repo)[1]}@${var.github_repo_id}"
}

# Full-admin role: used only by the `apply` job, which is gated behind the
# "prod" GitHub Environment (manual approval) — see .github/workflows/terraform.yml.
# Its subject is "environment:prod", not a branch ref, since Environment-
# gated jobs get that claim instead.
data "aws_iam_policy_document" "github_actions_admin_trust" {
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

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_actions_subject_prefix}:environment:prod"]
    }
  }
}

resource "aws_iam_role" "github_actions_admin" {
  name               = "github-actions-admin"
  assume_role_policy = data.aws_iam_policy_document.github_actions_admin_trust.json
}

resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Read-only role: used by the unattended `plan` job, which runs on every
# push with no manual gate — including feature branches (see the
# StringLike wildcard below), for pre-merge visibility. Deliberately can't
# mutate anything — if this job's credentials ever leaked, the blast
# radius is "can read/enumerate this account's resources," not "can
# change them," regardless of which branch triggered it.
data "aws_iam_policy_document" "github_actions_plan_trust" {
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

    # StringLike (not StringEquals) with a "refs/heads/*" wildcard: this
    # role is meant to be assumable from any branch, not just master, so
    # feature-branch pushes get plan visibility too. Safe to broaden since
    # ReadOnlyAccess can't mutate anything regardless of which branch.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_actions_subject_prefix}:ref:refs/heads/*"]
    }
  }
}

resource "aws_iam_role" "github_actions_plan" {
  name               = "github-actions-plan"
  assume_role_policy = data.aws_iam_policy_document.github_actions_plan_trust.json
}

resource "aws_iam_role_policy_attachment" "github_actions_plan" {
  role       = aws_iam_role.github_actions_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess deliberately excludes s3:PutObject/DeleteObject, but
# Terraform's S3 native locking (use_lockfile) needs to create/delete a
# lock file even for a plain `plan` — it still protects against
# concurrent state reads. Scoped to exactly the lock object, not the
# state file itself (no read/write access to the actual state content
# beyond what ReadOnlyAccess's s3:GetObject already grants).
data "aws_iam_policy_document" "github_actions_plan_state_lock" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tf_state.arn}/root/terraform.tfstate.tflock"]
  }
}

resource "aws_iam_role_policy" "github_actions_plan_state_lock" {
  name   = "state-lock"
  role   = aws_iam_role.github_actions_plan.name
  policy = data.aws_iam_policy_document.github_actions_plan_state_lock.json
}
