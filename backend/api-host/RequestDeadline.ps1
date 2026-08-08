Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EffectiveRequestTimeoutSeconds {
    [CmdletBinding()]
    param(
        [int]$ConfiguredSeconds = 180,
        [AllowEmptyString()][string]$EnvironmentValue = ''
    )

    $seconds = $ConfiguredSeconds
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentValue)) {
        $parsed = 0
        if ([int]::TryParse($EnvironmentValue.Trim(), [ref]$parsed)) {
            $seconds = $parsed
        }
    }

    # A deadline that is too short turns ordinary scans into restart loops; a
    # deadline that is unbounded recreates the freeze this guard prevents.
    if ($seconds -lt 30) { return 30 }
    if ($seconds -gt 3600) { return 3600 }
    return $seconds
}

function Resolve-RequestDeadlineAction {
    [CmdletBinding()]
    param(
        [bool]$Armed,
        [datetime]$DeadlineUtc,
        [datetime]$NowUtc = ([datetime]::UtcNow)
    )

    if (-not $Armed) { return 'idle' }
    if ($NowUtc -ge $DeadlineUtc) { return 'terminate' }
    return 'wait'
}

function Start-RequestDeadlineWatchdog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][string]$IncidentLogPath,
        [int]$PollMilliseconds = 250
    )

    $state = [hashtable]::Synchronized(@{
        Armed         = $false
        RequestId     = ''
        CorrelationId = ''
        Method        = ''
        Path          = ''
        StartedAtUtc  = [datetime]::MinValue
        DeadlineUtc   = [datetime]::MaxValue
        StopRequested = $false
    })

    $watchdog = [powershell]::Create()
    $null = $watchdog.AddScript({
        param($State, $TimeoutSeconds, $IncidentLogPath, $PollMilliseconds)

        while (-not [bool]$State.StopRequested) {
            Start-Sleep -Milliseconds $PollMilliseconds
            if (-not [bool]$State.Armed) { continue }

            $requestId = [string]$State.RequestId
            $deadlineUtc = [datetime]$State.DeadlineUtc
            if ([datetime]::UtcNow -lt $deadlineUtc) { continue }

            # Re-check the generation after reading the deadline. A request
            # that completed exactly at the boundary must not terminate the
            # next request that reused the synchronized state.
            if (-not [bool]$State.Armed -or [string]$State.RequestId -ne $requestId) { continue }

            try {
                $logDir = Split-Path -Path $IncidentLogPath -Parent
                if (-not [string]::IsNullOrWhiteSpace($logDir)) {
                    [System.IO.Directory]::CreateDirectory($logDir) | Out-Null
                }
                $incident = [ordered]@{
                    timestamp      = [datetime]::UtcNow.ToString('o')
                    eventType      = 'api.request_deadline_exceeded'
                    requestId      = $requestId
                    correlationId  = [string]$State.CorrelationId
                    method         = [string]$State.Method
                    path           = [string]$State.Path
                    startedAt      = ([datetime]$State.StartedAtUtc).ToString('o')
                    deadlineAt     = $deadlineUtc.ToString('o')
                    timeoutSeconds = [int]$TimeoutSeconds
                    processId      = [int]$PID
                }
                $line = ($incident | ConvertTo-Json -Compress) + [Environment]::NewLine
                [System.IO.File]::AppendAllText($IncidentLogPath, $line, [System.Text.UTF8Encoding]::new($false))
            } catch { }

            # The route dispatcher is intentionally single-threaded. PowerShell
            # cannot safely abort a synchronous native call in-place, so exiting
            # is the only reliable way to release the accept loop. Shawl's
            # --restart policy and SCM recovery bring the host back within
            # seconds; the external watchdog remains a second line of defense.
            [Environment]::FailFast("API request deadline exceeded for $($State.Method) $($State.Path) (correlationId=$($State.CorrelationId), timeoutSeconds=$TimeoutSeconds).")
        }
    }).AddArgument($state).AddArgument($TimeoutSeconds).AddArgument($IncidentLogPath).AddArgument($PollMilliseconds)

    $asyncResult = $watchdog.BeginInvoke()
    return [pscustomobject]@{
        State       = $state
        PowerShell  = $watchdog
        AsyncResult = $asyncResult
    }
}

function Set-RequestDeadline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Controller,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][string]$CorrelationId,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path
    )

    $nowUtc = [datetime]::UtcNow
    $Controller.State.Armed = $false
    $Controller.State.RequestId = [guid]::NewGuid().ToString('n')
    $Controller.State.CorrelationId = $CorrelationId
    $Controller.State.Method = $Method
    $Controller.State.Path = $Path
    $Controller.State.StartedAtUtc = $nowUtc
    $Controller.State.DeadlineUtc = $nowUtc.AddSeconds($TimeoutSeconds)
    $Controller.State.Armed = $true
}

function Clear-RequestDeadline {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Controller)

    $Controller.State.Armed = $false
    $Controller.State.RequestId = ''
    $Controller.State.CorrelationId = ''
    $Controller.State.Method = ''
    $Controller.State.Path = ''
    $Controller.State.StartedAtUtc = [datetime]::MinValue
    $Controller.State.DeadlineUtc = [datetime]::MaxValue
}

function Stop-RequestDeadlineWatchdog {
    [CmdletBinding()]
    param([AllowNull()][object]$Controller)

    if ($null -eq $Controller) { return }
    try { $Controller.State.StopRequested = $true } catch { }
    try {
        if ($null -ne $Controller.AsyncResult) {
            $null = $Controller.AsyncResult.AsyncWaitHandle.WaitOne(2000)
        }
    } catch { }
    try {
        if ($Controller.PowerShell.InvocationStateInfo.State -eq [System.Management.Automation.PSInvocationState]::Running) {
            $Controller.PowerShell.Stop()
        }
    } catch { }
    try { $Controller.PowerShell.Dispose() } catch { }
}
