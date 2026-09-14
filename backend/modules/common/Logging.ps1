function Write-StructuredLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Debug','Info','Warning','Error')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$CorrelationId,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [object]$Details,

        [Parameter()]
        [string]$LogPath
    )

    $entry = [pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        level = $Level
        component = $Component
        operation = $Operation
        correlationId = $CorrelationId
        message = $Message
        details = $Details
    }

    $json = $entry | ConvertTo-Json -Depth 8 -Compress
    Write-Host $json

    if ($LogPath) {
        Add-Content -LiteralPath $LogPath -Value $json -Encoding UTF8
    }
}
