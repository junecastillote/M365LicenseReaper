function Remove-MLRUserLicenseAssignment {
    [CmdletBinding()]
    [Alias('Remove-MLRUserLicenseAssigned')]
    param (
        [Parameter(Mandatory)]
        [string]
        $Username,

        [Parameter(Mandatory)]
        [guid[]]
        $SkuId,

        [Parameter()]
        [switch]
        $TestMode
    )

    # If user exists and has license, remove them.
    $params = @{
        addLicenses    = @(

        )
        removeLicenses = @(
            $skuid
        )
    }

    try {
        if (-not $TestMode) {
            $null = Set-MgUserLicense -UserId $Username -BodyParameter $params -ErrorAction Stop
        }
        return "Successful"
    }
    catch {
        SayError $($_.Exception.Message)
        return "Failed - $($_.Exception.Message)"
    }
}