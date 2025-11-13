function Get-MLRUserDueForLicenseRemoval {
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

    $today = (Get-Date)
    $todayUTC = $today.ToUniversalTime()
    $todayUTCDateString = $todayUTC.ToString('yyyy-MM-dd')

    # Get the site name and root host
    $siteName = $siteUrl.Split("/")[-1]
    $rootSiteHost = $siteUrl.Split("/")[2]

    # Get the SP Site Id
    try {
        $site = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/sites/$($rootSiteHost):/sites/$($siteName)" -OutputType PSObject -ErrorAction Stop
        $siteId = $site.Id
    }
    catch {
        SayError "Error getting the site [$($SiteUrl)]."
        SayError "  > Make sure that the URL is correct and the site exists."
        SayError "  > $($_.Exception.Message)"
        return $null
    }

    # Get SP Site list
    try {
        $splist = Get-MgSiteList -SiteId $siteId -ListId $List -ErrorAction Stop
        $listId = $splist.Id
        $listUrl = $splist.WebUrl
    }
    catch {
        SayError "Error getting the list [$List]."
        SayError "  > Make sure that the list name or id is correct and that it exists."
        SayError "  > $($_.Exception.Message)"
        return $null
    }

    $result = [System.Collections.Generic.List[System.Object]]@()

    # Get SP list items
    try {
        <#
            Filter:

            fields/Status = Pending
            AND
            fields/DueDate < or = Date Today in UTC
        #>
        $listItemCollection = @(Get-MgSiteListItem -SiteId $siteId -ListId $listId -ExpandProperty "fields" -Filter "fields/Status eq 'Pending' and fields/DueDate le '$($todayUTCDateString)'" -ErrorAction Stop)
        if ($listItemCollection) {
            foreach ($listItem in $listItemCollection) {
                $fields = New-Object psobject -Property $listItem.fields.additionalProperties
                $result.Add(
                    $(
                        [PSCustomObject]([ordered]@{
                                TaskTicket             = $fields.Title
                                TaskUsername           = $fields.Username
                                TaskDueDate            = (Get-Date $fields.DueDate)
                                TaskStatusPreOp        = $fields.Status
                                TaskCreatedByUser      = $listItem.CreatedBy.User.DisplayName
                                TaskCreatedByUserEmail = $listItem.CreatedBy.User.AdditionalProperties.email
                                TaskCreatedDate        = $fields.Created -as [datetime]
                                TaskCompletedDate      = $fields.CompleteDate
                                TaskSiteUrl            = $SiteUrl
                                TaskSiteId             = $siteId
                                TaskSiteName           = $site.Name
                                TaskListId             = $listId
                                TaskListName           = $splist.Name
                                TaskListUrl            = $listUrl
                                TaskListItemId         = $listItem.id
                                TaskListItemURL        = "$($listUrl)/DispForm.aspx?ID=$($listItem.id)"
                                # TaskLastMessage        = $fields.LastMessage
                            })
                    )
                )
            }
        }
        return $result
    }
    catch {
        SayError "Error getting the items from the list [$($list.DisplayName)]."
        SayError "  > $($_.Exception.Message)"
        return $null
    }
}