resource "digitalocean_droplet" "fintrack_nodes" {
  count      = var.instance_count
  name       = "${var.app_name}-${var.environment}-node-${count.index + 1}"
  region     = var.region
  size       = var.droplet_size
  image      = "ubuntu-24-04-lts"
  monitoring = true
  vpc_uuid   = data.terraform_remote_state.core_network.outputs.hub_vpc_id
  tags       = [var.app_name, var.environment]
}