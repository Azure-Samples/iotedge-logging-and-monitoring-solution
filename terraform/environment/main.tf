terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.75.0"
    }
  }

  backend "azurerm" {
  }
}

provider "azurerm" {
  features {}
  #skip_provider_registration = true
}

resource "random_id" "elms" {
  byte_length = 2
}

resource "azurerm_resource_group" "elms" {
  name     = "rg-elms"
  location = var.location
}

module "iothub" {
  source                    = "../../modules/iothub"
  rg_name                   = azurerm_resource_group.elms.name
  location                  = var.location
  random_id                 = lower(random_id.elms.hex)
  name_identifier           = var.name_identifier
  #keyvault_id               = module.keyvault_deployment.keyvault_id
  #keyvault_access_policy_id = module.keyvault_deployment.keyvault_access_policy_id
  tier                      = "S1"
  units                     = "1"
}

module "iotelms" {
  source                    = "../../modules/iotelms"
  rg_name                   = azurerm_resource_group.elms.name
  location                  = var.location
  name_identifier           = var.name_identifier
  random_id                 = lower(random_id.elms.hex)
  iothub_id                 = module.iothub.iothub_id
  iothub_name               = module.iothub.iothub_name
  iothub_connection_string  = module.iothub.iothub_connection_string
  edge_device_name          = var.edge_device_name
  create_edge_device_id     = module.iotedgedevice.create_edge_device_id
  keyvault_id               = module.keyvault.keyvault_id
  keyvault_access_policy_id = module.keyvault.keyvault_access_policy_id
}