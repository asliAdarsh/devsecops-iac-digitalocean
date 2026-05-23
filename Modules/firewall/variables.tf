variable "firewall_name" {
  type        = string
  description = "The naming descriptor for this security barrier."
}

variable "droplet_ids" {
  type        = list(number)
  description = "The target droplet cluster IDs to lock behind this firewall."
}