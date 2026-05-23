output "spoke_vpc_id" {
  value       = data.terraform_remote_state.core_network.outputs.hub_vpc_id
  description = "Exposing the network ID to the data layer."
}
output "droplet_urns" {
  value       = digitalocean_droplet.fintrack_nodes[*].urn
  description = "Exposing uniform resource names for identity layer project binding."
}