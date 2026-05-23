output "database_cluster_id" {
  value       = digitalocean_database_cluster.mongodb_cluster.id
  description = "The unique cluster resource ID locator."
}

output "database_urn" {
  value       = digitalocean_database_cluster.mongodb_cluster.urn
  description = "The uniform resource name required for Identity layer project workspace binding."
}