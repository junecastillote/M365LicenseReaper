function Get-MLRM365ProductIdTable {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        ## This is URL path to the the licensing reference table document from GitHub.
        ## The current working URL is the default value.
        ## In case Microsoft moved the document, use this parameter to point to the new URL.
        [parameter()]
        [string]
        $URL = 'https://raw.githubusercontent.com/MicrosoftDocs/entra-docs/main/docs/identity/users/licensing-service-plan-reference.md',

        # Return only the matching SkuId
        [Parameter(ParameterSetName = 'SkuId', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [guid[]]
        $SkuId,

        # Return only the matching SkuPartNumber
        [Parameter(ParameterSetName = 'SkuPartNumber', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $SkuPartNumber,

        ## Force convert license names to title case.
        [parameter()]
        [switch]
        $TitleCase,

        ## Force to download the online version instead of checking table in the current session
        [parameter()]
        [switch]
        $ForceOnline,

        ## Specifiy the list delimiter for ChildServicePlan and ChildServicePlanName.
        ## Default character delimited is comma ","
        [parameter()]
        [string]
        $ListDelimiterCharacter
    )

    function ShowResult {
        $visible_properties = [string[]]@('SkuName', 'SkuPartNumber', 'SkuId')
        [Management.Automation.PSMemberInfo[]]$default_properties = [System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', $visible_properties )
        $Global:mlrSkuTable | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value $default_properties -Force

        switch ($PSCmdlet.ParameterSetName) {
            # -SkuId <GUID>
            SkuId {
                Write-Verbose "Filtering by SkuId"
                foreach ($id in $SkuId) {
                    $Global:mlrSkuTable | Where-Object { $_.SkuId -eq $id }
                }
            }
            # -SkuPartNumber <SKU PART NUMBER>
            SkuPartNumber {
                Write-Verbose "Filtering by SkuPartNumber"
                foreach ($partNumber in $SkuPartNumber) {
                    $Global:mlrSkuTable | Where-Object { $_.SkuPartNumber -eq $partNumber }
                }
            }
            default {
                Write-Verbose "No filtering. Showing all results."
                $Global:mlrSkuTable
            }
        }
    }

    $ErrorActionPreference = 'STOP'

    if ($ForceOnline) { $Global:mlrSkuTable = @() }

    #https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference

    # Check first if the SKU table is already available in the session. This ensures that the script only downloads the online table once per session, unless the -ForceOnline switch is used.
    if ($Global:mlrSkuTable) {
        Write-Verbose "SKU table exists in session..."
        Write-Debug "SKU table exists in session..."
        return ShowResult
    }

    # Continue if the SKU table is not yet in the session
    Write-Verbose "Downloading SKU table online..."
    Write-Debug "Downloading SKU table online..."

    ## Parse the Markdown Table from the $URL
    try {
        $raw_Table = Invoke-RestMethod -Uri $URL -ErrorAction Stop
        $raw_Table = $raw_Table -split "`n"
    }
    catch {
        Write-Output "There was an error getting the licensing reference table at [$URL]. Please make sure that the URL is still valid."
        Write-Output $_.Exception.Message
        return $null
    }

    ## Determine the starting row index of the table
    $startLine = ($raw_Table.IndexOf('| Product name | String ID | GUID | Service plans included | Service plans included (friendly names) |') + 1)

    ## Determine the ending index of the table
    $endLine = ($raw_Table.IndexOf('## Service plans that cannot be assigned at the same time') - 1)

    ## Extract the string in between the lines $startLine and $endLine
    $result = for ($i = $startLine; $i -lt $endLine; $i++) {
        if ($raw_Table[$i] -notlike "*---*") {
            $raw_Table[$i].Substring(1, $raw_Table[$i].Length - 1)
        }
    }

    ## Perform a little clean-up
    ## replace "[space] | [space]" with "|"
    ## replace "[space]<br/>[space]" with ","
    ## replace "((" with "("
    ## replace "))" with ")"
    ## #replace ")[space](" with ")("

    $result = $result `
        -replace '\s*\|\s*', '|' `
        -replace '\s*<br/>\s*', ',' `
        -replace '\(\(', '(' `
        -replace '\)\)', ')' `
        -replace '\)\s*\(', ')('

    # Force title case conversion if -TitleCase is not used.
    if (-not $PSBoundParameters.ContainsKey('TitleCase')) {
        $TitleCase = $true
        Write-Verbose "TitleCase name conversion enabled"
        Write-Verbose "TitleCase name conversion enabled"
    }

    ## Create the result object
    $TextInfo = (Get-Culture).TextInfo

    # Set "," (comma) as the default delimiter character for ChildServicePlan and ChildServicePlanName
    if (-not $ListDelimiterCharacter) { $ListDelimiterCharacter = "," }
    $Global:mlrSkuTable = @($result | ConvertFrom-Csv -Delimiter "|" -Header 'SkuName', 'SkuPartNumber', 'SkuID', 'ChildServicePlan', 'ChildServicePlanName' | ForEach-Object {


            if ($ListDelimiterCharacter -ne ",") {
                $childServicePlan = (([string]$_.ChildServicePlan).Split(",") | Sort-Object) -join $ListDelimiterCharacter
                $childServicePlanName = (([string]$_.ChildServicePlanName).Split(",") | Sort-Object) -join $ListDelimiterCharacter
            }
            else {
                $childServicePlan = $_.ChildServicePlan
                $childServicePlanName = $_.ChildServicePlanName
            }

            [pscustomobject]@{
                SkuName              = if ($TitleCase) { $TextInfo.ToTitleCase($_.SkuName) } else { $_.SkuName }
                SkuPartNumber        = $_.SkuPartNumber
                SkuId                = [guid]$_.SkuId
                ChildServicePlan     = $childServicePlan
                ChildServicePlanName = if ($TitleCase) { $TextInfo.ToTitleCase($childServicePlanName) } else { $childServicePlanName }
            }
        })

    ## return the result
    return ShowResult
}