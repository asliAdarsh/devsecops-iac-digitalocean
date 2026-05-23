terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.39.0"
    }
  }
}
resource "digitalocean_droplet" "vm" {
  count      = var.droplet_count
  name       = var.droplet_count > 1 ? "${var.droplet_name}-node-${count.index + 1}" : var.droplet_name
  region     = var.region
  size       = var.size
  image      = var.vm_image
  monitoring = true
  vpc_uuid   = var.vpc_uuid
  tags       = var.tags
}