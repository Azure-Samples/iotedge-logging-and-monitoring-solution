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
  default = "../../../FunctionApp/FunctionApp/deploy.zip"
}

variable "iothub_id" {
  type = string
}

variable "iothub_name" {
  type = string
}

variable "name_identifier" {
  type = string
}

variable "send_metrics_device_to_cloud" {
  type = bool
}