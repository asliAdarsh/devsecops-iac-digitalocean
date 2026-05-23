variable "project_name" {
  type        = string
  description = "The name of the logical enterprise workspace group."
}

variable "description" {
  type    = string
  default = "Managed environment infrastructure mapping to assignment scope."
}

variable "environment" {
  type        = string
  description = "Target deployment boundary: Development, Staging, or Production."
}