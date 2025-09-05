function Get-ItemDueForLicenseRemoval {
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

    # $tz = Get-TimeZone
    # $tzOffsetString = $(
    #     if ($tz.BaseUtcOffset.ToString() -notlike "-*") {
    #         "UTC+$($tz.BaseUtcOffset.ToString())"
    #     }
    #     else {
    #         "UTC($tz.BaseUtcOffset.ToString())"
    #     }
    # )

    # Get the site name and root host
    $siteName = $siteUrl.Split("/")[-1]
    $rootSiteHost = $siteUrl.Split("/")[2]

    # Get the SP Site Id
    try {
        $site = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/sites/$($rootSiteHost):/sites/$($siteName)" -OutputType PSObject -ErrorAction Stop
        $siteId = $site.Id
    }
    catch {
        Write-Error "Error getting the site. Make sure that the URL is corrent and the site exists."
        Write-Error $($_.Exception.Message)
        return $null
    }

    # Get SP Site list
    try {
        $list = Get-MgSiteList -SiteId $siteId -ListId $listNameOrId -ErrorAction Stop
        $listId = $list.Id
    }
    catch {
        Write-Error "Error getting the list [$ListNameOrId]. Make sure that the list name or id is corrent and that it exists."
        Write-Error $($_.Exception.Message)
        return $null
    }

    # Get SP list items
    try {
        $listItem = Get-MgSiteListItem -SiteId $siteId -ListId $listId -ExpandProperty "fields" -Filter "fields/Status eq 'Pending'" -ErrorAction Stop
        return $listItem
    }
    catch {
        Write-Error "Error getting the items from the list [$($list.DisplayName)]."
        Write-Error $($_.Exception.Message)
        return $null
    }
}