module "core_global_workspace" {
  source       = "../../../Modules/resource_group"
  project_name = var.project_name
  environment  = var.environment == "prod" ? "Production" : "Development"
  description  = "The global governance master project container housing shared core landing zone architectures."

  # Bind the core network resources (like the hub corporate VPC) straight into this project dashboard canvas
  resources = [
    data.terraform_remote_state.core_network.outputs.hub_vpc_urn
  ]
}