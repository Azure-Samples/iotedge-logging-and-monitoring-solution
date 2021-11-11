terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.84.0"
    }
  }

  backend "azurerm" {
  }
}

provider "azurerm" {
  features {}
}

resource "random_id" "elms" {
  byte_length = 2
}

module "iotelms" {
  source                       = "../modules/iotelms"
  rg_name                      = var.rg_name
  location                     = var.location
  name_identifier              = var.name_identifier
  random_id                    = lower(random_id.elms.hex)
  iothub_id                    = var.iothub_id
  iothub_name                  = var.iothub_name
  send_metrics_device_to_cloud = var.send_metrics_device_to_cloud
}
