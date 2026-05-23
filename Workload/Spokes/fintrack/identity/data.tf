data "terraform_remote_state" "spoke_network" {
  backend = "s3"
  config = {
    endpoint                    = "sgp1.digitaloceanspaces.com"
    bucket                      = var.state_bucket_name
    key                         = "spokes/fintrack/network.tfstate"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
  }
}

data "terraform_remote_state" "spoke_data" {
  backend = "s3"
  config = {
    endpoint                    = "sgp1.digitaloceanspaces.com"
    bucket                      = var.state_bucket_name
    key                         = "spokes/fintrack/data.tfstate"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
  }
}