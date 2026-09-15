function Remove-MLRUserLicenseInherited {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [guid]
        $UserId,

        [Parameter(Mandatory)]
        [guid[]]
        $LicenseGroupId
    )

    $errors = @()
    $removedGroup = @()
    $errorGroup = @()
    $skippedGroup = @()


    foreach ($groupId in $LicenseGroupId) {
        $isMember = $null

        try {
            # Check if user is a member
            $isMember = Get-MgGroupMemberAsUser -GroupId $groupId -Filter "id eq '$($UserId)'" -ErrorAction SilentlyContinue

            # Remove if member
            if ($isMember) {
                Remove-MgGroupMemberByRef -DirectoryObjectId $UserId -GroupId $groupId -ErrorAction Stop
                $removedGroup += $groupId
            }
            else {
                Write-Debug "[$UserId] is not a member of [$groupId]"
                $skippedGroup += $groupId
            }
        }
        catch {
            SayError $($_.Exception.Message)
            $errors += "$($groupId) - $($_.Exception.Message)"
            $errorGroup += $groupId
        }
    }

    [pscustomobject]([ordered]@{
            UserId       = $UserId
            GroupId      = $LicenseGroupId
            RemovedGroup = $removedGroup
            SkippedGroup = $skippedGroup
            ErrorGroup   = $errorGroup
            Error        = $errors
        })
}