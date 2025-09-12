function Test-RecipientTable {
    param (
        [Parameter(Mandatory)]
        [hashtable]$RecipientTable
    )

    $recipientKeys = "To", "Cc", "Bcc"
    $errors = @()

    # --- Validate From ---
    if (-not $RecipientTable.ContainsKey("From")) {
        $errors += "Missing required key: 'From' must exist."
    }
    elseif ($null -eq $RecipientTable["From"] -or $RecipientTable["From"].Count -eq 0) {
        $errors += "Key 'From' must contain at least one value."
    }

    # --- Validate recipient keys ---
    $presentKeys = $RecipientTable.Keys | Where-Object { $_ -in $recipientKeys }
    if (-not $presentKeys) {
        $errors += "Missing required key: At least one of 'To', 'Cc', or 'Bcc' must exist."
    }
    else {
        $nonEmptyKeys = $presentKeys | Where-Object {
            $null -ne $RecipientTable[$_] -and $RecipientTable[$_].Count -gt 0
        }

        if (-not $nonEmptyKeys) {
            $errors += "At least one of the keys 'To', 'Cc', or 'Bcc' must contain a value."
        }
    }

    # --- Return result ---
    if ($errors.Count -eq 0) {
        return @{
            IsValid = $true
            Errors  = @()
        }
    }
    else {
        return @{
            IsValid = $false
            Errors  = $errors
        }
    }
}


# [enum]::GetValues([System.ConsoleColor])
function Say {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Text,
        [Parameter()]
        $Color = 'Cyan'
    )

    if ($Color) {
        $Host.UI.RawUI.ForegroundColor = $Color
    }
    $Text | Out-Host
    [Console]::ResetColor()
}

function SayError {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Text,
        [Parameter()]
        $Color = 'Red'
    )
    $Host.UI.RawUI.ForegroundColor = $Color
    "$(Get-Date -Format 'dd-MMM-yyyy HH:mm:ss') : [ERROR] - $Text" | Out-Host
    [Console]::ResetColor()
}

function SayInfo {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Text,
        [Parameter()]
        $Color = 'Green'
    )
    $Host.UI.RawUI.ForegroundColor = $Color
    "$(Get-Date -Format 'dd-MMM-yyyy HH:mm:ss') : [INFO] - $Text" | Out-Host
    [Console]::ResetColor()
}

function SayWarning {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Text,
        [Parameter()]
        $Color = 'DarkYellow'
    )
    $Host.UI.RawUI.ForegroundColor = $Color
    "$(Get-Date -Format 'dd-MMM-yyyy HH:mm:ss') : [WARNING] - $Text" | Out-Host
    [Console]::ResetColor()
}

function ThisModule {
    $MyInvocation.MyCommand.Module
}

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
        $htmlRow += "</tr>"
    }


    $htmlContent = $htmlContent -replace "vTableRows", ($htmlRow -join "`n") -replace "vOrganization", $reportOrganization -replace "vReportTitle", $reportTitle
    ($htmlContent -join "`n")
}

function Add-MLREmailRecipient {
    param(
        [Parameter(Mandatory)]
        [string[]]
        $Recipients
    )
    $jsonRecipients = @()
    $Recipients | ForEach-Object {
        $jsonRecipients += @{EmailAddress = @{Address = $_ } }
    }
    return $jsonRecipients
}
