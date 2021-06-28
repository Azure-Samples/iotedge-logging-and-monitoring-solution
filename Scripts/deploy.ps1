function New-IoTEnvironment() {
    # Get environment hash for name uniqueness
    $env_hash = Get-EnvironmentHash
    
    $root_path = Split-Path $PSScriptRoot -Parent
    
    #region script variables
    $create_iot_hub = $false
    $ask_for_location = $false
    $create_workspace = $false
    $create_storage = $false
    $create_event_grid = $false
    $enable_monitoring = $false
    $create_event_hubs = $false
    $create_event_hubs_namespace = $false
    $event_hubs_name = "metricscollector-$($env_hash)"
    $event_hubs_listen_rule = "listen-$($env_hash)"
    $event_hubs_send_rule = "send-$($env_hash)"
    $events_hubs_endpoint = "metricscollector-$($env_hash)"
    $event_hubs_route = "monitoringmetrics-$($env_hash)"
    $event_hubs_route_condition = "id = 'origin-iotedge-metrics-collector'"
    $deployment_condition = "tags.logPullEnabled='true'"
    $device_query = "SELECT * FROM devices WHERE $($deployment_condition)"
    $function_app_name = "iotedgelogsapp-$($env_hash)"
    $logs_regex = "\b(WRN?|ERR?|CRIT?)\b"
    $logs_encoding = "gzip"
    $metrics_encoding = "gzip"
    $invoke_log_upload_function_name = "InvokeUploadModuleLogs"
    $schedule_log_upload_function_name = "ScheduleUploadModuleLogs"
    $alert_function_name = "MonitorAlerts"
    $zip_package_name = "deploy.zip"
    $zip_package_path = "$($root_path)/FunctionApp/FunctionApp/$($zip_package_name)"
    #endregion

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

    #region deployment option
    $deployment_options = @("Create a sandbox environment for testing (fastest)", "Custom deployment (most flexible)", "Deploy Monitor Alerts (requires an existing deployment and the metrics collector solution running at the edge)")
    Write-Host
    Write-Host "Choose a deployment option from the list (using its Index):"
    for ($index = 0; $index -lt $deployment_options.Count; $index++) {
        Write-Host "$($index + 1): $($deployment_options[$index])"
    }
    while ($true) {
        $deployment_option = Read-Host -Prompt ">"
        try {
            if ([int]$deployment_option -ge 1 -and [int]$deployment_option -le $deployment_options.Count) {
                break
            }
        }
        catch {
            Write-Host "Invalid index '$($deployment_option)' provided."
        }
        Write-Host "Choose from the list using an index between 1 and $($deployment_options.Count)."
    }
    #endregion

    #region obtain resource group name
    if ($deployment_option -eq 1 -or $deployment_option -eq 2) {
        $create_resource_group = $false
        $resource_group = $null
        $first = $true
        while ([string]::IsNullOrEmpty($resource_group) -or ($resource_group -notmatch "^[a-z0-9-_]*$")) {
            if ($first -eq $false) {
                Write-Host "Use alphanumeric characters as well as '-' or '_'."
            }
            else {
                Write-Host
                Write-Host "Provide a name for the resource group to host all the new resources that will be deployed as part of your solution."
                $first = $false
            }
            $resource_group = Read-Host -Prompt ">"
        }

        $resourceGroup = az group list | ConvertFrom-Json | Where-Object { $_.name -eq $resource_group }
        if (!$resourceGroup) {
            Write-Host "Resource group '$resource_group' does not exist. It will be created later in the deployment."
            $create_resource_group = $true
        }
        else {
            Write-Host "Resource group '$resource_group' already exists in current subscription."
        }
    }
    #endregion

    if ($deployment_option -eq 1) {
        $ask_for_location = $true

        $create_iot_hub = $true
        $create_storage = $true
        $create_event_grid = $true
        $create_workspace = $true
        $enable_monitoring = $true
        $create_event_hubs = $true
        $create_event_hubs_namespace = $true
        $monitoring_mode = "IoTMessage"
    }
    elseif ($deployment_option -eq 2) {
        #region iot hub
        $iot_hubs = az iot hub list | ConvertFrom-Json | Sort-Object -Property id
        if ($iot_hubs.Count -gt 0) {
            $iot_hub_options = @("Create new IoT hub", "Use existing IoT hub")
            Write-Host
            Write-Host "Choose an option from the list for the IoT hub (using its Index):"
            for ($index = 0; $index -lt $iot_hub_options.Count; $index++) {
                Write-Host "$($index + 1): $($iot_hub_options[$index])"
            }
            while ($true) {
                $option = Read-Host -Prompt ">"
                try {
                    if ([int]$option -ge 1 -and [int]$option -le $iot_hub_options.Count) {
                        break
                    }
                }
                catch {
                    Write-Host "Invalid index '$($option)' provided."
                }
                Write-Host "Choose from the list using an index between 1 and $($iot_hub_options.Count)."
            }

            #region choose existing iot hub
            if ($option -eq 2) {
                Write-Host
                Write-Host "Choose an IoT hub to use from this list (using its Index):"
                for ($index = 0; $index -lt $iot_hubs.Count; $index++) {
                    Write-Host
                    Write-Host "$($index + 1): $($iot_hubs[$index].id)"
                }
                while ($true) {
                    $option = Read-Host -Prompt ">"
                    try {
                        if ([int]$option -ge 1 -and [int]$option -le $iot_hubs.Count) {
                            break
                        }
                    }
                    catch {
                        Write-Host "Invalid index '$($option)' provided."
                    }
                    Write-Host "Choose from the list using an index between 1 and $($iot_hubs.Count)."
                }

                $iot_hub_name = $iot_hubs[$option - 1].name
                $iot_hub_resource_group = $iot_hubs[$option - 1].resourcegroup
                $location = $iot_hubs[$option - 1].location
                $iot_hub_location = $location

                # handle IoT hub service policy
                $iot_hub_policies = az iot hub policy list --hub-name $iot_hub_name | ConvertFrom-Json
                $iot_hub_policy = $iot_hub_policies | Where-Object { $_.rights -like '*serviceconnect*' -and $_.rights -like '*registryread*' }
                if ($null -eq $iot_hub_policy) {
                    $iot_hub_policy_name = "iotedgelogs"
                    Write-Host
                    Write-Host "Creating IoT hub shared access policy '$($iot_hub_policy_name)' with permissions 'RegistryRead ServiceConnect'"
                    az iot hub policy create --hub-name $iot_hub_name --name $iot_hub_policy_name --permissions RegistryRead ServiceConnect
                }
                else {
                    $iot_hub_policy_name = $iot_hub_policy.keyName
                    Write-Host
                    Write-Host "Deployment will use existing IoT hub shared access policy '$($iot_hub_policy_name)'"
                }

                $logs_regex = ".*"
                Write-Host
                Write-Host -ForegroundColor Yellow "IMPORTANT: ELMS will be configured to capture all logs from the edge modules. To change this behavior, you can go to the Configuration section of the Function App '$($function_app_name)' and update the regular expression for the app setting 'LogsRegex'."
                
                Start-Sleep -Milliseconds 1500

                Write-Host
                Write-Host -ForegroundColor Yellow "IMPORTANT: You must update device twin for your IoT edge devices with `"$($deployment_condition)`" to collect logs from their modules."
                
                Start-Sleep -Milliseconds 1500
                
                Write-Host
                Write-Host "Press Enter to continue."
                Read-Host
            }
            #endregion
            else {
                $create_iot_hub = $true
                $ask_for_location = $true
            }
        }
        else {
            $create_iot_hub = $true
            $ask_for_location = $true
        }
        #endregion

        #region storage account
        $storage_accounts = az storage account list | ConvertFrom-Json | Sort-Object -Property id
        if ($storage_accounts.Count -gt 0) {
            $storage_options = @("Create new storage account", "Use existing storage account")
            Write-Host
            Write-Host "Choose an option from the list for the storage account to store log files (using its Index):"
            for ($index = 0; $index -lt $storage_options.Count; $index++) {
                Write-Host "$($index + 1): $($storage_options[$index])"
            }
            while ($true) {
                $option = Read-Host -Prompt ">"
                try {
                    if ([int]$option -ge 1 -and [int]$option -le $storage_options.Count) {
                        break
                    }
                }
                catch {
                    Write-Host "Invalid index '$($option)' provided."
                }
                Write-Host "Choose from the list using an index between 1 and $($storage_options.Count)."
            }

            #region existing storage account
            if ($option -eq 2) {
                Write-Host
                Write-Host "Choose a storage account to use from this list (using its Index):"
                for ($index = 0; $index -lt $storage_accounts.Count; $index++) {
                    Write-Host
                    Write-Host "$($index + 1): $($storage_accounts[$index].id)"
                }
                while ($true) {
                    $option = Read-Host -Prompt ">"
                    try {
                        if ([int]$option -ge 1 -and [int]$option -le $storage_accounts.Count) {
                            break
                        }
                    }
                    catch {
                        Write-Host "Invalid index '$($option)' provided."
                    }
                    Write-Host "Choose from the list using an index between 1 and $($storage_accounts.Count)."
                }

                $storage_account_id = $storage_accounts[$option - 1].id
                $storage_account_name = $storage_accounts[$option - 1].name
                $storage_account_resource_group = $storage_accounts[$option - 1].resourceGroup
                $storage_account_location = $storage_accounts[$option - 1].location

                #region system event grid
                $system_topics = az eventgrid system-topic list | ConvertFrom-Json
                $system_topic = $system_topics | Where-Object { $_.source -eq $storage_account_id }
                if (!!$system_topic) {
                    $system_topic_name = $system_topic.name
                    Write-Host
                    Write-Host "Deployment will use existing event grid system topic '$($system_topic_name)'"
                }
                else {
                    $create_event_grid = $true
                }
                #endregion
            }
            #endregion
            else {
                $create_storage = $true
                $create_event_grid = $true
            }
        }
        else {
            $create_storage = $true
            $create_event_grid = $true
        }
        #endregion

        #region log analytics
        $workspaces = az monitor log-analytics workspace list | ConvertFrom-Json | Sort-Object -Property id
        if ($workspaces.Count -gt 0) {
            $workspace_options = @("Create new log analytics workspace", "Use existing log analytics workspace")
            Write-Host
            Write-Host "Choose an option from the list for the Log Analytics workspace to connect to (using its Index):"
            for ($index = 0; $index -lt $workspace_options.Count; $index++) {
                Write-Host "$($index + 1): $($workspace_options[$index])"
            }
            while ($true) {
                $option = Read-Host -Prompt ">"
                try {
                    if ([int]$option -ge 1 -and [int]$option -le $workspace_options.Count) {
                        break
                    }
                }
                catch {
                    Write-Host "Invalid index '$($option)' provided."
                }
                Write-Host "Choose from the list using an index between 1 and $($workspace_options.Count)."
            }

            #region existing workspace
            if ($option -eq 2) {
                Write-Host
                Write-Host "Choose a log analytics workspace to use from this list (using its Index):"
                for ($index = 0; $index -lt $workspaces.Count; $index++) {
                    Write-Host
                    Write-Host "$($index + 1): $($workspaces[$index].id)"
                }
                while ($true) {
                    $option = Read-Host -Prompt ">"
                    try {
                        if ([int]$option -ge 1 -and [int]$option -le $workspaces.Count) {
                            break
                        }
                    }
                    catch {
                        Write-Host "Invalid index '$($option)' provided."
                    }
                    Write-Host "Choose from the list using an index between 1 and $($workspaces.Count)."
                }

                $workspace_name = $workspaces[$option - 1].name
                $workspace_resource_group = $workspaces[$option - 1].resourceGroup
                $workspace_location = $workspaces[$option - 1].location
            }
            #endregion
            else {
                $create_workspace = $true
            }
        }
        else {
            $create_workspace = $true
        }
        #endregion
    }
    elseif ($deployment_option -eq 3) {
        #region find iot hub
        $iot_hubs = az iot hub list | ConvertFrom-Json | Sort-Object -Property id
        Write-Host
        Write-Host "Choose an IoT hub to use from this list (using its Index):"
        for ($index = 0; $index -lt $iot_hubs.Count; $index++) {
            Write-Host
            Write-Host "$($index + 1): $($iot_hubs[$index].id)"
        }
        while ($true) {
            $option = Read-Host -Prompt ">"
            try {
                if ([int]$option -ge 1 -and [int]$option -le $iot_hubs.Count) {
                    break
                }
            }
            catch {
                Write-Host "Invalid index '$($option)' provided."
            }
            Write-Host "Choose from the list using an index between 1 and $($iot_hubs.Count)."
        }

        $iot_hub_id = $iot_hubs[$option - 1].id
        $iot_hub_name = $iot_hubs[$option - 1].name
        $iot_hub_resource_group = $iot_hubs[$option - 1].resourcegroup
        $location = $iot_hubs[$option - 1].location
        $iot_hub_location = $location
        #endregion

        #region ELMS function app
        $function_app = az functionapp list | ConvertFrom-Json | Sort-Object -Property id | Where-Object { $_.tags.iotHub -eq $iot_hub_id }
        
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
            Write-Host
            Write-Host "The function app '$($function_app.name)' in resource group '$($function_app.resourceGroup)' is linked to your IoT hub."
        }
        else {
            Write-Host
            Write-Host "Unable to find an ELMS function app associated to your IoT hub. Please deploy the ELMS solution linking it to your IoT hub before attempting to set up Monitor alerts."

            return
        }

        #region update tags in function app (if needed)
        if (!$function_app.tags.elms) {
            Write-Host
            Write-Host "The function app $($function_app.name) in resource group $($function_app.resourceGroup) is linked to your IoT hub. However, it lacks some of the latest tags that help identify the resource as part of your ELMS deployment."
            Write-Host "Updating resource tags..."

            az resource tag `
                --ids $function_app.id `
                --tags elms=true `
                -i | Out-Null
        }
        #endregion

        $env_hash = $function_app.name.Split('-')[1]
        #endregion

        #region monitor action groups
        Write-Host
        Write-Host "ELMS periodically pulls logs from IoT edge modules by default, but this deployment of Monitor alerts has the ability to proactively pull the most recent logs only when IoT edge devices trigger the alerts; optimizing network bandwidth and storage in Log Analytics."
        Write-Host
        Write-Host "Please choose an option from the list (using its Index):"
        $logs_pull_options = @("Continue pulling IoT edge module logs periodically", "Pull IoT edge module logs only when alerts are triggered")
        for ($index = 0; $index -lt $logs_pull_options.Count; $index++) {
            Write-Host "$($index + 1): $($logs_pull_options[$index])"
        }
        while ($true) {
            $option = Read-Host -Prompt ">"
            try {
                if ([int]$option -ge 1 -and [int]$option -le $logs_pull_options.Count) {
                    break
                }
            }
            catch {
                Write-Host "Invalid index '$($option)' provided."
            }
            Write-Host "Choose from the list using an index between 1 and $($logs_pull_options.Count)."
        }

        if ($option -eq 1) {
            $create_action_group = $false
        }
        elseif ($option -eq 2) {
            
            #region verify the function app contains monitor alerts function
            $function = az functionapp function show --name $function_app.name --resource-group $function_app.resourceGroup --function-name $alert_function_name | ConvertFrom-Json
            if (!$function.name) {
                Write-Host
                $upgrade_function_options = @("Yes", "No")
                
                Write-Host
                Write-Host "An update to your function app is required to handle Monitor alerts. Do you want to update it now?"
                for ($index = 0; $index -lt $upgrade_function_options.Count; $index++) {
                    Write-Host "$($index + 1): $($upgrade_function_options[$index])"
                }
                while ($true) {
                    $option = Read-Host -Prompt ">"
                    try {
                        if ([int]$option -ge 1 -and [int]$option -le $upgrade_function_options.Count) {
                            break
                        }
                    }
                    catch {
                        Write-Host "Invalid index '$($option)' provided."
                    }
                    Write-Host "Choose from the list using an index between 1 and $($upgrade_function_options.Count)."
                }
                
                if ($option -eq 1) {
                    Write-Host
                    Write-Host "Updating function app $($function_app.name)"
                    Write-Host
                    
                    az functionapp deployment source config-zip -g $function_app.resourceGroup -n $function_app.name --src $zip_package_path | Out-Null
                    
                    Write-Host
                    Write-Host "Function app updated successfully."
                }
                else {
                    Write-Host
                    Write-Host "No problem. Come back when you are ready to update your application."

                    return
                }
            }
            #endregion
            
            $create_action_group = $true

            # Write-Host
            # Write-Host -ForegroundColor Yello "NOTE: The periodic log pull functionality will be disabled after the Monitor alert deployment finishes."
        }

        $action_group_id = ""
        $action_groups = az monitor action-group list | ConvertFrom-Json
        if ($action_groups.Count -gt 0) {
            $action_group_options = @("Yes", "No")
            
            Write-Host
            Write-Host "Do you want to link an existing Monitor action group to the ELMS alerts? Choose an option from the list (using its Index):"
            for ($index = 0; $index -lt $action_group_options.Count; $index++) {
                Write-Host "$($index + 1): $($action_group_options[$index])"
            }
            while ($true) {
                $option = Read-Host -Prompt ">"
                try {
                    if ([int]$option -ge 1 -and [int]$option -le $action_group_options.Count) {
                        break
                    }
                }
                catch {
                    Write-Host "Invalid index '$($option)' provided."
                }
                Write-Host "Choose from the list using an index between 1 and $($action_group_options.Count)."
            }

            #region additional monitor action group
            if ($option -eq 1) {
                Write-Host
                Write-Host "Choose an action group from this list (using its Index):"
                for ($index = 0; $index -lt $action_groups.Count; $index++) {
                    Write-Host
                    Write-Host "$($index + 1): $($action_groups[$index].id)"
                }
                while ($true) {
                    $option = Read-Host -Prompt ">"
                    try {
                        if ([int]$option -ge 1 -and [int]$option -le $action_groups.Count) {
                            break
                        }
                    }
                    catch {
                        Write-Host "Invalid index '$($option)' provided."
                    }
                    Write-Host "Choose from the list using an index between 1 and $($action_groups.Count)."
                }

                $action_group_id = $action_groups[$option - 1].id
            }
            #endregion
        }
        #endregion

        #region deploy Monitor template
        $severity = 3
        $function_key = az functionapp keys list -g $function_app.resourceGroup -n $function_app.name --query 'functionKeys.default' -o tsv
        $alert_function_url = "https://$($function_app.defaultHostName)/api/$($alert_function_name)?code=$($function_key)"

        $platform_parameters = @{
            "location"                          = @{ "value" = $location }
            "environmentHashId"                 = @{ "value" = $env_hash }
            "scope"                             = @{ "value" = $iot_hub_id }
            "severity"                          = @{ "value" = $severity }
            
            "queueSizeAlertEvaluationFrequency" = @{ "value" = "PT30M" }
            "queueSizeAlertWindowSize"          = @{ "value" = "PT30M" }
            "queueSizeAlertThreshold"           = @{ "value" = 10 }
            
            "deviceDiskSpaceAlertEvaluationFrequency" = @{ "value" = "PT30M" }
            "deviceDiskSpaceAlertWindowSize"          = @{ "value" = "PT30M" }
            "deviceDiskSpaceAlertThreshold"           = @{ "value" = 75 }
            
            "deviceOfflineAlertEvaluationFrequency" = @{ "value" = "PT30M" }
            "deviceOfflineAlertWindowSize"          = @{ "value" = "PT30M" }
            "deviceOfflineAlertThreshold"           = @{ "value" = 10 }
            
            "createFunctionActionGroup"         = @{ "value" = $create_action_group }
            "additionalActionGroup"             = @{ "value" = $action_group_id }
            "functionAppName"                   = @{ "value" = $function_app.name }
            "functionAppResourceId"             = @{ "value" = $function_app.id }
            "alertFunctionName"                 = @{ "value" = $alert_function_name }
            "functionHttpTriggerUrl"            = @{ "value" = $alert_function_url }
            "templateUrl"                       = @{ "value" = "https://raw.githubusercontent.com/Azure-Samples/iotedge-logging-and-monitoring-solution" }
            "branchName"                        = @{ "value" = $(git rev-parse --abbrev-ref HEAD) }
        }
        Set-Content -Path "$($root_path)/Templates/monitor-deploy.parameters.json" -Value (ConvertTo-Json $platform_parameters -Depth 5)

        Write-Host
        Write-Host "Creating resource group deployment."
        $deployment_output = az deployment group create `
            --resource-group $function_app.resourceGroup `
            --name "ELMSAlerts-$($env_hash)" `
            --mode Incremental `
            --template-file "$($root_path)/Templates/monitor-deploy.json" `
            --parameters "$($root_path)/Templates/monitor-deploy.parameters.json" | ConvertFrom-Json
            
        if (!$deployment_output) {
            throw "Something went wrong with the resource group deployment. Ending script."
        }
        #endregion

        #region disable periodic log pull if desired
        if ($create_action_group) {
            $schedule_log_upload_function = az functionapp show `
                --resource-group $function_app.resourceGroup `
                --name $function_app.name `
                --function-name $schedule_log_upload_function_name | ConvertFrom-Json
            
            if (!$schedule_log_upload_function.isDisabled) {
                Write-Host
                Write-Host -ForegroundColor Yellow "NOTE: The function '$schedule_log_upload_function_name' will be disabled in your function app in order to turn off the periodic log pull functionality. You can always turn it back on by going to the 'Functions' section of your function app in the Azure Portal."
                az functionapp config appsettings set `
                    --resource-group $function_app.resourceGroup `
                    --name $function_app.name `
                    --settings "AzureWebJobs.$($schedule_log_upload_function_name).Disabled=true" | Out-Null

                Write-Host
                Write-Host "Function disabled."
            }
            #endregion
        }

        Write-Host
        Write-Host "Deployment completed."

        return
    }

    #region new resources details
    if ($create_iot_hub) {
        $iot_hub_name_prefix = "iothub"
        $iot_hub_name = "$($iot_hub_name_prefix)-$($env_hash)"
        $iot_hub_resource_group = $resource_group
        $iot_hub_policy_name = "iotedgelogs"
    }

    if ($create_storage) {
        $storage_account_name = "iotedgelogs$($env_hash)"
        $storage_account_resource_group = $resource_group
    }

    $storage_container_name = "modulelogs$($env_hash)"
    $storage_queue_name = "modulelogs$($env_hash)"

    if ($create_event_grid) {
        $system_topic_name = "iotedgelogs-$($env_hash)"
    }
    
    if ($create_workspace) {
        $workspace_name = "iotedgelogging-$($env_hash)"
        $workspace_resource_group = $resource_group
    }
    #endregion

    #region monitoring metrics
    if ($create_iot_hub) {
        $enable_monitoring = $true
        Write-Host
        Write-Host "In addition to logging, ELMS will enable IoT Edge monitoring with Azure Monitor. It will let you monitor your edge fleet at scale by using Azure Monitor to collect, store, visualize and generate alerts from metrics emitted by the IoT Edge runtime."
    }
    else {
        $metrics_options = @("Yes", "No")
        Write-Host
        Write-Host "In addition to logging, ELMS can enable IoT Edge monitoring with Azure Monitor. It will let you monitor your edge fleet at scale by using Azure Monitor to collect, store, visualize and generate alerts from metrics emitted by the IoT Edge runtime."
        Write-Host
        Write-Host "Do you want to enable IoT Edge monitoring? Choose an option from the list (using its Index):"
        for ($index = 0; $index -lt $metrics_options.Count; $index++) {
            Write-Host "$($index + 1): $($metrics_options[$index])"
        }
        while ($true) {
            $option = Read-Host -Prompt ">"
            try {
                if ([int]$option -ge 1 -and [int]$option -le $metrics_options.Count) {
                    break
                }
            }
            catch {
                Write-Host "Invalid index '$($option)' provided."
            }
            Write-Host "Choose from the list using an index between 1 and $($metrics_options.Count)."
        }

        if ($option -eq 1) {
            $enable_monitoring = $true
        }
    }

    #region enable monitoring
    if ($enable_monitoring) {
        if (!!$monitoring_mode -and $monitoring_mode -eq "AzureMonitor") {
            $option = 1
        }
        elseif (!!$monitoring_mode -and $monitoring_mode -eq "IoTMessage") {
            $option = 2
        }
        else {
            Write-Host
            Write-Host "Collected monitoring metrics can be uploaded directly to Log Analytics (requires outbound internet connectivity from the edge device(s)), or can be published as IoT messages (useful for local consumption). Metrics published as IoT messages are emitted as UTF8-encoded json from the endpoint '/messages/modules//outputs/metricOutput'."

            $metrics_options = @("To Log Analytics", "As IoT messages")
            Write-Host
            Write-Host "How should metrics be uploaded? Choose an option from the list (using its Index):"
            for ($index = 0; $index -lt $metrics_options.Count; $index++) {
                Write-Host "$($index + 1): $($metrics_options[$index])"
            }
            while ($true) {
                $option = Read-Host -Prompt ">"
                try {
                    if ([int]$option -ge 1 -and [int]$option -le $metrics_options.Count) {
                        break
                    }
                }
                catch {
                    Write-Host "Invalid index '$($option)' provided."
                }
                Write-Host "Choose from the list using an index between 1 and $($metrics_options.Count)."
            }
        }
        if ($option -eq 1) {
            Write-Host
            Write-Host -ForegroundColor Yellow "NOTE: Monitoring metrics will be sent directly from the edge to a log analytics workspace Log analytics workspace. Go to https://aka.ms/edgemon-docs to find more details."

            $monitoring_mode = "AzureMonitor"
            $event_hubs_namespace = ""
            $event_hubs_resouce_group = ""
            $event_hubs_location = ""
        }
        else {
            Write-Host
            Write-Host -ForegroundColor Yellow "NOTE: Monitoring metrics will be routed from IoT hub to an event hubs instance and processed by an Azure Function."

            $create_event_hubs = $true
            $monitoring_mode = "IoTMessage"

            if (!$create_iot_hub) {
                #region event hub
                $event_hubs_namespaces = az eventhubs namespace list | ConvertFrom-Json | Sort-Object -Property id
                if (!!$iot_hub_location) {
                    Write-Host
                    Write-Host -ForegroundColor Yellow "NOTE: For better performance, the event hubs namespace and function app will be in the same region as the IoT hub."
                    
                    $event_hubs_namespaces = $event_hubs_namespaces | Where-Object { $_.location.ToLower().Replace(' ', '') -eq $iot_hub_location }
                }

                if ($event_hubs_namespaces.Count -gt 0) {
                    $event_hubs_namespace_options = @("Create new event hubs namespace", "Use existing event hubs namespace")
                    Write-Host
                    Write-Host "Choose an option from the list for the event hubs namespace (using its Index):"
                    for ($index = 0; $index -lt $event_hubs_namespace_options.Count; $index++) {
                        Write-Host "$($index + 1): $($event_hubs_namespace_options[$index])"
                    }
                    while ($true) {
                        $option = Read-Host -Prompt ">"
                        try {
                            if ([int]$option -ge 1 -and [int]$option -le $event_hubs_namespace_options.Count) {
                                break
                            }
                        }
                        catch {
                            Write-Host "Invalid index '$($option)' provided."
                        }
                        Write-Host "Choose from the list using an index between 1 and $($event_hubs_namespace_options.Count)."
                    }

                    #region existing event hub namespace
                    if ($option -eq 2) {
                        Write-Host
                        Write-Host "Choose an event hubs namespace to use from this list (using its Index):"
                        for ($index = 0; $index -lt $event_hubs_namespaces.Count; $index++) {
                            Write-Host
                            Write-Host "$($index + 1): $($event_hubs_namespaces[$index].id)"
                        }
                        while ($true) {
                            $option = Read-Host -Prompt ">"
                            try {
                                if ([int]$option -ge 1 -and [int]$option -le $event_hubs_namespaces.Count) {
                                    break
                                }
                            }
                            catch {
                                Write-Host "Invalid index '$($option)' provided."
                            }
                            Write-Host "Choose from the list using an index between 1 and $($event_hubs_namespaces.Count)."
                        }

                        $event_hubs_namespace = $event_hubs_namespaces[$option - 1].name
                        $event_hubs_resouce_group = $event_hubs_namespaces[$option - 1].resourceGroup
                        $event_hubs_location = $event_hubs_namespaces[$option - 1].location
                    }
                    #endregion
                    else {
                        $create_event_hubs_namespace = $true
                    }
                }
                else {
                    $create_event_hubs_namespace = $true
                }
            }
            else {
                $create_event_hubs_namespace = $true
            }

            if ($create_event_hubs_namespace) {
                $event_hubs_namespace = "eventhubs-$($env_hash)"
                $event_hubs_resouce_group = $resource_group
            }
            #endregion
        }
    }
    else {
        $event_hubs_namespace = ""
        $event_hubs_resouce_group = ""
        $event_hubs_location = ""
    }
    #endregion

    #endregion

    #region obtain deployment location
    if ($ask_for_location) {
        $locations = Get-ResourceGroupLocations -provider 'Microsoft.Devices' -typeName 'ProvisioningServices'
        
        Write-Host
        Write-Host "Choose a location for your deployment from this list (using its Index):"
        for ($index = 0; $index -lt $locations.Count; $index++) {
            Write-Host "$($index + 1): $($locations[$index])"
        }
        while ($true) {
            $option = Read-Host -Prompt ">"
            try {
                if ([int]$option -ge 1 -and [int]$option -le $locations.Count) {
                    break
                }
            }
            catch {
                Write-Host "Invalid index '$($option)' provided."
            }
            Write-Host "Choose from the list using an index between 1 and $($locations.Count)."
        }
        $location_name = $locations[$option - 1]
        $location = $location_name.Replace(' ', '').ToLower()
    }
    
    Write-Host
    if ($create_iot_hub) {
        Write-Host "Using location '$($location)'"
    }
    else {
        Write-Host "Using location '$($location)' based on your IoT hub location"
    }

    if ($create_iot_hub) {
        $iot_hub_location = $location
    }
    if ($create_storage) {
        $storage_account_location = $location
    }
    if ($create_workspace) {
        $workspace_location = $location
    }
    if ($create_event_hubs_namespace) {
        $event_hubs_location = $location
    }
    #endregion

    #region create resource group after location has been defined
    if ($create_resource_group) {
        $resourceGroup = az group create --name $resource_group --location $location | ConvertFrom-Json
        
        Write-Host
        Write-Host "Created new resource group $($resource_group) in $($resourceGroup.location)."
    }
    #endregion

    #region create IoT platform

    #region edge virtual machine
    $skus = az vm list-skus | ConvertFrom-Json -AsHashtable
    $vm_skus = $skus | Where-Object { $_.resourceType -eq 'virtualMachines' -and $_.locations -contains $location -and $_.restrictions.Count -eq 0 }
    $vm_sku_names = $vm_skus | Select-Object -ExpandProperty Name -Unique
    
    # VM credentials
    $password_length = 12
    $vm_username = "azureuser"
    $vm_password = New-Password -length $password_length

    $edge_vm_name = "iotedgevm-$($env_hash)"
    
    # We will use VM with at least 2 cores and 8 GB of memory as gateway host.
    $edge_vm_sizes = az vm list-sizes --location $location | ConvertFrom-Json `
    | Where-Object { $vm_sku_names -icontains $_.name } `
    | Where-Object {
        ($_.numberOfCores -ge 2) -and `
        ($_.memoryInMB -ge 8192) -and `
        ($_.osDiskSizeInMB -ge 1047552) -and `
        ($_.resourceDiskSizeInMB -gt 8192)
    } `
    | Sort-Object -Property `
        NumberOfCores, MemoryInMB, ResourceDiskSizeInMB, Name
    # Pick top
    if ($edge_vm_sizes.Count -ne 0) {
        $edge_vm_size = $edge_vm_sizes[0].Name
        # Write-Host "Using $($edge_vm_size) as VM size for edge gateway host..."
    }
    #endregion

    #region virtual network parameters
    $vnet_name = "iot-vnet-$($env_hash)"
    $vnet_prefix = "10.0.0.0/16"
    $edge_subnet_name = "iotedge"
    $edge_subnet_prefix = "10.0.0.0/24"
    #endregion

    $platform_parameters = @{
        "location"                    = @{ "value" = $location }
        "environmentHashId"           = @{ "value" = $env_hash }
        "createIoTHub"                = @{ "value" = $create_iot_hub }
        "iotHubLocation"              = @{ "value" = $iot_hub_location }
        "iotHubName"                  = @{ "value" = $iot_hub_name }
        "iotHubResourceGroup"         = @{ "value" = $iot_hub_resource_group }
        "iotHubServicePolicyName"     = @{ "value" = $iot_hub_policy_name }
        "edgeVmName"                  = @{ "value" = $edge_vm_name }
        "edgeVmSize"                  = @{ "value" = $edge_vm_size }
        "adminUsername"               = @{ "value" = $vm_username }
        "adminPassword"               = @{ "value" = $vm_password }
        "vnetName"                    = @{ "value" = $vnet_name }
        "vnetAddressPrefix"           = @{ "value" = $vnet_prefix }
        "edgeSubnetName"              = @{ "value" = $edge_subnet_name }
        "edgeSubnetAddressRange"      = @{ "value" = $edge_subnet_prefix }
        "deviceQuery"                 = @{ "value" = $device_query }
        "createStorageAccount"        = @{ "value" = $create_storage }
        "storageAccountLocation"      = @{ "value" = $storage_account_location }
        "storageAccountName"          = @{ "value" = $storage_account_name }
        "storageAccountResourceGroup" = @{ "value" = $storage_account_resource_group }
        "storageContainerName"        = @{ "value" = $storage_container_name }
        "storageQueueName"            = @{ "value" = $storage_queue_name }
        "createEventGridSystemTopic"  = @{ "value" = $create_event_grid }
        "eventGridSystemTopicName"    = @{ "value" = $system_topic_name }
        "createWorkspace"             = @{ "value" = $create_workspace }
        "workspaceLocation"           = @{ "value" = $workspace_location }
        "workspaceName"               = @{ "value" = $workspace_name }
        "workspaceResourceGroup"      = @{ "value" = $workspace_resource_group }
        "createEventHubsNamespace"    = @{ "value" = $create_event_hubs_namespace }
        "createEventHubs"             = @{ "value" = $create_event_hubs }
        "eventHubResourceGroup"       = @{ "value" = $event_hubs_resouce_group }
        "eventHubsLocation"           = @{ "value" = $event_hubs_location }
        "eventHubsNamespace"          = @{ "value" = $event_hubs_namespace }
        "eventHubsName"               = @{ "value" = $event_hubs_name }
        "eventHubsEndpointName"       = @{ "value" = $events_hubs_endpoint }
        "eventHubsRouteName"          = @{ "value" = $event_hubs_route }
        "eventHubsRouteCondition"     = @{ "value" = $event_hubs_route_condition }
        "eventHubsListenPolicyName"   = @{ "value" = $event_hubs_listen_rule }
        "eventHubsSendPolicyName"     = @{ "value" = $event_hubs_send_rule }
        "functionAppName"             = @{ "value" = $function_app_name }
        "httpTriggerFunction"         = @{ "value" = $invoke_log_upload_function_name }
        "logsRegex"                   = @{ "value" = $logs_regex }
        "logsSince"                   = @{ "value" = "15m" }
        "logsEncoding"                = @{ "value" = $logs_encoding }
        "metricsEncoding"             = @{ "value" = $metrics_encoding }
        "templateUrl"                 = @{ "value" = "https://raw.githubusercontent.com/Azure-Samples/iotedge-logging-and-monitoring-solution" }
        "branchName"                  = @{ "value" = $(git rev-parse --abbrev-ref HEAD) }
    }
    Set-Content -Path "$($root_path)/Templates/azuredeploy.parameters.json" -Value (ConvertTo-Json $platform_parameters -Depth 5)

    Write-Host
    Write-Host "Creating resource group deployment."
    $deployment_output = az deployment group create `
        --resource-group $resource_group `
        --name "IoTEdgeLogging-$($env_hash)" `
        --mode Incremental `
        --template-file "$($root_path)/Templates/azuredeploy.json" `
        --parameters "$($root_path)/Templates/azuredeploy.parameters.json" | ConvertFrom-Json
    
    if (!$deployment_output) {
        throw "Something went wrong with the resource group deployment. Ending script."        
    }
    #endregion

    #region update azure function host key app setting
    $function_app_hostname = az functionapp show -g $resource_group -n $function_app_name --query defaultHostName -o tsv
    $function_key = az functionapp keys list -g $resource_group -n $function_app_name --query 'functionKeys.default' -o tsv

    az functionapp config appsettings set `
        --name $function_app_name `
        --resource-group $resource_group `
        --settings "HostUrl=https://$($function_app_hostname)" "HostKey=$($function_key)" | Out-Null
    #endregion

    #region generate monitoring deployment manifest
    $scrape_frequency = 300
    if ($metrics_encoding -eq "gzip") {
        $compress_for_upload = "true"
    }
    else {
        $compress_for_upload = "false"
    }
    $monitoring_template = "$($root_path)/EdgeSolution/monitoring.$($monitoring_mode.ToLower()).template.json"
    $monitoring_manifest = "$($root_path)/EdgeSolution/monitoring.deployment.json"
    Remove-Item -Path $monitoring_manifest -ErrorAction Ignore

    (Get-Content -Path $monitoring_template -Raw) | ForEach-Object {
        $_ -replace '__WORKSPACE_ID__', $deployment_output.properties.outputs.workspaceId.value `
            -replace '__SHARED_KEY__', $deployment_output.properties.outputs.workspaceSharedKey.value `
            -replace '__HUB_RESOURCE_ID__', $deployment_output.properties.outputs.iotHubResourceId.value `
            -replace '__UPLOAD_TARGET__', $monitoring_mode `
            -replace '__SCRAPE_FREQUENCY__', $scrape_frequency `
            -replace '__COMPRESS_FOR_UPLOAD__', $compress_for_upload
    } | Set-Content -Path $monitoring_manifest
    #endregion

    #region edge deployments
    if ($create_iot_hub) {
        # Create main deployment
        Write-Host "`r`nCreating main IoT edge device deployment"

        az iot edge deployment create `
            -d "main-deployment" `
            --hub-name $iot_hub_name `
            --content "$($root_path)/EdgeSolution/deployment.manifest.json" `
            --target-condition=$deployment_condition | Out-Null

        # Create monitoring deployment
        $deployment_name = "edge-monitoring"
        $priority = 1
        
        Write-Host "`r`nCreating IoT edge monitoring layered deployment $deployment_name"

        az iot edge deployment create `
            --layered `
            -d "$deployment_name" `
            --hub-name $iot_hub_name `
            --content $monitoring_manifest `
            --target-condition=$deployment_condition `
            --priority $priority | Out-Null

        # Create logging deployment
        $deployment_name = "sample-logging"
        $priority = 2
        
        Write-Host "`r`nCreating IoT edge logging layered deployment $deployment_name"

        az iot edge deployment create `
            --layered `
            -d "$deployment_name" `
            --hub-name $iot_hub_name `
            --content "$($root_path)/EdgeSolution/logging.deployment.json" `
            --target-condition=$deployment_condition `
            --priority $priority | Out-Null
    }
    #endregion

    #region function app
    Write-Host
    Write-Host "Deploying code to Function App $function_app_name"
    
    az functionapp deployment source config-zip -g $resource_group -n $function_app_name --src $zip_package_path | Out-Null

    if (!$create_event_hubs) {
        # Write-Host
        # Write-Host "Disabling metrics collector function"
        az functionapp config appsettings set --resource-group $resource_group --name $function_app_name --settings "AzureWebJobs.CollectMetrics.Disabled=true"
    }
    #endregion

    #region notify of monitoring deployment steps
    if (!$create_iot_hub -and $enable_monitoring) {
        #region create custom endpoint and message route
        if ($monitoring_mode -eq "IoTMessage") {
            Write-Host
            Write-Host "Creating IoT hub routing endpoint"

            $eh_conn_string = "Endpoint=sb://$($deployment_output.properties.outputs.eventHubsNamespaceEndpoint.value);SharedAccessKeyName=$($event_hubs_send_rule);SharedAccessKey=$($deployment_output.properties.outputs.eventHubsSendKey.value);EntityPath=$($event_hubs_name)"

            $routing_endpoints = az iot hub routing-endpoint create `
                --resource-group $iot_hub_resource_group `
                --hub-name $iot_hub_name `
                --endpoint-type eventhub `
                --endpoint-name "metricscollector-$($env_hash)" `
                --endpoint-resource-group $resource_group `
                --endpoint-subscription-id $(az account show --query id -o tsv) `
                --connection-string $eh_conn_string | ConvertFrom-Json

            Write-Host
            Write-Host "Creating IoT hub route"

            $routes = az iot hub route create `
                --resource-group $iot_hub_resource_group `
                --hub-name $iot_hub_name `
                --endpoint-name "metricscollector-$($env_hash)" `
                --source-type DeviceMessages `
                --route-name "metricscollector-$($env_hash)" `
                --condition $event_hubs_route_condition `
                --enabled true | ConvertFrom-Json
        }
        #endregion

        Write-Host
        Write-Host -ForegroundColor Yellow "IMPORTANT: To start collecting metrics for your edge devices, you must create an IoT edge deployment with the Azure Monitor module. You can use the deployment manifest below on IoT hub '$($iot_hub_name)'."

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
        $response = Invoke-WebRequest -Method Post -Uri "https://$($function_app_hostname)/api/$($invoke_log_upload_function_name)?code=$($function_key)" -ErrorAction Ignore
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

    #region completion message
    Write-Host
    Write-Host -ForegroundColor Green "Resource Group: $($resource_group)"
    Write-Host -ForegroundColor Green "Environment unique id: $($env_hash)"

    if ($create_iot_hub) {
        Write-Host
        Write-Host -ForegroundColor Green "IoT Edge VM Credentials:"
        Write-Host -ForegroundColor Green "Username: $vm_username"
        Write-Host -ForegroundColor Green "Password: $vm_password"
    }
    else {
        Write-Host
        Write-Host -ForegroundColor Green "REMINDER: Update device twin for your IoT edge devices with `"$($deployment_condition)`" to collect logs from their modules."
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

Function New-Password() {
    param(
        $length = 15
    )
    $punc = 46..46
    $digits = 48..57
    $lcLetters = 65..90
    $ucLetters = 97..122
    $password = `
        [char](Get-Random -Count 1 -InputObject ($lcLetters)) + `
        [char](Get-Random -Count 1 -InputObject ($ucLetters)) + `
        [char](Get-Random -Count 1 -InputObject ($digits)) + `
        [char](Get-Random -Count 1 -InputObject ($punc))
    $password += get-random -Count ($length - 4) `
        -InputObject ($punc + $digits + $lcLetters + $ucLetters) |`
        ForEach-Object -begin { $aa = $null } -process { $aa += [char]$_ } -end { $aa }

    return $password
}

function Get-EnvironmentHash(
    [int]$hash_length = 8
) {
    $env_hash = (New-Guid).Guid.Replace('-', '').Substring(0, $hash_length).ToLower()

    return $env_hash
}

Function Get-ResourceGroupLocations(
    $provider,
    $typeName
) {
    $providers = $(az provider show --namespace $provider | ConvertFrom-Json)
    $resourceType = $providers.ResourceTypes | Where-Object { $_.ResourceType -eq $typeName }

    return $resourceType.locations
}

New-IoTEnvironment