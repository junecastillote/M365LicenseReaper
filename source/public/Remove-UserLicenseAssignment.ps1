function Remove-MLRUserLicenseAssignment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Username,

        [Parameter(Mandatory)]
        [guid[]]
        $SkuId
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
        $null = Set-MgUserLicense -UserId $Username -BodyParameter $params -ErrorAction Stop
        return "Successful"
    }
    catch {
        SayError $($_.Exception.Message)
        return "Failed - $($_.Exception.Message)"
    }
}