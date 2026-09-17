function Write-MLRHtmlReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]
        $InputObject,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $CustomTitle,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $CustomOrganization
    )

    # --------------------------------------------------
    # Local helper: HTML-encode dynamic text
    # --------------------------------------------------

    function ConvertTo-MLRHtmlEncodedText {
        param (
            [Parameter()]
            [AllowNull()]
            [AllowEmptyString()]
            [object]
            $Value
        )

        if ($null -eq $Value) {
            return ''
        }

        return [System.Net.WebUtility]::HtmlEncode(
            [string]$Value
        )
    }

    # --------------------------------------------------
    # Local helper: convert status to friendly text
    # --------------------------------------------------

    function ConvertTo-MLRStatusDisplayText {
        param (
            [Parameter()]
            [AllowNull()]
            [AllowEmptyString()]
            [string]
            $Status
        )

        switch ($Status) {
            'Successful' {
                return 'Successful'
            }

            'AlreadySatisfied' {
                return 'Already satisfied'
            }

            'PartiallySuccessful' {
                return 'Partially successful'
            }

            'Failed' {
                return 'Failed'
            }

            'Simulated' {
                return 'Simulated'
            }

            'NotApplicable' {
                return 'Not applicable'
            }

            'NoActionRequired' {
                return 'No action required'
            }

            'Deferred' {
                return 'Deferred'
            }

            'Pending' {
                return 'Pending'
            }

            'Completed' {
                return 'Completed'
            }

            'Canceled' {
                return 'Canceled'
            }

            default {
                if ([string]::IsNullOrWhiteSpace($Status)) {
                    return 'Not available'
                }

                return $Status
            }
        }
    }

    # --------------------------------------------------
    # Local helper: map status to a CSS class
    # --------------------------------------------------

    function Get-MLRStatusCssClass {
        param (
            [Parameter()]
            [AllowNull()]
            [AllowEmptyString()]
            [string]
            $Status
        )

        switch ($Status) {
            'Successful' {
                return 'status-success'
            }

            'AlreadySatisfied' {
                return 'status-success'
            }

            'Completed' {
                return 'status-success'
            }

            'PartiallySuccessful' {
                return 'status-warning'
            }

            'Failed' {
                return 'status-failed'
            }

            'Deferred' {
                return 'status-pending'
            }

            'Pending' {
                return 'status-pending'
            }

            'Simulated' {
                return 'status-simulated'
            }

            'Canceled' {
                return 'status-neutral'
            }

            'NoActionRequired' {
                return 'status-neutral'
            }

            'NotApplicable' {
                return 'status-neutral'
            }

            default {
                return 'status-neutral'
            }
        }
    }

    # --------------------------------------------------
    # Initialize report information
    # --------------------------------------------------

    $module = ThisModule

    $firstInputObject = @($InputObject)[0]

    $runDateTime = (
        Get-Date $firstInputObject.TaskRunDateTime
    ).ToString(
        'MMMM dd, yyyy hh:mm tt [zzzz]'
    )

    if ($CustomTitle) {
        $reportTitle = "$CustomTitle - $runDateTime"
    }
    else {
        $reportTitle =
        "Microsoft 365 User License Reaper - $runDateTime"
    }

    if ($CustomOrganization) {
        $reportOrganization = $CustomOrganization
    }
    else {
        $reportOrganization = (
            Get-MgOrganization
        ).DisplayName
    }

    $htmlTemplateFile = Join-Path `
        -Path $module.ModuleBase `
        -ChildPath 'source\private\report_template.html'

    $htmlContent = Get-Content `
        -Path $htmlTemplateFile

    $htmlRowCollection = @()

    # --------------------------------------------------
    # Generate one report row per task
    # --------------------------------------------------

    foreach ($lineItem in $InputObject) {
        $htmlRowCollection += '<tr>'

        # ----------------------------------------------
        # Ticket
        # ----------------------------------------------

        $ticketHtml = ConvertTo-MLRHtmlEncodedText `
            -Value $lineItem.TaskTicket

        $ticketUrlHtml = ConvertTo-MLRHtmlEncodedText `
            -Value $lineItem.TaskListItemURL

        $htmlRowCollection += (
            '<td><a href="{0}">{1}</a></td>' -f
            $ticketUrlHtml,
            $ticketHtml
        )

        # ----------------------------------------------
        # Username
        # ----------------------------------------------

        $usernameHtml = ConvertTo-MLRHtmlEncodedText `
            -Value $lineItem.TaskUsername

        $htmlRowCollection += (
            '<td>{0}</td>' -f
            $usernameHtml
        )

        # ----------------------------------------------
        # Result
        # ----------------------------------------------

        # $htmlRowCollection += '<td>'

        # $htmlRowCollection += (
        #     '<table class="result-table" role="presentation" cellpadding="0" cellspacing="0" border="0">'
        # )

        $htmlRowCollection += (
            '<td class="result-column" width="220" style="width:220px;">'
        )

        $htmlRowCollection += (
            '<table class="result-table" role="presentation" width="210" cellpadding="0" cellspacing="0" border="0" style="width:210px;border-collapse:collapse;">'
        )

        # Task lifecycle status

        $taskStatusDisplay = ConvertTo-MLRStatusDisplayText `
            -Status $lineItem.TaskStatusPostOp

        $taskStatusDisplayHtml = ConvertTo-MLRHtmlEncodedText `
            -Value $taskStatusDisplay

        $taskStatusCssClass = Get-MLRStatusCssClass `
            -Status $lineItem.TaskStatusPostOp

        $htmlRowCollection += '<tr>'

        $htmlRowCollection += (
            '<td class="result-label">Task:</td>'
        )

        $htmlRowCollection += (
            '<td class="{0}">{1}</td>' -f
            $taskStatusCssClass,
            $taskStatusDisplayHtml
        )

        $htmlRowCollection += '</tr>'

        # Overall post-operation status

        $postOperationStatusDisplay =
        ConvertTo-MLRStatusDisplayText `
            -Status $lineItem.PostOperationStatus

        $postOperationStatusDisplayHtml =
        ConvertTo-MLRHtmlEncodedText `
            -Value $postOperationStatusDisplay

        $postOperationStatusCssClass =
        Get-MLRStatusCssClass `
            -Status $lineItem.PostOperationStatus

        $htmlRowCollection += '<tr>'

        $htmlRowCollection += (
            '<td class="result-label">Outcome:</td>'
        )

        $htmlRowCollection += (
            '<td class="{0}">{1}</td>' -f
            $postOperationStatusCssClass,
            $postOperationStatusDisplayHtml
        )

        $htmlRowCollection += '</tr>'

        # Direct operation status
        $showDirectStatus = $false

        if (
            $lineItem.DirectOperationStatus -and
            $lineItem.DirectOperationStatus -ne 'NotApplicable'
        ) {
            if (
                $lineItem.DirectOperationStatus -ne $lineItem.PostOperationStatus
            ) {
                $showDirectStatus = $true
            }

            if (
                $lineItem.DirectOperationStatus -in @(
                    'Failed',
                    'PartiallySuccessful',
                    'AlreadySatisfied'
                )
            ) {
                $showDirectStatus = $true
            }
        }

        if ($showDirectStatus) {
            $directStatusDisplay =
            ConvertTo-MLRStatusDisplayText `
                -Status $lineItem.DirectOperationStatus

            $directStatusDisplayHtml =
            ConvertTo-MLRHtmlEncodedText `
                -Value $directStatusDisplay

            $directStatusCssClass =
            Get-MLRStatusCssClass `
                -Status $lineItem.DirectOperationStatus

            $htmlRowCollection += '<tr>'

            $htmlRowCollection += (
                '<td class="result-label">Direct:</td>'
            )

            $htmlRowCollection += (
                '<td class="{0}">{1}</td>' -f
                $directStatusCssClass,
                $directStatusDisplayHtml
            )

            $htmlRowCollection += '</tr>'
        }

        # Inherited operation status

        $showGroupStatus = $false

        if (
            $lineItem.InheritedOperationStatus -and
            $lineItem.InheritedOperationStatus -ne 'NotApplicable'
        ) {
            if (
                $lineItem.InheritedOperationStatus -ne $lineItem.PostOperationStatus
            ) {
                $showGroupStatus = $true
            }

            if (
                $lineItem.InheritedOperationStatus -in @(
                    'Failed',
                    'PartiallySuccessful',
                    'AlreadySatisfied'
                )
            ) {
                $showGroupStatus = $true
            }
        }

        if ($showGroupStatus) {
            $inheritedStatusDisplay =
            ConvertTo-MLRStatusDisplayText `
                -Status $lineItem.InheritedOperationStatus

            $inheritedStatusDisplayHtml =
            ConvertTo-MLRHtmlEncodedText `
                -Value $inheritedStatusDisplay

            $inheritedStatusCssClass =
            Get-MLRStatusCssClass `
                -Status $lineItem.InheritedOperationStatus

            $htmlRowCollection += '<tr>'

            $htmlRowCollection += (
                '<td class="result-label">Group:</td>'
            )

            $htmlRowCollection += (
                '<td class="{0}">{1}</td>' -f
                $inheritedStatusCssClass,
                $inheritedStatusDisplayHtml
            )

            $htmlRowCollection += '</tr>'
        }

        $htmlRowCollection += '</table>'
        $htmlRowCollection += '</td>'

        # ----------------------------------------------
        # Details
        # ----------------------------------------------

        $htmlRowCollection += '<td>'

        $detailSectionCount = 0

        if (
            -not[string]::IsNullOrWhiteSpace(
                $lineItem.TaskResultDetailAssignedLicense
            )
        ) {
            # $directDetailHtml = ConvertTo-MLRHtmlEncodedText `
            #     -Value $lineItem.TaskResultDetailAssignedLicense

            $detailList = (($lineItem.TaskResultDetailAssignedLicense).Split('|').Trim() |
                ForEach-Object {
                    "<li>$(ConvertTo-MLRHtmlEncodedText -Value $_)</li>"
                })

            $directDetailHtml = "<ul>$($detailList -join "`n")</ul>"

            $htmlRowCollection += (
                '<div class="detail-section"><strong>Direct assignment:</strong><br>{0}</div>' -f
                $directDetailHtml
            )

            $detailSectionCount++
        }

        if (
            -not[string]::IsNullOrWhiteSpace(
                $lineItem.TaskResultDetailInheritedLicense
            )
        ) {
            # $inheritedDetailHtml = ConvertTo-MLRHtmlEncodedText `
            #     -Value $lineItem.TaskResultDetailInheritedLicense

            $detailList = (($lineItem.TaskResultDetailInheritedLicense).Split('|').Trim() |
                ForEach-Object {
                    "<li>$(ConvertTo-MLRHtmlEncodedText -Value $_)</li>"
                })

            $inheritedDetailHtml = "<ul>$($detailList -join "`n")</ul>"

            if ($detailSectionCount -gt 0) {
                $htmlRowCollection += (
                    '<div class="detail-separator">&nbsp;</div>'
                )
            }

            $htmlRowCollection += (
                '<div class="detail-section"><strong>Group assignment:</strong><br>{0}</div>' -f
                $inheritedDetailHtml
            )

            $detailSectionCount++
        }

        if ($detailSectionCount -eq 0) {
            $htmlRowCollection += '&nbsp;'
        }

        $htmlRowCollection += '</td>'

        # ----------------------------------------------
        # Removed license list
        # ----------------------------------------------

        $htmlRowCollection += '<td>'

        $removedLicenseSectionCount = 0

        if (
            -not[string]::IsNullOrWhiteSpace(
                $lineItem.RemovedAssignedLicenseName
            )
        ) {
            $directLicenseNameCollection = @(
                $lineItem.RemovedAssignedLicenseName -split ',' |
                Where-Object {
                    -not[string]::IsNullOrWhiteSpace($_)
                }
            )

            $directLicenseHtmlCollection = @(
                $directLicenseNameCollection |
                ForEach-Object {
                    # ConvertTo-MLRHtmlEncodedText -Value $_.Trim()
                    "<li>$(ConvertTo-MLRHtmlEncodedText -Value $_.Trim())</li>"
                }
            )

            $htmlRowCollection += (
                '<div class="license-section"><strong>Direct assignment removed:</strong><br>{0}</div>' -f
                (
                    # $directLicenseHtmlCollection -join ';<br>'
                    "<ul>$($directLicenseHtmlCollection -join "`n")</ul>"
                )
            )

            $removedLicenseSectionCount++
        }

        if (
            -not [string]::IsNullOrWhiteSpace(
                $lineItem.RemovedInheritedLicenseName
            )
        ) {
            $inheritedLicenseNameCollection = @(
                $lineItem.RemovedInheritedLicenseName -split ',' |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                }
            )

            $inheritedLicenseHtmlCollection = @(
                $inheritedLicenseNameCollection |
                ForEach-Object {
                    # ConvertTo-MLRHtmlEncodedText -Value $_.Trim()
                    "<li>$(ConvertTo-MLRHtmlEncodedText -Value $_.Trim())</li>"
                }
            )

            if ($removedLicenseSectionCount -gt 0) {
                $htmlRowCollection += (
                    '<div class="detail-separator">&nbsp;</div>'
                )
            }

            $htmlRowCollection += (
                '<div class="license-section"><strong>Group assignment removed:</strong><br>{0}</div>' -f
                (
                    # $inheritedLicenseHtmlCollection -join ';<br>'
                    "<ul>$($inheritedLicenseHtmlCollection -join "`n")</ul>"
                )
            )

            $removedLicenseSectionCount++
        }

        if (
            $lineItem.InheritedOperationStatus -eq 'AlreadySatisfied' -and
            -not [string]::IsNullOrWhiteSpace(
                $lineItem.InheritedLicenseName
            )
        ) {
            $alreadySatisfiedLicenseNameCollection = @(
                $lineItem.InheritedLicenseName -split ',' |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                }
            )

            $alreadySatisfiedLicenseHtmlCollection = @(
                $alreadySatisfiedLicenseNameCollection |
                ForEach-Object {
                    ConvertTo-MLRHtmlEncodedText `
                        -Value $_.Trim()
                }
            )

            if ($removedLicenseSectionCount -gt 0) {
                $htmlRowCollection += (
                    '<div class="detail-separator">&nbsp;</div>'
                )
            }

            $htmlRowCollection += (
                '<div class="license-section"><strong>Group assignment already absent:</strong><br>{0}</div>' -f
                (
                    $alreadySatisfiedLicenseHtmlCollection -join ';<br>'
                )
            )

            $removedLicenseSectionCount++
        }

        if ($removedLicenseSectionCount -eq 0) {
            $htmlRowCollection += '&nbsp;'
        }

        $htmlRowCollection += '</td>'

        # ----------------------------------------------
        # Created date
        # ----------------------------------------------

        $createdDateHtml = ''

        if ($lineItem.TaskCreatedDate) {
            $createdDateHtml = ConvertTo-MLRHtmlEncodedText `
                -Value $lineItem.TaskCreatedDate.ToString(
                'yyyy-MM-dd'
            )
        }

        $htmlRowCollection += (
            '<td>{0}</td>' -f
            $createdDateHtml
        )

        # ----------------------------------------------
        # Due date
        # ----------------------------------------------

        $dueDateHtml = ''

        if ($lineItem.TaskDueDate) {
            $dueDateHtml = ConvertTo-MLRHtmlEncodedText `
                -Value $lineItem.TaskDueDate.ToString(
                'yyyy-MM-dd'
            )
        }

        $htmlRowCollection += (
            '<td>{0}</td>' -f
            $dueDateHtml
        )

        # ----------------------------------------------
        # Completed date
        # ----------------------------------------------

        $completedDateHtml = ''

        if ($lineItem.TaskCompletedDate) {
            $completedDateHtml = ConvertTo-MLRHtmlEncodedText `
                -Value $lineItem.TaskCompletedDate.ToString(
                'yyyy-MM-dd HH:mm:ss'
            )
        }

        $htmlRowCollection += (
            '<td>{0}</td>' -f
            $completedDateHtml
        )

        # ----------------------------------------------
        # Task owner
        # ----------------------------------------------

        $taskOwnerNameHtml = ConvertTo-MLRHtmlEncodedText `
            -Value $lineItem.TaskCreatedByUser

        if ($lineItem.TaskCreatedByUserEmail) {
            $taskOwnerEmailHtml = ConvertTo-MLRHtmlEncodedText `
                -Value $lineItem.TaskCreatedByUserEmail

            $taskOwnerHtml = '{0} ({1})' -f
            $taskOwnerNameHtml,
            $taskOwnerEmailHtml
        }
        else {
            $taskOwnerHtml = $taskOwnerNameHtml
        }

        $htmlRowCollection += (
            '<td>{0}</td>' -f
            $taskOwnerHtml
        )

        $htmlRowCollection += '</tr>'
    }

    # --------------------------------------------------
    # Replace template placeholders
    # --------------------------------------------------

    $reportOrganizationHtml =
    ConvertTo-MLRHtmlEncodedText `
        -Value $reportOrganization

    $reportTitleHtml =
    ConvertTo-MLRHtmlEncodedText `
        -Value $reportTitle

    $computerNameHtml =
    ConvertTo-MLRHtmlEncodedText `
        -Value $(hostname)

    $moduleNameHtml =
    ConvertTo-MLRHtmlEncodedText `
        -Value "$($module.Name) v$($module.Version)"

    $moduleProjectUriHtml =
    ConvertTo-MLRHtmlEncodedText `
        -Value $module.ProjectUri

    $moduleInfoHtml = (
        '<a href="{0}">{1}</a>' -f
        $moduleProjectUriHtml,
        $moduleNameHtml
    )

    $htmlContent = $htmlContent -replace `
        'vTableRows', ($htmlRowCollection -join "`n") -replace `
        'vOrganization', $reportOrganizationHtml -replace `
        'vReportTitle', $reportTitleHtml -replace `
        'vComputerName', $computerNameHtml -replace `
        'vModuleInfo', $moduleInfoHtml -replace `
        'vPsHostInfo', $PSVersionTable.PSVersion.ToString()

    return (
        $htmlContent -join "`n"
    )
}