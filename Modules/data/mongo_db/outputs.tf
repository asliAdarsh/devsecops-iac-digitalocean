output "database_urn" {
  value       = digitalocean_database_cluster.mongodb_cluster.urn
  description = "The uniform resource name of the MongoDB cluster"
}
output "database_id" {
  value       = digitalocean_database_cluster.mongodb_cluster.id
  description = "The ID of the MongoDB cluster"
}