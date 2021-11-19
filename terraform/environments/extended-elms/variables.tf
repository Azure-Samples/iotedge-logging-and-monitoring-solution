variable "location" {
  type = string
}

variable "name_identifier" {
  type    = string
  default = "elms"
}

variable "tier" {
  type    = string
  default = "S1"
}

variable "units" {
  type    = string
  default = "1"
}

variable "send_metrics_device_to_cloud" {
  type    = bool
  default = false
}