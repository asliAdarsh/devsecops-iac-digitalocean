output "database_urn" {
  value       = data.terraform_remote_state.spoke_data.outputs.database_urn
  description = "The uniform resource name of the database cluster forwarded from the data tier state."
}