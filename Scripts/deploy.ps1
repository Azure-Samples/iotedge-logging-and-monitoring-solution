$root_path = Split-Path $PSScriptRoot -Parent
Import-Module "$root_path/Scripts/PS-Library"
$github_repo_url = "https://raw.githubusercontent.com/eedorenko/iotedge-logging-and-monitoring-solution"

function Set-EnvironmentHash {
    param(
        [int] $hash_length = 8
    )
    $script:env_hash = Get-EnvironmentHash -hash_length $hash_length
}

function Read-CliVersion {
    param (
        [version]$min_version = "2.21"
    )

    $az_version = az version | ConvertFrom-Json
    [version]$cli_version = $az_version.'azure-cli'

    Write-Host
    Write-Host "Verifying your Azure CLI installation version..."
    Start-Sleep -Milliseconds 500

    if ($min_version -gt $cli_version) {
        Write-Host
        Write-Host "You are currently using the Azure CLI version $($cli_version) and this wizard requires version $($min_version) or later. You can update your CLI installation with 'az upgrade' and come back at a later time."

        return $false
    }
    else {
        Write-Host
        Write-Host "Great! You are using a supported Azure CLI version."

        return $true
    }
}

function Set-AzureAccount {
    param()

    Write-Host
    Write-Host "Retrieving your current Azure subscription..."
    Start-Sleep -Milliseconds 500

    $account = az account show | ConvertFrom-Json

    $option = Get-InputSelection `
        -options @("Yes", "No. I want to use a different subscription") `
        -text "You are currently using the Azure subscription '$($account.name)'. Do you want to keep using it?" `
        -default_index 1
    
    if ($option -eq 2) {
        $accounts = az account list | ConvertFrom-Json | Sort-Object -Property name

        $account_list = $accounts | Select-Object -Property @{ label="displayName"; expression={ "$($_.name): $($_.id)" } }
        $option = Get-InputSelection `
            -options $account_list.displayName `
            -text "Choose a subscription to use from this list (using its Index):" `
            -separator "`r`n`r`n"

        $account = $accounts[$option - 1]

        Write-Host "Switching to Azure subscription '$($account.name)' with id '$($account.id)'."
        az account set -s $account.id
    }
}

function Set-ResourceGroupName {
    param()

    $script:create_resource_group = $false
    $script:resource_group_name = $null
    $first = $true

    while ([string]::IsNullOrEmpty($script:resource_group_name) -or ($script:resource_group_name -notmatch "^[a-z0-9-_]*$")) {
        if ($first -eq $false) {
            Write-Host "Use alphanumeric characters as well as '-' or '_'."
        }
        else {
            Write-Host
            Write-Host "Provide a name for the resource group to host all the new resources that will be deployed as part of your solution."
            $first = $false
        }
        $script:resource_group_name = Read-Host -Prompt ">"

        $resourceGroup = az group list | ConvertFrom-Json | Where-Object { $_.name -eq $script:resource_group_name }
        if (!$resourceGroup) {
            $script:create_resource_group = $true
        }
        else {
            $script:create_resource_group = $false
        }
    }
}

function Get-InputSelection {
    param(
        [array] $options,
        $text,
        $separator = "`r`n",
        $default_index = $null
    )

    Write-Host
    Write-Host $text -Separator "`r`n`r`n"
    $indexed_options = @()
    for ($index = 0; $index -lt $options.Count; $index++) {
        $indexed_options += ("$($index + 1): $($options[$index])")
    }

    Write-Host $indexed_options -Separator $separator

    if (!$default_index) {
        $prompt = ">"
    }
    else {
        $prompt = "> $default_index"
    }

    while ($true) {
        $option = Read-Host -Prompt $prompt
        try {
            if (!!$default_index -and !$option)  {
                $option = $default_index
                break
            }
            elseif ([int] $option -ge 1 -and [int] $option -le $options.Count) {
                break
            }
        }
        catch {
            Write-Host "Invalid index '$($option)' provided."
        }

        Write-Host
        Write-Host "Choose from the list using an index between 1 and $($options.Count)."
    }

    return $option
}

function Get-ExistingResource {
    param (
        [string] $type,
        [string] $display_name,
        [string] $separator = "`r`n"
    )
 
    $resources = az resource list --resource-type $type | ConvertFrom-Json | Sort-Object -Property id
    if ($resources.Count -gt 0) {
        
        $option = Get-InputSelection `
            -options $resources.id `
            -text "Choose $($prefix) $($display_name) to use from this list (using its Index):" `
            -separator $separator

        return $resources[$option - 1]
    }
    else {
        return $null
    }
}

function Get-NewOrExistingResource {
    param(
        [string] $type,
        [string] $display_name,
        [string] $separator = "`r`n"
    )

    $resources = az resource list --resource-type $type | ConvertFrom-Json | Sort-Object -Property id
    if ($resources.Count -gt 0) {
        
        $option = Get-InputSelection `
            -options @("Create new $($display_name)", "Use existing $($display_name)") `
            -text "Choose an option from the list for the $($display_name) (using its index):"

        if ($option -eq 2) {

            $regex = "^[aeiou].*$"
            if ($display_name -imatch $regex) {
                $prefix = "an"
            }
            else {
                $prefix = "a"
            }

            $option = Get-InputSelection `
                -options $resources.id `
                -text "Choose $($prefix) $($display_name) to use from this list (using its Index):" `
                -separator $separator

            return $resources[$option - 1]
        }
        else {
            return $null
        }
    }
    else {
        return $null
    }
}

function Set-IoTHub {
    param(
        [string] $prefix = "iothub",
        [string] $policy_name = "iotedgelogs")

    if (!$script:sandbox) {
        $iot_hub = Get-NewOrExistingResource -type "Microsoft.Devices/IoTHubs" -display_name "IoT hub" -separator "`r`n`r`n"

        if (!!$iot_hub) {
            $script:create_iot_hub = $false
            $script:iot_hub_name = $iot_hub.name
            $script:iot_hub_resource_group = $iot_hub.resourcegroup
            $script:iot_hub_location = $iot_hub.location
        }
        else {
            $script:create_iot_hub = $true
        }
    }
    else {
        $script:create_iot_hub = $true
    }

    if ($script:create_iot_hub) {
        $script:iot_hub_resource_group = $script:resource_group_name
        $script:iot_hub_name = "$($prefix)-$($script:env_hash)"
        $script:iot_hub_policy_name = $policy_name
    }
}

