output "edge_device_connection_string" {
  value     = data.external.edge_device_connection_string.result["connectionString"]
  sensitive = true
}