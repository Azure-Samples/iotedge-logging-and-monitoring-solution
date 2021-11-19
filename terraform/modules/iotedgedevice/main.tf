# Azure CLI scripts were used as a workaround until the support for IoT Hub device creation 
# https://github.com/hashicorp/terraform-provider-azurerm/issues/12604 is implemented

resource "null_resource" "create_edge_device" {
  provisioner "local-exec" {
    when        = create
    command     = "${var.script_path}/create-edge-device.sh ${var.edge_device_name} ${var.iothub_name} ${var.script_path}"
    interpreter = ["/bin/bash", "-c"]
  }
}

data "external" "edge_device_connection_string" {
  depends_on = [null_resource.create_edge_device]
  program    = ["/bin/bash", "${var.script_path}/get-edge-device-connection-string.sh"]
  query = {
    edge_device_name = var.edge_device_name
    iothub_name      = var.iothub_name
    script_path      = var.script_path
  }
}

resource "null_resource" "create_edge_device_twin_tag" {
  count = var.edge_device_name != "" ? 1 : 0
  provisioner "local-exec" {
    when        = create
    command     = "${var.script_path}/create-edge-device-twin-tag.sh ${var.edge_device_name} ${var.iothub_name} ${var.script_path}"
    interpreter = ["/bin/bash", "-c"]
  }
  # Edge device needs to exist before creating edge device twin tag.
  # So create-edge-device script needs to be completed before this resource can be created.
  depends_on = [null_resource.create_edge_device]
}