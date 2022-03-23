# deploy end-to-end
# proviisiion 9 devices
# update twin of the 0 device

# az iot hub module-twin update -n {iothub_name} -d {device_id} -m {module_id} --desired '{"condition":{"temperature":{"critical": null}}}'

Write-Host $PSScriptRoot

# New-Variable -Scope global -Name env_hash -Value "One"
# New-Variable -Scope script -Name deployment_parameters -Value "One"

&$PSScriptRoot/deploy.ps1 "e2e" "deployment_parameters"

Write-Host $env_hash
Write-Host $deployment_parameters.environmentHashId.value

&$PSScriptRoot/add_devices.sh $deployment_parameters.environmentHashId.value 10 $deployment_parameters.iotHubResourceGroup.value $deployment_parameters.iotHubName.value

az iot hub module-twin update -n $deployment_parameters.iotHubName.value `
                              -d $deployment_parameters.edgeVmName.value `
                              -m "FilterModule" `
                              --desired '{\"minTemperatureThreshold\":30, \"maxTemperatureThreshold\":70}'

az iot hub invoke-module-method --method-name 'RestartModule' `
                              -n $deployment_parameters.iotHubName.value `c
                              -d $deployment_parameters.edgeVmName.value `
                              -m '$edgeAgent' `
                              --method-payload `
                                '
                                    {
                                        \"schemaVersion\": \"1.0\",
                                        \"id\": \"FilterModule\"
                                    }
                                '