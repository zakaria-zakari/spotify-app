include "root" {
  path = "../../terragrunt.hcl"
}

locals {
  env_cfg = read_terragrunt_config("../terragrunt.hcl")
}

dependency "networking" {
  config_path = "../networking"
}

terraform {
  source = "../../../terraform/modules/database"
}

inputs = {
  name                  = local.env_cfg.locals.name
  environment           = local.env_cfg.locals.env_name
  vpc_id                = dependency.networking.outputs.vpc_id
  subnet_id             = dependency.networking.outputs.private_subnet_ids[0]
  ami_id                = local.env_cfg.locals.database_ami
  instance_type         = local.env_cfg.locals.database_instance_type
  volume_size           = 50
  volume_type           = "gp3"
  db_username           = local.env_cfg.locals.db_username
  db_password           = local.env_cfg.locals.db_password
  backup_retention_days = local.env_cfg.locals.backup_retention_days
  enable_cloudwatch_agent = true
  key_name              = local.env_cfg.locals.ssh_key_name
  enable_backups        = false
  tags                  = local.env_cfg.locals.tags
}
