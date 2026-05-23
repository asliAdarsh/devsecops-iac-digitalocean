variable "cluster_name" {
  type        = string
  description = "The database cluster name identifier."
}

variable "environment" {
  type        = string
  description = "Target deployment environment (dev, prod, etc.)."
}

variable "region" {
  type        = string
  description = "The DigitalOcean datacenter region slug."
}

variable "node_count" {
  type        = number
  description = "Number of database nodes in the cluster (1 for dev, 3 for high-availability prod)."
  default     = 1
}

variable "size_slug" {
  type        = string
  description = "Computing engine size profile for the cluster nodes."
  default     = "db-s-1vcpu-1gb"
}

variable "private_network_uuid" {
  type        = string
  description = "The private VPC network identifier where this database cluster will be isolated."
}

variable "db_name" {
  type        = string
  description = "The initial application database schema name to provision inside the cluster."
}