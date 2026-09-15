function Get-MLRUserAccountState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Username,

        [Parameter()]
        [switch]
        $SkipIfEnabled,

        # Parameter help description
        [Parameter()]
        [bool]
        $IncludeInheritedLicense = $true,

        [Parameter()]
        [switch]
        $ForceRefreshGroupCache
    )
    # Write-Debug $MyInvocation.MyCommand.Name
    Write-Debug "Processing - $($Username)"

    $today = (Get-Date)
    $todayDateString = $today.ToString('yyyy-MM-dd')

    $action = ''
    $actionReason = ''
    $readinessNote = ''

    $groupProperties = @('id', 'assignedLicenses', 'displayname')

    if ($IncludeInheritedLicense) {
        Write-Debug "Switch -IncludeInheritedLicense used."
        Write-Debug "  - The inherited licenses assigned by group will be included."

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

    if (-not $Global:mlrSubscribedSku) {
        Write-Debug "Caching SubscribedSku in session..."
        $Global:mlrSubscribedSku = Get-MgSubscribedSku -All
    }
    else {
        Write-Debug "SubscribedSku cache exists in session..."
    }

    # try {
    #     # Get M365 Product ID table
    #     $skuTable = Get-MLRM365ProductIdTable -ErrorAction Stop
    # }
    # catch {
    #     SayError "[$($MyInvocation.MyCommand.Name)]: There was an error getting the Sku Table from Microsoft Learn. The license names will not be resolved to friendly names."
    # }

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
        SayError "[$($MyInvocation.MyCommand.Name)]: $($_.Exception.Message)"
        if ($_.Exception.Message -like "*does not exist*") {
            $action = 'Cancel'
            $actionReason = 'User does not exist'
            $readinessNote = 'User account is not found. This task will not be retried.'
        }
        else {
            $action = 'Skip'
            $actionReason = 'Error'
            $readinessNote = "Cannot determine readiness because there was an error while getting the user account. $($_.Exception.Message)"
        }

        return $([PSCustomObject]([ordered]@{
                    Username             = $Username
                    UserId               = ''
                    AccountEnabled       = ''
                    AssignedLicense      = ''
                    AssignedLicenseName  = ''
                    InheritedLicense     = ''
                    InheritedLicenseName = ''
                    LicenseGroup         = ''
                    LicenseGroupName     = ''
                    Action               = $action
                    ActionReason         = $actionReason
                    ReadinessNote        = $readinessNote
                }))
    }

    try {
        # Get user licenses
        $userLicenseCollection = $(
            if (-not $IncludeInheritedLicense) {
                $user.LicenseAssignmentStates | Where-Object { -not $_.AssignedByGroup }
            }
            else {
                $user.LicenseAssignmentStates
            }
        )

        if ($userLicenseCollection) {
            foreach ($license in $userLicenseCollection) {
                # Add the skupartnumber property
                $license | Add-Member -Name SkuPartNumber -MemberType NoteProperty -Value $(($Global:mlrSubscribedSku | Where-Object { $_.SkuId -eq $license.SkuId })).SkuPartNumber -Force
            }

            $licenseGroupIds = $userLicenseCollection.AssignedByGroup | Sort-Object | Select-Object -Unique
        }

        $licenseGroupNames = @()

        # Update the group cache
        if ($licenseGroupIds -and $IncludeInheritedLicense) {
            foreach ($id in $licenseGroupIds) {
                if (-not ($groupName = ($Global:mlrGroupCache | Where-Object { $_.ID -eq $id }).DisplayName)) {
                    Write-Debug "Group [$($id)] not found in cache. Retrieving group online."
                    $group = Get-MgGroup -GroupId $id -Property $groupProperties | Select-Object $groupProperties
                    $Global:mlrGroupCache.Add($group)
                    $groupName = $group.DisplayName
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
            $actionReason = 'No license'
            $readinessNote = "User accout is not licensed as of $($todayDateString). This task will not be retried."
            $assignedLicense = ''
        }

        # if with license
        if ($userLicenseCollection) {
            # Control logic: Skip if the account is still enabled.
            if ($SkipIfEnabled -eq $true) {
                # with license + account enabled (skip)
                if ($user.AccountEnabled) {
                    $action = 'Skip'
                    $actionReason = 'Account enabled'
                    $readinessNote = "License removal not allowed - user account is currently enabled. This task will be retried."
                }

                # with license + account disabled
                if (!$user.AccountEnabled) {
                    $action = 'Remove'
                    $actionReason = 'Account disabled'
                    $readinessNote = "License removal allowed - user account is disabled. This task is final."
                }
            }

            # Control logic: Remove, as long as the user is licensed. Ignore whether account is still enabled.
            else {
                $action = 'Remove'
                $actionReason = 'User has license'
                $readinessNote = "License removal allowed. This task is final."
            }

            # $assignedLicense = @()
            $assignedLicenseName = @()
            $inheritedLicenseName = @()
            # $licenseNames = (Get-LicenseNameFromCache $userLicenseCollection.SkuId -Debug:$false)
            foreach ($license in $userLicenseCollection) {
                $skuName = Get-LicenseNameFromCache $license.SkuId -Debug:$false
                if ($license.AssignedByGroup) {
                    # If inherited by group
                    $inheritedLicenseName += $skuName
                }
                else {
                    # If directly assigned
                    $assignedLicenseName += $skuName
                }
            }
            $assignedLicense = ($userLicenseCollection | Where-Object { -not $_.AssignedByGroup }).SkuId -join ","
            $assignedLicenseName = $assignedLicenseName -join ","
            $inheritedLicense = ($userLicenseCollection | Where-Object { $_.AssignedByGroup }).SkuId -join ","
            $inheritedLicenseName = $inheritedLicenseName -join ","
        }

        return $([PSCustomObject]([ordered]@{
                    Username             = $Username
                    UserId               = $user.Id
                    AccountEnabled       = $user.AccountEnabled
                    AssignedLicense      = $assignedLicense
                    AssignedLicenseName  = $assignedLicenseName
                    InheritedLicense     = $inheritedLicense
                    InheritedLicenseName = $inheritedLicenseName
                    LicenseGroup         = $licenseGroupIds -join ","
                    LicenseGroupName     = $licenseGroupNames -join ","
                    Action               = $action
                    ActionReason         = $actionReason
                    ReadinessNote        = $readinessNote
                }))
    }
    catch {
        SayError "[$($MyInvocation.MyCommand.Name)]: $($_.Exception.Message)"
        return $([PSCustomObject]([ordered]@{
                    Username             = $Username
                    UserId               = ''
                    AccountEnabled       = ''
                    AssignedLicense      = ''
                    AssignedLicenseName  = ''
                    InheritedLicense     = ''
                    InheritedLicenseName = ''
                    LicenseGroup         = ''
                    LicenseGroupName     = ''
                    Action               = 'Skip'
                    ActionReason         = 'Error'
                    ReadinessNote        = "Cannot determine readiness because there was an error getting the user license details. $($_.Exception.Message). This task will be retried."
                }))
    }
}