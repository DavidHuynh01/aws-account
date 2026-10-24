terraform {
  # S3-native state locking needs 1.10 or later.
  required_version = "~> 1.16"

  # State lives in the bucket defined in state.tf. use_lockfile writes a lock
  # file next to it, so a second run waits instead of corrupting the state.
  backend "s3" {
    bucket       = "davidhuynh01-tfstate"
    key          = "aws-account/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# The account ID is looked up, never written down: this repo is public.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  region       = data.aws_region.current.region
  github_owner = "DavidHuynh01"
}
