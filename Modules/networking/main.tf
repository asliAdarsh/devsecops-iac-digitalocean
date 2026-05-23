resource "digitalocean_vpc" "network" {
  name     = var.vpc_name
  region   = var.region
  ip_range = var.cidr_range
}