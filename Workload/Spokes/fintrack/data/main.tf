resource "digitalocean_database_cluster" "db" {
  name                 = "fintrack-${var.environment}-mongodb"
  engine               = "mongodb"
  version              = "7.0"
  size                 = "db-s-1vcpu-1gb"
  node_count           = 1
  region               = var.region
  private_network_uuid = data.terraform_remote_state.spoke_network.outputs.spoke_vpc_id
}

resource "digitalocean_database_db" "fintrack_db" {
  cluster_id = digitalocean_database_cluster.db.id
  name       = "fintrack_production_store"
}