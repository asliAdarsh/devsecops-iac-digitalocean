# 1. Fetch the compute node uniform resource names (URNs) from the network tier state
data "terraform_remote_state" "spoke_network" {
  backend = "s3"
  config = {
    endpoint = "sgp1.digitaloceanspaces.com"
    bucket   = var.state_bucket_name
    key      = "spokes/fintrack/network.tfstate"
    region   = "us-east-1"
  }
}

# 2. Fetch the private database uniform resource name (URN) from the data tier state
data "terraform_remote_state" "spoke_data" {
  backend = "s3"
  config = {
    endpoint = "sgp1.digitaloceanspaces.com"
    bucket   = var.state_bucket_name
    key      = "spokes/fintrack/data.tfstate"
    region   = "us-east-1"
  }
}