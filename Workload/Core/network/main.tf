module "hub_rg" {
  source       = "../../../Modules/resource_group"
  project_name = var.project_name
  environment  = var.environment
}

module "hub_vpc" {
  source     = "../../../Modules/networking"
  vpc_name   = var.vpc_name
  region     = var.region
  cidr_range = var.cidr_range
}