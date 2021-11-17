output "iothub_name" {
  value = azurerm_iothub.elms.name
}

output "iothub_id" {
  value     = azurerm_iothub.elms.id
  sensitive = true
}
