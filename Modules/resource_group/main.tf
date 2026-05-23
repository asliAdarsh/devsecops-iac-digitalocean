terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.39.0"
    }
  }
}
resource "digitalocean_project" "rg" {
  name        = var.project_name
  description = var.description
  environment = var.environment
  purpose     = "Web Application"
}

# This resource dynamically assigns resources to the project if a list is passed in
resource "digitalocean_project_resources" "bindings" {
  count     = length(var.resources) > 0 ? 1 : 0
  project   = digitalocean_project.rg.id
  resources = var.resources
}