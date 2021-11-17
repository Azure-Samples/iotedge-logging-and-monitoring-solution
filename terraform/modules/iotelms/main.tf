resource "azurerm_storage_account" "elmslogs" {
  name                     = "stlogs${replace(var.name_identifier, "-", "")}${var.random_id}"
  resource_group_name      = var.rg_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_account" "elmsfunc" {
  name                     = "stfunc${replace(var.name_identifier, "-", "")}${var.random_id}"
  resource_group_name      = var.rg_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_queue" "elms" {
  name                 = "elmstoragequeue"
  storage_account_name = azurerm_storage_account.elmslogs.name
}

resource "azurerm_storage_container" "elmslogs" {
  name                  = "elmstoragecontainer"
  storage_account_name  = azurerm_storage_account.elmslogs.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "elmsfunc" {
  name                  = "funcstoragecontainer"
  storage_account_name  = azurerm_storage_account.elmsfunc.name
  container_access_type = "private"
}

resource "azurerm_eventgrid_system_topic" "elms" {
  name                   = "evgt-${var.name_identifier}-${var.random_id}"
  resource_group_name    = var.rg_name
  location               = var.location
  source_arm_resource_id = azurerm_storage_account.elmslogs.id
  topic_type             = "Microsoft.Storage.StorageAccounts"
}

resource "azurerm_eventgrid_system_topic_event_subscription" "elms" {
  name                = "evgs-${var.name_identifier}-${var.random_id}"
  system_topic        = azurerm_eventgrid_system_topic.elms.name
  resource_group_name = var.rg_name

  storage_queue_endpoint {
    storage_account_id = azurerm_storage_account.elmslogs.id
    queue_name         = azurerm_storage_queue.elms.name
  }

  included_event_types = ["Microsoft.Storage.BlobCreated"]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/${azurerm_storage_container.elmslogs.name}/"
  }
}

resource "azurerm_app_service_plan" "elms" {
  name                = "plan-${var.name_identifier}-${var.random_id}"
  resource_group_name = var.rg_name
  location            = var.location
  kind                = "functionapp"

  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_function_app" "elms" {
  name                       = "func-${var.name_identifier}-${var.random_id}"
  location                   = var.location
  resource_group_name        = var.rg_name
  app_service_plan_id        = azurerm_app_service_plan.elms.id
  storage_account_name       = azurerm_storage_account.elmsfunc.name
  storage_account_access_key = azurerm_storage_account.elmsfunc.primary_access_key
  version                    = "~3"

  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.elms.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.elms.connection_string
    "AzureWebJobs.CollectMetrics.Disabled"  = var.send_metrics_device_to_cloud == true ? false : true
    "AzureWebJobs.MonitorAlerts.Disabled"   = true
    "ContainerName"                         = azurerm_storage_container.elmslogs.name
    "CompressForUpload"                     = true
    "DeviceQuery"                           = "SELECT * FROM devices WHERE tags.logPullEnabled='true'"
    "EventHubConnectionString"              = var.send_metrics_device_to_cloud == true ? azurerm_eventhub_namespace_authorization_rule.elms[0].primary_connection_string : ""
    "EventHubConsumerGroup"                 = var.send_metrics_device_to_cloud == true ? azurerm_eventhub_consumer_group.elms[0].name : ""
    "EventHubName"                          = var.send_metrics_device_to_cloud == true ? azurerm_eventhub.elms[0].name : ""
    "FUNCTIONS_WORKER_RUNTIME"              = "dotnet"
    "HASH"                                  = base64encode(filesha256(var.functionapp))
    "HttpTriggerFunction"                   = "InvokeUploadModuleLogs"
    "HostUrl"                               = "https://func-${var.name_identifier}-${var.random_id}.azurewebsites.net"
    "HubConnectionString"                   = azurerm_iothub_shared_access_policy.elms.primary_connection_string
    "HubResourceId"                         = var.iothub_id
    "LogsContentType"                       = "json"
    "LogsEncoding"                          = "gzip"
    "LogsMaxSizeMB"                         = "28"
    "LogsIdRegex"                           = ".*"
    "LogsRegex"                             = ".*"
    "LogsSince"                             = "15m"
    "LogType"                               = "iotedgemodulelogs"
    "MetricsEncoding"                       = "gzip"
    "QueueName"                             = azurerm_storage_queue.elms.name
    "StorageConnectionString"               = azurerm_storage_account.elmslogs.primary_connection_string
    "WorkspaceApiVersion"                   = "2016-04-01"
    "WorkspaceDomainSuffix"                 = "azure.com"
    "WorkspaceId"                           = azurerm_log_analytics_workspace.elms.workspace_id
    "WorkspaceKey"                          = azurerm_log_analytics_workspace.elms.primary_shared_key
    "WEBSITE_RUN_FROM_PACKAGE"              = "https://${azurerm_storage_account.elmsfunc.name}.blob.core.windows.net/${azurerm_storage_container.elmsfunc.name}/${azurerm_storage_blob.elms.name}${data.azurerm_storage_account_blob_container_sas.elms.sas}"
    "WEBSITE_LOAD_USER_PROFILE"             = 1 // this is required for proper certificate loading in the CollectMetrics function
  }

  site_config {
    cors {
      allowed_origins = ["*"]
    }
  }
}

