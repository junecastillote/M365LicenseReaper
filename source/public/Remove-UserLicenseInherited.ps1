function Remove-MLRUserLicenseInherited {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [guid]
        $UserId,

        [Parameter(Mandatory)]
        [guid[]]
        $LicenseGroupId,

        [Parameter()]
        [switch]
        $TestMode,

        [Parameter()]
        [switch]
        $ForceRefreshGroupCache
    )

    $LicenseGroupId = @(
        $LicenseGroupId |
        Select-Object -Unique
    )

    New-GBLCache `
        -ForceRefreshGroupCache:$ForceRefreshGroupCache

    $removedGroup = @()
    $removedGroupName = @()

    $simulatedGroup = @()
    $simulatedGroupName = @()

    $simulatedLicense = @()
    $simulatedLicenseName = @()

    $skippedGroup = @()
    $skippedGroupName = @()
    $skippedGroupNotes = @()

    $errorGroup = @()
    $errorGroupName = @()
    $errors = @()

    $groupNameCollection = @()
    $removedLicense = @()
    $removedLicenseName = @()
    $notes = @()

    foreach ($groupId in $LicenseGroupId) {
        $group = Get-GroupFromCache -Id $groupId

        if ($group) {
            $groupName = $group.DisplayName
        }
        else {
            $groupName = $groupId.ToString()
        }

        $groupNameCollection += $groupName

        try {
            $isMember = Get-MgGroupMemberAsUser `
                -GroupId $groupId `
                -Filter "id eq '$($UserId)'" `
                -ErrorAction Stop

            if ($isMember) {
                if ($TestMode) {
                    $simulatedGroup += $groupId
                    $simulatedGroupName += $groupName
                }
                else {
                    Remove-MgGroupMemberByRef `
                        -DirectoryObjectId $UserId `
                        -GroupId $groupId `
                        -ErrorAction Stop

                    $removedGroup += $groupId
                    $removedGroupName += $groupName
                }
            }
            else {
                Write-Debug "[$UserId] is not a member of [$groupName]"

                $skippedGroup += $groupId
                $skippedGroupName += $groupName
                $skippedGroupNotes += "Not a member of [$groupName]"
            }
        }
        catch {
            $errorMessage = "$groupName - $($_.Exception.Message)"

            SayError $errorMessage

            $errors += $errorMessage
            $errorGroup += $groupId
            $errorGroupName += $groupName
        }
    }

    if ($TestMode) {
        $notes += 'Test mode. No group memberships were removed.'
    }

    if ($removedGroup.Count -gt 0) {
        foreach ($groupId in $removedGroup) {
            $group = Get-GroupFromCache -Id $groupId

            if ($group) {
                $removedLicense += @(
                    $group.AssignedLicenses.SkuId
                )
            }
        }

        if ($removedLicense.Count -gt 0) {
            $removedLicense = @(
                $removedLicense |
                Select-Object -Unique
            )

            $removedLicenseName = @(
                Get-LicenseNameFromCache `
                    -SkuId $removedLicense `
                    -Debug:$false
            )
        }
    }

    $satisfiedGroupCount =
    $removedGroup.Count +
    $skippedGroup.Count

    if ($simulatedGroup.Count -gt 0) {

        foreach ($groupId in $simulatedGroup) {

            $group = Get-GroupFromCache -Id $groupId

            if ($group) {
                $simulatedLicense += @(
                    $group.AssignedLicenses.SkuId
                )
            }
        }

        if ($simulatedLicense.Count -gt 0) {

            $simulatedLicense = @(
                $simulatedLicense |
                Select-Object -Unique
            )

            $simulatedLicenseName = @(
                Get-LicenseNameFromCache `
                    -SkuId $simulatedLicense `
                    -Debug:$false
            )
        }
    }

    $status = if (
        $TestMode -and
        $simulatedGroup.Count -gt 0
    ) {
        'Simulated'
    }
    elseif (
        $errorGroup.Count -gt 0 -and
        $satisfiedGroupCount -gt 0
    ) {
        'PartiallySuccessful'
    }
    elseif (
        $errorGroup.Count -gt 0 -and
        $satisfiedGroupCount -eq 0
    ) {
        'Failed'
    }
    elseif (
        $removedGroup.Count -eq 0 -and
        $skippedGroup.Count -gt 0
    ) {
        'AlreadySatisfied'
    }
    else {
        'Successful'
    }

    return [PSCustomObject]([ordered]@{
            UserId               = $UserId
            GroupId              = @($LicenseGroupId)
            GroupName            = @($groupNameCollection)

            Status               = $status

            RemovedGroupId       = @($removedGroup)
            RemovedGroupName     = @($removedGroupName)
            RemovedLicenseId     = @($removedLicense)
            RemovedLicenseName   = @($removedLicenseName)

            SimulatedGroupId     = @($simulatedGroup)
            SimulatedGroupName   = @($simulatedGroupName)

            SimulatedLicenseId   = @($simulatedLicense)
            SimulatedLicenseName = @($simulatedLicenseName)

            SkippedGroupId       = @($skippedGroup)
            SkippedGroupName     = @($skippedGroupName)
            SkippedGroupNotes    = @($skippedGroupNotes)

            ErrorGroupId         = @($errorGroup)
            ErrorGroupName       = @($errorGroupName)
            Error                = @($errors)

            Note                 = @($notes)
            TestMode             = [bool]$TestMode
        })
}