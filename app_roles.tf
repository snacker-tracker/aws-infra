# Per-application GitHub Actions deploy roles. Each one is scoped to a
# single app's repo (and the subjects it actually authenticates as — a
# branch ref, a GitHub Environment, or both), gets only the permissions
# that app needs to deploy, and — via modules.github_actions_role — always
# gets app_role_boundary.tf's permissions boundary attached. See
# app_role_reporter_serverless.tf for a real, filled-in example.
#
# Skeleton for a new app:
#
# module "snacker_tracker_deploy" {
#   source = "./modules/github_actions_role"
#
#   role_name                = "github-actions-snacker-tracker-deploy"
#   github_repo              = "snacker-tracker/snacker-tracker"
#   github_org_id            = var.github_org_id # same org as this repo
#   github_repo_id           = "<numeric repo ID, see README for how to find it>"
#   subjects                 = ["ref:refs/heads/main"] # or ["environment:prod"], etc.
#   oidc_provider_arn        = aws_iam_openid_connect_provider.github_actions.arn
#   permissions_boundary_arn = aws_iam_policy.app_role_boundary.arn
#
#   policy_json = data.aws_iam_policy_document.snacker_tracker_deploy.json
# }
#
# data "aws_iam_policy_document" "snacker_tracker_deploy" {
#   statement {
#     effect    = "Allow"
#     actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
#     resources = [...]
#   }
# }
