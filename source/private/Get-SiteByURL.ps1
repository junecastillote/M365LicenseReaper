function Get-MLRSiteByURL {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $SiteURL
    )

    if (-not (IsMLRGraphConnected)) {
        return $null
    }

    $mgContext = Get-MgContext

    if ($mgContext.AuthType -eq 'Delegated') {
        $loginType = 'User'
        $loginAccount = $mgContext.Account
    }
    else {
        $loginType = 'Application'
        $loginAccount = "$($mgContext.AppName) - $($mgContext.ClientId)"
    }

    # Get the site name and root host
    $siteName = $SiteUrl.Split("/")[-1]
    $rootSiteHost = $SiteUrl.Split("/")[2]

    # Get the SP Site Id
    try {
        $spSite = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/sites/$($rootSiteHost):/sites/$($siteName)" -OutputType PSObject -ErrorAction Stop
        return $spSite
    }
    catch {
        SayError "[$($MyInvocation.MyCommand.Name)]: Error getting the site [$($SiteUrl)]."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > Make sure that the URL is correct and the logged in $($loginType) [$($loginAccount)] has permission to the site."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > $($_.Exception.Message)"
        return $null
    }
}