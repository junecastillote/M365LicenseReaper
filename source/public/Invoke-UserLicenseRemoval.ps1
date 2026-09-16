function Invoke-MLRUserLicenseRemoval {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteUrl,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $List,

        [Parameter()]
        [hashtable]
        $SendReportToEmailRecipient,

        [Parameter()]
        [string]
        $SendReportToTeamsURL,

        [Parameter()]
        [string]
        $OutputFolder = "$($env:USERPROFILE)\M365LicenseReaper",

        [Parameter()]
        [int]
        $MaxDaysToKeepFiles = 7,

        [parameter()]
        [switch]
        $ReturnResult,

        [Parameter()]
        [switch]
        $SkipIfEnabled,

        [parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $CustomTitle,

        [parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $CustomOrganization,

        [Parameter()]
        [bool]
        $IncludeInheritedLicense = $true,

        # Parameter help description
        [Parameter()]
        [switch]
        $TestMode
    )

    $module = ThisModule
    $moduleString = "|   $($module.Name) v$($module.Version)   |"
    Say "$("=" * $moduleString.Length)"
    Say $moduleString
    Say "$("=" * $moduleString.Length)"

    Write-Debug "Keys = $($PSBoundParameters.Keys -join ";")"

    if ($TestMode) {
        SayWarning "[$($MyInvocation.MyCommand.Name)]: Running in TestMode. No changes will be made to users and list items."
    }

    # Local time zone
    $tz = Get-TimeZone

    # Get the offset string, ie. +08:00:00
    $tzOffsetString = $(
        if ($tz.BaseUtcOffset.ToString() -notlike "-*") {
            "UTC+$($tz.BaseUtcOffset.ToString())"
        }
        else {
            "UTC($tz.BaseUtcOffset.ToString())"
        }
    )

    # Current date
    $dateNow = (Get-Date)

    $runDateTime = ($dateNow).ToString("MMMM dd, yyyy hh:mm tt [zzzz]")

    if ($CustomTitle) {
        $reportTitle = "$CustomTitle"
    }
    else {
        $reportTitle = "Microsoft 365 User License Reaper"
    }

    if ($CustomOrganization) {
        $organizationName = $CustomOrganization
    }
    else {
        $organizationName = (Get-MgOrganization).DisplayName
    }

    $subject = "[$($organizationName)] $reportTitle - $($runDateTime)"


    # If -SendReportToEmailRecipient is used, validate the email recipient table.
    if ($PSBoundParameters.ContainsKey('SendReportToEmailRecipient')) {
        $emailRecipientTable = Test-MLRRecipientTable $SendReportToEmailRecipient
        if ($emailRecipientTable.IsValid -ne $true) {
            SayError "[$($MyInvocation.MyCommand.Name)]: SendReportToEmailRecipient parameter validation failed."
            $emailRecipientTable.Errors | ForEach-Object {
                SayError "[$($MyInvocation.MyCommand.Name)]:   > $_"
            }
            throw "SendReportToEmailRecipient parameter validation failed."
        }
        else {
            # If recipient table is validated, the initialize the message content.

            # Compose the mailbody
            $mailBody = @{
                message = @{
                    subject                = $subject
                    body                   = @{
                        content     = ''
                        contentType = "HTML"
                    }
                    internetMessageHeaders = @(
                        @{
                            name  = "X-Mailer"
                            value = "M365LicenseReaper by june.castillote@gmail.com"
                        }
                    )
                }
            }

            # To recipients
            if ($SendReportToEmailRecipient.To) {
                $mailBody.message += @{
                    toRecipients = @(
                        $(Add-MLREmailRecipient $SendReportToEmailRecipient.To)
                    )
                }
            }

            # Cc recipients
            if ($SendReportToEmailRecipient.Cc) {
                $mailBody.message += @{
                    ccRecipients = @(
                        $(Add-MLREmailRecipient $SendReportToEmailRecipient.Cc)
                    )
                }
            }

            # BCC recipients
            if ($SendReportToEmailRecipient.Bcc) {
                $mailBody.message += @{
                    bccRecipients = @(
                        $(Add-MLREmailRecipient $SendReportToEmailRecipient.Bcc)
                    )
                }
            }
        }
    }

    # Create the output folder if it doesn't exist.
    if (-not (Test-Path $OutputFolder)) {
        try {
            $null = New-Item -ItemType Directory -Path $OutputFolder -ErrorAction Stop
        }
        catch {
            SayError "[$($MyInvocation.MyCommand.Name)]: Failed to create the output directory [$($OutputFolder)]."
            throw $_.Exception.Message
        }
    }

    $OutputFolder = (Resolve-Path $OutputFolder).Path

    $dateNowString = $datenow.ToString('yyyyMMddTHHmmss')
    $csvFileName = "$OutputFolder\M365LicenseReaper_Raw_$($dateNowString).csv"
    $htmlFileName = "$OutputFolder\M365LicenseReaper_Report_$($dateNowString).html"

    SayInfo "[$($MyInvocation.MyCommand.Name)]: Output file will be saved to $($OutputFolder)"

    # Get the task list from the specified SharePoint Online site and list.
    $usersForLicenseRemoval = @(Get-MLRUserDueForLicenseRemoval -SiteUrl $SiteUrl -List $List)

    # If there are no users due for license removal.
    if (-not $usersForLicenseRemoval) {
        SayInfo "[$($MyInvocation.MyCommand.Name)]: There are no users due for license removal."

        $htmlContent = ((Get-Content (Join-Path $module.ModuleBase 'source\private\report_template_no_users.html')) -join "`n")

        $htmlContent = $htmlContent -replace `
            "vOrganization", $organizationName -replace `
            "vReportTitle", $reportTitle -replace `
            "vComputerName", $(hostname) -replace `
            "vModuleInfo", $('<a href="' + $module.ProjectUri + '">' + "$($module.Name) v$($module.Version)" + '</a>')

        $htmlContent | Out-File $htmlFileName -Encoding utf8 -Force -Confirm:$false -ErrorAction Stop

        if ($emailRecipientTable.IsValid) {
            $mailBody.message.body.content = $htmlContent
            try {
                SayInfo "[$($MyInvocation.MyCommand.Name)]: Sending notification to recipients..."
                Send-MgUserMail -UserId $SendReportToEmailRecipient.From -BodyParameter $mailBody -ErrorAction Stop
            }
            catch {
                # If the send email failed, throw a terminating error.
                throw "Send email failed: $($_.Exception.Message)"
            }
        }
        # If there are no users due for license removal, the script ends here, without error.
        return $null
    }

    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskRunDateTime -Value $dateNow
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name AssignedLicense -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name AssignedLicenseName -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name InheritedLicense -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name InheritedLicenseName -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskAction -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskStatusAssignedLicensePostop -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskStatusInheritedLicensePostop -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskResultAssignedLicense -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskResultInheritedLicense -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskResultDetailAssignedLicense -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskResultDetailInheritedLicense -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name RemovedAssignedLicense -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name RemovedAssignedLicenseName -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name RemovedInheritedLicense -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name RemovedInheritedLicenseName -Value ''

    $lastMessageColumnName = ($Global:mlrTaskList.Columns.Columns | Where-Object { $_.DisplayName -eq 'Last Message' }).InternalName
    $completedDateColumnName = ($Global:mlrTaskList.Columns.Columns | Where-Object { $_.DisplayName -eq 'Completed Date' }).InternalName

    $counter = 1
    $total = $usersForLicenseRemoval.Count
    foreach ($user in $usersForLicenseRemoval) {

        SayInfo "[$($MyInvocation.MyCommand.Name)]: Processing [$($counter)/$($total)] - Ticket: $($user.TaskTicket), Username: $($user.TaskUsername)"

        # Initialize vars
        $taskStatusAssignedLicensePostop = ''
        $taskResultAssignedLicense = ''
        $taskResultDetailAssignedLicense = ''
        $taskStatusInheritedLicensePostop = ''
        $taskResultInheritedLicense = ''
        $taskResultDetailInheritedLicense = ''
        $completedDate = $null

        $removeAssignedLicenseResult = ''
        $removeInheritedLicenseResult = ''
        # $readinessState = $null

        # Get the user account's readiness state for license removal
        $readinessState = Get-MLRUserAccountState -Username $user.TaskUsername -SkipIfEnabled:$SkipIfEnabled -IncludeInheritedLicense:$IncludeInheritedLicense

        $user.TaskAction = $readinessState.Action
        $user.AssignedLicense = $readinessState.AssignedLicense
        $user.AssignedLicenseName = $readinessState.AssignedLicenseName

        # If readiness action state is 'Cancel'
        if ($readinessState.Action -eq 'Cancel') {
            $taskStatusAssignedLicensePostop = 'Canceled'
            $taskResultAssignedLicense = "Completed - No action"
            # $taskResultDetail = $($readinessState.ReadinessNote)
            $completedDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }

        # If readiness action state is 'Skip'
        if ($readinessState.Action -eq 'Skip') {
            $taskStatusAssignedLicensePostop = 'Pending'

            switch ($readinessState.ActionReason) {
                'Error' { $taskResultAssignedLicense = 'Skipped - Error' }
                'Account enabled' { $taskResultAssignedLicense = 'Skipped - Not allowed' }
                default { $taskResultAssignedLicense = 'Skipped' }
            }

            # $taskResultDetail = $($readinessState.ReadinessNote)
            $completedDate = $null
        }

        # If readiness action state is 'Remove'
        if ($readinessState.Action -eq 'Remove') {
            if ($readinessState.AssignedLicense) {
                $removeAssignedLicenseResult = Remove-MLRUserLicenseAssignment -Username $user.TaskUsername -SkuId ($readinessState.AssignedLicense -split ",") -TestMode:$TestMode
                if ($removeAssignedLicenseResult -eq 'Successful') {
                    $taskStatusAssignedLicensePostop = 'Completed'
                    $taskResultAssignedLicense = "Completed - Direct license removed"
                    $taskResultDetailAssignedLicense = "Direct license removed on $(Get-Date -Format "yyyy-MM-dd hh:mm:ss tt") ($tzOffsetString)"
                    $user.RemovedAssignedLicense = $readinessState.AssignedLicense
                    $user.RemovedAssignedLicenseName = $readinessState.AssignedLicenseName
                    $completedDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                else {
                    $taskStatusAssignedLicensePostop = $readinessState.TaskStatusPreOp
                    $taskResultAssignedLicense = "Failed - Error"
                    $taskResultDetailAssignedLicense = $removeAssignedLicenseResult -replace "Failed - ", ""
                    $user.RemovedAssignedLicense = ""
                    $user.RemovedAssignedLicenseName = ""
                    $completedDate = $null
                }
            }
            if ($IncludeInheritedLicense -and $readinessState.InheritedLicense) {
                $user.InheritedLicense = $readinessState.InheritedLicense -join ","
                $user.InheritedLicenseName = $readinessState.InheritedLicenseName -join ","
                $licenseIds = $readinessState.LicenseGroup -split ","
                $removeInheritedLicenseResult = Remove-MLRUserLicenseInherited -UserId $readinessState.UserId -LicenseGroupId $licenseIds -TestMode:$TestMode
                if ($removeInheritedLicenseResult.Status -eq 'Successful') {
                    $taskStatusInheritedLicensePostop = 'Completed'
                    $taskResultInheritedLicense = "Completed - Inherited license removed"
                    $taskResultDetailInheritedLicense = "Inherited license removed on $(Get-Date -Format "yyyy-MM-dd hh:mm:ss tt") ($tzOffsetString)"
                    $user.RemovedInheritedLicense = $removeInheritedLicenseResult.RemovedLicenseId -join ","
                    $user.RemovedInheritedLicenseName = $removeInheritedLicenseResult.RemovedLicenseName -join ","
                    $completedDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                elseif ($removeInheritedLicenseResult.Status -eq 'Skipped') {
                    $taskStatusInheritedLicensePostop = 'Completed'
                    $taskResultInheritedLicense = "Completed - Skipped (see details)"
                    $taskResultDetailInheritedLicense = ($removeInheritedLicenseResult.SkippedGroupNotes -join ",")
                    $user.RemovedInheritedLicense = ""
                    $user.RemovedInheritedLicenseName = ""
                    $completedDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                else {
                    # $taskStatusInheritedLicensePostop = $removeInheritedLicenseResult.Status
                    $taskStatusInheritedLicensePostop = $readinessState.TaskStatusPreOp
                    $taskResultInheritedLicense = "Failed - (see details)"
                    $taskResultDetailInheritedLicense = ($removeInheritedLicenseResult.Error -join ",")
                    $user.RemovedInheritedLicense = ""
                    $user.RemovedInheritedLicenseName = ""
                    $completedDate = $null
                }
            }
        }

        try {
            <#
            - As of 2025-09-07, Update-MgSiteListItem and Update-MgSiteListItemField cannot update a DATE field to null value.
            - Reference - https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/2724
            - Microsoft closed the issue without it being resolved.
            - As a workaround, used Invoke-MgGraphRequest to update the fields.
            #>

            $fields = @{
                fields = @{
                    "Status"                      = $taskStatusAssignedLicensePostop
                    "Notes"                       = $taskResultDetailAssignedLicense
                    "$($completedDateColumnName)" = $completedDate
                    "$($lastMessageColumnName)"   = $taskResultDetailAssignedLicense
                }
            }

            Write-Debug "Updating SPO List item for $($user.TaskUsername)"
            if (-not $TestMode) {
                $null = Invoke-MgGraphRequest `
                    -Method PATCH `
                    -Uri "https://graph.microsoft.com/v1.0/sites/$($user.TaskSiteId)/lists/$($user.TaskListId)/items/$($user.TaskListItemId)" `
                    -Body $fields `
                    -ContentType "application/json" `
                    -ErrorAction Stop
            }
            $user.TaskResultAssignedLicense = $taskResultAssignedLicense
            $user.TaskResultDetailAssignedLicense = $(if ($readinessState.Action -ne 'Remove') { $readinessState.ReadinessNote } else { $taskResultDetailAssignedLicense })
            $user.TaskStatusAssignedLicensePostop = $taskStatusAssignedLicensePostop
            $user.TaskStatusInheritedLicensePostop = $taskStatusInheritedLicensePostop
            $user.TaskResultInheritedLicense = $TaskResultInheritedLicense
            $user.TaskResultDetailInheritedLicense = $taskResultDetailInheritedLicense
            $user.TaskCompletedDate = $(if ($null -ne $completedDate) { (Get-Date $completedDate) })
        }
        catch {
            SayError $_.Exception.Message
            $user.TaskResultAssignedLicense = 'Failed - Error'
            $user.TaskResultDetailAssignedLicense = $_.Exception.Message
            $user.TaskStatusAssignedLicensePostop = $readinessState.TaskStatusPreOp
            $user.TaskCompletedDate = $null
        }
        $counter++
    }

    try {
        $usersForLicenseRemoval | Export-Csv -Path $csvFileName -NoTypeInformation -Encoding utf8 -Force -Confirm:$false -ErrorAction Stop
        SayInfo "[$($MyInvocation.MyCommand.Name)]: CSV raw data file saved to $($csvFileName)."
    }
    catch {
        SayError "[$($MyInvocation.MyCommand.Name)]: Failed to save the CSV output file."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > $($_.Exception.Message)"
        # NOTE: Failure to save the CSV file is a non-terminating error and the script continues.
    }

    try {

        $htmlContent = Write-MLRHtmlReport -InputObject $usersForLicenseRemoval -CustomTitle $reportTitle -CustomOrganization $organizationName
        Start-Sleep -Seconds 1
        if (-not $htmlContent) {
            SayWarning "HTML content failed to generate."
        }
        else {
            $htmlContent | Out-File $htmlFileName -Encoding utf8 -Force -Confirm:$false -ErrorAction Stop
            # $usersForLicenseRemoval | Export-Csv -Path $csvFileName -NoTypeInformation -Encoding utf8 -Force -Confirm:$false
            SayInfo "[$($MyInvocation.MyCommand.Name)]: HTML report file saved to $($htmlFileName)."
        }
    }
    catch {
        SayError "[$($MyInvocation.MyCommand.Name)]: Failed to save the HTML output file."
        SayError "[$($MyInvocation.MyCommand.Name)]:   > $($_.Exception.Message)"
        # NOTE: Failure to save the HTML file is a non-terminating error and the script continues.
    }

    if ($emailRecipientTable.IsValid) {
        $mailBody.message.body.content = $htmlContent
        try {
            SayInfo "[$($MyInvocation.MyCommand.Name)]: Sending report to recipients..."
            Send-MgUserMail -UserId $SendReportToEmailRecipient.From -BodyParameter $mailBody -ErrorAction Stop
        }
        catch {
            # SayError "[$($MyInvocation.MyCommand.Name)]: Send email failed: $($_.Exception.Message)"
            throw "Send email failed: $($_.Exception.Message)"
        }
    }

    if ($ReturnResult) { $usersForLicenseRemoval }
}