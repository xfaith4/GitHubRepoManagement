function New-AdapterResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$CorrelationId,

        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [Parameter()]
        [object]$Data,

        [Parameter()]
        [string]$Error,

        [Parameter()]
        [hashtable]$Meta
    )

    return [pscustomobject]@{
        operation = $Operation
        correlationId = $CorrelationId
        success = $Success
        timestamp = (Get-Date).ToString('o')
        data = $Data
        error = $Error
        meta = if ($Meta) { $Meta } else { @{} }
    }
}

function Get-ErrorCategory {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return 'internal'
    }

    $text = $Message.ToLowerInvariant()
    if ($text -match 'validation|invalid|missing required|cannot bind') {
        return 'validation'
    }
    if ($text -match 'timeout|timed out') {
        return 'timeout'
    }
    if ($text -match 'gh|github|network|dns|socket|connection|api') {
        return 'dependency'
    }

    return 'internal'
}
