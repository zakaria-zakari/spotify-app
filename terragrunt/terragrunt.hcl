locals {
  aws_region = "us-east-1"
  project    = "playlistparser"
  bucket     = "zakaria-spotify-bucket"
  table      = "terraform-state-locks"
  tags = {
    Project = "playlistparser"
  }
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    bucket         = local.bucket
    key            = "hack-tuah/${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    encrypt        = true
    dynamodb_table = local.table
  }
}

# Generate a provider so modules/environments don't hardcode region
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
provider "aws" {
  region = "${local.aws_region}"
}
EOF
}
