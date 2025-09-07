function Invoke-MLRUserLicenseRemoval {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteUrl,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ListNameOrId
    )

    $tz = Get-TimeZone
    $tzOffsetString = $(
        if ($tz.BaseUtcOffset.ToString() -notlike "-*") {
            "UTC+$($tz.BaseUtcOffset.ToString())"
        }
        else {
            "UTC($tz.BaseUtcOffset.ToString())"
        }
    )

    $usersForLicenseRemoval = Get-MLRUserDueForLicenseRemoval -SiteUrl $SiteUrl -ListNameOrId $ListNameOrId
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name AssignedLicense -Value @()
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskAction -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskStatusPostOp -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskResult -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name RemovedLicense -Value @()

    foreach ($user in $usersForLicenseRemoval) {
        $taskStatusPostOp = ''
        $taskResult = ''
        $completedDate = $null

        $readinessState = Get-MLRUserAccountState -Username $user.TaskUsername

        $user.TaskAction = $readinessState.Action
        $user.AssignedLicense = $readinessState.AssignedLicense

        if ($readinessState.Action -eq 'Cancel') {
            $taskStatusPostOp = 'Cancelled'
            $taskResult = $($readinessState.ReadinessNote)
            $completedDate = (Get-Date)
        }

        if ($readinessState.Action -eq 'Skip') {
            $taskStatusPostOp = 'Pending'
            $taskResult = $($readinessState.ReadinessNote)
        }

        if ($readinessState.Action -eq 'Remove') {

            $removeResult = Remove-MLRUserLicenseAssignment -Username $user.TaskUsername -SkuId $readinessState.AssignedLicense

            if ($removeResult -eq 'Successful') {
                $taskStatusPostOp = 'Completed'
                $taskResult = "License removed on $(Get-Date -Format "yyyy-MM-dd hh:mm:ss tt") ($tzOffsetString)"
                $user.RemovedLicense = $readinessState.AssignedLicense
                $completedDate = (Get-Date)
            }
            else {
                $taskStatusPostOp = $readinessState.TaskStatusPreOp
                $taskResult = $removeResult
            }
        }

        try {
            <#
            - As of 2025-09-07, Update-MgSiteListItem and Update-MgSiteListItemField cannot update a DATE field to null value.
            - Reference - https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/2724
            - Microsoft closed the issue without it being resolved.
            - As a workaround, used Invoke-MgGraphRequest to update the fields.
            #>

            $fields = @{fields = @{
                    "Status"        = $taskStatusPostOp
                    "Notes"         = $taskResult
                    "CompletedDate" = $completedDate
                }
            }

            $null = Invoke-MgGraphRequest `
                -Method PATCH `
                -Uri "https://graph.microsoft.com/v1.0/sites/$($user.TaskSiteId)/lists/$($user.TaskListId)/items/$($user.TaskListItemId)" `
                -Body $fields `
                -ContentType "application/json" `
                -ErrorAction Stop

            $user.TaskResult = $taskResult
            $user.TaskStatusPostOp = $taskStatusPostOp
            $user.TaskCompletedDate = $completedDate
        }
        catch {
            SayError $_.Exception.Message
            $user.TaskResult = $_.Exception.Message
            $user.TaskStatusPostOp = $readinessState.TaskStatusPreOp
            $user.TaskCompletedDate = $null
        }
    }

    $usersForLicenseRemoval
}