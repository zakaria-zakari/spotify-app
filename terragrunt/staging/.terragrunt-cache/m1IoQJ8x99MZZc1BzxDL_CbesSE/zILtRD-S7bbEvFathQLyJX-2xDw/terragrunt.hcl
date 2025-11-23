include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../terraform/environments/staging"
}

inputs = {
  environment_name = "staging"
  aws_region       = "us-east-1"
  app_repository   = "https://github.com/pxl-digital/playlist-parser.git"

  # Supply secrets via environment variables to avoid committing them
  spotify_client_id     = get_env("SPOTIFY_CLIENT_ID", "")
  spotify_client_secret = get_env("SPOTIFY_CLIENT_SECRET", "")
  spotify_redirect_uri  = get_env("SPOTIFY_REDIRECT_URI", "http://placeholder/api/auth/callback")

  frontend_ami = "ami-xxxxxxxx"
  api_ami      = "ami-xxxxxxxx"
  database_ami = "ami-xxxxxxxx"

  frontend_instance_type = "t3.micro"
  api_instance_type      = "t3.micro"
  database_instance_type = "t3.small"

  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  availability_zones   = ["us-east-1a", "us-east-1b"]

  ssh_key_name = "hockey.pem"

  tags = {
    Project = "playlistparser"
  }
}
