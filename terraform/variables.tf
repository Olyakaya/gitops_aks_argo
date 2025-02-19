# Resource Group Variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "OlhaBuchynska"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "westeurope"
}

# Network Variables
variable "vnet_address_space" {
  description = "Address space for Virtual Network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for Subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

# AKS Cluster Variables
variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "gitops-k8s"
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string
  default     = "gitops-k8s"
}

variable "node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "default_node_pool_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 1
}

variable "workload_node_pool_count" {
  description = "Number of nodes in the workload node pool"
  type        = number
  default     = 1
}

# Network Profile Variables
variable "service_cidr" {
  description = "CIDR for Kubernetes services"
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for DNS services in the cluster"
  type        = string
  default     = "172.16.0.10"
}

# ACR Variables
variable "acr_name" {
  description = "Name of the Azure Container Registry"
  type        = string
  default     = "olhabuchynskacr"
}

variable "acr_sku" {
  description = "SKU for acr"
  type        = string
  default     = "Basic"
}

# Namespace for argocd
variable "app_namespace" {
  description = "Namespace for the application"
  type        = string
  default     = "argocd"
}

# Namespace of nginx-ingress
variable "nginx_ingress_namespace" {
  description = "Namespace fo nginx-imgress"
  type        = string
  default     = "ingress-nginx"
}

# Namespace for myapp
variable "application_namespace" {
  description = "Namespace for the application"
  type        = string
  default     = "myapp"
}