function Set-Storage {
    param([string] $prefix = "iotedgelogs")

    if (!$script:sandbox) {
        $storage_account = Get-NewOrExistingResource -type "Microsoft.Storage/storageAccounts" -display_name "storage account" -separator "`r`n`r`n"

        if (!!$storage_account) {
            $script:create_storage = $false
            $script:storage_account_id = $storage_account.id
            $script:storage_account_name = $storage_account.name
            $script:storage_account_resource_group = $storage_account.resourceGroup
            $script:storage_account_location = $storage_account.location

            #region event grid system topic
            $system_topics = az eventgrid system-topic list | ConvertFrom-Json
            $system_topic = $system_topics | Where-Object { $_.source -eq $script:storage_account_id }
            if (!!$system_topic) {
                $script:create_event_grid = $false
                $script:event_grid_topic_name = $system_topic.name
            }
            else {
                $script:create_event_grid = $true
            }
            #endregion
        }
        else {
            $script:create_storage = $true
            $script:create_event_grid = $true
        }
    }
    else {
        $script:create_storage = $true
        $script:create_event_grid = $true
    }

    if ($script:create_storage) {
        $script:storage_account_resource_group = $script:resource_group_name
        $script:storage_account_name = "$($prefix)$($script:env_hash)"
    }

    if ($script:create_event_grid) {
        $script:event_grid_topic_name = "$($prefix)-$($script:env_hash)"
    }

    $script:storage_container_name = "$($prefix)$($script:env_hash)"
    $script:storage_queue_name = "$($prefix)$($script:env_hash)"
}

function Set-LogAnalyticsWorkspace {
    param([string] $prefix = "iotedgelogs")

    if (!$script:sandbox) {
        $workspace = Get-NewOrExistingResource -type "Microsoft.OperationalInsights/workspaces" -display_name "log analytics workspace" -separator "`r`n`r`n"

        if (!!$workspace) {
            $script:create_workspace = $false
            $script:workspace_name = $workspace.name
            $script:workspace_resource_group = $workspace.resourceGroup
            $script:workspace_location = $workspace.location
        }
        else {
            $script:create_workspace = $true
        }
    }
    else {
        $script:create_workspace = $true
    }

    if ($script:create_workspace) {
        $script:workspace_resource_group = $script:resource_group_name
        $script:workspace_name = "$($prefix)-$($script:env_hash)"
    }
}

# function Set-ApplicationInsights!!!!! {

function Set-EventHubsNamespace {
    param(
        [string] $prefix = "metricscollector",
        [string] $route_prefix = "monitoringmetrics",
        [string] $route_condition
    )

    if ($script:enable_monitoring -and $script:monitoring_mode -eq "IoTMessage") {
        if (!$script:sandbox) {
            $namespace = Get-NewOrExistingResource -type "Microsoft.EventHub/namespaces" -display_name "event hubs namespace" -separator "`r`n`r`n"

            if (!!$namespace) {
                $script:create_event_hubs_namespace = $false
                $script:event_hubs_resource_group = $namespace.resourceGroup
                $script:event_hubs_namespace = $namespace.name
                $script:event_hubs_location = $namespace.location
            }
            else {
                $script:create_event_hubs_namespace = $true
            }
        }
        else {
            $script:create_event_hubs_namespace = $true
        }

        if ($script:create_event_hubs_namespace) {
            $script:event_hubs_resource_group = $script:iot_hub_resource_group
            $script:event_hubs_namespace = "$($prefix)-$($script:env_hash)"
        }

        $script:create_event_hubs = $true
        $script:event_hubs_name = "$($prefix)-$($script:env_hash)"
        $script:event_hubs_listen_rule = "listen-$($script:env_hash)"
        $script:event_hubs_send_rule = "send-$($script:env_hash)"
        $script:event_hubs_endpoint = "$($prefix)-$($script:env_hash)"
        $script:event_hubs_route = "$($route_prefix)-$($script:env_hash)"
        $script:event_hubs_route_condition = $route_condition
    }
    else {
        $script:create_event_hubs_namespace = $false
        $script:create_event_hubs = $false
    }
}

