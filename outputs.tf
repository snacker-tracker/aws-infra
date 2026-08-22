output "account_alias" {
  value = aws_iam_account_alias.this.account_alias
}

output "github_actions_admin_role_arn" {
  description = "Set this as the AWS_ROLE_ARN repo variable in GitHub Actions"
  value       = aws_iam_role.github_actions_admin.arn
}
