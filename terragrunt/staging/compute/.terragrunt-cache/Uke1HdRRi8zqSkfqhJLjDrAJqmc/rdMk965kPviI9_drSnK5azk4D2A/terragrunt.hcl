include "root" {
  path = "../../terragrunt.hcl"
}

dependency "networking" { config_path = "../networking" }
dependency "database"   { config_path = "../database" }

locals {
  env_cfg = read_terragrunt_config("../terragrunt.hcl")
}

terraform {
  # Relative path correcting module location under repo root.
  source = "../../../terraform/modules/compute"
}

inputs = {
  name               = local.env_cfg.locals.name
  environment        = local.env_cfg.locals.env_name
  vpc_id             = dependency.networking.outputs.vpc_id
  public_subnet_ids  = dependency.networking.outputs.public_subnet_ids
  private_subnet_ids = dependency.networking.outputs.private_subnet_ids
  alb_idle_timeout   = local.env_cfg.locals.alb_idle_timeout
  frontend_port      = local.env_cfg.locals.frontend_port
  api_port           = local.env_cfg.locals.api_port
  alb_listener_port  = local.env_cfg.locals.alb_listener_port
  tags               = local.env_cfg.locals.tags

  frontend_launch_template = {
    ami_id                  = local.env_cfg.locals.frontend_ami
    instance_type           = local.env_cfg.locals.frontend_instance_type
    desired_capacity        = local.env_cfg.locals.frontend_desired_capacity
    min_size                = local.env_cfg.locals.frontend_desired_capacity
    max_size                = local.env_cfg.locals.frontend_desired_capacity
    key_name                = local.env_cfg.locals.ssh_key_name
    enable_cloudwatch_agent = true
    environment_variables   = {
      APP_SOURCE_URL    = local.env_cfg.locals.app_repository
      VITE_API_BASE_URL = "/api"
    }
  }

  api_launch_template = {
    ami_id                  = local.env_cfg.locals.api_ami
    instance_type           = local.env_cfg.locals.api_instance_type
    desired_capacity        = local.env_cfg.locals.api_desired_capacity
    min_size                = local.env_cfg.locals.api_desired_capacity
    max_size                = local.env_cfg.locals.api_desired_capacity
    key_name                = local.env_cfg.locals.ssh_key_name
    enable_cloudwatch_agent = true
    environment_variables   = {
      APP_SOURCE_URL        = local.env_cfg.locals.app_repository
      NODE_ENV              = "production"
      SPOTIFY_CLIENT_ID     = local.env_cfg.locals.spotify_client_id
      SPOTIFY_CLIENT_SECRET = local.env_cfg.locals.spotify_client_secret
      SPOTIFY_REDIRECT_URI  = get_env("SPOTIFY_REDIRECT_URI", "http://placeholder/api/auth/callback")
      API_BASE_PATH         = "/api"
      SESSION_SECRET        = get_env("SESSION_SECRET", "dev-secret-change-me-please")
      TOKEN_ENC_KEY         = get_env("TOKEN_ENC_KEY", "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff")
      DATABASE_URL          = "postgres://${local.env_cfg.locals.db_username}:${local.env_cfg.locals.db_password}@${dependency.database.outputs.private_ip}:5432/playlistparser"
      PORT                  = tostring(local.env_cfg.locals.api_port)
    }
  }
}
