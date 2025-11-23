terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

resource "random_password" "database" {
  length  = 24
  special = true
}

locals {
  name_prefix       = "playlistparser"
  tags              = merge(var.tags, { "Environment" = var.environment_name })
  database_password = random_password.database.result
}

# Default AMI fallback: latest Ubuntu 22.04 LTS (Jammy) to match apt-based provisioning
data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

locals {
  default_ami            = data.aws_ami.ubuntu_2204.id
  effective_frontend_ami = can(regex("^ami-[0-9a-f]+$", var.frontend_ami)) ? var.frontend_ami : local.default_ami
  effective_api_ami      = can(regex("^ami-[0-9a-f]+$", var.api_ami)) ? var.api_ami : local.default_ami
  effective_database_ami = can(regex("^ami-[0-9a-f]+$", var.database_ami)) ? var.database_ami : local.default_ami
}

module "networking" {
  source = "../../modules/networking"

  name               = local.name_prefix
  environment        = var.environment_name
  cidr_block         = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  tags                 = local.tags
}

module "database" {
  source = "../../modules/database"

  name                   = local.name_prefix
  environment            = var.environment_name
  vpc_id                 = module.networking.vpc_id
  subnet_id              = module.networking.private_subnet_ids[0]
  ami_id                 = local.effective_database_ami
  instance_type          = var.database_instance_type
  volume_size            = var.database_volume_size
  volume_type            = var.database_volume_type
  db_username            = var.db_username
  db_password            = local.database_password
  backup_retention_days  = var.backup_retention_days
  enable_cloudwatch_agent = true
  key_name               = var.ssh_key_name
  tags                   = local.tags
}

locals {
  database_url = "postgres://${var.db_username}:${local.database_password}@${module.database.private_ip}:5432/playlistparser"
  frontend_env = merge(var.frontend_additional_environment_variables, {
    APP_SOURCE_URL    = var.app_repository,
    VITE_API_BASE_URL = "/api"
  })
  api_env = merge(var.api_additional_environment_variables, {
    APP_SOURCE_URL        = var.app_repository,
    NODE_ENV              = "production",
    SPOTIFY_CLIENT_ID     = var.spotify_client_id,
    SPOTIFY_CLIENT_SECRET = var.spotify_client_secret,
    SPOTIFY_REDIRECT_URI  = var.spotify_redirect_uri,
    DATABASE_URL          = local.database_url,
    PORT                  = tostring(var.api_port)
  })
}

module "compute" {
  source = "../../modules/compute"

  name                = local.name_prefix
  environment         = var.environment_name
  vpc_id              = module.networking.vpc_id
  public_subnet_ids   = module.networking.public_subnet_ids
  private_subnet_ids  = module.networking.private_subnet_ids
  alb_idle_timeout    = var.alb_idle_timeout
  frontend_port       = var.frontend_port
  api_port            = var.api_port
  alb_listener_port   = var.alb_listener_port
  tags                 = local.tags

  frontend_launch_template = {
    ami_id                  = local.effective_frontend_ami
    instance_type           = var.frontend_instance_type
    desired_capacity        = var.frontend_desired_capacity
    min_size                = var.frontend_desired_capacity
    max_size                = var.frontend_desired_capacity
    key_name                = var.ssh_key_name
    enable_cloudwatch_agent = true
    environment_variables   = local.frontend_env
  }

  api_launch_template = {
    ami_id                  = local.effective_api_ami
    instance_type           = var.api_instance_type
    desired_capacity        = var.api_desired_capacity
    min_size                = var.api_desired_capacity
    max_size                = var.api_desired_capacity
    key_name                = var.ssh_key_name
    enable_cloudwatch_agent = true
    environment_variables   = local.api_env
  }
}

resource "aws_security_group_rule" "allow_api_to_db" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.database.security_group_id
  source_security_group_id = module.compute.api_security_group_id
}
