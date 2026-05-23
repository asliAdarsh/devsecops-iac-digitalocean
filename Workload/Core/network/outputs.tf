output "hub_vpc_id" {
  value       = module.hub_vpc.vpc_id
  description = "Crucial output data bridge exposed to all application spokes."
}