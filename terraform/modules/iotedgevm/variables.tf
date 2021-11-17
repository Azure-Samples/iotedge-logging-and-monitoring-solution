variable "name_identifier" {
  type = string
}

variable "random_id" {
  type = string
}

variable "iot_hub_name" {
  type = string
}

variable "rg_name" {
  type = string
}

variable "location" {
  type = string
}

variable "vm_user_name" {
  type    = string
  default = ""
}

variable "vm_user_password" {
  type    = string
  default = ""
}

variable "iot_edge_connection_string" {
  type = string
}

