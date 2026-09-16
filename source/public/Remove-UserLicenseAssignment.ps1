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

    $result = [ordered]@{
        Username         = $Username
        SkuId            = @($SkuId)
        Status           = ''
        RemovedLicenseId = @()
        Error             = @()
        Note              = @()
        TestMode          = [bool]$TestMode
    }

    $params = @{
        addLicenses    = @()
        removeLicenses = @($SkuId)
    }

    if ($TestMode) {
        $result.Status = 'Simulated'
        $result.Note = @(
            'Test mode. No direct license assignments were removed.'
        )

        return [PSCustomObject]$result
    }

    try {
        $null = Set-MgUserLicense `
            -UserId $Username `
            -BodyParameter $params `
            -ErrorAction Stop

        $result.Status = 'Successful'
        $result.RemovedLicenseId = @($SkuId)
    }
    catch {
        SayError $_.Exception.Message

        $result.Status = 'Failed'
        $result.Error = @(
            $_.Exception.Message
        )
    }

    return [PSCustomObject]$result
}