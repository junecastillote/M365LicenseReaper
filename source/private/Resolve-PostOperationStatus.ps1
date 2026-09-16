function Resolve-MLRPostOperationStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet(
            'NotApplicable',
            'Successful',
            'AlreadySatisfied',
            'PartiallySuccessful',
            'Failed',
            'Simulated'
        )]
        [string]
        $DirectOperationStatus,

        [Parameter(Mandatory)]
        [ValidateSet(
            'NotApplicable',
            'Successful',
            'AlreadySatisfied',
            'PartiallySuccessful',
            'Failed',
            'Simulated'
        )]
        [string]
        $InheritedOperationStatus
    )

    $operationStatusCollection = @(
        $DirectOperationStatus
        $InheritedOperationStatus
    )

    $applicableOperationCollection = @(
        $operationStatusCollection |
            Where-Object {
                $_ -ne 'NotApplicable'
            }
    )

    if ($applicableOperationCollection.Count -eq 0) {
        return 'NoActionRequired'
    }

    if ($applicableOperationCollection -contains 'PartiallySuccessful') {
        return 'PartiallySuccessful'
    }

    if ($applicableOperationCollection -contains 'Simulated') {
        return 'Simulated'
    }

    $failedOperationCollection = @(
        $applicableOperationCollection |
            Where-Object {
                $_ -eq 'Failed'
            }
    )

    $satisfiedOperationCollection = @(
        $applicableOperationCollection |
            Where-Object {
                $_ -eq 'Successful' -or
                $_ -eq 'AlreadySatisfied'
            }
    )

    if ($failedOperationCollection.Count -eq 0) {
        return 'Successful'
    }

    if (
        $failedOperationCollection.Count -gt 0 -and
        $satisfiedOperationCollection.Count -gt 0
    ) {
        return 'PartiallySuccessful'
    }

    return 'Failed'
}