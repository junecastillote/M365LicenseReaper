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