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

    $Global:mlrTaskList = Test-MLRTaskList -SiteUrl $SiteUrl -List $List

    if ($Global:mlrTaskList.Status -ne 'Passed') {
        SayError "[$($MyInvocation.MyCommand.Name)]: SharePoint Site, List, Columns validation failed."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > $($Global:mlrTaskList.Issues)"
        return $null
    }
    else {
        $site = $Global:mlrTaskList.Site
        $siteId = $Global:mlrTaskList.Site.id
        $spList = $Global:mlrTaskList.List
        $listId = $Global:mlrTaskList.List.Id
        $listUrl = $Global:mlrTaskList.List.WebUrl
        $listColumns = $Global:mlrTaskList.Columns.Columns
        $dueDateColumnName = ($listColumns | Where-Object { $_.DisplayName -eq 'Due Date' }).InternalName
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
        $listItemCollection = @(Get-MgSiteListItem -SiteId $siteId -ListId $listId -ExpandProperty "fields" -Filter "fields/Status eq 'Pending' and fields/$($dueDateColumnName) le '$($todayUTCDateString)'" -ErrorAction Stop)
        if ($listItemCollection) {
            foreach ($listItem in $listItemCollection) {
                $fields = New-Object psobject -Property $listItem.fields.additionalProperties
                $result.Add(
                    $(
                        [PSCustomObject]([ordered]@{
                                TaskTicket             = $fields.Title
                                TaskUsername           = $fields.Username
                                TaskDueDate            = (Get-Date $fields."$($dueDateColumnName)")
                                TaskStatusPreOp        = $fields.Status
                                TaskCreatedByUser      = $listItem.CreatedBy.User.DisplayName
                                TaskCreatedByUserEmail = $listItem.CreatedBy.User.AdditionalProperties.email
                                TaskCreatedDate        = $fields.Created -as [datetime]
                                TaskCompletedDate      = $fields.CompleteDate
                                TaskSiteUrl            = $SiteUrl
                                TaskSiteId             = $siteId
                                TaskSiteName           = $site.Name
                                TaskListId             = $listId
                                TaskListName           = $spList.Name
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
        SayError "[$($MyInvocation.MyCommand.Name)]: Error getting the items from the list [$($spList.DisplayName)]."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > $($_.Exception.Message)"
        return $null
    }
}