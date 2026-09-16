function Write-MLRHtmlReport {
    [CmdletBinding()]
    param (
        [Parameter()]
        $InputObject,

        [parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $CustomTitle,

        [parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $CustomOrganization
    )

    $module = ThisModule

    $runDateTime = (Get-Date (@($InputObject)[0].TaskRunDateTime)).ToString("MMMM dd, yyyy hh:mm tt [zzzz]")

    if ($CustomTitle) {
        $reportTitle = "$CustomTitle - $($runDateTime)"
    }
    else {
        $reportTitle = "Microsoft 365 User License Reaper - $($runDateTime)"
    }

    if ($CustomOrganization) {
        $reportOrganization = $CustomOrganization
    }
    else {
        $reportOrganization = (Get-MgOrganization).DisplayName
    }

    $htmlTemplateFile = Join-Path $module.ModuleBase 'source\private\report_template.html'
    $htmlContent = Get-Content -Path $htmlTemplateFile

    $htmlRow = @()
    foreach ($lineItem in $InputObject) {
        $htmlRow += "<tr>"
        $htmlRow += '<td><a href="' + $lineItem.TaskListItemURL + '" target="_blank">' + $lineItem.TaskTicket + '</a>' + '</td>'
        $htmlRow += '<td>' + $lineItem.TaskUsername + '</td>'

        $htmlRow += '<td>'
        $htmlRow += '<table style="border-collapse:collapse; border:none;">'

        if ($lineItem.RemovedAssignedLicenseName) {
            $htmlRow += '<tr>'
            $htmlRow += '<td class="' + ($lineItem.TaskStatusAssignedLicensePostop.ToLower()) + '">' + ($lineItem.TaskResultAssignedLicense -split ' - ')[-1] + '</td>'
            $htmlRow += '</tr>'
        }

        if ($lineItem.RemovedInheritedLicenseName) {
            if ($lineItem.RemovedAssignedLicenseName) {
                $htmlRow += '<tr>'
                $htmlRow += '<td style="border: none;"></td>'
                $htmlRow += '</tr>'
            }
            $htmlRow += '<tr>'
            $htmlRow += '<td class="' + ($lineItem.TaskStatusInheritedLicensePostop.ToLower()) + '">' + ($lineItem.TaskResultInheritedLicense -split ' - ')[-1] + '</td>'
            $htmlRow += '</tr>'
        }

        # if ($lineItem.TaskStatusAssignedLicensePostop -eq 'Canceled') {
        if (-not $lineItem.RemovedInheritedLicenseName -and -not $lineItem.RemovedAssignedLicenseName) {
            $htmlRow += '<tr>'
            $htmlRow += '<td class="' + ($lineItem.TaskStatusAssignedLicensePostop.ToLower()) + '">' + ($lineItem.TaskResultAssignedLicense -split ' - ')[-1] + '</td>'
            $htmlRow += '</tr>'
        }

        $htmlRow += '</table>'
        $htmlRow += '</td>'

        # $htmlRow += '<td class="' + ($lineItem.TaskStatusAssignedLicensePostop.ToLower()) + '">' + $lineItem.TaskResultAssignedLicense + '</td>'
        $htmlRow += '<td class="' + ($lineItem.TaskStatusAssignedLicensePostop.ToLower()) + '">' + $lineItem.TaskResultDetailAssignedLicense + '</td>'
        # $htmlRow += '<td>' + ($lineItem.RemovedAssignedLicenseName -replace ',', ';<br>') + '</td>'

        $htmlRow += '<td>'
        if ($lineItem.RemovedAssignedLicenseName) {
            $htmlRow += '<strong>Individual Assignment:</strong><br>' + ($lineItem.RemovedAssignedLicenseName -replace ',', ';<br>') + '<br><br>'
        }

        if ($lineItem.RemovedInheritedLicenseName) {
            $htmlRow += '<strong>Group Assignment:</strong><br>' + ($lineItem.RemovedInheritedLicenseName -replace ',', ';<br>')
        }

        if (-not $lineItem.RemovedAssignedLicenseName -and -not $lineItem.RemovedInheritedLicenseName) {
            # $htmlRow += '<td></td>'
        }

        $htmlRow += '</td>'

        # if ($lineItem.RemovedAssignedLicenseName) {
        #     $htmlRow += '<td><strong>Individual Assignment:</strong><br>' + ($lineItem.RemovedAssignedLicenseName -replace ',', ';<br>') + '</td>'
        # }
        # else {
        #     $htmlRow += '<td></td>'
        # }

        $htmlRow += '<td>' + $lineItem.TaskCreatedDate.ToString('yyyy-MM-dd') + '</td>'
        $htmlRow += '<td>' + $lineItem.TaskDueDate.ToString('yyyy-MM-dd') + '</td>'
        $htmlRow += '<td>' + $(if ($lineItem.TaskCompletedDate) { $lineItem.TaskCompletedDate.ToString('yyyy-MM-dd HH:mm:ss') }) + '</td>'
        if ($lineItem.TaskCreatedByUserEmail) {
            $htmlRow += '<td>' + "$($lineItem.TaskCreatedByUser) ($($lineItem.TaskCreatedByUserEmail))" + '</td>'
        }
        else {
            $htmlRow += '<td>' + "$($lineItem.TaskCreatedByUser)" + '</td>'
        }

        $htmlRow += "</tr>"
    }

    $htmlContent = $htmlContent -replace `
        "vTableRows", ($htmlRow -join "`n") -replace `
        "vOrganization", $reportOrganization -replace `
        "vReportTitle", $reportTitle -replace `
        "vComputerName", $(hostname) -replace `
        "vModuleInfo", $('<a href="' + $module.ProjectUri + '">' + "$($module.Name) v$($module.Version)" + '</a>')
    ($htmlContent -join "`n")
}