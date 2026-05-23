output "droplet_ids" {
  value       = digitalocean_droplet.vm[*].id
  description = "List of generated unique instance IDs (used to attach firewalls)."
}

output "droplet_urns" {
  value       = digitalocean_droplet.vm[*].urn
  description = "List of uniform resource names (used for Project workspace mappings)."
}