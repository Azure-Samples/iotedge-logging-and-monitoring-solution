function New-IoTEnvironment() {
    # Get environment hash for name uniqueness
    $env_hash = Get-EnvironmentHash
    
    $root_path = Split-Path $PSScriptRoot -Parent
    
    Write-Host
    Write-Host "################################################"
    Write-Host "################################################"
    Write-Host "####                                        ####"
    Write-Host "#### IoT Edge Logging & Monitoring Solution ####"
    Write-Host "####         IoT Edge Device Creator        ####"
    Write-Host "####                                        ####"
    Write-Host "################################################"
    Write-Host "################################################"
    Write-Host

    Start-Sleep -Milliseconds 1500

    #region obtain resource group name
    $create_resource_group = $false
    $resource_group = $null
    $first = $true
    while ([string]::IsNullOrEmpty($resource_group) -or ($resource_group -notmatch "^[a-z0-9-_]*$")) {
        if ($first -eq $false) {
            Write-Host "Use alphanumeric characters as well as '-' or '_'."
        }
        else {
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
    #endregion

    #region iot hub
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

    $iot_hub_name = $iot_hubs[$option - 1].name
    $iot_hub_resource_group = $iot_hubs[$option - 1].resourcegroup
    $location = $iot_hubs[$option - 1].location
    
    Write-Host
    Write-Host "Using location '$($location)' based on your IoT hub location"
    #endregion

    #region device provisioning service
    $dps = $null
    $dps_services = az iot dps list | ConvertFrom-Json
    foreach ($dps_service in $dps_services)
    {
        $linked_hub = $dps_service.properties.iotHubs | Where-Object { $_.name -like "$($iot_hub_name).*" }
        if (!!$linked_hub)
        {
            $dps = $dps_service
            break
        }
    }

    Write-Host
    Write-Host "Using DPS '$($dps.name)' since it is connected to IoT hub '$($iot_hub_name)'"

    $dps_id_scope = $dps.properties.idScope
    $dps_access_policy = az iot dps access-policy list -g $dps.resourceGroup --dps-name $dps.name | ConvertFrom-Json | Where-Object { $_.rights -like '*DeviceConnect*' }
    
    Write-Host
    Write-Host "Using DPS access policy '$($dps_access_policy.keyName)'"

    $dps_conn_string = "HostName=$($dps.properties.serviceOperationsHostName);SharedAccessKeyName=$($dps_access_policy.keyName);SharedAccessKey=$($dps_access_policy.primaryKey)"
    #endregion

    #region virtual network
    $vnets = az network vnet list | ConvertFrom-Json | Sort-Object -Property id
    
    Write-Host
    Write-Host "Choose virtual network to use from this list (using its Index):"
    for ($index = 0; $index -lt $vnets.Count; $index++) {
        Write-Host
        Write-Host "$($index + 1): $($vnets[$index].id)"
    }
    while ($true) {
        $option = Read-Host -Prompt ">"
        try {
            if ([int]$option -ge 1 -and [int]$option -le $vnets.Count) {
                break
            }
        }
        catch {
            Write-Host "Invalid index '$($option)' provided."
        }
        Write-Host "Choose from the list using an index between 1 and $($vnets.Count)."
    }
    $vnet_name = $vnets[$option - 1].name
    $vnet_resource_group = $vnets[$option - 1].resourceGroup
    #endregion

    #region subnet
    $subnets = az network vnet subnet list -g $vnet_resource_group --vnet-name $vnet_name | ConvertFrom-Json | Sort-Object -Property name
    
    if ($subnets.Count -gt 1)
    {
        Write-Host
        Write-Host "Choose virtual network subnet to use from this list (using its Index):"
        for ($index = 0; $index -lt $subnets.Count; $index++) {
            Write-Host
            Write-Host "$($index + 1): $($subnets[$index].id)"
        }
        while ($true) {
            $option = Read-Host -Prompt ">"
            try {
                if ([int]$option -ge 1 -and [int]$option -le $subnets.Count) {
                    break
                }
            }
            catch {
                Write-Host "Invalid index '$($option)' provided."
            }
            Write-Host "Choose from the list using an index between 1 and $($subnets.Count)."
        }
        $edge_subnet_id = $subnets[$option - 1].id
    }
    else
    {
        Write-Host
        Write-Host "Using subnet '$($subnets[0].name)'"
        $edge_subnet_id = $subnets[0].id
    }
    #endregion

    #region edge virtual machine
    Write-Host
    Write-Host "Provide a prefix for the edge virtual machine."
    $edge_vm_prefix = Read-Host -Prompt ">"
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

    $edge_vm_name = "$($edge_vm_prefix)-$($env_hash)"
    
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

    #endregion

    $platform_parameters = @{
        "location"                    = @{ "value" = $location }
        "edgeVmName"                  = @{ "value" = $edge_vm_name }
        "edgeVmSize"                  = @{ "value" = $edge_vm_size }
        "adminUsername"               = @{ "value" = $vm_username }
        "adminPassword"               = @{ "value" = $vm_password }
        "edgeSubnetId"                = @{ "value" = $edge_subnet_id }
        "dpsIdScope"                  = @{ "value" = $dps_id_scope }
        "dpsConnectionString"         = @{ "value" = $dps_conn_string }
        "templateUrl"                 = @{ "value" = "https://raw.githubusercontent.com/Azure-Samples/iotedge-logging-and-monitoring-solution" }
        "branchName"                  = @{ "value" = $(git rev-parse --abbrev-ref HEAD) }
    }
    Set-Content -Path "$($root_path)/Templates/iotedge-vm-deploy.parameters.json" -Value (ConvertTo-Json $platform_parameters -Depth 5)

    if ($create_resource_group) {
        $resourceGroup = az group create --name $resource_group --location $location | ConvertFrom-Json
        
        Write-Host
        Write-Host "Created new resource group $($resource_group) in $($resourceGroup.location)."
    }

    Write-Host
    Write-Host "Creating resource group deployment"
    $deployment_output = az deployment group create `
        --resource-group $resource_group `
        --name "IoTEdgeVM-$($env_hash)" `
        --template-file "$($root_path)/Templates/iotedge-vm-deploy.json" `
        --parameters "$($root_path)/Templates/iotedge-vm-deploy.parameters.json" | ConvertFrom-Json
    
    if (!$deployment_output) {
        throw "Something went wrong with the resource group deployment. Ending script."        
    }
    #endregion

    Write-Host
    Write-Host -ForegroundColor Green "Environment Id: $($env_hash)"
    Write-Host -ForegroundColor Green "Resource Group: $($resource_group)"
    
    Write-Host
    Write-Host -ForegroundColor Green "IoT Edge VM Credentials:"
    Write-Host -ForegroundColor Green "VM name: $edge_vm_name"
    Write-Host -ForegroundColor Green "Username: $vm_username"
    Write-Host -ForegroundColor Green "Password: $vm_password"
    
    Write-Host
    Write-Host -ForegroundColor Green "##############################################"
    Write-Host -ForegroundColor Green "##############################################"
    Write-Host -ForegroundColor Green "####                                      ####"
    Write-Host -ForegroundColor Green "####        Deployment Succeeded          ####"
    Write-Host -ForegroundColor Green "####                                      ####"
    Write-Host -ForegroundColor Green "##############################################"
    Write-Host -ForegroundColor Green "##############################################"
    Write-Host
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