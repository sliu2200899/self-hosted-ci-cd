# Application (client) ID — from Entra → App registrations → Overview.
# Must NOT be the "Secret ID" from Certificates & secrets (that GUID is unrelated).
variable "client_id" {
    type = string
    default = "66845f66-71e5-49a9-9b9c-635c77a3982a"
}

# Secret VALUE shown once when the secret is created — never paste the Secret ID here.
# Prefer setting via tfvars or env (e.g. ARM_CLIENT_SECRET), not defaults in repo.
variable "client_secret" {
    type      = string
    sensitive = true
}

variable "tenant_id" {
    type = string
    default = "0eaba051-ee2d-426b-a2b4-365c0d876306"
}

variable "subscription_id" {
    type = string
    default = "dab544a2-6a18-4be1-9676-ce2fbce7713a"
}

variable "location" {
    type = string
}
variable "tag" {
    type = string
}
variable "cluster_name" {
    type = string
}

variable "vnet_name" {
    type = string
}

variable "subnet_name" {
    type = string
}

# RFC1918 range that must not overlap cluster node subnet/VNet peers or on‑prem ranges.
variable "aks_service_cidr" {
    type        = string
    default     = "172.24.0.0/16"
    description = "Kubernetes Service ClusterIP range for kubenet; must not overlap VNet subnets."
}

variable "aks_dns_service_ip" {
    type        = string
    default     = "172.24.0.10"
    description = "kube-dns/CoreDNS IP inside aks_service_cidr (not usable as a ClusterIP)."
}

variable "rdev_sku" {
    type = string
}

variable "rdev_additional_sku" {
    type = string
}

variable "additional_nodepool" {
    type = bool
    default = false
}

variable "rdev_min_count" {
    type = number
    default = 1
}

variable "rdev_max_count" {
    type = number
    default = 10
}

variable "rdev_gpu_sku" {
    type = string
}

variable "os_sku" {
    type = string
    default = "Ubuntu"
}

variable "kubernetes_version" {
    type = string
}

variable "rdev_node_version" {
    type = string
}