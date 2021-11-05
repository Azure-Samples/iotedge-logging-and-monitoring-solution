output "iothub_name" {
  value = azurerm_iothub.elms.name
}

output "iothub_connection_string" {
  value     = azurerm_iothub_shared_access_policy.elms.primary_connection_string
  sensitive = true
}

output "iothub_id" {
  value     = azurerm_iothub.elms.id
  sensitive = true
}
