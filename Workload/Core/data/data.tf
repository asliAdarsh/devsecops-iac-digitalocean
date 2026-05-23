# This layer reads the Core Network outputs if a shared database needs to bind to the Hub VPC.
data "terraform_remote_state" "core_network" {
  backend = "s3"
  config = {
    endpoint                    = "sgp1.digitaloceanspaces.com"
    bucket                      = "fintrack-tfstate-bucket" # Fallback/Override default managed via pipeline
    key                         = "core/network/global.tfstate"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
