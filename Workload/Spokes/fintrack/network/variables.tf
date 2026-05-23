variable "region" { type = string }
variable "environment" { type = string }
variable "droplet_size" { type = string }
variable "instance_count" { type = number }
variable "app_name" {
  type        = string
  default     = "fintrack"
  description = "Enterprise unified tagging system key."
}
variable "state_bucket_name" { type = string }