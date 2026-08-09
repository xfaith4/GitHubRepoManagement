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

function Get-LongRunningScanRoutePattern {
    <#
        .SYNOPSIS
            Routes whose work is a full-portfolio scan, not a request.

        .DESCRIPTION
            Every path here reaches Get-OperationsReposPayload / Invoke-PortfolioAssessment,
            which on a cold cache assesses the entire workspace (75+ repos). That legitimately
            outruns the ordinary request deadline, so killing the host on expiry would turn a
            normal scan into a restart loop — the freeze guard destroying the host it protects.
            These routes get the extended tier instead: still bounded, just bounded higher.
    #>
    [CmdletBinding()]
    param()

    return @(
        '/api/portfolio/assessment'
        '/api/portfolio/assessment/*'
        '/api/operations/repos'
        '/api/operations/repos/*'
        '/api/automation/run'
        '/api/automation/package-run'
        '/api/digest/preview'
        '/api/digest/send'
        '/api/reconcile'
        '/api/docreview/run'
        '/api/badges/*'
        '/api/v1/agent/*'
    )
}

function Test-LongRunningScanRoute {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Path = '')

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    $normalized = '/' + (($Path -replace '\\', '/') -replace '^/+', '' -replace '/+', '/')
    if ($normalized.Length -gt 1) { $normalized = $normalized.TrimEnd('/') }

    foreach ($pattern in (Get-LongRunningScanRoutePattern)) {
        if ($normalized -like $pattern) { return $true }
    }
    return $false
}

function Get-EffectiveScanRequestTimeoutSeconds {
    <#
        .SYNOPSIS
            The extended deadline applied to long-running scan routes.

        .DESCRIPTION
            Clamped by the same 30-3600 floor/ceiling as the ordinary deadline, then raised to
            at least BaseSeconds: an extended tier shorter than the tier it extends would be a
            silent downgrade for exactly the routes that need the most headroom.
    #>
    [CmdletBinding()]
    param(
        [int]$ConfiguredSeconds = 900,
        [AllowEmptyString()][string]$EnvironmentValue = '',
        [int]$BaseSeconds = 180
    )

    $seconds = Get-EffectiveRequestTimeoutSeconds -ConfiguredSeconds $ConfiguredSeconds -EnvironmentValue $EnvironmentValue
    if ($seconds -lt $BaseSeconds) { return $BaseSeconds }
    return $seconds
}

function Get-RequestDeadlineSecondsForPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Path = '',
        [Parameter(Mandatory)][int]$DefaultSeconds,
        [Parameter(Mandatory)][int]$ScanSeconds
    )

    if (Test-LongRunningScanRoute -Path $Path) { return $ScanSeconds }
    return $DefaultSeconds
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
        # Per-request, because scan routes run on an extended tier. Reported in
        # the incident record so the log says which deadline actually fired.
        TimeoutSeconds = $TimeoutSeconds
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
            $effectiveTimeout = [int]$State.TimeoutSeconds
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
                    timeoutSeconds = $effectiveTimeout
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
            [Environment]::FailFast("API request deadline exceeded for $($State.Method) $($State.Path) (correlationId=$($State.CorrelationId), timeoutSeconds=$effectiveTimeout).")
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
    $Controller.State.TimeoutSeconds = $TimeoutSeconds
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
