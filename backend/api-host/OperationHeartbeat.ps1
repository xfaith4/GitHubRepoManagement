# Long-running-operation progress heartbeat (portal incident 2026-08-10).
#
# The host is single-threaded: while a full-portfolio scan runs, /health/live
# cannot be answered. The external watchdog read that silence as a freeze and
# force-restarted the service every ~3 minutes, killing scans that the request
# deadline explicitly allows 900s to finish — 10 restarts in one stretch, and a
# portal that never completed a scan. Lane 0.4 fixed the same bug class in the
# in-process request deadline; the watchdog kept its own shorter budget.
#
# The contract here is PROGRESS, not liveness and not CPU. A healthy scan can
# sit for long stretches waiting on GitHub, `git`/`gh` child processes, or the
# filesystem while burning almost no CPU, so "CPU advanced" is not a progress
# signal — it is at best corroboration. Conversely a runaway loop burns CPU
# while progressing not at all. So the host states plainly what it is doing and
# when it last moved; the watchdog suppresses a restart only while that
# statement is FRESH.
#
# Dot-sourced rather than defined in the host script, for the reason
# RequestDeadline.ps1 and GitHubRateLimit.ps1 are: a helper reachable only by
# starting the listener is a helper nothing can test.
#
# Safety properties, all load-bearing:
#  - Absence of proof is never suppression. A missing, empty, unparseable, or
#    inactive state file means "no operation active" -> ordinary restart policy.
#  - The marker cannot suppress forever. Suppression is gated on the AGE of
#    lastProgressAt, so an orphaned active marker (host killed mid-scan) goes
#    stale on its own and restarts resume without any cleanup step.
#  - The host clears the marker at startup, so a fresh process never inherits a
#    predecessor's claim to be busy.
#  - The file declares the producer's own cadence, so the watchdog can validate
#    its tolerance against what this side actually promises instead of against a
#    number copied by hand into a second file.

# The host guarantees a progress write at least this often while an operation is
# active. The watchdog's no-progress tolerance must be at least this (enforced by
# Test-WatchdogToleranceInvariant in Watch-PortalHealth.ps1) or a legitimately
# slow stage reads as stale. Raise this ONLY together with that tolerance.
$script:PortalHeartbeatIntervalSeconds = 30

# Last on-disk progress write, for write throttling. Per-repository callbacks
# fire hundreds of times a scan; the freshness contract needs a write every few
# seconds, not every item.
$script:PortalOperationLastWriteUtc = [datetime]::MinValue
$script:PortalOperationWriteThrottleSeconds = 5

# Last heartbeat write failure, kept for diagnosis. The write is best-effort by
# design — a heartbeat failure must never take down the operation it describes —
# but "best effort" must not mean "invisible", so the reason is retained here
# rather than discarded into an empty catch.
$script:PortalOperationLastWriteError = ''

function Get-PortalOperationStatePath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    Join-Path $WorkspaceRoot 'output\logs\portal-operation.json'
}

function Get-PortalOperationLastWriteError {
    <# Diagnostic accessor: why the most recent heartbeat write failed, if it did. #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return $script:PortalOperationLastWriteError
}

function Write-PortalOperationState {
    <# Single writer. Best-effort by design: a missed write ages the marker,
       which fails SAFE (toward restarting), not toward suppression. #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Internal heartbeat writer for a gitignored status file; -WhatIf plumbing on a liveness signal would be noise, and no caller is interactive.')]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][hashtable]$State)
    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        ([pscustomobject]$State | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $Path -Encoding UTF8
        $script:PortalOperationLastWriteError = ''
    }
    catch {
        $script:PortalOperationLastWriteError = $_.Exception.Message
    }
}

function Start-PortalOperation {
    <# Mark a long-running operation active. Returns the state hashtable so the
       caller can thread it through progress updates without re-reading disk. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Marks an in-flight operation in a gitignored status file; nothing destructive and no interactive caller.')]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$Operation,
        [string]$CorrelationId = '',
        [string]$Stage = 'starting',
        [int]$Total = 0
    )
    $nowUtc = [datetime]::UtcNow.ToString('o')
    $state = @{
        active                   = $true
        operation                = $Operation
        correlationId            = $CorrelationId
        stage                    = $Stage
        completed                = 0
        total                    = $Total
        startedAt                = $nowUtc
        lastProgressAt           = $nowUtc
        heartbeatIntervalSeconds = $script:PortalHeartbeatIntervalSeconds
        hostPid                  = $PID
    }
    Write-PortalOperationState -Path (Get-PortalOperationStatePath -WorkspaceRoot $WorkspaceRoot) -State $state
    $script:PortalActiveOperationState = $state
    $script:PortalActiveOperationWorkspace = $WorkspaceRoot
    return $state
}

function Update-PortalOperationProgress {
    <# Record that the operation MOVED. Call on real stage boundaries and item
       completions — never on a timer, or the heartbeat would keep a wedged host
       alive, which is precisely the failure the watchdog exists to catch.

       Disk writes are throttled to one per PortalOperationWriteThrottleSeconds
       (stage changes and -Force always write), which is well inside the
       PortalHeartbeatIntervalSeconds freshness promise while keeping a
       75-repository scan to a handful of writes rather than hundreds. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Advances an in-flight progress marker in a gitignored status file; nothing destructive and no interactive caller.')]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][hashtable]$State,
        [string]$Stage = '',
        [int]$Completed = -1,
        [switch]$Force
    )
    if (-not $State.active) { return $State }
    $stageChanged = ($Stage -and $Stage -ne [string]$State.stage)
    if ($Stage) { $State.stage = $Stage }
    if ($Completed -ge 0) { $State.completed = $Completed }
    $nowUtc = [datetime]::UtcNow
    $State.lastProgressAt = $nowUtc.ToString('o')
    $dueForWrite = ($nowUtc - $script:PortalOperationLastWriteUtc).TotalSeconds -ge $script:PortalOperationWriteThrottleSeconds
    if ($Force -or $stageChanged -or $dueForWrite) {
        Write-PortalOperationState -Path (Get-PortalOperationStatePath -WorkspaceRoot $WorkspaceRoot) -State $State
        $script:PortalOperationLastWriteUtc = $nowUtc
    }
    return $State
}

