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
