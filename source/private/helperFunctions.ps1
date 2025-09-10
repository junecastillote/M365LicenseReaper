function Test-RecipientTable {
    param (
        [Parameter(Mandatory)]
        [hashtable]$RecipientTable
    )

    $validKeys = "To", "Cc", "Bcc"
    $errors = @()

    # 1. Must have at least one of the keys
    $presentKeys = $RecipientTable.Keys | Where-Object { $_ -in $validKeys }
    if (-not $presentKeys) {
        $errors += "Missing required key: At least one of 'To', 'Cc', or 'Bcc' must exist."
    }
    else {
        # 2. At least one present key must have values
        $nonEmptyKeys = $presentKeys | Where-Object {
            $null -ne $RecipientTable[$_] -and $RecipientTable[$_].Count -gt 0
        }

        if (-not $nonEmptyKeys) {
            $errors += "At least one of the keys 'To', 'Cc', or 'Bcc' must contain a value."
        }
    }

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