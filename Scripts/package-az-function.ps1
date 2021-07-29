$root_path = Split-Path $PSScriptRoot -Parent
$function_path = "$($root_path)/FunctionApp/FunctionApp/"
$zip_package_name = "deploy.zip"

Set-Location $function_path

dotnet build /p:DeployOnBuild=true /p:DeployTarget=Package
dotnet publish /p:CreatePackageOnPublish=true -o .\bin\Publish

Compress-Archive -Path .\bin\publish\*  -DestinationPath $zip_package_name -Update

Set-Location $root_path

$function_apps = az functionapp list | ConvertFrom-Json | Sort-Object -property id
for ($index = 0; $index -lt $function_apps.Count; $index++) {
    Write-Host
    Write-Host "$($index + 1): $($function_apps[$index].id)"
}
while ($true) {
    $option = Read-Host -Prompt ">"
    try {
        if ([int]$option -ge 1 -and [int]$option -le $function_apps.Count) {
            break
        }
    }
    catch {
        Write-Host "Invalid index '$($option)' provided."
    }
    Write-Host "Choose from the list using an index between 1 and $($function_apps.Count)."
}

az functionapp deployment source config-zip `
    -g $function_apps[$option - 1].resourceGroup `
    -n $function_apps[$option - 1].name `
    --src "$($function_path)/$($zip_package_name)"