function Set-EdgeInfrastructure {
    param (
        [string] $vm_prefix = "iotedgevm",
        [string] $vm_username = "azureuser",
        [int] $vm_password_length = 15,
        [int] $vm_cpu_cores = 2,
        [int] $vm_memory_mb = 8192,
        [int] $vm_os_disk_size = 1047552,
        [int] $vm_resource_disk_size = 8192,
        [string] $vnet_prefix = "iot-vnet",
        [string] $vnet_addr_prefix = "10.0.0.0/16",
        [string] $subnet_name = "iotedge",
        [string] $subnet_addr_prefix = "10.0.0.0/24"
    )

    if ($script:create_iot_hub) {
        #region virtual machine
        $skus = (az vm list-skus --location $script:iot_hub_location --all $false | Out-String).ToLower() | ConvertFrom-Json
        $vm_skus = $skus | Where-Object { $_.resourceType -ieq 'virtualMachines' -and $_.restrictions.Count -eq 0 }
        $vm_sku_names = $vm_skus | Select-Object -ExpandProperty Name -Unique
        
        $script:vm_name = "$($vm_prefix)-$($script:env_hash)"
        $script:vm_username = $vm_username
        $script:vm_password = New-Password -length $vm_password_length

        $vm_sizes = az vm list-sizes --location $script:iot_hub_location | ConvertFrom-Json `
        | Where-Object { $vm_sku_names -icontains $_.name } `
        | Where-Object {
            ($_.numberOfCores -ge $vm_cpu_cores) -and `
            ($_.memoryInMB -ge $vm_memory_mb) -and `
            ($_.osDiskSizeInMB -ge $vm_os_disk_size) -and `
            ($_.resourceDiskSizeInMB -gt $vm_resource_disk_size)
        } `
        | Sort-Object -Property `
            NumberOfCores, MemoryInMB, ResourceDiskSizeInMB, Name
        
        # Pick top
        if ($vm_sizes.Count -ne 0) {
            $script:vm_size = $vm_sizes[0].Name
        }
        #endregion

        #region virtual network parameters
        $script:vnet_name = "$($vnet_prefix)-$($script:env_hash)"
        $script:vnet_addr_prefix = $vnet_addr_prefix
        $script:subnet_name = $subnet_name
        $script:subnet_addr_prefix = $subnet_addr_prefix
        #endregion
    }
}

function Set-ELMSAlerts {
    param(
        [bool] $new_deployment = $true
    )

    #region greeting
    $alerts_greeting = "Monitoring Alerts feed from built-in metrics from the IoT Edge runtime collected by the metrics-collector module. The pre-configured alert rules monitor three events in your IoT edge devices: offline devices or not sending messages upstream at an expected rate, edge hub queues growing in size over time and percentage of total disk space used per edge device. "
    if (!$new_deployment) {
        $alerts_greeting += "Additionally, you can choose between pulling logs from edge devices into Log Analytics periodically or whenever an alert is triggered, thus using less bandwidth and overall storage. "
    }

    $alerts_greeting += "You can also link an existing Monitoring action group to the pre-configured alerts to get user notifications in real-time. For more information on the Azure Monitor Log alerts associated with IoT edge devices, visit https://docs.microsoft.com/en-us/azure/iot-edge/how-to-create-alerts?view=iotedge-2020-11."
    
    Write-Host
    Write-Host $alerts_greeting
    Write-Host
    Write-Host "Press Enter to continue."
    Read-Host
    # Write-Host
    # Write-Host $alerts_greeting
    # Write-Host
    # $option = Get-InputSelection `
    #     -options @( "Yes", "No") `
    #     -text "Do you want to set up monitoring alerts now?" `
    #     -default_index 1

    # if ($option -eq 2) {
    #     Write-Host
    #     Write-Host "No problem. You can set up alerts at any time by running this wizard and choosing option 3."
    #     return $null
    # }
    #endregion

    #region iot hub
    if (!$new_deployment) {
        $iot_hub = Get-ExistingResource -type "Microsoft.Devices/IoTHubs" -display_name "IoT hub" -separator "`r`n`r`n"

        if (!!$iot_hub) {
            $script:create_iot_hub = $false
            $script:iot_hub_name = $iot_hub.name
            $script:iot_hub_resource_group = $iot_hub.resourcegroup
            $script:iot_hub_location = $iot_hub.location
        }

        else {
            Write-Host "Unable to find an IoT hub in your subscription. Please create a new ELMS deployment, or if you have already; use the 'az account set' command to choose the right Azure subscription."
            return $null
        }
    }
    
    $script:iot_hub_id = az iot hub show -n $script:iot_hub_name --query id -o tsv
    #endregion

    #region ELMS function app
    $function_app = az functionapp list | ConvertFrom-Json | Sort-Object -Property id | Where-Object { $_.tags.iotHub -eq $script:iot_hub_id }
    if ($function_app.Count -gt 1) {
        Write-Host
        Write-Host "Found multiple function apps linked to your IoT hub. Choose the one your want to use from this list (using its Index):"
        for ($index = 0; $index -lt $function_app.Count; $index++) {
            Write-Host
            Write-Host "$($index + 1): $($function_app[$index].id)"
        }
        while ($true) {
            $option = Read-Host -Prompt ">"
            try {
                if ([int]$option -ge 1 -and [int]$option -le $function_app.Count) {
                    break
                }
            }
            catch {
                Write-Host "Invalid index '$($option)' provided."
            }
            Write-Host "Choose from the list using an index between 1 and $($function_app.Count)."
        }

        $function_app = $function_app[$option - 1]
    }
    elseif ($function_app.Count -eq 1) {
        if (!$new_deployment) {
            Write-Host
            Write-Host "The function app '$($function_app.name)' in resource group '$($function_app.resourceGroup)' is linked to your IoT hub."
        }
    }
    else {
        Write-Host
        Write-Host "Unable to find an ELMS function app associated to your IoT hub. Please deploy the ELMS solution linking it to your IoT hub before attempting to set up Monitor alerts."

        return $null
    }

    #region update tags in function app (if needed)
    if (!$function_app.tags.elms) {
        Write-Host
        Write-Host "The function app '$($function_app.name)' lacks some of the latest tags that help identify the resource as part of your ELMS deployment."
        Write-Host "Updating resource tags..."

        az resource tag `
            --ids $function_app.id `
            --tags elms=true `
            -i | Out-Null
    }
    #endregion

    $script:env_hash = $function_app.name.Split('-')[1]
    #endregion

    #region verify workspace and that InsightsMetrics table contains data
    Write-Host
    $workspace_resource_id = $function_app.tags.logAnalyticsWorkspace
    if (!!$workspace_resource_id) {
        Write-Host
        Write-Host "Verifying that there are metrics in your Log Analytics workspace..."

        $workspace_id = az resource show --id $workspace_resource_id --query 'properties.customerId' -o tsv

        $query = "let hasNonEmptyTable = (T:string) { toscalar( union isfuzzy=true ( table(T) | count as Count ), (print Count=0) | summarize sum(Count) ) > 0 }; let TableName = 'InsightsMetrics'; print IsPresent=iif(hasNonEmptyTable(TableName), 'yes', 'no')"
        $insights_metrics = az monitor log-analytics query `
        -w $workspace_id `
        --analytics-query $query | ConvertFrom-Json
        if ($insights_metrics.IsPresent -eq 'no' ) {
            Write-Host
            Write-Host "It looks like there is no metrics data in your Log Analytics workspace. Make sure you enable the monitoring option on your ELMS solution and the metrics collector module has been running on your IoT edge devices for at least 10 minutes before you attemp to set up monitoring alerts."
            Write-Host
            Read-Host -Prompt "Press Enter to exit"

            return $null
        }
    }
    else {
        Write-Host "Unable to find a Log Analytics workspace that is linked to your ELMS Function App. Please add the tag 'logAnalyticsWorkspace': '<your-workspace-resource-id>' to your Function App in order to link it."
        return $null
    }
    #endregion

    #region monitor action groups
    if (!$new_deployment) {
        $option = Get-InputSelection `
            -options @("Pull IoT edge module logs periodically", "Pull IoT edge module logs only when alerts are triggered") `
            -text @("ELMS periodically pulls logs from IoT edge modules by default, but this deployment of Monitor alerts has the ability to proactively pull the most recent logs only when IoT edge devices trigger the alerts; optimizing network bandwidth and storage in Log Analytics.", "Please choose an option from the list (using its Index):")

        if ($option -eq 1) {
            $create_action_group = $false
        }
        elseif ($option -eq 2) {
            
            #region verify the function app contains monitor alerts function
            $function = az functionapp function show --name $function_app.name --resource-group $function_app.resourceGroup --function-name $script:alert_function_name | ConvertFrom-Json
            if (!$function.name) {
                $option = Get-InputSelection `
                    -options @("Yes", "No") `
                    -text "An update to your function app is required to handle Monitor alerts. Do you want to update it now?"

                if ($option -eq 1) {
                    Write-Host
                    Write-Host "Updating function app $($function_app.name)"
                    Write-Host
                    
                    az functionapp deployment source config-zip -g $function_app.resourceGroup -n $function_app.name --src $script:zip_package_path | Out-Null
                    
                    Write-Host
                    Write-Host "Function app updated successfully."
                }
                else {
                    Write-Host
                    Write-Host "No problem. Come back when you are ready to update your application."

                    return $null
                }
            }
            #endregion
            
            $create_action_group = $true

            # Write-Host
            # Write-Host -ForegroundColor Yello "NOTE: The periodic log pull functionality will be disabled."
        }
    }
    else {
        $create_action_group = $false
    }

    $additional_action_group_id = ""
    $action_groups = az monitor action-group list | ConvertFrom-Json
    if ($action_groups.Count -gt 0) {
        
        $option = Get-InputSelection `
            -options @("Yes", "No") `
            -text @("Action Groups in Azure Monitor are a collection of notification preferences defined by the owner of an Azure subscription. Azure Monitor and Service Health alerts use action groups to notify users that an alert has been triggered.", "Do you want to link an existing action group to the ELMS alerts? Choose an option from the list (using its Index):")

        if ($option -eq 1) {
            $action_group = Get-ExistingResource `
                -type "Microsoft.Insights/ActionGroups" `
                -display_name "action group" `
                -separator "`r`n`r`n"

            $additional_action_group_id = $action_group.id
        }
    }
    #endregion

    #region deploy Monitor template
    $severity = 3
    $function_key = az functionapp keys list -g $function_app.resourceGroup -n $function_app.name --query 'functionKeys.default' -o tsv
    $alert_function_url = "https://$($function_app.defaultHostName)/api/$($alert_function_name)?code=$($function_key)"

    $template_parameters = @{
        "location"                                = @{ "value" = $script:iot_hub_location }
        "environmentHashId"                       = @{ "value" = $script:env_hash }
        "scope"                                   = @{ "value" = $script:iot_hub_id }
        "severity"                                = @{ "value" = $severity }
        
        "queueSizeAlertEvaluationFrequency"       = @{ "value" = "PT30M" }
        "queueSizeAlertWindowSize"                = @{ "value" = "PT30M" }
        "queueSizeAlertThreshold"                 = @{ "value" = 3 }
        "queueSizeAlertOperator"                  = @{ "value" = "GreaterThan" }
        "queueSizeAlertTimeAggregation"           = @{ "value" = "Count" }
        
        "deviceDiskSpaceAlertEvaluationFrequency" = @{ "value" = "PT30M" }
        "deviceDiskSpaceAlertWindowSize"          = @{ "value" = "PT30M" }
        "deviceDiskSpaceAlertThreshold"           = @{ "value" = 75 }
        "deviceDiskSpaceAlertOperator"            = @{ "value" = "GreaterThan" }
        "deviceDiskSpaceAlertTimeAggregation"     = @{ "value" = "Total" }
        
        "deviceOfflineAlertEvaluationFrequency"   = @{ "value" = "PT30M" }
        "deviceOfflineAlertWindowSize"            = @{ "value" = "PT30M" }
        "deviceOfflineAlertThreshold"             = @{ "value" = 3 }
        "deviceOfflineAlertOperator"              = @{ "value" = "LessThan" }
        "deviceOfflineAlertTimeAggregation"       = @{ "value" = "Total" }

        "createFunctionActionGroup"               = @{ "value" = $create_action_group }
        "additionalActionGroup"                   = @{ "value" = $additional_action_group_id }
        "functionAppName"                         = @{ "value" = $function_app.name }
        "functionAppResourceId"                   = @{ "value" = $function_app.id }
        "alertFunctionName"                       = @{ "value" = $script:alert_function_name }
        "functionHttpTriggerUrl"                  = @{ "value" = $alert_function_url }
        "templateUrl"                             = @{ "value" = $github_repo_url }
        "branchName"                              = @{ "value" = $(git rev-parse --abbrev-ref HEAD) }
    }
    Set-Content -Path "$($root_path)/Templates/monitor-deploy.parameters.json" -Value (ConvertTo-Json $template_parameters -Depth 5)

    Write-Host
    Write-Host "Creating resource group deployment."

    $script:deployment_output = az deployment group create `
        --resource-group $function_app.resourceGroup `
        --name "ELMSAlerts-$($script:env_hash)" `
        --mode Incremental `
        --template-file "$($root_path)/Templates/monitor-deploy.json" `
        --parameters "$($root_path)/Templates/monitor-deploy.parameters.json" | ConvertFrom-Json
        
    if (!$script:deployment_output) {
        throw "Something went wrong with the resource group deployment. Ending script."
    }
    #endregion

    #region enable/disable periodic log pull if desired
    $schedule_log_upload_function = az functionapp function show `
        --resource-group $function_app.resourceGroup `
        --name $function_app.name `
        --function-name $schedule_log_upload_function_name | ConvertFrom-Json

    if ($create_action_group) {
        if (!$schedule_log_upload_function.isDisabled) {
            Write-Host
            Write-Host -ForegroundColor Yellow "NOTE: The timer function '$schedule_log_upload_function_name' will be disabled in your function app in order to turn off the periodic log pull functionality. You can always turn it back on by going to the 'Functions' section of your function app in the Azure Portal."
            az functionapp config appsettings set `
                --resource-group $function_app.resourceGroup `
                --name $function_app.name `
                --settings "AzureWebJobs.$($schedule_log_upload_function_name).Disabled=true" | Out-Null

            Write-Host
            Write-Host "Function disabled."
        }
    }
    else {
        if ($schedule_log_upload_function.isDisabled) {
            Write-Host
            Write-Host -ForegroundColor Yellow "NOTE: The timer function '$schedule_log_upload_function_name' will be enabled in your function app in order to resume the periodic log pull functionality. You can change the function's state at any time by going to the 'Functions' section of your function app in the Azure Portal."
            az functionapp config appsettings set `
                --resource-group $function_app.resourceGroup `
                --name $function_app.name `
                --settings "AzureWebJobs.$($schedule_log_upload_function_name).Disabled=false" | Out-Null

            Write-Host
            Write-Host "Function disabled."
        }
    }
    #endregion

    Write-Host
    Write-Host "Deployment completed."

    return
}

function New-ELMSEnvironment() {

    #region script variables
    Set-EnvironmentHash

    $metrics_collector_message_id = "origin-iotedge-metrics-collector"
    $script:deployment_condition = "tags.logPullEnabled='true'"
    $script:device_query = "SELECT * FROM devices WHERE $($script:deployment_condition)"
    $script:function_app_name = "iotedgelogsapp-$($script:env_hash)"
    $script:function_app_dotnet_backend_name = "iot-dotnet-backend-$($script:env_hash)"
    $script:function_app_java_backend_name = "iot-java-backend-$($script:env_hash)"
    $script:logs_regex = "\b(WRN?|ERR?|CRIT?)\b"
    $script:logs_since = "15m"
    $script:logs_encoding = "gzip"
    $script:metrics_encoding = "gzip"
    $script:invoke_log_upload_function_name = "InvokeUploadModuleLogs"
    $script:schedule_log_upload_function_name = "ScheduleUploadModuleLogs"
    $script:alert_function_name = "MonitorAlerts"
    $script:zip_package_name = "deploy.zip"
    $script:zip_package_path = "$($root_path)/FunctionApp/FunctionApp/$($zip_package_name)"
    $script:zip_package_app_dotnet_backend_path = "$($root_path)/Backend/dotnetfunction/iot-dotnet-backend.zip"
    $script:zip_package_app_java_backend_path = "$($root_path)/Backend/javafunction/iot-java-backend.zip"
    #endregion

    #region greetings
    Write-Host
    Write-Host "################################################"
    Write-Host "################################################"
    Write-Host "####                                        ####"
    Write-Host "#### IoT Edge Logging & Monitoring Solution ####"
    Write-Host "####                                        ####"
    Write-Host "################################################"
    Write-Host "################################################"

    Start-Sleep -Milliseconds 1500

    Write-Host
    Write-Host "Welcome to IoT ELMS (Edge Logging & Monitoring Solution). This deployment script will help you deploy IoT ELMS in your Azure subscription. It can be deployed as a sandbox environment, with a new IoT hub and a test IoT Edge device generating sample logs and collecting monitoring metrics, or it can connect to your existing IoT Hub and Log analytics workspace."
    Write-Host
    Write-Host "Press Enter to continue."
    Read-Host
    #endregion

    #region validate CLI version
    $cli_valid = Read-CliVersion
    if (!$cli_valid) {
        return $null
    }
    #endregion

    # set azure susbcription
    Set-AzureAccount

    $option = Get-InputSelection `
        -options @("End-to-End Sample", "Cloud Workflow Sample") `
        -text @("Do you want to deploy End-to-End Sample or Cloud Workflow Sample? Choose an option from the list (using its Index):") `
        -default_index 1
    
    
    $script:enable_e2e_sample = ($option -eq 1)

    if ($script:enable_e2e_sample) {
        $deployment_option = 1
    }   
    else {
        #region deployment option
        $deployment_options = @(
            "Create a sandbox environment for testing (fastest)",
            "Custom deployment (most flexible)",
            "Deploy Monitoring alerts (requires an existing ELMS deployment with metrics collection enabled)"
        )

        $deployment_option = Get-InputSelection `
            -options $deployment_options `
            -text "Choose a deployment option from the list (using its Index):"
        #endregion
    }    
    
    

    #region obtain resource group name
    if ($deployment_option -eq 1 -or $deployment_option -eq 2) {
        
        Set-ResourceGroupName

        Write-Host
        if ($script:create_resource_group) {
            Write-Host "Resource group '$script:resource_group_name' does not exist. It will be created later in the deployment."
        }
        else {
            Write-Host "Resource group '$script:resource_group_name' already exists in current subscription."
        }
    }
    #endregion

    if ($deployment_option -eq 1) {

        $script:sandbox = $true

        Set-IoTHub
        Set-Storage
        Set-LogAnalyticsWorkspace
    }

    elseif ($deployment_option -eq 2) {

        #region iot hub
        Set-IoTHub

        if (!$script:create_iot_hub) {

            #region handle IoT hub service policy
            $iot_hub_policies = az iot hub policy list --hub-name $script:iot_hub_name | ConvertFrom-Json
            $iot_hub_policy = $iot_hub_policies | Where-Object { $_.rights -like '*serviceconnect*' -and $_.rights -like '*registryread*' }

            if (!$iot_hub_policy) {
                
                $script:iot_hub_policy_name = "iotedgelogs"
                Write-Host
                Write-Host "Creating IoT hub shared access policy '$($script:iot_hub_policy_name)' with permissions 'RegistryRead ServiceConnect'."
                
                az iot hub policy create `
                    --hub-name $script:iot_hub_name `
                    --name $script:iot_hub_policy_name `
                    --permissions RegistryRead ServiceConnect
            }
            else {
                
                $script:iot_hub_policy_name = $iot_hub_policy.keyName
                Write-Host
                Write-Host "The existing IoT hub shared access policy '$($script:iot_hub_policy_name)' will be used in the deployment."
            }
            #endregion

            $script:logs_regex = ".*"
            Write-Host
            Write-Host -ForegroundColor Yellow "IMPORTANT: ELMS will be configured to capture all logs from the edge modules. To change this behavior, you can go to the Configuration section of the Function App '$($script:function_app_name)' and update the regular expression for the app setting 'LogsRegex'."
            
            Start-Sleep -Milliseconds 1500
    
            Write-Host
            Write-Host -ForegroundColor Yellow "IMPORTANT: You must update device twin for your IoT edge devices with `"$($script:deployment_condition)`" to collect logs from their modules."
            
            Start-Sleep -Milliseconds 1500
            
            Write-Host
            Write-Host "Press Enter to continue."
            Read-Host
        }
        #endregion

        #region storage account
        Set-Storage

        if (!$script:create_event_grid) {
            Write-Host
            Write-Host "The existing event grid system topic '$($script:event_grid_topic_name)' will be used in the deployment."
        }
        #endregion

        #region log analytics
        Set-LogAnalyticsWorkspace
        #endregion
    }
    
    elseif ($deployment_option -eq 3) {
        
        Set-ELMSAlerts -new_deployment $false
        return
    }

    #region metrics monitoring
    if ($script:sandbox) {
        $script:enable_monitoring = $true
        $script:monitoring_mode = "IoTMessage"
    }
    else {
        $option = Get-InputSelection `
            -options @("Yes", "No") `
            -text @("ELMS can enable IoT Edge monitoring with Azure Monitor. It will let you monitor your edge fleet at scale by using Azure Monitor to collect, store, visualize and generate alerts from metrics emitted by the IoT Edge runtime.", "Do you want to enable IoT Edge monitoring? Choose an option from the list (using its Index):") `
            -default_index 1
        
        if ($option -eq 1) {
            $script:enable_monitoring = $true
        }
    }
        

    #region select monitoring type
    if ($script:enable_monitoring -and $null -eq $script:monitoring_mode) {

        $option = Get-InputSelection `
            -options @("To Log Analytics", "As IoT messages") `
            -text @("Collected monitoring metrics can be uploaded directly to Log Analytics (requires outbound internet connectivity from the edge device(s)), or can be published as IoT messages (useful for local consumption). Metrics published as IoT messages are emitted as UTF8-encoded json from the endpoint '/messages/modules//outputs/metricOutput'.", "How should metrics be uploaded? Choose an option from the list (using its Index):")
        
        if ($option -eq 1) {
            Write-Host
            Write-Host -ForegroundColor Yellow "NOTE: Monitoring metrics will be sent directly from the edge to a log analytics workspace Log analytics workspace. Go to https://aka.ms/edgemon-docs to find more details."

            $script:monitoring_mode = "AzureMonitor"
            $script:create_event_hubs = $false
        }
        elseif ($option -eq 2) {
            Write-Host
            Write-Host -ForegroundColor Yellow "NOTE: Monitoring metrics will be routed from IoT hub to an event hubs instance and processed by an Azure Function."

            $script:monitoring_mode = "IoTMessage"
            $script:create_event_hubs = $true
        }
    }
    #endregion

    if ($script:enable_monitoring) {
        Set-EventHubsNamespace -route_condition  "id = '$metrics_collector_message_id'"
    }
    else {
        $script:create_event_hubs_namespace = $false
        $script:create_event_hubs = $false
    }
    #endregion

    #region obtain deployment location
    if ($script:create_iot_hub) {
        $locations = Get-ResourceProviderLocations -provider 'Microsoft.Devices' -typeName 'ProvisioningServices'

        $option = Get-InputSelection `
            -options $locations `
            -text "Choose a location for your deployment from this list (using its Index):"

        $script:iot_hub_location = $locations[$option - 1].Replace(' ', '').ToLower()
    }

    Write-Host
    if ($script:create_iot_hub) {
        Write-Host "Using location '$($script:iot_hub_location)'"
    }
    else {
        Write-Host "Using location '$($script:iot_hub_location)' based on your IoT hub location"
    }
    #endregion

    #region create resource group
    if ($script:create_resource_group) {
        az group create --name $script:resource_group_name --location $script:iot_hub_location | ConvertFrom-Json | Out-Null
        
        Write-Host
        Write-Host "Created new resource group $($script:resource_group_name) in $($script:iot_hub_location)."
    }
    #endregion

    #region set resource location
    if (!$script:storage_account_location) {
        $script:storage_account_location = $script:iot_hub_location
    }
    if (!$script:workspace_location) {
        $script:workspace_location = $script:iot_hub_location
    }
    if (!$script:event_hubs_location) {
        $script:event_hubs_location = $script:iot_hub_location
    }
    #endregion

    #region create deployment

    Set-EdgeInfrastructure

    $template_parameters = @{
        "location"                    = @{ "value" = $script:iot_hub_location }
        "environmentHashId"           = @{ "value" = $script:env_hash }
        "createIoTHub"                = @{ "value" = $script:create_iot_hub }
        "iotHubLocation"              = @{ "value" = $script:iot_hub_location }
        "iotHubName"                  = @{ "value" = $script:iot_hub_name }
        "iotHubResourceGroup"         = @{ "value" = $script:iot_hub_resource_group }
        "iotHubServicePolicyName"     = @{ "value" = $script:iot_hub_policy_name }
        "deviceQuery"                 = @{ "value" = $script:device_query }
        "createStorageAccount"        = @{ "value" = $script:create_storage }
        "storageAccountLocation"      = @{ "value" = $script:storage_account_location }
        "storageAccountName"          = @{ "value" = $script:storage_account_name }
        "storageAccountResourceGroup" = @{ "value" = $script:storage_account_resource_group }
        "storageContainerName"        = @{ "value" = $script:storage_container_name }
        "storageQueueName"            = @{ "value" = $script:storage_queue_name }
        "createEventGridSystemTopic"  = @{ "value" = $script:create_event_grid }
        "eventGridSystemTopicName"    = @{ "value" = $script:event_grid_topic_name }
        "createWorkspace"             = @{ "value" = $script:create_workspace }
        "workspaceLocation"           = @{ "value" = $script:workspace_location }
        "workspaceName"               = @{ "value" = $script:workspace_name }
        "workspaceResourceGroup"      = @{ "value" = $script:workspace_resource_group }
        "functionAppName"             = @{ "value" = $script:function_app_name } 
        "functionAppDotNetName"       = @{ "value" = $script:function_app_dotnet_backend_name }
        "functionAppJavaName"         = @{ "value" = $script:function_app_java_backend_name }        
        "httpTriggerFunction"         = @{ "value" = $script:invoke_log_upload_function_name }
        "logsRegex"                   = @{ "value" = $script:logs_regex }
        "logsSince"                   = @{ "value" = $script:logs_since }
        "logsEncoding"                = @{ "value" = $script:logs_encoding }
        "metricsEncoding"             = @{ "value" = $script:metrics_encoding }
        "templateUrl"                 = @{ "value" = $github_repo_url }
        "branchName"                  = @{ "value" = $(git rev-parse --abbrev-ref HEAD) }
        "createE2ESample"        = @{ "value" = $script:enable_e2e_sample }
    }

    if ($script:create_iot_hub) {
        $template_parameters.Add("edgeVmName", @{ "value" = $script:vm_name })
        $template_parameters.Add("edgeVmSize", @{ "value" = $script:vm_size })
        $template_parameters.Add("adminUsername", @{ "value" = $script:vm_username })
        $template_parameters.Add("adminPassword", @{ "value" = $script:vm_password })
        $template_parameters.Add("vnetName", @{ "value" = $script:vnet_name })
        $template_parameters.Add("vnetAddressPrefix", @{ "value" = $script:vnet_addr_prefix })
        $template_parameters.Add("edgeSubnetName", @{ "value" = $script:subnet_name })
        $template_parameters.Add("edgeSubnetAddressRange", @{ "value" = $script:subnet_addr_prefix })
    }

    $template_parameters.Add("createEventHubsNamespace", @{ "value" = $script:create_event_hubs_namespace })
    $template_parameters.Add("createEventHubs", @{ "value" = $script:create_event_hubs })
    if ($script:create_event_hubs) {
        $template_parameters.Add("eventHubResourceGroup", @{ "value" = $script:event_hubs_resource_group })
        $template_parameters.Add("eventHubsLocation", @{ "value" = $script:event_hubs_location })
        $template_parameters.Add("eventHubsNamespace", @{ "value" = $script:event_hubs_namespace })
        $template_parameters.Add("eventHubsName", @{ "value" = $script:event_hubs_name })
        $template_parameters.Add("eventHubsEndpointName", @{ "value" = $script:event_hubs_endpoint })
        $template_parameters.Add("eventHubsRouteName", @{ "value" = $script:event_hubs_route })
        $template_parameters.Add("eventHubsRouteCondition", @{ "value" = $script:event_hubs_route_condition })
        $template_parameters.Add("eventHubsListenPolicyName", @{ "value" = $script:event_hubs_listen_rule })
        $template_parameters.Add("eventHubsSendPolicyName", @{ "value" = $script:event_hubs_send_rule })
    }

    Set-Content -Path "$($root_path)/Templates/azuredeploy.parameters.json" -Value (ConvertTo-Json $template_parameters -Depth 5)

    Write-Host
    Write-Host "Creating resource group deployment."

    $script:deployment_output = az deployment group create `
        --resource-group $script:resource_group_name `
        --name "IoTEdgeLogging-$($script:env_hash)" `
        --mode Incremental `
        --template-file "$($root_path)/Templates/azuredeploy.json" `
        --parameters "$($root_path)/Templates/azuredeploy.parameters.json" | ConvertFrom-Json
    
    if (!$script:deployment_output) {
        throw "Something went wrong with the resource group deployment. Ending script."        
    }
    #endregion

    #region update azure function host key app setting
    $script:function_app_hostname = az functionapp show -g $script:resource_group_name -n $script:function_app_name --query defaultHostName -o tsv
    $script:function_key = az functionapp keys list -g $script:resource_group_name -n $script:function_app_name --query 'functionKeys.default' -o tsv

    az functionapp config appsettings set `
        --name $script:function_app_name `
        --resource-group $script:resource_group_name `
        --settings "HostUrl=https://$($script:function_app_hostname)" "HostKey=$($script:function_key)" | Out-Null
    #endregion

    #region generate monitoring deployment manifest
    if ($script:enable_monitoring) {
        if ($script:enable_e2e_sample) {
            $e2e_template = "$($root_path)/EdgeSolution/e2e.deployment.template.json"
            $e2e_manifest = "$($root_path)/EdgeSolution/e2e.deployment.manifest.json"
            Remove-Item -Path $e2e_manifest -ErrorAction Ignore

            (Get-Content -Path $e2e_template -Raw) | ForEach-Object {
                $_  -replace '\$\{APPINSIGHTS_INSTRUMENTATION_KEY\}', $script:deployment_output.properties.outputs.appInsightsInstrumentationKey.value `
                    -replace '\$\{IOTHUB_ARM_RESOURCEID\}', $script:deployment_output.properties.outputs.iotHubResourceId.value `
                    -replace '\$\{LOG_ANALYTICS_WSID\}', $script:deployment_output.properties.outputs.workspaceId.value `
                    -replace '\$\{LOG_ANALYTICS_SHARED_KEY\}', $script:deployment_output.properties.outputs.workspaceSharedKey.value

            } | Set-Content -Path $e2e_manifest    
        } 
        $script:scrape_frequency = 300
        if ($script:metrics_encoding -eq "gzip") {
            $script:compress_for_upload = "true"
        }
        else {
            $script:compress_for_upload = "false"
        }
        $monitoring_template = "$($root_path)/EdgeSolution/monitoring.$($script:monitoring_mode.ToLower()).template.json"
        $monitoring_manifest = "$($root_path)/EdgeSolution/monitoring.deployment.json"
        Remove-Item -Path $monitoring_manifest -ErrorAction Ignore

        (Get-Content -Path $monitoring_template -Raw) | ForEach-Object {
            $_ -replace '__WORKSPACE_ID__', $script:deployment_output.properties.outputs.workspaceId.value `
                -replace '__SHARED_KEY__', $script:deployment_output.properties.outputs.workspaceSharedKey.value `
                -replace '__HUB_RESOURCE_ID__', $script:deployment_output.properties.outputs.iotHubResourceId.value `
                -replace '__UPLOAD_TARGET__', $script:monitoring_mode `
                -replace '__SCRAPE_FREQUENCY__', $script:scrape_frequency `
                -replace '__COMPRESS_FOR_UPLOAD__', $script:compress_for_upload `
                -replace '__COMPRESS_FOR_UPLOAD__', $script:compress_for_upload
        } | Set-Content -Path $monitoring_manifest    
        
    }
    #endregion

    #region edge deployments
    if ($script:create_iot_hub) {



        if ($script:enable_e2e_sample) {
            # Create logging deployment
            $deployment_name = "e2e-sample"
            $priority = 0
            
            Write-Host "`r`nCreating end-to-end IoT edge sample deployment $deployment_name"

            az iot edge deployment create `
                --layered `
                -d "$deployment_name" `
                --hub-name $script:iot_hub_name `
                --content $e2e_manifest `
                --target-condition=$script:deployment_condition `
                --priority $priority | Out-Null  

            az deployment group create `
                --resource-group $script:resource_group_name `
                --template-file "$($root_path)/MonitoringInstruments/alerts.json" `
                --parameters iotHubName=$script:iot_hub_name             

            az deployment group create `
                --resource-group $script:resource_group_name `
                --template-file "$($root_path)/MonitoringInstruments/workbook.json" `
                --parameters iotHubName=$script:iot_hub_name             

        } else {
            # Create main deployment
            Write-Host "`r`nCreating main IoT edge device deployment"

            az iot edge deployment create `
                -d "main-deployment" `
                --hub-name $script:iot_hub_name `
                --content "$($root_path)/EdgeSolution/deployment.manifest.json" `
                --target-condition=$script:deployment_condition | Out-Null

            $priority = 0

            # Create monitoring deployment
            if ($script:enable_monitoring) {
                $deployment_name = "edge-monitoring"
                $priority += 1
                
                Write-Host "`r`nCreating IoT edge monitoring layered deployment $deployment_name"

                az iot edge deployment create `
                    --layered `
                    -d "$deployment_name" `
                    --hub-name $script:iot_hub_name `
                    --content $monitoring_manifest `
                    --target-condition=$script:deployment_condition `
                    --priority $priority | Out-Null
            }

            # Create logging deployment
            $deployment_name = "sample-logging"
            $priority += 1
            
            Write-Host "`r`nCreating IoT edge logging layered deployment $deployment_name"

            az iot edge deployment create `
                --layered `
                -d "$deployment_name" `
                --hub-name $script:iot_hub_name `
                --content "$($root_path)/EdgeSolution/logging.deployment.json" `
                --target-condition=$script:deployment_condition `
                --priority $priority | Out-Null
        }
        

    }
    #endregion

    #region function app
    Write-Host
    Write-Host "Deploying code to Function App $script:function_app_name"
    
    az functionapp deployment source config-zip -g $script:resource_group_name -n $script:function_app_name --src $script:zip_package_path | Out-Null

    if (!$script:create_event_hubs) {

        az functionapp config appsettings set --resource-group $script:resource_group_name --name $script:function_app_name --settings "AzureWebJobs.CollectMetrics.Disabled=true" | Out-Null
    }
    #endregion

    #region backend apps
    if ($script:enable_e2e_sample) {
        Write-Host
        Write-Host "Deploying code to dotnet backend app $script:function_app_dotnet_backend_name"            
        az functionapp deployment source config-zip -g $script:resource_group_name -n $script:function_app_dotnet_backend_name --src $script:zip_package_app_dotnet_backend_path | Out-Null

        Write-Host
        Write-Host "Deploying code to java backend app $script:function_app_java_backend_name"            
        az functionapp deployment source config-zip -g $script:resource_group_name -n $script:function_app_java_backend_name --src $script:zip_package_app_java_backend_path | Out-Null
    }
    #endregion

    #region notify of monitoring deployment steps
    if (!$script:create_iot_hub -and $script:enable_monitoring) {
        
        #region create custom endpoint and message route
        if ($script:monitoring_mode -eq "IoTMessage") {
            Write-Host
            Write-Host "Creating IoT hub routing endpoint"

            $script:iot_hub_endpoint_name = "metricscollector-$($script:env_hash)"
            $script:iot_hub_route_name = "metricscollector-$($script:env_hash)"
            $eh_conn_string = "Endpoint=sb://$($script:deployment_output.properties.outputs.eventHubsNamespaceEndpoint.value);SharedAccessKeyName=$($script:event_hubs_send_rule);SharedAccessKey=$($script:deployment_output.properties.outputs.eventHubsSendKey.value);EntityPath=$($script:event_hubs_name)"

            az iot hub routing-endpoint create `
                --resource-group $script:iot_hub_resource_group `
                --hub-name $script:iot_hub_name `
                --endpoint-type eventhub `
                --endpoint-name $script:iot_hub_endpoint_name `
                --endpoint-resource-group $script:resource_group_name `
                --endpoint-subscription-id $(az account show --query id -o tsv) `
                --connection-string $eh_conn_string | ConvertFrom-Json | Out-Null

            Write-Host
            Write-Host "Creating IoT hub route"

            az iot hub route create `
                --resource-group $script:iot_hub_resource_group `
                --hub-name $script:iot_hub_name `
                --endpoint-name $script:iot_hub_endpoint_name `
                --source-type DeviceMessages `
                --route-name $script:iot_hub_route_name `
                --condition $event_hubs_route_condition `
                --enabled true | ConvertFrom-Json | Out-Null
        }
        #endregion

        Write-Host
        Write-Host -ForegroundColor Yellow "IMPORTANT: To start collecting metrics for your edge devices, you must create an IoT edge deployment with the Azure Monitor module. You can use the deployment manifest below on IoT hub '$($script:iot_hub_name)'."

        Write-Host
        Write-Host -ForegroundColor Yellow $(Get-Content $monitoring_manifest) -Separator "`r`n"

        Write-Host
        Write-Host -ForegroundColor Yellow "Go to https://aka.ms/edgemon-docs for more details."
    }
    #endregion

    #region make the first module logs upload request
    Write-Host
    Write-Host "Waiting for edge deployment to be applied"
    Start-Sleep -Seconds 120

    Write-Host
    Write-Host "Invoking first module logs pull request"
    $attemps = 3
    do {
        $response = Invoke-WebRequest -Method Post -Uri "https://$($script:function_app_hostname)/api/$($script:invoke_log_upload_function_name)?code=$($script:function_key)" -ErrorAction Ignore
        $attemps--

        if ($response.StatusCode -eq 200) {
            Write-Host
            Write-Host "First function execution submitted successfully"
        }
        else {
            Start-Sleep -Seconds 10
        }
    } while ($response.StatusCode -ne 200 -and $attemps -gt 0)
    #endregion

    # alerts
    # Set-ELMSAlerts -new_deployment $true

    #region completion message
    Write-Host
    Write-Host -ForegroundColor Green "Resource Group: $($script:resource_group_name)"
    Write-Host -ForegroundColor Green "Environment unique id: $($script:env_hash)"

    if ($script:create_iot_hub) {
        Write-Host
        Write-Host -ForegroundColor Green "IoT Edge VM Credentials:"
        Write-Host -ForegroundColor Green "Username: $script:vm_username"
        Write-Host -ForegroundColor Green "Password: $script:vm_password"
    }
    else {
        Write-Host
        Write-Host -ForegroundColor Green "REMINDER: Update device twin for your IoT edge devices with `"$($script:deployment_condition)`" to collect logs from their modules."
    }

    Write-Host
    Write-Host -ForegroundColor Green "##############################################"
    Write-Host -ForegroundColor Green "##############################################"
    Write-Host -ForegroundColor Green "####                                      ####"
    Write-Host -ForegroundColor Green "####        Deployment Succeeded          ####"
    Write-Host -ForegroundColor Green "####                                      ####"
    Write-Host -ForegroundColor Green "##############################################"
    Write-Host -ForegroundColor Green "##############################################"
    Write-Host
    #endregion
}

New-ELMSEnvironment