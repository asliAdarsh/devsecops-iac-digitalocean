terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.39.0"
    }
  }
}
resource "digitalocean_database_cluster" "mongodb_cluster" {
  name                 = var.cluster_name
  engine               = "mongodb"
  version              = "7.0"
  size                 = var.size_slug
  node_count           = var.node_count
  region               = var.region
  private_network_uuid = var.private_network_uuid

  tags = ["database", var.environment]
}

# Provision the logical application database instance inside that cluster container
resource "digitalocean_database_db" "app_database" {
  cluster_id = digitalocean_database_cluster.mongodb_cluster.id
  name       = var.db_name
}