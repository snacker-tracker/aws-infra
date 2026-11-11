# The GitHub OIDC provider and this repo's own CI roles (github-actions-admin
# and github-actions-plan) are managed by terraform-aws-accounts
# (accounts/snacker-tracker), so a bad apply here can't lock CI out. This
# stack only looks the provider up, for the app deploy roles that trust it.
data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

removed {
  from = aws_iam_openid_connect_provider.github_actions

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_role.github_actions_admin

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_role_policy_attachment.github_actions_admin

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_role.github_actions_plan

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_role_policy_attachment.github_actions_plan

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_role_policy.github_actions_plan_state_lock

  lifecycle {
    destroy = false
  }
}
