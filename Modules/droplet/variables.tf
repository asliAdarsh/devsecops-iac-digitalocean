variable "droplet_count" {
  type        = number
  description = "Number of droplets to provision."
  default     = 1
}

variable "droplet_name" {
  type        = string
  description = "Base naming prefix for the compute instances."
}

variable "region" {
  type        = string
  description = "Target datacenter region slug."
}

variable "size" {
  type        = string
  description = "The computing size slug profile."
}

variable "vpc_uuid" {
  type        = string
  description = "The specific private VPC network UUID to bind this droplet into."
}

variable "tags" {
  type        = list(string)
  description = "Metadata grouping tags applied to the instances."
  default     = []
}