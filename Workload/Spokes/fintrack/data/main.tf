# Call our central reusable MongoDB template
module "fintrack_mongodb" {
  source       = "../../../../Modules/data/mongo_db"
  cluster_name = "fintrack-${var.environment}-mongodb"
  environment  = var.environment
  region       = var.region
  size_slug    = "db-s-1vcpu-1gb"
  node_count   = 1
  db_name      = "fintrack_production_store"

  # Fetches the network ID dynamically from your network tier remote state bridge file!
  private_network_uuid = data.terraform_remote_state.spoke_network.outputs.spoke_vpc_id
}