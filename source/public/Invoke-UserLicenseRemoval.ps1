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
        $ReturnResult
    )

    Write-Debug "Keys = $($PSBoundParameters.Keys -join ";")"

    # If -SendReportToEmailRecipient is used, validate the email recipient table.
    if ($PSBoundParameters.ContainsKey('SendReportToEmailRecipient')) {
        $emailRecipientTable = Test-RecipientTable $SendReportToEmailRecipient
        if ($emailRecipientTable.IsValid -ne $true) {
            $emailRecipientTable.Errors | ForEach-Object {
                SayError "SendReportToEmailRecipient parameter validation failed."
                SayError "  > $_"
            }
            return $null
        }
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

    # Create the output folder if it doesn't exist.
    if (-not (Test-Path $OutputFolder)) {
        try {
            $null = New-Item -ItemType Directory -Path $OutputFolder -ErrorAction Stop
        }
        catch {
            SayError "Failed to create the output directory [$($OutputFolder)]."
            SayError "  > $($_.Exception.Message)"
            return $null
        }
    }

    $dateNowString = $datenow.ToString('yyyyMMddTHHmmss')
    $csvFileName = "$OutputFolder\M365LicenseReaper_Raw_$($dateNowString).csv"
    $htmlFileName = "$OutputFolder\M365LicenseReaper_Report_$($dateNowString).html"

    SayInfo "Output file will be saved to $($OutputFolder)"

    # Get the task list from the specified SharePoint Online site and list.
    $usersForLicenseRemoval = @(Get-MLRUserDueForLicenseRemoval -SiteUrl $SiteUrl -List $List)
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskRunDateTime -Value $dateNow
    # $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name AssignedLicense -Value @()
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name AssignedLicense -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskAction -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskStatusPostOp -Value ''
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name TaskResult -Value ''
    # $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name RemovedLicense -Value @()
    $usersForLicenseRemoval | Add-Member -MemberType NoteProperty -Name RemovedLicense -Value ''

    $counter = 1
    $total = $usersForLicenseRemoval.Count
    foreach ($user in $usersForLicenseRemoval) {

        SayInfo "Processing [$($counter)/$($total)] - Ticket: $($user.TaskTicket), Username: $($user.TaskUsername)"

        # Initialize vars
        $taskStatusPostOp = ''
        $taskResult = ''
        $completedDate = $null

        # Get the user account's readiness state for license removal
        $readinessState = Get-MLRUserAccountState -Username $user.TaskUsername

        $user.TaskAction = $readinessState.Action
        $user.AssignedLicense = $readinessState.AssignedLicense

        # If readiness action state is 'Cancel'
        if ($readinessState.Action -eq 'Cancel') {
            $taskStatusPostOp = 'Canceled'
            $taskResult = $($readinessState.ReadinessNote)
            $completedDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }

        # If readiness action state is 'Skip'
        if ($readinessState.Action -eq 'Skip') {
            $taskStatusPostOp = 'Pending'
            $taskResult = $($readinessState.ReadinessNote)
            $completedDate = $null
        }

        # If readiness action state is 'Remove'
        if ($readinessState.Action -eq 'Remove') {
            $removeResult = Remove-MLRUserLicenseAssignment -Username $user.TaskUsername -SkuId ($readinessState.AssignedLicense -split ",")
            if ($removeResult -eq 'Successful') {
                $taskStatusPostOp = 'Completed'
                $taskResult = "License removed on $(Get-Date -Format "yyyy-MM-dd hh:mm:ss tt") ($tzOffsetString)"
                $user.RemovedLicense = $readinessState.AssignedLicense
                $completedDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
            else {
                $taskStatusPostOp = $readinessState.TaskStatusPreOp
                $taskResult = $removeResult
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
                    "Status"        = $taskStatusPostOp
                    "Notes"         = $taskResult
                    "CompletedDate" = $completedDate
                    "LastMessage"   = $taskResult
                }
            }

            $null = Invoke-MgGraphRequest `
                -Method PATCH `
                -Uri "https://graph.microsoft.com/v1.0/sites/$($user.TaskSiteId)/lists/$($user.TaskListId)/items/$($user.TaskListItemId)" `
                -Body $fields `
                -ContentType "application/json" `
                -ErrorAction Stop

            $user.TaskResult = $taskResult
            $user.TaskStatusPostOp = $taskStatusPostOp
            $user.TaskCompletedDate = $(if ($completedDate) { (Get-Date $completedDate) })
        }
        catch {
            SayError $_.Exception.Message
            $user.TaskResult = $_.Exception.Message
            $user.TaskStatusPostOp = $readinessState.TaskStatusPreOp
            $user.TaskCompletedDate = $null
        }
        $counter++
    }

    try {
        $usersForLicenseRemoval | Export-Csv -Path $csvFileName -NoTypeInformation -Encoding utf8 -Force -Confirm:$false -ErrorAction Stop
        SayInfo "CSV raw data file saved to $($csvFileName)."
    }
    catch {
        SayError "Failed to save the CSV output file."
        SayError "  > $($_.Exception.Message)"
    }

    try {
        $htmlContent = Write-MLRHtmlReport -InputObject $usersForLicenseRemoval
        $htmlContent | Out-File $htmlFileName -Encoding utf8 -Force -Confirm:$false -ErrorAction Stop
        # $usersForLicenseRemoval | Export-Csv -Path $csvFileName -NoTypeInformation -Encoding utf8 -Force -Confirm:$false
        SayInfo "HTML report file saved to $($htmlFileName)."
    }
    catch {
        SayError "Failed to save the HTML output file."
        SayError "  > $($_.Exception.Message)"
    }

    if ($emailRecipientTable.IsValid) {
        $runDateTime = ($dateNow).ToString("MMMM dd, yyyy hh:mm tt [zzzz]")
        $organizationName = (Get-MgOrganization).DisplayName
        $subject = "[$($organizationName)] Microsoft 365 User License Reaper - $($runDateTime)"

        $mailBody = @{
            message = @{
                subject                = $subject
                body                   = @{
                    content     = $htmlContent
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
                    $(ConvertRecipientsToJSON $SendReportToEmailRecipient.Bcc)
                )
            }
        }

        try {
            Send-MgUserMail -UserId $SendReportToEmailRecipient.From -BodyParameter $mailBody -ErrorAction Stop
        }
        catch {
            SayError "Send email failed: $($_.Exception.Message)"
        }
    }

    if ($ReturnResult) { $usersForLicenseRemoval }
}