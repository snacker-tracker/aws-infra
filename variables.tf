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

# Numeric GitHub org ID, for app deploy roles whose repos put it in the
# OIDC `sub` claim (see the OIDC gotchas in README.md). IDs are stable
# across org renames (that's the whole point of GitHub embedding them).
variable "github_org_id" {
  description = "Numeric GitHub organization ID for the snacker-tracker org"
  type        = string
  default     = "59108816"
}
