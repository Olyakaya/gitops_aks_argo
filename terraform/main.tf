# main.tf

terraform {
  required_version = ">= 0.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }

    grafana = {
      source  = "grafana/grafana"
      version = "~> 2.1.0"
    }    

  }

  backend "azurerm" {
    # Empty configuration - will be filled by pipeline
  }
}


provider "azurerm" {
  features {}
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}


# Create Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.resource_group_name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
}

# Create Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "${var.resource_group_name}-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.subnet_address_prefixes
}

# Create Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                =  var.acr_sku
  admin_enabled       = true
}

resource "random_id" "kvault_suffix" {
  byte_length = 2
}

resource "azurerm_key_vault" "olhabuchynskavault" {
  name                       = "kv-ob-${random_id.kvault_suffix.hex}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = "8d1157bb-1f96-415f-824b-ab0a29485d7d"
  sku_name                   = "premium"
  soft_delete_retention_days = 7

  access_policy {
    tenant_id = "8d1157bb-1f96-415f-824b-ab0a29485d7d"
    object_id = "48876955-a785-4cd2-a659-e4b35a304624"

    key_permissions = [
      "Create",
      "Get",
    ]

    secret_permissions = [
      "Set",
      "Get",
      "Delete",
      "Purge",
      "Recover"
    ]
  }
}



# Create AKS cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix

  default_node_pool {
    name           = "default"
    node_count     = var.default_node_pool_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = azurerm_subnet.subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  # Network profile
  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    network_policy    = "azure"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
  }

  # Dev/Test configuration
  sku_tier = "Free"

  # Enabling monitoring using Azure Monitor (OMS)
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics.id
  }
}

# # # Attach ACR to AKS
# resource "azurerm_role_assignment" "aks_acr" {
#   principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].principal_id
#   role_definition_name            = "AcrPull"
#   scope                           = azurerm_container_registry.acr.id
#   skip_service_principal_aad_check = true
#   }

# Create additional node pool
resource "azurerm_kubernetes_cluster_node_pool" "workloadpool" {
  name                  = "workloadpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.node_vm_size
  node_count            = var.workload_node_pool_count
  
  node_labels = {
    "agentpool" = "workloadpool"
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks,
  ]
}

# Create namespace foa app
resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = var.app_namespace
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}


# Namecpase for ingress-nginx
resource "kubernetes_namespace" "nginx_ingress_namespace" {
  metadata {
    name = var.nginx_ingress_namespace
  }
}

resource "azurerm_public_ip" "nginx_ingress_ip" {
  name                = "nginx-ingress-ip"
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group # Use the node resource group created by AKS
  location            = var.location
  allocation_method   = "Static"
  sku                  = "Standard"  # Required for Ingress controllers
}

resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = var.nginx_ingress_namespace
  create_namespace = false

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

    set {
    name  = "controller.service.loadBalancerIP"
    value = azurerm_public_ip.nginx_ingress_ip.ip_address
  }

    depends_on = [
    azurerm_public_ip.nginx_ingress_ip
    ]

}

# Then modify the ArgoCD helm release
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

#  values = [
#    file("argocd.yaml")
# ]

  depends_on = [azurerm_public_ip.nginx_ingress_ip]
}

# Namecpase for myapp
resource "kubernetes_namespace" "app_namespac" {
  metadata {
    name = var.application_namespace
  }
  
}


resource "azurerm_log_analytics_workspace" "log_analytics" {
  name                = "aks-log-workspace-${formatdate("YYYYMMDD-HHmm", timestamp())}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "aks_monitor" {
  name               = "aks-monitoring-${formatdate("YYYYMMDD-HHmm", timestamp())}"
  target_resource_id = azurerm_kubernetes_cluster.aks.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics.id

  enabled_log {
    category = "kube-apiserver"
 }

  enabled_log {
   category = "kube-controller-manager"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
 }
}

# Create namespace for monitoring
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# Deploy Prometheus using Helm
resource "helm_release" "prometheus" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name


  set {
    name  = "grafana.enabled"
    value = "false"  # We deploy Grafana separately
  }

  set {
    name  = "prometheus.service.type"
    value = "ClusterIP"
  }

}

# Create Azure Public IP for Grafana
resource "azurerm_public_ip" "grafana_ip" {
  name                = "grafana-public-ip"
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group
  location            = var.location
  allocation_method   = "Static"
  sku                = "Standard"
}

# Deploy Grafana using Helm
resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "service.loadBalancerIP"
    value = azurerm_public_ip.grafana_ip.ip_address
  }

  set {
    name  = "persistence.enabled"
    value = "true"
  }

  set {
    name  = "persistence.storageClassName"
    value = "default"
  }

  set {
    name  = "persistence.accessModes[0]"
    value = "ReadWriteOnce"
  }

  set {
    name  = "persistence.size"
    value = "10Gi"
  }

  set {
    name  = "adminPassword"
    value = "SuperSecurePassword123"  # Replace with a secure password
  }

  # Add Prometheus as a data source in Grafana
  set {
    name  = "datasources.datasources.yaml.apiVersion"
    value = "1"
  }

  set {
    name  = "datasources.datasources.yaml.datasources[0].name"
    value = "Prometheus"
  }

  set {
    name  = "datasources.datasources.yaml.datasources[0].type"
    value = "prometheus"
  }

  set {
    name  = "datasources.datasources.yaml.datasources[0].url"
    value = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
  }

  set {
    name  = "datasources.datasources.yaml.datasources[0].access"
    value = "proxy"
  }

  set {
    name  = "datasources.datasources.yaml.datasources[0].isDefault"
    value = "true"
  }

}