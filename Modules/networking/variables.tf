variable "vpc_name" {
  type = string
}
variable "region" {
  type = string
}
variable "cidr_range" {
  type        = string
  description = "The internal network private IP allocation block (CIDR)."
}