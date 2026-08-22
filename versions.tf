terraform {
  required_version = ">= 1.10.0" # needed for backend use_lockfile (S3-native locking, no DynamoDB)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket       = "snacker-tracker-aws-infra-tfstate"
    key          = "root/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
