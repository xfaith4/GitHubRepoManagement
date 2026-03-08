function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [int]$MaxAttempts = 3,

        [Parameter()]
        [int]$BaseDelayMs = 250,

        [Parameter()]
        [int]$MaxDelayMs = 3000,

        [Parameter()]
        [string]$Operation = 'operation',

        [Parameter()]
        [string]$Component = 'common',

        [Parameter()]
        [string]$CorrelationId = '',

        [Parameter()]
        [string]$LogPath
    )

    if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }
    if ($BaseDelayMs -lt 0) { $BaseDelayMs = 0 }
    if ($MaxDelayMs -lt $BaseDelayMs) { $MaxDelayMs = $BaseDelayMs }

    $lastError = $null

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $ScriptBlock
        }
        catch {
            $lastError = $_
            if ($attempt -ge $MaxAttempts) { break }

            $delayNoJitter = [math]::Min($MaxDelayMs, $BaseDelayMs * [math]::Pow(2, $attempt - 1))
            $jitter = Get-Random -Minimum 0 -Maximum ([math]::Max([int]($delayNoJitter * 0.2), 1))
            $sleepMs = [int]($delayNoJitter + $jitter)

            if (Get-Command -Name Write-StructuredLog -ErrorAction SilentlyContinue) {
                Write-StructuredLog `
                    -Level Warning `
                    -Component $Component `
                    -Operation $Operation `
                    -CorrelationId $CorrelationId `
                    -Message 'Operation failed, retrying with backoff' `
                    -Details @{ attempt = $attempt; maxAttempts = $MaxAttempts; sleepMs = $sleepMs; error = $_.Exception.Message } `
                    -LogPath $LogPath
            }

            Start-Sleep -Milliseconds $sleepMs
        }
    }

    throw $lastError
}