data "azurerm_function_app_host_keys" "elms" {
  name                = azurerm_function_app.elms.name
  resource_group_name = var.rg_name

  depends_on = [azurerm_function_app.elms]
}

resource "null_resource" "check_key" {
  triggers = {
    key = data.azurerm_function_app_host_keys.elms.default_function_key
  }

  provisioner "local-exec" {
    command     = "az functionapp config appsettings set --name ${azurerm_function_app.elms.name} --resource-group ${var.rg_name} --settings \"HostKey=${data.azurerm_function_app_host_keys.elms.default_function_key}\" --output none"
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "azurerm_storage_blob" "elms" {
  name                   = "deploy.zip"
  storage_account_name   = azurerm_storage_account.elmsfunc.name
  storage_container_name = azurerm_storage_container.elmsfunc.name
  type                   = "Block"
  content_md5            = filemd5(var.functionapp)
  source                 = var.functionapp
}

data "azurerm_storage_account_blob_container_sas" "elms" {
  connection_string = azurerm_storage_account.elmsfunc.primary_connection_string
  container_name    = azurerm_storage_container.elmsfunc.name

  start  = "2021-07-01T00:00:00Z"
  expiry = "2122-01-01T00:00:00Z"

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = false
  }
}

resource "azurerm_application_insights" "elms" {
  name                = "appi-${var.name_identifier}-${var.random_id}"
  resource_group_name = var.rg_name
  location            = var.location
  application_type    = "web"
}

resource "azurerm_log_analytics_workspace" "elms" {
  name                = "log-${var.name_identifier}-${var.random_id}"
  resource_group_name = var.rg_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_eventhub_namespace" "elms" {
  count               = var.send_metrics_device_to_cloud == true ? 1 : 0
  name                = "evhns-${var.name_identifier}-${var.random_id}"
  resource_group_name = var.rg_name
  location            = var.location
  sku                 = "Standard"
  capacity            = 1
}

resource "azurerm_eventhub" "elms" {
  count               = var.send_metrics_device_to_cloud == true ? 1 : 0
  name                = "evh-${var.name_identifier}"
  resource_group_name = var.rg_name
  namespace_name      = azurerm_eventhub_namespace.elms[0].name
  partition_count     = 4
  message_retention   = 1
}

resource "azurerm_eventhub_consumer_group" "elms" {
  count               = var.send_metrics_device_to_cloud == true ? 1 : 0
  name                = "metricsCollectorConsumerGroup"
  resource_group_name = var.rg_name
  namespace_name      = azurerm_eventhub_namespace.elms[0].name
  eventhub_name       = azurerm_eventhub.elms[0].name
}

resource "azurerm_eventhub_namespace_authorization_rule" "elms" {
  count               = var.send_metrics_device_to_cloud == true ? 1 : 0
  name                = "listen-rule"
  resource_group_name = var.rg_name
  namespace_name      = azurerm_eventhub_namespace.elms[0].name
  listen              = true
}

resource "azurerm_eventhub_authorization_rule" "elms" {
  count               = var.send_metrics_device_to_cloud == true ? 1 : 0
  name                = "send-rule"
  resource_group_name = var.rg_name
  namespace_name      = azurerm_eventhub_namespace.elms[0].name
  eventhub_name       = azurerm_eventhub.elms[0].name
  send                = true
}

resource "azurerm_iothub_endpoint_eventhub" "elms" {
  count               = var.send_metrics_device_to_cloud == true ? 1 : 0
  resource_group_name = var.rg_name
  iothub_name         = var.iothub_name
  name                = "metricscollector-${var.name_identifier}"

  connection_string = azurerm_eventhub_authorization_rule.elms[0].primary_connection_string
}

resource "azurerm_iothub_route" "elms" {
  count               = var.send_metrics_device_to_cloud == true ? 1 : 0
  resource_group_name = var.rg_name
  iothub_name         = var.iothub_name
  name                = "metricscollector-${var.name_identifier}"

  source         = "DeviceMessages"
  condition      = "id = 'origin-iotedge-metrics-collector'"
  endpoint_names = [azurerm_iothub_endpoint_eventhub.elms[0].name]
  enabled        = true
}

resource "azurerm_iothub_shared_access_policy" "elms" {
  name                = "iotedgelogs"
  resource_group_name = var.rg_name
  iothub_name         = var.iothub_name

  registry_read   = true
  registry_write  = false
  service_connect = true
  device_connect  = false
}