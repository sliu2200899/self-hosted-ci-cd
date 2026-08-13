# Azure Resource Group (shared resource across environments, provisioned in Azure portal)
data "azurerm_resource_group" "wus3-rdev-rg" {
  name = "wus3-rdev-rg"
}

# Network Resource Group (provisioned by az command)
data "azurerm_resource_group" "network" {
  name = "network"
}

# Subnet (provisioned by az command)
data "azurerm_subnet" "snet" {
  resource_group_name  = data.azurerm_resource_group.network.name
  virtual_network_name = var.vnet_name
  name                 = var.subnet_name
}

# Managed Identity
data "azurerm_user_assigned_identity" "aks_identity" {
  resource_group_name = data.azurerm_resource_group.wus3-rdev-rg.name
  name = "rdev-identity"
}

# Public IP
# it's used for the outbound traffic from the AKS cluster
# AKS handles the provisioning of inbound load balancer + public IP when Kubernetes asks for it 
# (via Service/ingress)
resource "azurerm_public_ip" "aks_ip" {
  name                = "${var.cluster_name}-public-ip"
  resource_group_name = data.azurerm_resource_group.wus3-rdev-rg.name
  location            = data.azurerm_resource_group.wus3-rdev-rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                    = "${var.cluster_name}"
  location                = data.azurerm_resource_group.wus3-rdev-rg.location
  resource_group_name     = data.azurerm_resource_group.wus3-rdev-rg.name
  dns_prefix              = "${var.cluster_name}"
  sku_tier                = "Standard"
  node_resource_group     = "${var.cluster_name}-rg"

  kubernetes_version      = var.kubernetes_version

  private_cluster_enabled             = false

  azure_policy_enabled                = true

  node_os_channel_upgrade             = "None"
  oidc_issuer_enabled = true

  default_node_pool {
    name                         = "default"
    min_count                    = 1
    max_count                    = 6
    enable_auto_scaling          = true
    vm_size                      = "Standard_D2s_v3"
    vnet_subnet_id               = data.azurerm_subnet.snet.id
    only_critical_addons_enabled = true
    os_sku                       = var.os_sku
    orchestrator_version         = var.kubernetes_version
    temporary_name_for_rotation  = "defaulttemp"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.aks_identity.id]
  }

  network_profile {
    load_balancer_sku = "standard"
    network_plugin    = "kubenet"

    # Must NOT overlap node subnet or other VNET address space (default 10.0.0.0/16
    # conflicts with e.g. 10.0.1.0/24 — see aka.ms/aks/servicecidroverlap).
    service_cidr    = var.aks_service_cidr
    dns_service_ip  = var.aks_dns_service_ip

    load_balancer_profile {
      outbound_ip_address_ids = [azurerm_public_ip.aks_ip.id]
    }
  }

  role_based_access_control_enabled = true

  tags = {
    environment = var.tag
  }

  # enable the oms agent (container insights) for this aks cluster
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks_insights_workspace.id
    msi_auth_for_monitoring_enabled = true
  }
}

# rdev operator node pool
resource "azurerm_kubernetes_cluster_node_pool" "operator" {
  name                  = "operator"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_D2s_v3"
  min_count             = 1
  max_count             = 6
  enable_auto_scaling   = true
  node_labels           = {"node.linkedin.com/pool" = "operator"}
  node_taints           = ["node-pool=operators-only:NoSchedule"]
  vnet_subnet_id        = data.azurerm_subnet.snet.id
  os_sku                = var.os_sku
  orchestrator_version  = var.kubernetes_version
}

# General rdev node pool
resource "azurerm_kubernetes_cluster_node_pool" "rdev" {
  name                  = "rdev"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.rdev_sku
  min_count             = var.rdev_min_count
  max_count             = var.rdev_max_count
  enable_auto_scaling   = true
  node_labels           = {"node.linkedin.com/pool" = "rdev"}
  vnet_subnet_id        = data.azurerm_subnet.snet.id
  os_sku                = var.os_sku
  orchestrator_version  = var.rdev_node_version
}

# Create Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "aks_insights_workspace" {
  name                = "${var.cluster_name}-logs"
  location            = data.azurerm_resource_group.wus3-rdev-rg.location
  resource_group_name = data.azurerm_resource_group.wus3-rdev-rg.name
  retention_in_days   = 30

  tags = {
    environment = var.tag
  }
}

# Enable container insights
resource "azurerm_log_analytics_solution" "aks_insights_solution" {
  solution_name         = "ContainerInsights"
  location              = data.azurerm_resource_group.wus3-rdev-rg.location
  resource_group_name   = data.azurerm_resource_group.wus3-rdev-rg.name
  workspace_resource_id = azurerm_log_analytics_workspace.aks_insights_workspace.id
  workspace_name        = azurerm_log_analytics_workspace.aks_insights_workspace.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }

  tags = {
    environment = var.tag
  }
}