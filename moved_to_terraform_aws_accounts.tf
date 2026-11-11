# Now managed by leprechaun/terraform-aws-accounts (accounts/snacker-tracker),
# which imported them. destroy = false only drops them from this state.

# The GitHub OIDC provider and this repo's own CI roles (github-actions-admin
# and github-actions-plan).
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

# The khanom.xyz zone. Its records stay with the apps that use them.
removed {
  from = aws_route53_zone.khanom_xyz

  lifecycle {
    destroy = false
  }
}

# The permissions boundaries.
removed {
  from = aws_iam_policy.app_role_boundary
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_policy.runtime_role_boundary
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_policy.reporter_serverless_runtime_boundary
  lifecycle {
    destroy = false
  }
}

# The app deploy roles, with their policies and attachments.
removed {
  from = module.reporter_serverless_deploy
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.interface_deploy
  lifecycle {
    destroy = false
  }
}

# The Lambda image repositories, with their pull and lifecycle policies.
removed {
  from = aws_ecr_repository.snacker_tracker_lambda_interface
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_ecr_repository_policy.snacker_tracker_lambda_interface
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_ecr_lifecycle_policy.snacker_tracker_lambda_interface
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_ecr_repository.snacker_tracker_lambda_append_to_bronze
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_ecr_repository_policy.snacker_tracker_lambda_append_to_bronze
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_ecr_lifecycle_policy.snacker_tracker_lambda_append_to_bronze
  lifecycle {
    destroy = false
  }
}

# Account-wide settings, now in member-baseline for every member account.
removed {
  from = aws_iam_account_alias.this

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_account_public_access_block.this

  lifecycle {
    destroy = false
  }
}

# The state bucket, still this stack's backend (versions.tf) and the apps'.
removed {
  from = aws_s3_bucket.tf_state

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_bucket_versioning.tf_state

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_bucket_server_side_encryption_configuration.tf_state

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_bucket_public_access_block.tf_state

  lifecycle {
    destroy = false
  }
}
