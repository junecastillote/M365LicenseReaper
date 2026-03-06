function Test-MLRTaskList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteUrl,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $List
    )

    $result = [ordered]@{
        Site    = $null
        List    = $null
        Columns = $null
        Status  = 'Failed'
        Issues  = @()
    }

    $issues = @()


    # Get the site name and root host
    $siteName = $SiteUrl.Split("/")[-1]
    $rootSiteHost = $SiteUrl.Split("/")[2]

    # Get the SP Site Id
    try {
        $spSite = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/sites/$($rootSiteHost):/sites/$($siteName)" -OutputType PSObject -ErrorAction Stop
        $spSiteId = $spSite.Id
        $result.Site = $spSite
    }
    catch {
        SayError "[$($MyInvocation.MyCommand.Name)]: Error getting the site [$($SiteUrl)]."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > Make sure that the URL is correct, the site exists, and permission is added."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > $($_.Exception.Message)"
        $result.Issues = "Site Check: $($_.Exception.Message)"
        return [pscustomobject]$result
    }

    # Get SP Site list
    try {
        $splist = Get-MgSiteList -SiteId $spSiteId -ListId $List -ErrorAction Stop
        $listId = $splist.Id
        $result.List = $splist
    }
    catch {
        SayError "[$($MyInvocation.MyCommand.Name)]: Error getting the list [$List]."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > Make sure that the list name or id is correct and that it exists."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > $($_.Exception.Message)"
        $result.Issues = "List Check: $($_.Exception.Message)"
        return [pscustomobject]$result
    }

    # Get columns
    try {
        $listColumns = Get-MgSiteListColumn -SiteId $spSiteId -ListId $listId -ErrorAction Stop
    }
    catch {
        SayError "[$($MyInvocation.MyCommand.Name)]: Error getting the column collection."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > $($_.Exception.Message)"
        $result.Issues = "Column Check: $($_.Exception.Message)"
        return [pscustomobject]$result
    }

    $schemaTest = Test-MLRSPListSchemaCompliance -ListColumns $listColumns -Detailed
    $result.Columns = $schemaTest
    if ($schemaTest.OverallStatus -ne 'NonCompliant') {
        $result.Status = 'Passed'
    }
    else {
        $schemaTest.Columns | Where-Object { $_.Status -ne 'OK' } | ForEach-Object {
            $issues += $(
                "Column Check: [$($_.Column)] $($_.Details)"
            )
        }
        $result.Issues += $issues
    }
    return [pscustomobject]$result
}