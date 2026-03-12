function Deploy-MLRTaskList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteUrl,

        [Parameter()]
        [String]
        $List
    )

    $spSite = Get-MLRSiteByURL -SiteURL $SiteUrl

    if (-not $spSite) {
        return $null
    }

    if (-not $List) { $List = 'M365 License Reaper Schedule' }

    $spList = Get-MLRSiteListByName -SiteURL $SiteUrl -List $List

    if ($spList) {
        SayError "[$($MyInvocation.MyCommand.Name)]: A list with the name [$($List)] already exists. Specify a different list name using the -List parameter."
        return $null
    }

    $params = @{
        displayName = $List
        columns     = @(
            @{
                name     = "Username"
                text     = @{
                    AllowMultipleLines = $false
                }
                required = $true
            }
            @{
                name     = "Due Date"
                datetime = @{
                    displayAs = "standard"
                    format    = "dateOnly"
                }
                indexed  = $true
                required = $true
            }
            @{
                name         = "Status"
                choice       = @{
                    choices        = @(
                        'Pending',
                        'Completed',
                        'Canceled'
                    )
                    AllowTextEntry = $false
                    DisplayAs      = 'dropDownMenu'
                }
                defaultValue = @{
                    value = "Pending"
                }
                indexed      = $true
            }
            @{
                name     = "Completed Date"
                datetime = @{
                    displayAs = "standard"
                    format    = "dateTime"
                }
            }
            @{
                name = "Last Message"
                text = @{
                    AllowMultipleLines = $false
                }
            }
            @{
                name = "Notes"
                text = @{
                    AllowMultipleLines          = $true
                    AppendChangesToExistingText = $true
                    LinesForEditing             = 6
                    TextType                    = 'plain'
                }
            }
        )
    }

    try {
        $newList = New-MgSiteList -SiteId $spSite.id -BodyParameter $params -ErrorAction Stop
        SayInfo "[$($MyInvocation.MyCommand.Name)]: The task list [$($List)] has been created."
    }
    catch {
        SayError "[$($MyInvocation.MyCommand.Name)]: Error creating the list [$List]."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > $($_.Exception.Message)"
        return $null
    }

    try {
        Update-MgSiteListColumn -SiteId $spsite.id -ListId $newList.Id -ColumnDefinitionId "Title" -DisplayName "Ticket" -Indexed:$true -ErrorAction Stop | Out-Null
        $newList = Get-MLRSiteListByName -SiteURL $SiteUrl -List $List -ErrorAction Stop
        return $newList
    }
    catch {
        SayError "[$($MyInvocation.MyCommand.Name)]: Error updating the Title column display name."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > $($_.Exception.Message)"
        return $null
    }
}