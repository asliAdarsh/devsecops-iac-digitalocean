variable "project_name" { type = string }
variable "environment" { type = string }

variable "description" {
  type    = string
  default = "Managed workload workspace container."
}

variable "resources" {
  type        = list(string)
  description = "Optional list of resource URNs to attach to this project container."
  default     = []
}