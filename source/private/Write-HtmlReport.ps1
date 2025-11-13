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

    $htmlTemplateFile = Join-Path $module.ModuleBase 'source' 'private' 'report_template.html'
    $htmlContent = Get-Content -Path $htmlTemplateFile

    $htmlRow = @()
    foreach ($lineItem in $InputObject) {
        $htmlRow += "<tr>"
        $htmlRow += '<td><a href="' + $lineItem.TaskListItemURL + '" target="_blank">' + $lineItem.TaskTicket + '</a>' + '</td>'
        $htmlRow += '<td>' + $lineItem.TaskUsername + '</td>'
        $htmlRow += '<td class="' + ($lineItem.TaskStatusPostOp.ToLower()) + '">' + $lineItem.TaskStatusPostOp + '</td>'
        $htmlRow += '<td>' + $lineItem.TaskCreatedDate + '</td>'
        $htmlRow += '<td>' + $lineItem.TaskDueDate + '</td>'
        $htmlRow += '<td>' + $lineItem.TaskCompletedDate + '</td>'
        $htmlRow += '<td>' + "$($lineItem.TaskCreatedByUser) ($($lineItem.TaskCreatedByUserEmail))" + '</td>'
        $htmlRow += '<td>' + $lineItem.TaskResult + '</td>'

        # if ($lineItem.AssignedLicenseName) {
        #     $htmlRow += '<td><ul>'
        #     $lineItem.AssignedLicenseName -split "," | ForEach-Object {
        #         $htmlRow += "<li>$($_)</li>"
        #     }
        #     $htmlRow += '</ul></td>'
        # }
        # else {
        #     $htmlRow += '<td></td>'
        # }

        $htmlRow += '<td>' + ($lineItem.AssignedLicenseName -replace ',', ';<br>') + '</td>'
        $htmlRow += "</tr>"
    }

    $htmlContent = $htmlContent -replace "vTableRows", ($htmlRow -join "`n") -replace "vOrganization", $reportOrganization -replace "vReportTitle", $reportTitle
    ($htmlContent -join "`n")
}