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