# The operation currently in flight, so deep scan code can report progress
# without every layer between it and the request loop having to thread a
# callback. Set by Start-PortalOperation, cleared by Complete-PortalOperation.
$script:PortalActiveOperationState = $null
$script:PortalActiveOperationWorkspace = ''

function Update-ActivePortalOperationProgress {
    <# Ambient progress tick. No-ops when nothing is active, so scan engines can
       call it unconditionally — including on routes that run outside a tracked
       operation. This is what makes coverage a property of the request loop
       rather than of remembering to instrument each route. #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Advances an in-flight progress marker in a gitignored status file; nothing destructive and no interactive caller.')]
    param([string]$Stage = '', [int]$Completed = -1, [switch]$Force)
    if ($null -eq $script:PortalActiveOperationState) { return }
    $null = Update-PortalOperationProgress -WorkspaceRoot $script:PortalActiveOperationWorkspace `
        -State $script:PortalActiveOperationState -Stage $Stage -Completed $Completed -Force:$Force
}

function Get-ActivePortalOperationTick {
    <# The ambient tick as a scriptblock, for APIs that take an -OnProgress
       callback (Get-StatusAdapterResult / Get-LocalFolderInventory). #>
    [CmdletBinding()]
    [OutputType([scriptblock])]
    param([string]$Stage = '')
    $stageName = $Stage
    # Capture the function BODY, not just variables: .GetNewClosure() closes over
    # variables only, and this scriptblock is invoked from inside the reconcile
    # module's scope where the name would not resolve.
    $updater = ${function:Update-ActivePortalOperationProgress}
    return {
        param($scanned)
        & $updater -Stage $stageName -Completed ([int]$scanned)
    }.GetNewClosure()
}

function Complete-PortalOperation {
    <# Clear the active marker. MUST run on the failure path too (finally), or a
       thrown scan leaves a marker that suppresses restarts until it ages out. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Clears an in-flight progress marker in a gitignored status file; nothing destructive and no interactive caller.')]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [hashtable]$State,
        [string]$Outcome = 'completed'
    )
    $final = if ($State) { $State } else { @{} }
    $final.active = $false
    $final.stage = $Outcome
    $final.lastProgressAt = [datetime]::UtcNow.ToString('o')
    if (-not $final.ContainsKey('heartbeatIntervalSeconds')) { $final.heartbeatIntervalSeconds = $script:PortalHeartbeatIntervalSeconds }
    Write-PortalOperationState -Path (Get-PortalOperationStatePath -WorkspaceRoot $WorkspaceRoot) -State $final
    $script:PortalActiveOperationState = $null
    $script:PortalActiveOperationWorkspace = ''
    return $final
}

function Test-PortalOperationActive {
    <# Whether an operation is currently tracked in this process. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return ($null -ne $script:PortalActiveOperationState)
}

function Clear-PortalOperationState {
    <# Startup reset: a new process has no operation in flight, whatever the
       previous one was killed mid-way through claiming. #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Resets a gitignored status file at host startup; nothing destructive and no interactive caller.')]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $null = Complete-PortalOperation -WorkspaceRoot $WorkspaceRoot -State $null -Outcome 'host-restarted'
}

function Read-PortalOperationState {
    <# Watchdog side. Returns $null for missing/empty/unparseable — every one of
       which means "no proof of progress", i.e. do not suppress. #>
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        # Unparseable state is indistinguishable from no state: both mean the
        # host has not proven progress, so both must fall through to ordinary
        # restart policy rather than silently protecting a frozen host.
        return $null
    }
}

function Get-PortalOperationProgressAge {
    <# Pure: seconds since the state last recorded progress. Returns $null when
       there is no active operation or no readable timestamp — the caller treats
       $null as "no suppression", never as "age 0". #>
    [CmdletBinding()]
    [OutputType([object])]
    param([object]$State, [datetime]$NowUtc = [datetime]::UtcNow)
    if ($null -eq $State) { return $null }
    if (-not (Test-PortalStateHasProperty -State $State -Name 'active')) { return $null }
    if (-not [bool]$State.active) { return $null }
    if (-not (Test-PortalStateHasProperty -State $State -Name 'lastProgressAt')) { return $null }
    $stamp = [string]$State.lastProgressAt
    if ([string]::IsNullOrWhiteSpace($stamp)) { return $null }
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($stamp, [ref]$parsed)) { return $null }
    # ConvertFrom-Json yields Kind=Unspecified; treat it as the UTC it was
    # written as rather than letting ToUniversalTime() shift it by the local
    # offset (the Kind=Unspecified double-conversion bug class fixed elsewhere).
    if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified) {
        $parsed = [datetime]::SpecifyKind($parsed, [System.DateTimeKind]::Utc)
    }
    return [math]::Max(0, ($NowUtc - $parsed.ToUniversalTime()).TotalSeconds)
}

function Test-PortalStateHasProperty {
    <# Property probe that works for both PSCustomObject (ConvertFrom-Json) and
       hashtable states, without try/catch around a missing-member access. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][object]$State, [Parameter(Mandatory)][string]$Name)
    if ($State -is [System.Collections.IDictionary]) { return $State.Contains($Name) }
    return ($null -ne $State.PSObject.Properties[$Name])
}
