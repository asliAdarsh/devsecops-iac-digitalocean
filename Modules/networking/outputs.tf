output "vpc_id" {
  value       = digitalocean_vpc.network.id
  description = "The unique network identifier passed to downstream compute grids."
}

output "hub_vpc_urn" {
  value       = digitalocean_vpc.network.urn
  description = "The uniform resource name of the hub VPC, used for project workspace mappings."
}