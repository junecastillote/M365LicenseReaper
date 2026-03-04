function Get-MLRUserAccountState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Username,

        [Parameter()]
        [switch]
        $SkipIfEnabled
    )
    # Write-Debug $MyInvocation.MyCommand.Name
    Write-Debug "Processing - $($Username)"

    $today = (Get-Date)
    $todayDateString = $today.ToString('yyyy-MM-dd')

    if (-not $Global:mlrGroupCache) {
        Write-Debug "Creating group cache in session..."
        $Global:mlrGroupCache = @{}
    }
    else {
        Write-Debug "Group cache exists in session..."
    }

    if (-not $Global:mlrSubscribedSku) {
        Write-Debug "Caching SubscribedSku in session..."
        $Global:mlrSubscribedSku = Get-MgSubscribedSku -All
    }
    else {
        Write-Debug "SubscribedSku cache exists in session..."
    }

    try {
        # Get M365 Product ID table
        $skuTable = Get-MLRM365ProductIdTable -ErrorAction Stop
    }
    catch {
        SayError "There was an error getting the Sku Table from Microsoft Learn. The license names will not be resolved to friendly names."
    }

    try {
        $properties = @(
            'Id',
            'UserPrincipalName',
            'AccountEnabled',
            'LicenseAssignmentStates'
        )

        # Get user object
        Write-Debug "Getting user object - $($Username)"
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
                    Username             = $Username
                    AccountEnabled       = ''
                    AssignedLicense      = ''
                    AssignedLicenseName  = ''
                    InheritedLicense     = ''
                    InheritedLicenseName = ''
                    LicenseGroup         = ''
                    LicenseGroupName     = ''
                    Action               = $action
                    ReadinessNote        = $readinessNote
                }))
    }

    try {
        # Get user licenses
        # $userLicenseCollection = @(Get-MgUserLicenseDetail -UserId $Username -ErrorAction Stop)
        $userLicenseCollection = $user.LicenseAssignmentStates

        if ($userLicenseCollection) {
            foreach ($license in $userLicenseCollection) {
                # Add the skupartnumber property
                $license | Add-Member -Name SkuPartNumber -MemberType NoteProperty -Value $(($Global:mlrSubscribedSku | Where-Object { $_.SkuId -eq $license.SkuId })).SkuPartNumber -Force
            }

            $licenseGroupIds = $userLicenseCollection.AssignedByGroup | Sort-Object | Select-Object -Unique
        }

        $licenseGroupNames = @()

        # Update the group cache
        if ($licenseGroupIds) {
            foreach ($id in $licenseGroupIds) {
                if (-not ($groupName = $Global:mlrGroupCache[$id])) {
                    Write-Debug "Group [$($id)] not found in cache. Retrieving group online."
                    $group = Get-MgGroup -GroupId $id -Property Id, DisplayName
                    $Global:mlrGroupCache.Add($group.Id, $group.DisplayName)
                }
                else {
                    Write-Debug "Group [$($groupName) ($($id))] found in cache."
                }
                $licenseGroupNames += $groupName
            }
        }

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
            $inheritedLicenseName = @()
            foreach ($license in $userLicenseCollection) {
                # If M365 Product ID table exists
                if ($skuTable) {
                    # Find the friendly name
                    $skuName = ($skuTable | Where-Object { $_.SkuId -eq $license.SkuId }).SkuName

                    # If the friendly name is found
                    if ($skuName) {
                        if ($license.AssignedByGroup) {
                            # If inherited by group
                            $inheritedLicenseName += $skuName
                        }
                        else {
                            # If directly assigned
                            $assignedLicenseName += $skuName
                        }
                    }
                    # If the friendly name is NOT found
                    else {
                        $assignedLicenseName += "$($license.SkuPartNumber)"
                        if ($license.AssignedByGroup) {
                            # If inherited by group
                            $inheritedLicenseName += "$($license.SkuPartNumber)"
                        }
                        else {
                            # If directly assigned
                            $assignedLicenseName += "$($license.SkuPartNumber)"
                        }
                    }
                }
                # If M365 Product ID table does not exist
                else {

                    if ($license.AssignedByGroup) {
                        # If inherited by group
                        $inheritedLicenseName += "$($license.SkuPartNumber)"
                    }
                    else {
                        # If directly assigned
                        $assignedLicenseName += "$($license.SkuPartNumber)"
                    }
                }

            }
            # $assignedLicense = $userLicenseCollection.SkuId -join ","
            $assignedLicense = ($userLicenseCollection | Where-Object { -not $_.AssignedByGroup }).SkuId -join ","
            $assignedLicenseName = $assignedLicenseName -join ","
            $inheritedLicense = ($userLicenseCollection | Where-Object { $_.AssignedByGroup }).SkuId -join ","
            $inheritedLicenseName = $inheritedLicenseName -join ","
        }

        return $([PSCustomObject]([ordered]@{
                    Username             = $Username
                    AccountEnabled       = $user.AccountEnabled
                    AssignedLicense      = $assignedLicense
                    AssignedLicenseName  = $assignedLicenseName
                    InheritedLicense     = $inheritedLicense
                    InheritedLicenseName = $inheritedLicenseName
                    LicenseGroup         = $licenseGroupIds -join ","
                    LicenseGroupName     = $licenseGroupNames -join ","
                    Action               = $action
                    ReadinessNote        = $readinessNote
                }))
    }
    catch {
        SayError "$($_.Exception.Message)"
        return $([PSCustomObject]([ordered]@{
                    Username             = $Username
                    AccountEnabled       = ''
                    AssignedLicense      = ''
                    AssignedLicenseName  = ''
                    InheritedLicense     = ''
                    InheritedLicenseName = ''
                    LicenseGroup         = ''
                    LicenseGroupName     = ''
                    Action               = 'Skip'
                    ReadinessNote        = "Cannot determine readiness because there was an error getting the user license details. $($_.Exception.Message). This task will be retried."
                }))
    }
}