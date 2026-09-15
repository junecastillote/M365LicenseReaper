function Remove-MLRUserLicenseInherited {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [guid]
        $UserId,

        [Parameter(Mandatory)]
        [guid[]]
        $LicenseGroupId,

        # Parameter help description
        [Parameter()]
        [switch]
        $TestMode
    )

    $errors = @()
    $removedLicense = @()
    $removedLicenseName = @()
    $removedGroup = @()
    $removedGroupName = @()
    $errorGroup = @()
    $errorGroupName = @()
    $skippedGroup = @()
    $skippedGroupName = @()
    $groupName = @()
    $notes = @()

    foreach ($groupId in $LicenseGroupId) {
        $groupName = $((Get-GroupFromCache $groupId).DisplayName)
        $isMember = $null
        try {
            # Check if user is a member
            $isMember = Get-MgGroupMemberAsUser -GroupId $groupId -Filter "id eq '$($UserId)'" -ErrorAction SilentlyContinue

            # Remove if member
            if ($isMember) {
                if (-not $TestMode) {
                    Remove-MgGroupMemberByRef -DirectoryObjectId $UserId -GroupId $groupId -ErrorAction Stop
                }
                $removedGroup += $groupId
            }
            else {
                Write-Debug "[$UserId] is not a member of [$($groupName)]"
                $skippedGroup += $groupId
                $notes += "Not a member of [$($groupName)]"
            }
        }
        catch {
            SayError "$($groupName) - $($_.Exception.Message)"
            $errors += "$($groupName) - $($_.Exception.Message)"
            $errorGroup += $groupId
        }
    }

    if ($TestMode) { $notes += 'Test mode. No changes.' }

    $groupName += (($LicenseGroupId | ForEach-Object { Get-GroupFromCache $_ }).DisplayName)
    if ($removedGroup) {
        $removedGroupName += (($removedGroup | ForEach-Object { Get-GroupFromCache $_ }).DisplayName)
        $removedLicense = $(
            foreach ($group in $removedGroup) {
                ($Global:mlrGroupCache | Where-Object { $_.id -eq $group }).AssignedLicenses.SkuId
            }
        )

        # $removedLicenseName += $(
        #     foreach ($license in $removedLicense) {
        #         Get-LicenseNameFromCache $license
        #     }
        # )

        $removedLicenseName += (Get-LicenseNameFromCache $removedLicense -Debug:$false)
    }

    if ($skippedGroup) {
        $skippedGroupName += (($skippedGroup | ForEach-Object { Get-GroupFromCache $_ }).DisplayName)
    }
    if ($errorGroup) {
        $errorGroupName += (($errorGroup | ForEach-Object { Get-GroupFromCache $_ }).DisplayName)
    }

    [pscustomobject]([ordered]@{
            UserId             = $UserId
            GroupId            = $LicenseGroupId
            GroupName          = $groupName
            RemovedGroupId     = $removedGroup
            RemovedGroupName   = $removedGroupName
            RemovedLicenseId   = $removedLicense
            RemovedLicenseName = $removedLicenseName
            SkippedGroupId     = $skippedGroup
            SkippedGroupName   = $skippedGroupName
            ErrorGroup         = $errorGroup
            ErrorGroupName     = $errorGroupName
            Error              = $errors
            Note               = $notes
            TestMode           = $TestMode
            Status             = $(
                if ($errorGroup -or $errors) {
                    'Failed'
                }
                elseif ($removedGroup.Count -lt 1) {
                    'Skipped'
                }
                else {
                    'Successful'
                }
            )
        })
}