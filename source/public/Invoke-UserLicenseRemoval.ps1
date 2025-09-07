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
    # $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name AccountEnabled -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name AssignedLicense -Value @()
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskAction -Value ''
    # $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name ReadinessNote -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskStatusPostOp -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskResult -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name RemovedLicense -Value @()

    $taskStatusPostOp = ''
    $taskResult = ''
    $listItemParam = ''
    $completedDate = ''

    foreach ($user in $usersForLicenseRemoval) {
        $readinessState = Get-MLRUserAccountState -Username $user.TaskUsername

        $user.TaskAction = $readinessState.Action
        $user.AssignedLicense = $readinessState.AssignedLicense

        if ($readinessState.Action -eq 'Cancel') {
            $taskStatusPostOp = 'Cancelled'
            $taskResult = $($readinessState.ReadinessNote)
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


            $listItemParam = @{
                Status = $taskStatusPostOp
                Notes  = $taskResult
            }
            if ($completedDate) { $listItemParam.Add('CompletedDate', $completedDate) }

            $null = Update-MgSiteListItemField -SiteId $user.TaskSiteId -ListId $user.TaskListId -ListItemId $user.TaskListItemId -BodyParameter $listItemParam -ErrorAction Stop
            $user.TaskResult = $taskResult
            $user.TaskStatusPostOp = $taskStatusPostOp
            $user.TaskCompletedDate = $completedDate
        }
        catch {

        }


    }

    $usersForLicenseRemoval
}