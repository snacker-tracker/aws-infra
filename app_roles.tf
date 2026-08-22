# Per-application GitHub Actions deploy roles. Each one is scoped to a
# single app's repo (and ref), gets only the permissions that app needs to
# deploy, and — via modules.github_actions_role — always gets
# app_role_boundary.tf's permissions boundary, so none of them can touch
# IAM regardless of what their own policy grants.
#
# Example, once there's a real app to wire up:
#
# module "snacker_tracker_deploy" {
#   source = "./modules/github_actions_role"
#
#   role_name                = "github-actions-snacker-tracker-deploy"
#   github_repo              = "snacker-tracker/snacker-tracker"
#   workflow_path             = ".github/workflows/deploy.yml"
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
