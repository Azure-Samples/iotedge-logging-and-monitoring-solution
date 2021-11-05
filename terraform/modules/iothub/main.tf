resource "azurerm_iothub" "elms" {
  name                          = "iot-${var.name_identifier}-${var.random_id}"
  resource_group_name           = var.rg_name
  location                      = var.location
  public_network_access_enabled = true

  sku {
    name     = var.tier
    capacity = var.units
  }

  fallback_route {
    source         = "DeviceMessages"
    endpoint_names = ["events"]
    enabled        = true
  }
}

resource "azurerm_iothub_shared_access_policy" "elms" {
  name                = "iotedgelogs"
  resource_group_name = var.rg_name
  iothub_name         = azurerm_iothub.elms.name

  registry_read   = true
  registry_write  = false
  service_connect = true
  device_connect  = false
}
