function Test-MLRRecipientTable {
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


