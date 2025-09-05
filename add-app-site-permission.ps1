<#

NOTE:

This example gives the the Entra ID registered app with Sites.Selected API permission specific to the target SharePoint site.

PREREQUISITES:

1. The Entra ID App's ID (ie. ClientId = 84184c4e-43b5-41f9-b292-c0a9d455e5e8)
2. You must connect to Graph API with scope - Sites.FullControl.All, Application.Read.All
3. You must have Owner access to the target SharePoint site.

#>

[CmdletBinding()]
param (
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [String]
  $SiteUrl,


  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [guid]
  $ClientId,

  # reference: https://learn.microsoft.com/en-us/sharepoint/dev/sp-add-ins-modernize/understanding-rsc-for-msgraph-and-sharepoint-online#granting-permissions-via-microsoft-graph
  [Parameter()]
  [ValidateSet('fullcontrol', 'read', 'write', 'manage')]
  [string]
  $Role = 'fullcontrol'
)

# Get the site name and root host
$siteName = $siteUrl.Split("/")[-1]
$rootSiteHost = $siteUrl.Split("/")[2]

# Get the SP Site Id
try {
  $site = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/sites/$($rootSiteHost):/sites/$($siteName)" -OutputType PSObject -ErrorAction Stop
  $siteId = $site.id
}
catch {
  Write-Error "Error getting the site. Make sure that the URL is corrent and the site exists."
  Write-Error $($_.Exception.Message)
  return $null
}

# Get the application name
try {
  $appName = (Get-MgApplicationByAppId -AppId $clientId -ErrorAction Stop).DisplayName
}
catch {
  Write-Error "Error getting the application. Make sure that the client Id is correct and the app exists."
  Write-Error $($_.Exception.Message)
  return $null
}

$requestBody = [ordered]@{
  roles               = @($Role)
  grantedToIdentities = @(
    @{application = @{
        id          = $ClientId
        displayName = $appName
      }
    }
  )
}

# Add the app's permission to the site.
try {
  # $appPerm = New-MgSitePermission -SiteId $siteId -BodyParameter $jsonBody -ErrorAction Stop
  $appPerm = New-MgSitePermission -SiteId $siteId -BodyParameter ($requestBody | ConvertTo-Json -Depth 3) -ErrorAction Stop
  [PSCustomObject]([ordered]@{
      SitePermissionId = $appPerm.Id
      SitePermission   = $appPerm.Roles -join ", "
      SiteUrl          = $SiteUrl
      GrantedToApp     = "$ClientId,$appName"
    })
}
catch {
  Write-Error "Failed to add / update the site permission."
  Write-Error $($_.Exception.Message)
  return $null
}
