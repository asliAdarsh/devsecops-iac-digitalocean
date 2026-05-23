variable "project_name" { type = string }
variable "environment" { type = string }
variable "region" { type = string }
variable "vpc_name" { type = string }
variable "cidr_range" { type = string }
variable "state_bucket_name" {
  type        = string
  description = "The name of the DigitalOcean Spaces bucket for state tracking"
}