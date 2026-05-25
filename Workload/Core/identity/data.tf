data "terraform_remote_state" "core_network" {
  backend = "s3"
  config = {
    endpoint                    = "https://sgp1.digitaloceanspaces.com"
    bucket                      = var.state_bucket_name
    key                         = "core/network.tfstate"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}