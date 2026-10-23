variable "role_name" {
  description = "Name for the IAM role"
  type        = string
}

variable "github_repo" {
  description = "GitHub \"org/repo\" allowed to assume this role via OIDC"
  type        = string
}

variable "subjects" {
  description = "List of OIDC subject suffixes allowed to assume this role, e.g. [\"ref:refs/heads/main\"] for branch-based auth, or [\"environment:prod\"] for a GitHub Environment-gated job. Multiple entries are OR'd (any one matching is enough)."
  type        = list(string)
  default     = ["ref:refs/heads/main"]
}

# Numeric GitHub org/repo IDs, needed to build the OIDC `sub` condition
# value ONLY for repos where GitHub embeds them (immutable-ID subject
# claims). This turned out to be configured per-repo, not org-wide as
# first assumed: aws-infra's tokens have them, reporter-serverless's
# don't. Leave both null (default) for a plain "repo:org/repo:..." sub;
# set both to enable the "repo:org@ORGID/repo@REPOID:..." form. Always
# verify empirically (see README's OIDC gotchas) rather than assuming
# either format — don't just copy whatever the last app used.
variable "github_org_id" {
  description = "Numeric GitHub organization ID for github_repo's owner, or null for a plain (non-ID-embedded) sub"
  type        = string
  default     = null
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID for github_repo, or null for a plain (non-ID-embedded) sub"
  type        = string
  default     = null
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
  description = "IAM policy document (JSON) granting this role's actual permissions, as an inline policy. Set either this or policies, not both."
  type        = string
  default     = null

  validation {
    condition     = (var.policy_json == null) != (length(var.policies) == 0)
    error_message = "Set exactly one of policy_json or policies."
  }
}

variable "policies" {
  description = "Managed policies to create and attach, as {name suffix: policy JSON}; each is named <role_name>-<suffix>. For permissions too large for one inline policy. Set either this or policy_json, not both."
  type        = map(string)
  default     = {}
}
