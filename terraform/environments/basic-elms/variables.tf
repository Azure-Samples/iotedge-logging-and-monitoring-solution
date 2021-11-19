variable "location" {
  type = string
}

variable "name_identifier" {
  type    = string
  default = "elms"
}

variable "rg_name" {
  type = string
}

variable "iothub_id" {
  type = string
}

variable "iothub_name" {
  type = string
}

variable "send_metrics_device_to_cloud" {
  type    = bool
  default = false
}