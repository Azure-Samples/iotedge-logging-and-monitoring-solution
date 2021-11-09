variable "rg_name" {
  type = string
}

variable "location" {
  type = string
}

variable "random_id" {
  type = string
}

variable "functionapp" {
  type    = string
  default = "../../FunctionApp/FunctionApp/deploy.zip"
}

variable "iothub_id" {
  type = string
}

variable "iothub_name" {
  type = string
}

variable "edge_device_name" {
  type    = string
  default = ""
}

variable "name_identifier" {
  type = string
}

variable "script_path" {
  type    = string
  default = "../../../scripts"
}

variable "create_edge_device_id" {
  type    = string
  default = ""
}

variable "send_metrics_device_to_cloud" {
  type    = bool
}