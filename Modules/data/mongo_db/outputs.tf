output "database_urn" {
  # Points to module.MODULE_BLOCK_NAME.CHILD_OUTPUT_NAME
  value       = module.fintrack_mongodb.database_urn
  description = "The uniform resource name of the database cluster forwarded from the mongo_db module"
}
output "database_id" {
  value       = digitalocean_database_cluster.mongodb_cluster.id
  description = "The ID of the MongoDB cluster"
}