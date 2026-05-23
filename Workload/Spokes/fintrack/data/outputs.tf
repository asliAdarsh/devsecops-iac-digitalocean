output "database_urn" {
  # Change from digitalocean_database_cluster.db.urn to your module path:
  value = module.fintrack_mongodb.database_urn
}