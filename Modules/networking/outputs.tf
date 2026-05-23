output "vpc_id" {
  value       = digitalocean_vpc.network.id
  description = "The unique network identifier passed to downstream compute grids."
}