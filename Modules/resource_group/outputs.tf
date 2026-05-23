output "project_id" {
  value       = digitalocean_project.rg.id
  description = "The unique UUID of the project workspace container."
}