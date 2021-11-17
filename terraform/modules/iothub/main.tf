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
