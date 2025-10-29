function Get-MLRUserAccountState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Username,

        [Parameter()]
        [bool]
        $SkipIfEnabled = $false
    )

    $today = (Get-Date)
    $todayDateString = $today.ToString('yyyy-MM-dd')

    try {
        # Get M365 Product ID table
        $skuTable = Get-MLRM365ProductIdTable -ErrorAction Stop
    }
    catch {
        SayError "There was an error getting the Sku Table from Microsoft Learn. The license names will not be resolved to friendly names."
    }

    try {
        $properties = @(
            'UserPrincipalName',
            'AccountEnabled'
        )

        # Get user object
        $user = Get-MgUser -UserId $Username -ErrorAction Stop -Property $properties | Select-Object $properties
    }
    catch {
        SayError "$($_.Exception.Message)"
        if ($_.Exception.Message -like "*does not exist*") {
            $action = 'Cancel'
            $readinessNote = 'User account is not found. This task will not be retried.'
        }
        else {
            $action = 'Skip'
            $readinessNote = "Cannot determine readiness because there was an error whlie getting the user account. $($_.Exception.Message)"
        }

        return $([PSCustomObject]([ordered]@{
                    Username            = $Username
                    AccountEnabled      = ''
                    AssignedLicense     = ''
                    AssignedLicenseName = ''
                    Action              = $action
                    ReadinessNote       = $readinessNote
                }))
    }

    try {
        # Get user licenses
        # $userLicenseCollection = @(Get-MgUserLicenseDetail -UserId $Username -ErrorAction Stop | Select-Object SkuId)
        # $userLicenseCollection = @(Get-MgUserLicenseDetail -UserId $Username -ErrorAction Stop | Select-Object SkuId, SkuPartNumber, SkuName)
        $userLicenseCollection = @(Get-MgUserLicenseDetail -UserId $Username -ErrorAction Stop)

        # If without license
        if (!$userLicenseCollection) {
            $action = 'Cancel'
            $readinessNote = "License removal canceled - user accout is not licensed as of $($todayDateString). This task will not be retried."
            $assignedLicense = ''
        }

        # if with license
        if ($userLicenseCollection) {
            # Control logic: Skip if the account is still enabled.
            if ($SkipIfEnabled -eq $true) {
                # with license + account enabled (skip)
                if ($user.AccountEnabled) {
                    $action = 'Skip'
                    $readinessNote = "License removal not allowed - user account is currently enabled. This task will be retried."
                }

                # with license + account disabled
                if (!$user.AccountEnabled) {
                    $action = 'Remove'
                    $readinessNote = "License removal allowed - user account is disabled. This task is final."
                }
            }
            # Control logic: Remove, as long as the user is licensed. Ignore whether account is still enabled.
            else {
                $action = 'Remove'
                $readinessNote = "License removal allowed. This task is final."
            }

            # $assignedLicense = @()
            $assignedLicenseName = @()
            foreach ($license in $userLicenseCollection) {
                if ($skuTable) {
                    $skuName = ($skuTable | Where-Object { $_.SkuId -eq $license.SkuId }).SkuName
                    if ($skuName) {
                        $assignedLicenseName += $skuName
                    }
                    else {
                        $assignedLicenseName += "$($license.SkuPartNumber)"
                    }
                }
                else {
                    $assignedLicenseName += "$($license.SkuPartNumber)"
                }

            }
            $assignedLicense = $userLicenseCollection.SkuId -join ","
            $assignedLicenseName = $assignedLicenseName -join ","
        }

        return $([PSCustomObject]([ordered]@{
                    Username            = $Username
                    AccountEnabled      = $user.AccountEnabled
                    AssignedLicense     = $assignedLicense
                    AssignedLicenseName = $assignedLicenseName
                    Action              = $action
                    ReadinessNote       = $readinessNote
                }))
    }
    catch {
        SayError "$($_.Exception.Message)"
        return $([PSCustomObject]([ordered]@{
                    Username            = $Username
                    AccountEnabled      = ''
                    AssignedLicense     = ''
                    AssignedLicenseName = ''
                    Action              = 'Skip'
                    ReadinessNote       = "Cannot determine readiness because there was an error getting the user license details. $($_.Exception.Message). This task will be retried."
                }))
    }
}