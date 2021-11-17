resource "random_string" "vm_user_name" {
  length  = 10
  special = false
}

resource "random_password" "vm_user_password" {
  length           = 10
  min_upper        = 1
  min_lower        = 1
  min_special      = 1
  min_numeric      = 1
  override_special = "!@#$%&"
}

locals {
  dns_label_prefix = "${var.name_identifier}-iot-edge"
  vm_username      = var.vm_user_name != "" ? var.vm_user_name : random_string.vm_user_name.result
  vm_user_password = var.vm_user_password != "" ? var.vm_user_password : random_password.vm_user_password.result
}

resource "azurerm_public_ip" "iot_edge" {
  name                = "${local.dns_label_prefix}-ip"
  resource_group_name = var.rg_name
  location            = var.location
  allocation_method   = "Dynamic"
  domain_name_label   = "${local.dns_label_prefix}-${var.random_id}"
}

resource "azurerm_virtual_network" "iot_edge" {
  name                = "${local.dns_label_prefix}-vnet"
  location            = var.location
  resource_group_name = var.rg_name
  address_space       = ["10.0.0.0/16"]

  subnet {
    name           = "${local.dns_label_prefix}-subnet"
    address_prefix = "10.0.1.0/24"
  }
}

resource "azurerm_network_interface" "iot_edge" {
  name                = "${local.dns_label_prefix}-nic"
  location            = var.location
  resource_group_name = var.rg_name

  ip_configuration {
    name                          = "${local.dns_label_prefix}-ipconfig"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.iot_edge.id
    subnet_id                     = azurerm_virtual_network.iot_edge.subnet.*.id[0]
  }
}

resource "azurerm_linux_virtual_machine" "iot_edge" {
  name                            = "${local.dns_label_prefix}-vm"
  location                        = var.location
  resource_group_name             = var.rg_name
  admin_username                  = local.vm_username
  disable_password_authentication = false
  admin_password                  = local.vm_user_password
  provision_vm_agent              = false
  allow_extension_operations      = false
  size                            = "Standard_DS1_v2"
  network_interface_ids = [
    azurerm_network_interface.iot_edge.id
  ]
  custom_data = base64encode(replace(file("${path.module}/cloud-init.yaml"), "<REPLACE_WITH_CONNECTION_STRING>", var.iot_edge_connection_string))

  source_image_reference {
    offer     = "UbuntuServer"
    publisher = "Canonical"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
}
