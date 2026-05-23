# Call the reusable architectural security standard from our central modules folder
module "fintrack_security_barrier" {
  source        = "../../../../Modules/firewall"
  firewall_name = "${var.app_name}-${var.environment}-firewall"

  # Pulls the array of resource IDs directly out of your local compute module/resource
  droplet_ids = module.fintrack_compute.droplet_ids
}