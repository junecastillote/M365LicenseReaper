function Get-MLRUserAccountState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Username
    )

    $today = (Get-Date)
    $todayDateString = $today.ToString('yyyy-MM-dd')

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
                    Username        = $Username
                    AccountEnabled  = ''
                    AssignedLicense = ''
                    Action          = $action
                    ReadinessNote   = $readinessNote
                }))
    }

    try {
        # Get user licenses
        $userLicenseCollection = @(Get-MgUserLicenseDetail -UserId $Username -ErrorAction Stop | Select-Object SkuId)

        # If without license
        if (!$userLicenseCollection) {
            $action = 'Cancel'
            $readinessNote = "License removal cancelled - user accout is not licensed as of $($todayDateString). This task will not be retried."
            $assignedLicense = ''
        }

        # if with license
        if ($userLicenseCollection) {
            # with license + account disabled
            if (!$user.AccountEnabled) {
                $action = 'Remove'
                $readinessNote = "License removal allowed - user account is disabled. This task is final."
            }

            # with license + account enabled (skip)
            if ($user.AccountEnabled) {
                $action = 'Skip'
                $readinessNote = "License removal not allowed - user account is currently enabled. This task will be retried."
            }

            $assignedLicense = $userLicenseCollection.SkuId -join ","
        }

        return $([PSCustomObject]([ordered]@{
                    Username        = $Username
                    AccountEnabled  = $user.AccountEnabled
                    AssignedLicense = $assignedLicense
                    Action          = $action
                    ReadinessNote   = $readinessNote
                }))
    }
    catch {
        SayError "$($_.Exception.Message)"
        return $([PSCustomObject]([ordered]@{
                    Username        = $Username
                    AccountEnabled  = ''
                    # AssignedLicense = @()
                    AssignedLicense = ''
                    Action          = 'Skip'
                    ReadinessNote   = "Cannot determine readiness because there was an error getting the user license details. $($_.Exception.Message). This task will be retried."
                }))
    }
}