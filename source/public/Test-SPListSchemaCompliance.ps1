# v5.0
function Test-MLRSPListSchemaCompliance {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$ListColumns,

        [switch]$Detailed
    )

    # --------------------------------------------------
    # Helper: Normalize Internal Name (for matching only)
    # --------------------------------------------------
    function Repair-Name {
        param ($Name)

        if (-not $Name) { return $null }

        $normalized = $Name -replace "_x0020_", ""
        $normalized = $normalized -replace "\s", ""
        return $normalized.ToLower()
    }

    # --------------------------------------------------
    # Expected Schema Definition
    # --------------------------------------------------
    $expectedSchema = @(
        @{
            DisplayName        = "Ticket"
            InternalNameMustBe = "Title"
            Type               = "Text"
            Required           = $true
            Indexed            = $true
            Unique             = $false
        },
        @{
            DisplayName = "Username"
            Type        = "Text"
            Required    = $true
            Indexed     = $false
            Unique      = $false
        },
        @{
            DisplayName = "Due Date"
            Type        = "DateTime"
            Required    = $true
            Indexed     = $true
            Unique      = $false
        },
        @{
            DisplayName = "Status"
            Type        = "Choice"
            Required    = $false
            Indexed     = $true
            Unique      = $false
            Choices     = @("Pending", "Completed", "Canceled")
            Default     = "Pending"
        },
        @{
            DisplayName = "Completed Date"
            Type        = "DateTime"
            Required    = $false
            Indexed     = $false
            Unique      = $false
        },
        @{
            DisplayName = "Last Message"
            Type        = "Text"
            Required    = $false
            Indexed     = $false
            Unique      = $false
        },
        @{
            DisplayName = "Notes"
            Type        = "Multiline"
            Required    = $false
            Indexed     = $false
            Unique      = $false
        }
    )

    # --------------------------------------------------
    # Build Lookup USING INTERNAL NAME (Name property)
    # --------------------------------------------------
    $columnLookup = @{}

    foreach ($col in $ListColumns) {

        if (-not $col.Name) { continue }

        $internalKey = Repair-Name $col.Name

        if (-not $internalKey) { continue }

        # Defensive: true internal name must be unique
        if ($columnLookup.ContainsKey($internalKey)) {
            throw "Duplicate internal Name detected: '$($col.Name)'. Aborting validation."
        }

        $columnLookup[$internalKey] = $col
    }

    # --------------------------------------------------
    # Validation Loop
    # --------------------------------------------------
    $columnResults = foreach ($expected in $expectedSchema) {

        # Match using INTERNAL NAME if specified
        if ($expected.InternalNameMustBe) {
            $lookupKey = Repair-Name $expected.InternalNameMustBe
        }
        else {
            $lookupKey = Repair-Name $expected.DisplayName
        }

        $column = $columnLookup[$lookupKey]

        if (-not $column) {
            [PSCustomObject]@{
                Column  = $expected.DisplayName
                Status  = "Missing"
                Details = "Column not found"
            }
            continue
        }

        $issues = @()

        # -------------------------
        # Type Detection (Improved)
        # -------------------------
        if ($column.Choice -and $column.Choice.Choices) {
            $actualType = "Choice"
        }
        elseif ($column.DateTime.Format) {
            $actualType = "DateTime"
        }
        elseif ($column.Text -and $column.Text.AllowMultipleLines) {
            $actualType = "Multiline"
        }
        elseif ($column.Text -and $column.Text.AllowMultipleLines -eq $false) {
            $actualType = "Text"
        }
        else {
            $actualType = "Other"
        }

        if ($actualType -ne $expected.Type) {
            $issues += "Type mismatch (Expected $($expected.Type), Actual $actualType)"
        }

        if ($column.Required -ne $expected.Required) {
            $issues += "Required mismatch"
        }

        if ($column.Indexed -ne $expected.Indexed) {
            $issues += "Indexed mismatch"
        }

        if ($column.EnforceUniqueValues -ne $expected.Unique) {
            $issues += "Unique value mismatch"
        }

        # Internal name enforcement
        if ($expected.InternalNameMustBe) {
            if ($column.Name -ne $expected.InternalNameMustBe) {
                $issues += "Internal name must be '$($expected.InternalNameMustBe)' but is '$($column.Name)'"
            }
        }

        # Choice validation
        if ($expected.Type -eq "Choice") {

            $actualChoices = @($column.Choice.Choices)

            if (
                ($actualChoices.Count -ne $expected.Choices.Count) -or
                (Compare-Object $actualChoices $expected.Choices)
            ) {
                $issues += "Choice values mismatch"
            }

            $actualDefault = $column.DefaultValue.Value
            # if (-not $actualDefault) {
            #     $actualDefault = $column.Choice.DefaultValue
            # }

            if ($actualDefault -ne $expected.Default) {
                $issues += "Default value mismatch"
            }
        }

        # Output
        if ($Detailed) {
            [PSCustomObject]@{
                DisplayName  = $expected.DisplayName
                InternalName = $column.Name
                TypeExpected = $expected.Type
                TypeActual   = $actualType
                Required     = $column.Required
                Indexed      = $column.Indexed
                Unique       = $column.EnforceUniqueValues
                Status       = if ($issues.Count -eq 0) { "OK" } else { "Mismatch" }
                Details      = if ($issues.Count -eq 0) { "All properties match" } else { $issues -join "; " }
            }
        }
        else {
            [PSCustomObject]@{
                DisplayName = $expected.DisplayName
                Status      = if ($issues.Count -eq 0) { "OK" } else { "Mismatch" }
                Details     = if ($issues.Count -eq 0) { "All properties match" } else { $issues -join "; " }
            }
        }
    }

    # --------------------------------------------------
    # Summary Compliance Output
    # --------------------------------------------------
    $overallStatus = if (
        ($columnResults.Status -contains "Mismatch") -or
        ($columnResults.Status -contains "Missing")
    ) {
        "NonCompliant"
    }
    else {
        "Compliant"
    }

    [PSCustomObject]@{
        OverallStatus = $overallStatus
        Columns       = $columnResults
    }
}