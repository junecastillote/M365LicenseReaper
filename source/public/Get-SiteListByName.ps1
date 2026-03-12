function Get-MLRSiteListByName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $SiteURL,

        [Parameter(Mandatory)]
        [string]
        $List
    )

    if (-not (IsMLRGraphConnected)) {
        return $null
    }

    $spSite = Get-MLRSiteByURL -SiteURL $SiteURL
    if (-not $spSite) {
        return $null
    }

    try {
        $splist = Get-MgSiteList -SiteId $spSite.Id -ListId $List -ErrorAction Stop
        return $splist
    }
    catch {
        if ($_.Exception.Message -like "*itemNotFound*") {
            # do nothing, means the list does not exist.
        }
        else {
            SayError "[$($MyInvocation.MyCommand.Name)]: Error getting the list [$List]."
            SayError "[$($MyInvocation.MyCommand.Name)]:   > Make sure that the list name or id is correct and that it exists."
            SayError "[$($MyInvocation.MyCommand.Name)]:   > $($_.Exception.Message)"
        }
        return $null
    }
}