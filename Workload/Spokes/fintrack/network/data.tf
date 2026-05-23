data "terraform_remote_state" "core_network" {
  backend = "s3"
  config = {
    # 1. Fixed: Added https:// prefix to prevent API transport handshake errors
    endpoint                    = "https://sgp1.digitaloceanspaces.com"
    bucket                      = var.state_bucket_name
    
    # 2. Fixed: Matched exactly to the 'state_key' parameter in your workflow yaml file
    key                         = "core/network.tfstate" 
    
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}