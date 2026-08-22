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

variable "workflow_path" {
  description = "Path to the workflow file (relative to repo root) allowed to assume this role, e.g. .github/workflows/deploy.yml"
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
