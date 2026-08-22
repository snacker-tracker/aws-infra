variable "role_name" {
  description = "Name for the IAM role"
  type        = string
}

variable "github_repo" {
  description = "GitHub \"org/repo\" allowed to assume this role via OIDC"
  type        = string
}

variable "ref" {
  description = "Git ref allowed to assume this role, e.g. refs/heads/main"
  type        = string
  default     = "refs/heads/main"
}

# Numeric GitHub org/repo IDs, needed to build the OIDC `sub` condition
# value. See the comment in main.tf for why `sub` is used instead of
# job_workflow_ref (which was found not to work in this AWS account).
# IDs are stable across org/repo renames.
variable "github_org_id" {
  description = "Numeric GitHub organization ID for github_repo's owner"
  type        = string
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID for github_repo"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider"
  type        = string
}

variable "permissions_boundary_arn" {
  description = "ARN of the permissions boundary policy to attach to this role"
  type        = string
}

variable "policy_json" {
  description = "IAM policy document (JSON) granting this role's actual permissions"
  type        = string
}
