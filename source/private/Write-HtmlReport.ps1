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
        # $htmlRow += '<td class="' + ($lineItem.TaskStatusPostOp.ToLower()) + '">' + $lineItem.TaskStatusPostOp + '</td>'
        $htmlRow += '<td class="' + ($lineItem.TaskStatusPostOp.ToLower()) + '">' + $lineItem.TaskResult + '</td>'
        $htmlRow += '<td class="' + ($lineItem.TaskStatusPostOp.ToLower()) + '">' + $lineItem.TaskResultDetail + '</td>'
        $htmlRow += '<td>' + ($lineItem.AssignedLicenseName -replace ',', ';<br>') + '</td>'
        # $htmlRow += '<td>' + $lineItem.TaskCreatedDate.ToString('yyyy-MM-dd HH:mm:ss') + '</td>'
        $htmlRow += '<td>' + $lineItem.TaskCreatedDate.ToString('yyyy-MM-dd') + '</td>'
        $htmlRow += '<td>' + $lineItem.TaskDueDate.ToString('yyyy-MM-dd') + '</td>'
        $htmlRow += '<td>' + $(if ($lineItem.TaskCompletedDate) { $lineItem.TaskCompletedDate.ToString('yyyy-MM-dd HH:mm:ss') }) + '</td>'
        if ($lineItem.TaskCreatedByUserEmail) {
            $htmlRow += '<td>' + "$($lineItem.TaskCreatedByUser) ($($lineItem.TaskCreatedByUserEmail))" + '</td>'
        }
        else {
            $htmlRow += '<td>' + "$($lineItem.TaskCreatedByUser)" + '</td>'
        }
        # $htmlRow += '<td>' + "$($lineItem.TaskCreatedByUser) ($($lineItem.TaskCreatedByUserEmail))" + '</td>'


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