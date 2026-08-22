variable "region" {
  description = "Default AWS region for this account"
  type        = string
  default     = "ap-southeast-1"
}

variable "account_alias" {
  description = "IAM account alias for this account (must be globally unique across all of AWS)"
  type        = string
  default     = "snacker-tracker"
}

variable "github_repo" {
  description = "GitHub \"org/repo\" allowed to assume the CI admin role via OIDC"
  type        = string
  default     = "snacker-tracker/aws-infra"
}

# Numeric GitHub org/repo IDs, needed to build the OIDC `sub` condition
# value. See the comment in github_oidc.tf for why these are required
# instead of matching on job_workflow_ref. IDs are stable across
# org/repo renames (that's the whole point of GitHub embedding them).
variable "github_org_id" {
  description = "Numeric GitHub organization ID for github_repo's owner"
  type        = string
  default     = "59108816"
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID for github_repo"
  type        = string
  default     = "1342946994"
}
