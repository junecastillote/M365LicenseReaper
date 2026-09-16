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

        [Parameter()]
        [switch]
        $TestMode,

        [Parameter()]
        [switch]
        $PauseBeforeProcessingRemoval
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
    $usersForLicenseRemoval |
    Add-Member `
        -MemberType NoteProperty `
        -Name DirectOperationStatus `
        -Value 'NotApplicable'

    $usersForLicenseRemoval |
    Add-Member `
        -MemberType NoteProperty `
        -Name InheritedOperationStatus `
        -Value 'NotApplicable'

    $usersForLicenseRemoval |
    Add-Member `
        -MemberType NoteProperty `
        -Name PostOperationStatus `
        -Value ''

    $usersForLicenseRemoval |
    Add-Member `
        -MemberType NoteProperty `
        -Name TaskStatusPostOp `
        -Value ''
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
    $postOperationStatusColumnName = (
        $Global:mlrTaskList.Columns.Columns |
        Where-Object {
            $_.DisplayName -eq 'PostOperationStatus'
        }
    ).InternalName

    $counter = 1
    $total = $usersForLicenseRemoval.Count

    if ($PauseBeforeProcessingRemoval) {
        Read-Host -Prompt "Paused. Press any key to continue."
    }

    foreach ($user in $usersForLicenseRemoval) {

        SayInfo "[$($MyInvocation.MyCommand.Name)]: Processing [$($counter)/$($total)] - Ticket: $($user.TaskTicket), Username: $($user.TaskUsername)"

        # --------------------------------------------------
        # Initialize operation results
        # --------------------------------------------------

        $directOperationStatus = 'NotApplicable'
        $inheritedOperationStatus = 'NotApplicable'
        $postOperationStatus = ''
        $taskStatusPostOp = $user.TaskStatusPreOp

        $taskResultAssignedLicense = ''
        $taskResultInheritedLicense = ''

        $taskResultDetailAssignedLicense = ''
        $taskResultDetailInheritedLicense = ''

        $completedDate = $null

        $removeAssignedLicenseResult = $null
        $removeInheritedLicenseResult = $null

        # --------------------------------------------------
        # Determine readiness
        # --------------------------------------------------

        $readinessState = Get-MLRUserAccountState `
            -Username $user.TaskUsername `
            -SkipIfEnabled:$SkipIfEnabled `
            -IncludeInheritedLicense:$IncludeInheritedLicense

        $user.TaskAction = $readinessState.Action

        $user.AssignedLicense = $readinessState.AssignedLicense
        $user.AssignedLicenseName = $readinessState.AssignedLicenseName

        $user.InheritedLicense = $readinessState.InheritedLicense
        $user.InheritedLicenseName = $readinessState.InheritedLicenseName

        # --------------------------------------------------
        # Readiness: no action required
        # --------------------------------------------------

        if ($readinessState.Action -eq 'Cancel') {
            $directOperationStatus = 'NotApplicable'
            $inheritedOperationStatus = 'NotApplicable'

            $postOperationStatus = 'NoActionRequired'
            $taskStatusPostOp = 'Canceled'

            $taskResultAssignedLicense = 'Completed - No action'
            $taskResultDetailAssignedLicense = $readinessState.ReadinessNote

            if (-not $TestMode) {
                $completedDate = (
                    Get-Date
                ).ToUniversalTime().ToString(
                    'yyyy-MM-ddTHH:mm:ssZ'
                )
            }
        }

        # --------------------------------------------------
        # Readiness: temporarily deferred
        # --------------------------------------------------

        elseif ($readinessState.Action -eq 'Skip') {
            $directOperationStatus = 'NotApplicable'
            $inheritedOperationStatus = 'NotApplicable'

            $postOperationStatus = 'Deferred'
            $taskStatusPostOp = 'Pending'

            switch ($readinessState.ActionReason) {
                'Error' {
                    $taskResultAssignedLicense = 'Skipped - Error'
                }

                'Account enabled' {
                    $taskResultAssignedLicense = 'Skipped - Not allowed'
                }

                default {
                    $taskResultAssignedLicense = 'Skipped'
                }
            }

            $taskResultDetailAssignedLicense = $readinessState.ReadinessNote
            $completedDate = $null
        }

        # --------------------------------------------------
        # Readiness: perform license removal
        # --------------------------------------------------

        elseif ($readinessState.Action -eq 'Remove') {

            # ----------------------------------------------
            # Direct license removal
            # ----------------------------------------------

            if ($readinessState.AssignedLicense) {
                $directSkuId = @(
                    $readinessState.AssignedLicense -split ',' |
                    Where-Object {
                        -not[string]::IsNullOrWhiteSpace($_)
                    }
                )

                $removeAssignedLicenseResult =
                Remove-MLRUserLicenseAssignment `
                    -Username $user.TaskUsername `
                    -SkuId $directSkuId `
                    -TestMode:$TestMode

                $directOperationStatus =
                $removeAssignedLicenseResult.Status

                switch ($directOperationStatus) {
                    'Successful' {
                        $taskResultAssignedLicense =
                        'Completed - Direct license removed'

                        $taskResultDetailAssignedLicense =
                        "Direct license removed on $(Get-Date -Format 'yyyy-MM-dd hh:mm:ss tt') ($tzOffsetString)"

                        $user.RemovedAssignedLicense = (
                            $removeAssignedLicenseResult.RemovedLicenseId -join ','
                        )

                        $user.RemovedAssignedLicenseName =
                        $readinessState.AssignedLicenseName
                    }

                    'Simulated' {
                        $taskResultAssignedLicense =
                        'Simulated - Direct license removal'

                        $taskResultDetailAssignedLicense = (
                            $removeAssignedLicenseResult.Note -join '; '
                        )

                        $user.RemovedAssignedLicense = ''
                        $user.RemovedAssignedLicenseName = ''
                    }

                    'Failed' {
                        $taskResultAssignedLicense =
                        'Failed - Direct license removal'

                        $taskResultDetailAssignedLicense = (
                            $removeAssignedLicenseResult.Error -join '; '
                        )

                        $user.RemovedAssignedLicense = ''
                        $user.RemovedAssignedLicenseName = ''
                    }

                    default {
                        $taskResultAssignedLicense =
                        "Failed - Unexpected direct operation status [$directOperationStatus]"

                        $taskResultDetailAssignedLicense =
                        'The direct-removal function returned an unsupported status.'

                        $directOperationStatus = 'Failed'

                        $user.RemovedAssignedLicense = ''
                        $user.RemovedAssignedLicenseName = ''
                    }
                }
            }
            else {
                $directOperationStatus = 'NotApplicable'

                $taskResultAssignedLicense =
                'Not applicable - No direct license assignment'
            }

            # ----------------------------------------------
            # Inherited license removal
            # ----------------------------------------------

            if (
                $IncludeInheritedLicense -and
                $readinessState.InheritedLicense
            ) {
                $licenseGroupIds = @(
                    $readinessState.LicenseGroup -split ',' |
                    Where-Object {
                        -not[string]::IsNullOrWhiteSpace($_)
                    }
                )

                $removeInheritedLicenseResult =
                Remove-MLRUserLicenseInherited `
                    -UserId $readinessState.UserId `
                    -LicenseGroupId $licenseGroupIds `
                    -TestMode:$TestMode

                $inheritedOperationStatus =
                $removeInheritedLicenseResult.Status

                switch ($inheritedOperationStatus) {
                    'Successful' {
                        $taskResultInheritedLicense =
                        'Completed - Inherited license removed'

                        $detailCollection = @()

                        if (
                            $removeInheritedLicenseResult.RemovedGroupName.Count -gt 0
                        ) {
                            $detailCollection += (
                                'Removed membership from group(s): {0}' -f
                                (
                                    $removeInheritedLicenseResult.RemovedGroupName -join ', '
                                )
                            )
                        }

                        if (
                            $removeInheritedLicenseResult.SkippedGroupNotes.Count -gt 0
                        ) {
                            $detailCollection += (
                                $removeInheritedLicenseResult.SkippedGroupNotes -join '; '
                            )
                        }

                        $detailCollection += (
                            "Inherited license removal completed on $(Get-Date -Format 'yyyy-MM-dd hh:mm:ss tt') ($tzOffsetString)"
                        )

                        $taskResultDetailInheritedLicense = (
                            $detailCollection -join ' | '
                        )

                        $user.RemovedInheritedLicense = (
                            $removeInheritedLicenseResult.RemovedLicenseId -join ','
                        )

                        $user.RemovedInheritedLicenseName = (
                            $removeInheritedLicenseResult.RemovedLicenseName -join ','
                        )
                    }

                    'AlreadySatisfied' {
                        $taskResultInheritedLicense =
                        'Completed - Membership already absent'

                        $taskResultDetailInheritedLicense = (
                            $removeInheritedLicenseResult.SkippedGroupNotes -join '; '
                        )

                        $user.RemovedInheritedLicense = ''
                        $user.RemovedInheritedLicenseName = ''
                    }

                    'PartiallySuccessful' {
                        $taskResultInheritedLicense =
                        'Partially completed - Inherited license removal'

                        $detailCollection = @()

                        if (
                            $removeInheritedLicenseResult.RemovedGroupName.Count -gt 0
                        ) {
                            $detailCollection += (
                                'Removed from group(s): {0}' -f
                                (
                                    $removeInheritedLicenseResult.RemovedGroupName -join ', '
                                )
                            )
                        }

                        if (
                            $removeInheritedLicenseResult.SkippedGroupNotes.Count -gt 0
                        ) {
                            $detailCollection += (
                                $removeInheritedLicenseResult.SkippedGroupNotes -join '; '
                            )
                        }

                        if (
                            $removeInheritedLicenseResult.Error.Count -gt 0
                        ) {
                            $detailCollection += (
                                'Error(s): {0}' -f
                                (
                                    $removeInheritedLicenseResult.Error -join '; '
                                )
                            )
                        }

                        $taskResultDetailInheritedLicense = (
                            $detailCollection -join ' | '
                        )

                        $user.RemovedInheritedLicense = (
                            $removeInheritedLicenseResult.RemovedLicenseId -join ','
                        )

                        $user.RemovedInheritedLicenseName = (
                            $removeInheritedLicenseResult.RemovedLicenseName -join ','
                        )
                    }

                    'Simulated' {
                        $taskResultInheritedLicense =
                        'Simulated - Inherited license removal'

                        $detailCollection = @(
                            $removeInheritedLicenseResult.Note
                        )

                        if (
                            $removeInheritedLicenseResult.SimulatedGroupName.Count -gt 0
                        ) {
                            $detailCollection += (
                                'Would remove membership from group(s): {0}' -f
                                (
                                    $removeInheritedLicenseResult.SimulatedGroupName -join ', '
                                )
                            )
                        }

                        if (
                            $removeInheritedLicenseResult.SimulatedLicenseName.Count -gt 0
                        ) {
                            $detailCollection += (
                                'Would remove license(s): {0}' -f
                                (
                                    $removeInheritedLicenseResult.SimulatedLicenseName -join ', '
                                )
                            )
                        }

                        if (
                            $removeInheritedLicenseResult.SkippedGroupNotes.Count -gt 0
                        ) {
                            $detailCollection += (
                                $removeInheritedLicenseResult.SkippedGroupNotes -join '; '
                            )
                        }

                        if (
                            $removeInheritedLicenseResult.Error.Count -gt 0
                        ) {
                            $detailCollection += (
                                'Validation error(s): {0}' -f
                                (
                                    $removeInheritedLicenseResult.Error -join '; '
                                )
                            )
                        }

                        $taskResultDetailInheritedLicense = (
                            $detailCollection -join ' | '
                        )

                        $user.RemovedInheritedLicense = ''
                        $user.RemovedInheritedLicenseName = ''
                    }

                    'Failed' {
                        $taskResultInheritedLicense =
                        'Failed - Inherited license removal'

                        $taskResultDetailInheritedLicense = (
                            $removeInheritedLicenseResult.Error -join '; '
                        )

                        $user.RemovedInheritedLicense = ''
                        $user.RemovedInheritedLicenseName = ''
                    }

                    default {
                        $taskResultInheritedLicense =
                        "Failed - Unexpected inherited operation status [$inheritedOperationStatus]"

                        $taskResultDetailInheritedLicense =
                        'The inherited-removal function returned an unsupported status.'

                        $inheritedOperationStatus = 'Failed'

                        $user.RemovedInheritedLicense = ''
                        $user.RemovedInheritedLicenseName = ''
                    }
                }
            }
            else {
                $inheritedOperationStatus = 'NotApplicable'

                if (-not $IncludeInheritedLicense) {
                    $taskResultInheritedLicense =
                    'Not applicable - Inherited license processing disabled'
                }
                else {
                    $taskResultInheritedLicense =
                    'Not applicable - No inherited license assignment'
                }
            }

            # ----------------------------------------------
            # Aggregate both independent operation results
            # ----------------------------------------------

            $postOperationStatus =
            Resolve-MLRPostOperationStatus `
                -DirectOperationStatus $directOperationStatus `
                -InheritedOperationStatus $inheritedOperationStatus

            switch ($postOperationStatus) {
                'Successful' {
                    $taskStatusPostOp = 'Completed'

                    if (-not $TestMode) {
                        $completedDate = (
                            Get-Date
                        ).ToUniversalTime().ToString(
                            'yyyy-MM-ddTHH:mm:ssZ'
                        )
                    }
                }

                'NoActionRequired' {
                    $taskStatusPostOp = 'Canceled'

                    if (-not $TestMode) {
                        $completedDate = (
                            Get-Date
                        ).ToUniversalTime().ToString(
                            'yyyy-MM-ddTHH:mm:ssZ'
                        )
                    }
                }

                'PartiallySuccessful' {
                    $taskStatusPostOp = 'Pending'
                    $completedDate = $null
                }

                'Failed' {
                    $taskStatusPostOp = 'Pending'
                    $completedDate = $null
                }

                'Simulated' {
                    $taskStatusPostOp = 'Pending'
                    $completedDate = $null
                }

                default {
                    $postOperationStatus = 'Failed'
                    $taskStatusPostOp = 'Pending'
                    $completedDate = $null
                }
            }
        }

        # --------------------------------------------------
        # Store results on the returned task object
        # --------------------------------------------------

        $user.DirectOperationStatus =
        $directOperationStatus

        $user.InheritedOperationStatus =
        $inheritedOperationStatus

        $user.PostOperationStatus =
        $postOperationStatus

        $user.TaskStatusPostOp =
        $taskStatusPostOp

        $user.TaskStatusAssignedLicensePostop =
        $directOperationStatus

        $user.TaskStatusInheritedLicensePostop =
        $inheritedOperationStatus

        $user.TaskResultAssignedLicense =
        $taskResultAssignedLicense

        $user.TaskResultInheritedLicense =
        $taskResultInheritedLicense

        $user.TaskResultDetailAssignedLicense =
        $taskResultDetailAssignedLicense

        $user.TaskResultDetailInheritedLicense =
        $taskResultDetailInheritedLicense

        if ($null -ne $completedDate) {
            $user.TaskCompletedDate = Get-Date $completedDate
        }
        else {
            $user.TaskCompletedDate = $null
        }

        # --------------------------------------------------
        # Build combined operational detail
        # --------------------------------------------------

        $postOperationDetailCollection = @()

        if (
            -not[string]::IsNullOrWhiteSpace(
                $taskResultDetailAssignedLicense
            )
        ) {
            $postOperationDetailCollection += (
                'Direct: {0}' -f
                $taskResultDetailAssignedLicense
            )
        }

        if (
            -not[string]::IsNullOrWhiteSpace(
                $taskResultDetailInheritedLicense
            )
        ) {
            $postOperationDetailCollection += (
                'Inherited: {0}' -f
                $taskResultDetailInheritedLicense
            )
        }

        if ($postOperationDetailCollection.Count -gt 0) {
            $postOperationDetail = (
                $postOperationDetailCollection -join ' | '
            )
        }
        else {
            $postOperationDetail = $readinessState.ReadinessNote
        }

        # --------------------------------------------------
        # Update SharePoint task
        # --------------------------------------------------

        try {
            $fields = @{
                fields = @{
                    'Status'                         = $taskStatusPostOp

                    "$postOperationStatusColumnName" =
                    $postOperationStatus

                    'Notes'                          =
                    $postOperationDetail

                    "$completedDateColumnName"       =
                    $completedDate

                    "$lastMessageColumnName"         =
                    $postOperationDetail
                }
            }

            Write-Debug "Updating SPO List item for $($user.TaskUsername)"

            if (-not $TestMode) {
                $null = Invoke-MgGraphRequest `
                    -Method PATCH `
                    -Uri "https://graph.microsoft.com/v1.0/sites/$($user.TaskSiteId)/lists/$($user.TaskListId)/items/$($user.TaskListItemId)" `
                    -Body $fields `
                    -ContentType 'application/json' `
                    -ErrorAction Stop
            }
        }
        catch {
            SayError $_.Exception.Message

            $sharePointUpdateError = $_.Exception.Message

            $user.PostOperationStatus = 'Failed'
            $user.TaskStatusPostOp = $user.TaskStatusPreOp
            $user.TaskCompletedDate = $null

            if (
                [string]::IsNullOrWhiteSpace(
                    $user.TaskResultDetailAssignedLicense
                )
            ) {
                $user.TaskResultDetailAssignedLicense =
                "SharePoint task update failed: $sharePointUpdateError"
            }
            else {
                $user.TaskResultDetailAssignedLicense = (
                    '{0} | SharePoint task update failed: {1}' -f
                    $user.TaskResultDetailAssignedLicense,
                    $sharePointUpdateError
                )
            }
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
            throw "Send email failed: $($_.Exception.Message)"
        }
    }

    if ($ReturnResult) { $usersForLicenseRemoval }
}