function New-Password {
    param(
        [int] $length = 15
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
        ForEach-Object -begin { $aa = $null } -process { $aa += [char] $_ } -end { $aa }

    return $password
}

function Get-EnvironmentHash {
    param(
        [int] $hash_length = 8
    )
    $env_hash = (New-Guid).Guid.Replace('-', '').Substring(0, $hash_length).ToLower()

    return $env_hash
}

function Get-ResourceProviderLocations {
    param(
        [string] $provider,
        [string] $typeName
    )

    $providers = $(az provider show --namespace $provider | ConvertFrom-Json)
    $resourceType = $providers.ResourceTypes | Where-Object { $_.ResourceType -eq $typeName }

    return $resourceType.locations
}