terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.39.0"
    }
  }
}

resource "digitalocean_vpc" "network" {
  name     = var.vpc_name
  region   = var.region
  ip_range = var.cidr_range
}