terraform {
    required_version = ">=1.0"

    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "=3.112.0"
        }
        kubernetes = {
            source = "hashicorp/kubernetes"
            version = "=2.19.0"
        }
        helm = {
            source = "hashicorp/helm"
            version = "=2.9.0"
        }
    }
}

provider "azurerm" {
    features {}
    client_id = var.client_id
    client_secret = var.client_secret
    tenant_id = var.tenant_id
    subscription_id = var.subscription_id

    skip_provider_registration = true
}