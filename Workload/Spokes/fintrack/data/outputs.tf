output "database_urn" {
  # ──► Grabs the output exposed by the module blueprint instead of a raw resource
  value       = module.fintrack_mongodb.database_urn
  description = "Forwarding the Uniform Resource Name downstream to the identity bucket."
}