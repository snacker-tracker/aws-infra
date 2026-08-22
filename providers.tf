provider "aws" {
  region = var.region

  # No explicit `profile` or `assume_role` here on purpose: auth is resolved
  # via the standard AWS SDK credential chain, i.e. whatever AWS_PROFILE (or
  # AWS_ACCESS_KEY_ID/etc.) is set in the shell you run terraform from. See
  # README.md for how that profile should be configured to reach this
  # account through OrganizationAccountAccessRole.

  default_tags {
    tags = {
      ManagedBy = "terraform"
    }
  }
}
