# [enum]::GetValues([System.ConsoleColor])
function Say {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Text,
        [Parameter()]
        $Color = 'Cyan'
    )

    if ($Color) {
        $Host.UI.RawUI.ForegroundColor = $Color
    }
    $Text | Out-Host
    [Console]::ResetColor()
}

function SayError {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Text,
        [Parameter()]
        $Color = 'Red'
    )
    $Host.UI.RawUI.ForegroundColor = $Color
    "$(Get-Date -Format 'dd-MMM-yyyy HH:mm:ss') : [ERROR] - $Text" | Out-Host
    [Console]::ResetColor()
}

function SayInfo {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Text,
        [Parameter()]
        $Color = 'Green'
    )
    $Host.UI.RawUI.ForegroundColor = $Color
    "$(Get-Date -Format 'dd-MMM-yyyy HH:mm:ss') : [INFO] - $Text" | Out-Host
    [Console]::ResetColor()
}

function SayWarning {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Text,
        [Parameter()]
        $Color = 'DarkYellow'
    )
    $Host.UI.RawUI.ForegroundColor = $Color
    "$(Get-Date -Format 'dd-MMM-yyyy HH:mm:ss') : [WARNING] - $Text" | Out-Host
    [Console]::ResetColor()
}

function ThisModule {
    $MyInvocation.MyCommand.Module
}

function IsMLRGraphConnected {
    param()
    if (-not (Get-Module Microsoft.Graph.Authentication)) {
        SayError "[$($MyInvocation.MyCommand.Name)]: Microsoft Graph is not connected."
        return $false
    }

    if (-not (Get-MgContext)) {
        SayError "[$($MyInvocation.MyCommand.Name)]: Microsoft Graph is not connected."
        return $false
    }

    return $true
}


function New-GBLCache {
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]
        $ForceRefreshGroupCache
    )

    $groupProperties = @('id', 'assignedLicenses', 'displayname')

    if ($ForceRefreshGroupCache) {
        Write-Debug "Force creating group-based licensing list cache in session..."
        $Global:mlrGroupCache = [System.Collections.ArrayList]@(Get-MgGroup -Property $groupProperties -Filter "assignedLicenses/any()" | Select-Object $groupProperties)
    }
    else {
        if (-not $Global:mlrGroupCache) {
            Write-Debug "Creating group-based licensing list cache in session..."
            $Global:mlrGroupCache = [System.Collections.ArrayList]@(Get-MgGroup -Property $groupProperties -Filter "assignedLicenses/any()" | Select-Object $groupProperties)
        }
        else {
            Write-Debug "Group cache exists in session..."
        }
    }
}

function Get-GroupFromCache {
    param(
        $id
    )
    ($global:mlrGroupCache | Where-Object { $_.Id -eq $id })

}

function Get-LicenseNameFromCache {
    [CmdletBinding()]
    param (
        [guid[]]$skuId
    )

    try {
        # Get M365 Product ID table
        $skuTable = Get-MLRM365ProductIdTable -ErrorAction Stop
    }
    catch {
        SayError "[$($MyInvocation.MyCommand.Name)]: There was an error getting the Sku Table from Microsoft Learn. The license names will not be resolved to friendly names."
    }

    foreach ($id in $skuid) {
        if ($skuName = ($skuTable | Where-Object { $_.SkuId -eq $id }).SkuName) {
            $skuName
        }
        # If friendly name isnot found, get SkuPartNumber instead
        else {
            ($global:mlrSubscribedSku | Where-Object { $_.SkuId -eq $id }).SkuPartNumber
        }
    }
}