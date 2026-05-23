# Workload/Spokes/fintrack/network/main.tf
module "fintrack_compute" {
  source        = "../../../../Modules/droplet"
  droplet_count = var.instance_count
  droplet_name  = "${var.app_name}-${var.environment}"
  region        = var.region
  size          = var.droplet_size

  # This works instantly because data.tf is loaded in the same workspace directory!
  vpc_uuid = data.terraform_remote_state.core_network.outputs.hub_vpc_id
  tags     = [var.app_name, var.environment]
}