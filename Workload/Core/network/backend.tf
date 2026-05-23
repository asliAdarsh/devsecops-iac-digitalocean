terraform {
  backend "s3" {
    # 1. Provide the complete HTTPS scheme to fix the URL warning
    endpoint = "https://sgp1.digitaloceanspaces.com"
    region   = "us-east-1"

    # 2. Hardcode the absolute bypass flags directly in the file
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true # ◄── THIS CRUSHES THE ACCOUNT ID ERROR COMPLETELY
  }
}