variable "region" {
  type        = string
  description = "Target DigitalOcean datacenter region slug."
}

variable "environment" {
  type        = string
  description = "Infrastructure environment classification tier."
}

variable "project_name" {
  type        = string
  description = "The root name descriptor for the core platform layout."
}

variable "state_bucket_name" {
  type        = string
  description = "The name of the DigitalOcean Spaces bucket holding Terraform state files."
}