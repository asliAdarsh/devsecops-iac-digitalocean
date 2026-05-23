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