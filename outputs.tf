output "account_alias" {
  value = aws_iam_account_alias.this.account_alias
}

output "github_actions_admin_role_arn" {
  description = "Set this as the AWS_ROLE_ARN repo variable in GitHub Actions"
  value       = aws_iam_role.github_actions_admin.arn
}

output "github_actions_plan_role_arn" {
  description = "Set this as the AWS_PLAN_ROLE_ARN repo variable in GitHub Actions"
  value       = aws_iam_role.github_actions_plan.arn
}

output "khanom_xyz_nameservers" {
  description = "Update khanom.xyz's NS records at its registrar to these"
  value       = aws_route53_zone.khanom_xyz.name_servers
}

output "reporter_serverless_deploy_role_arn" {
  description = "Set this as the AWS_ROLE_ARN repo variable in reporter-serverless, replacing its static access keys"
  value       = module.reporter_serverless_deploy.role_arn
}

output "runtime_role_boundary_arn" {
  description = "Set as permissions_boundary on every runtime role an app's Terraform creates"
  value       = aws_iam_policy.runtime_role_boundary.arn
}

output "interface_deploy_role_arns" {
  description = "Per environment: the role interface's deploy.yml assumes, replacing snacker-tracker-<env>-ci"
  value       = { for env, role in module.interface_deploy : env => role.role_arn }
}

output "snacker_tracker_lambda_interface_repository_url" {
  value = aws_ecr_repository.snacker_tracker_lambda_interface.repository_url
}

output "snacker_tracker_lambda_append_to_bronze_repository_url" {
  value = aws_ecr_repository.snacker_tracker_lambda_append_to_bronze.repository_url
}
