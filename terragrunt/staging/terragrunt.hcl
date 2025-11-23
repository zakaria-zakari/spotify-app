# Environment-level locals only (no include to avoid nested include depth)

# Environment-level locals consumed by per-module terragrunt configs.
locals {
  env_name                 = "staging"
  name                     = "playlistparser"
  vpc_cidr                 = "10.0.0.0/16"
  public_subnet_cidrs      = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs     = ["10.0.10.0/24", "10.0.11.0/24"]
  availability_zones       = ["us-east-1a", "us-east-1b"]
  frontend_instance_type   = "t3.micro"
  api_instance_type        = "t3.micro"
  database_instance_type   = "t3.small"
  frontend_desired_capacity = 1
  api_desired_capacity      = 1
  backup_retention_days    = 7
  db_username              = "playlistparser"
  db_password              = get_env("STAGING_DB_PASSWORD", "CHANGE_ME")
  spotify_client_id        = get_env("SPOTIFY_CLIENT_ID", "")
  spotify_client_secret    = get_env("SPOTIFY_CLIENT_SECRET", "")
  app_repository           = "https://github.com/pxl-digital/playlist-parser.git"
  # Name of an existing EC2 key pair (not the .pem filename). Override via AWS_KEY_NAME env var.
  ssh_key_name             = get_env("AWS_KEY_NAME", "hockey")
  frontend_port            = 80
  api_port                 = 3000
  alb_listener_port        = 80
  alb_idle_timeout         = 60
  frontend_ami             = get_env("FRONTEND_AMI", "ami-xxxxxxxx")
  api_ami                  = get_env("API_AMI", "ami-xxxxxxxx")
  database_ami             = get_env("DATABASE_AMI", "ami-xxxxxxxx")
  tags = {
    Project     = "playlistparser"
    Environment = "staging"
  }
}

# Child module terragrunt.hcl files under staging/{networking,database,compute} will read this file via read_terragrunt_config.
