resource "digitalocean_project" "fintrack_project" {
  name        = "FinTrack-${var.environment}-Workspace"
  description = "Environment workload container group for FinTrack."
  purpose     = "Web Application"
  environment = var.environment == "prod" ? "Production" : "Development"
}

resource "digitalocean_project_resources" "bindings" {
  project = digitalocean_project.fintrack_project.id
  resources = concat(
    data.terraform_remote_state.spoke_network.outputs.droplet_urns,
    [data.terraform_remote_state.spoke_data.outputs.database_urn]
  )
}