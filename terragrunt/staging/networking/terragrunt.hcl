include "root" {
  path = "../../terragrunt.hcl"
}

locals {
  env_cfg = read_terragrunt_config("../terragrunt.hcl")
}

terraform {
  # Relative to this file: ../../../terraform/modules/networking
  # Fixes previous incorrect resolution that skipped the repo root directory.
  source = "../../../terraform/modules/networking"
}

inputs = {
  name                = local.env_cfg.locals.name
  environment         = local.env_cfg.locals.env_name
  cidr_block          = local.env_cfg.locals.vpc_cidr
  public_subnet_cidrs = local.env_cfg.locals.public_subnet_cidrs
  private_subnet_cidrs = local.env_cfg.locals.private_subnet_cidrs
  availability_zones  = local.env_cfg.locals.availability_zones
  tags                = local.env_cfg.locals.tags
}
