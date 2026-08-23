output "account_alias" {
  value = aws_iam_account_alias.this.account_alias
}

output "github_actions_admin_role_arn" {
  description = "Set this as the AWS_ROLE_ARN repo variable in GitHub Actions"
  value       = aws_iam_role.github_actions_admin.arn
}

output "khanom_xyz_nameservers" {
  description = "Update khanom.xyz's NS records at its registrar to these"
  value       = aws_route53_zone.khanom_xyz.name_servers
}

output "reporter_serverless_deploy_role_arn" {
  description = "Set this as the AWS_ROLE_ARN repo variable in reporter-serverless, replacing its static access keys"
  value       = module.reporter_serverless_deploy.role_arn
}

output "snacker_tracker_lambda_append_to_bronze_repository_url" {
  value = aws_ecr_repository.snacker_tracker_lambda_append_to_bronze.repository_url
}
