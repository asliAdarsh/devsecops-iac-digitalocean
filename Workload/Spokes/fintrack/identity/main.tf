module "fintrack_workspace" {
  source       = "../../../../Modules/resource_group"
  project_name = "FinTrack-${var.environment}-Workspace"
  environment  = var.environment == "prod" ? "Production" : "Development"
  description  = "Environment tenant isolation container group for the FinTrack application workload."

  # Combines the droplet URN string array and the isolated DB URN string into a single flat array
  resources = concat(
    data.terraform_remote_state.spoke_network.outputs.droplet_urns,
    [data.terraform_remote_state.spoke_data.outputs.database_urn]
  )
}