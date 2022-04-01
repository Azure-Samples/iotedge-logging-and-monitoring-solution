# deploy end-to-end
# proviisiion 9 devices
# update twin of the 0 device

&$PSScriptRoot/deploy.ps1 "e2e"

Write-Host $env_hash
Write-Host $output_parameters.environmentHashId.value
Write-Host $output_parameters.iotHubName.value
Write-Host output_parameters.edgeVmName.value

&$PSScriptRoot/add_devices.sh $output_parameters.environmentHashId.value 10 $output_parameters.iotHubResourceGroup.value $output_parameters.iotHubName.value

az iot hub module-twin update -n $output_parameters.iotHubName.value `
                              -d $output_parameters.edgeVmName.value `
                              -m "FilterModule" `
                              --desired '{\"minTemperatureThreshold\":30, \"maxTemperatureThreshold\":70}'

az iot hub invoke-module-method --method-name 'RestartModule' `
                              -n $output_parameters.iotHubName.value `
                              -d $output_parameters.edgeVmName.value `
                              -m '$edgeAgent' `
                              --method-payload `
                                '
                                    {
                                        \"schemaVersion\": \"1.0\",
                                        \"id\": \"FilterModule\"
                                    }
                                '