Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
    Release 3.0 — operator-runner presence.

    The portal enqueues work it structurally cannot execute: `gh agent-task`
    needs an OAuth credential and `claude` needs an authenticated session, and a
    LocalSystem service holds neither. Execution therefore happens in
    Invoke-RoadmapTaskRunner.ps1, running as the operator.

    That creates a failure mode with no symptom: queueing into an empty room
    looks exactly like queueing into a running one. The entry is written, the
    route returns 200, and the operator finds out only when nothing ever leaves
    `queued`. This reader turns that silence into an answer the portal can give
    BEFORE the work is queued.
#>

function _Runner_GetField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return $Default
    }
    if ($null -ne $Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $Name)) { return $Obj.$Name }
    return $Default
}

function _Runner_ToUtc {
    <# Kind=Unspecified from ConvertFrom-Json already holds the UTC instant;
       calling ToUniversalTime() on it shifts it again and would put the last
       heartbeat in the future, making a dead runner look freshly alive. #>
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    $dt = [datetime]::MinValue
    if ($Value -is [datetime]) {
        $dt = [datetime]$Value
    }
    else {
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        if (-not [datetime]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$dt)) {
            return $null
        }
    }
    if ($dt.Kind -eq [System.DateTimeKind]::Unspecified) { return [datetime]::SpecifyKind($dt, [System.DateTimeKind]::Utc) }
    return $dt.ToUniversalTime()
}

function Get-RunnerHeartbeatFilePath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    return (Join-Path $WorkspaceRoot 'output\roadmap-task-runner.heartbeat.json')
}

function Resolve-RunnerPresence {
    <#
    .SYNOPSIS
        Pure — classify a heartbeat record as present / stale / absent.
    .DESCRIPTION
        The staleness budget is derived from the runner's OWN reported poll
        interval rather than a constant, so a deliberately slow runner
        (-PollSeconds 300) is not reported dead every cycle. `GraceFactor`
        tolerates one missed beat; two is absent.

        A heartbeat that cannot be parsed is `absent`, never `present`. This
        surface exists to stop the portal claiming a runner is there when it is
        not — defaulting an unreadable record to healthy would reintroduce
        exactly the false-green it was built to remove.
    .PARAMETER Heartbeat
        The parsed heartbeat object, or $null when no file exists.
    .PARAMETER Now
        Injectable clock for deterministic tests.
    .PARAMETER GraceFactor
        Missed poll intervals tolerated before the runner is called stale.
    .PARAMETER MinimumStaleSeconds
        Floor on the staleness budget, so a 1-second poll interval does not make
        every reader race the writer.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][object]$Heartbeat = $null,
        [Parameter()][datetime]$Now = [datetime]::UtcNow,
        [Parameter()][double]$GraceFactor = 3.0,
        [Parameter()][int]$MinimumStaleSeconds = 60
    )

    $nowUtc = _Runner_ToUtc -Value $Now
    if ($null -eq $nowUtc) { $nowUtc = [datetime]::UtcNow }

    if ($null -eq $Heartbeat) {
        return [pscustomobject]@{
            state            = 'absent'
            present          = $false
            hostname         = ''
            user             = ''
            pid              = 0
            mode             = ''
            pollSeconds      = 0
            claimedCount     = 0
            lastHeartbeatAt  = $null
            secondsSinceBeat = $null
            staleAfterSeconds = $MinimumStaleSeconds
            message          = ('No operator runner has ever reported in. Queued work will sit at "queued" until one runs: ' +
                                'pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1')
            evaluatedAt      = $nowUtc.ToString('o')
        }
    }

    $pollSeconds = [int](_Runner_GetField -Obj $Heartbeat -Name 'pollSeconds' -Default 15)
    if ($pollSeconds -le 0) { $pollSeconds = 15 }
    $staleAfter = [int][math]::Max($MinimumStaleSeconds, [math]::Ceiling($pollSeconds * $GraceFactor))

    $beatAt = _Runner_ToUtc -Value (_Runner_GetField -Obj $Heartbeat -Name 'lastHeartbeatAt' -Default $null)
    if ($null -eq $beatAt) {
        return [pscustomobject]@{
            state            = 'absent'
            present          = $false
            hostname         = [string](_Runner_GetField -Obj $Heartbeat -Name 'hostname' -Default '')
            user             = [string](_Runner_GetField -Obj $Heartbeat -Name 'user' -Default '')
            pid              = [int](_Runner_GetField -Obj $Heartbeat -Name 'pid' -Default 0)
            mode             = [string](_Runner_GetField -Obj $Heartbeat -Name 'mode' -Default '')
            pollSeconds      = $pollSeconds
            claimedCount     = [int](_Runner_GetField -Obj $Heartbeat -Name 'claimedCount' -Default 0)
            lastHeartbeatAt  = $null
            secondsSinceBeat = $null
            staleAfterSeconds = $staleAfter
            message          = 'A runner heartbeat exists but carries no readable timestamp, so its liveness cannot be confirmed. Treating it as absent.'
            evaluatedAt      = $nowUtc.ToString('o')
        }
    }

    $secondsSince = [math]::Round(($nowUtc - $beatAt).TotalSeconds, 1)
    $stale = ($secondsSince -gt $staleAfter)
    $state = if ($stale) { 'stale' } else { 'present' }
    $hostName = [string](_Runner_GetField -Obj $Heartbeat -Name 'hostname' -Default '')
    $userName = [string](_Runner_GetField -Obj $Heartbeat -Name 'user' -Default '')
    $claimed = [int](_Runner_GetField -Obj $Heartbeat -Name 'claimedCount' -Default 0)

    $message = if ($stale) {
        ("The last runner heartbeat was {0}s ago on {1}\{2}; it beats every {3}s, so the runner has probably stopped. Queued work will not move until one runs." -f `
            $secondsSince, $hostName, $userName, $pollSeconds)
    }
    else {
        ("Runner alive on {0}\{1} (heartbeat {2}s ago, {3} task(s) claimed this cycle)." -f $hostName, $userName, $secondsSince, $claimed)
    }

    return [pscustomobject]@{
        state            = $state
        present          = (-not $stale)
        hostname         = $hostName
        user             = $userName
        pid              = [int](_Runner_GetField -Obj $Heartbeat -Name 'pid' -Default 0)
        mode             = [string](_Runner_GetField -Obj $Heartbeat -Name 'mode' -Default '')
        pollSeconds      = $pollSeconds
        claimedCount     = $claimed
        lastHeartbeatAt  = $beatAt.ToString('o')
        secondsSinceBeat = $secondsSince
        staleAfterSeconds = $staleAfter
        message          = $message
        evaluatedAt      = $nowUtc.ToString('o')
    }
}

function Get-RunnerPresence {
    <#
    .SYNOPSIS
        Read the heartbeat from disk and classify it.
    .DESCRIPTION
        An unreadable or corrupt heartbeat file is reported as absent, not
        thrown: this route's whole job is to answer "is anything going to pick
        this up", and a 500 answers it less usefully than "no".
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][datetime]$Now = [datetime]::UtcNow
    )

    $path = Get-RunnerHeartbeatFilePath -WorkspaceRoot $WorkspaceRoot
    $heartbeat = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($raw)) { $heartbeat = ConvertFrom-Json -InputObject $raw }
        }
        catch { $heartbeat = $null }
    }

    $presence = Resolve-RunnerPresence -Heartbeat $heartbeat -Now $Now
    $presence | Add-Member -NotePropertyName 'heartbeatPath' -NotePropertyValue $path -Force
    return $presence
}

function Test-InProcessCloudDispatchAllowed {
    <#
    .SYNOPSIS
        Pure — may THIS process run `gh agent-task create` itself? Never, from
        the API host; the answer names the runner instead.
    .DESCRIPTION
        Release 3.0's one dispatch model. The host is refused unconditionally,
        not merely when it detects it is running as a service:

          * The service detection is a heuristic. Refusing only when it fires
            means the failure comes back the moment it is wrong, and the symptom
            (a wizard that dead-ends at its last step) is far away from the cause.
          * Even in an interactive host, in-process dispatch would inherit the
            host's environment — including the PAT it reads for every other
            GitHub call — and gh ignores its stored OAuth credential whenever
            GH_TOKEN/GITHUB_TOKEN is set. So the interactive case fails too, for
            a reason that looks nothing like the service case.

        `-DispatchMode copilot` stays reachable from an operator shell, where the
        credential and the session are the operator's own. This is the guard for
        the HOST, not for the CLI.
    .PARAMETER Caller
        Name of the surface asking, echoed into the refusal so the log says which
        route tried.
    .PARAMETER RunningAsService
        Recorded in the refusal for diagnosis. It does NOT change the verdict.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowEmptyString()][string]$Caller = 'api-host',
        [Parameter()][bool]$RunningAsService = $false
    )

    return [pscustomobject]@{
        allowed          = $false
        code             = 'operator-runner-required'
        runningAsService = $RunningAsService
        caller           = $Caller
        message          = ("Cloud (Copilot) dispatch cannot run inside the API host. 'gh agent-task create' requires an OAuth credential " +
                            "this process does not hold, and gh ignores its stored credential whenever GH_TOKEN/GITHUB_TOKEN is set — which " +
                            "this host sets for its own GitHub calls. Work is enqueued instead and executed by the operator-session runner: " +
                            "pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1")
    }
}

function Get-QueuedTaskBacklog {
    <#
    .SYNOPSIS
        How much queued work is waiting, split by dispatch target.
    .DESCRIPTION
        Presence alone understates the problem. "No runner" matters far more
        when 12 tasks are already queued behind it than when none are, and the
        split by target says which kind of runner session is missing.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

    $queuePath = Join-Path $WorkspaceRoot 'output\roadmap-task-queue.jsonl'
    $runsDir = Join-Path $WorkspaceRoot 'output\roadmap-task-history\runs'
    $claude = 0
    $copilot = 0
    $oldestQueuedAt = $null

    if (Test-Path -LiteralPath $queuePath -PathType Leaf) {
        foreach ($line in @(Get-Content -LiteralPath $queuePath -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $entry = $null
            try { $entry = ConvertFrom-Json -InputObject $line } catch { continue }

            # Only entries still sitting at `queued` count: the queue file is
            # append-only, so counting every line would report every task ever
            # dispatched as a backlog forever.
            $summaryPath = Join-Path $runsDir ("{0}.summary.json" -f [string](_Runner_GetField -Obj $entry -Name 'runId' -Default ''))
            $status = ''
            if (Test-Path -LiteralPath $summaryPath -PathType Leaf) {
                try { $status = [string]((Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json).status) } catch { $status = '' }
            }
            if ($status -ne 'queued') { continue }

            $target = [string](_Runner_GetField -Obj $entry -Name 'dispatchTarget' -Default 'claude')
            if ([string]::IsNullOrWhiteSpace($target)) { $target = 'claude' }
            if ($target.ToLowerInvariant() -eq 'copilot') { $copilot++ } else { $claude++ }

            # Release 3.5 milestone 6 -- the queue-age alarm's raw fact. The
            # oldest still-queued entry's timestamp travels on the payload, so
            # the header can escalate work sitting unclaimed past a day.
            $queuedAtRaw = [string](_Runner_GetField -Obj $entry -Name 'queuedAt' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($queuedAtRaw)) {
                $parsedQueuedAt = [datetime]::MinValue
                $qaStyles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
                if ([datetime]::TryParse($queuedAtRaw, [System.Globalization.CultureInfo]::InvariantCulture, $qaStyles, [ref]$parsedQueuedAt)) {
                    if ($null -eq $oldestQueuedAt -or $parsedQueuedAt -lt $oldestQueuedAt) { $oldestQueuedAt = $parsedQueuedAt }
                }
            }
        }
    }

    return [pscustomobject]@{
        queuedTotal    = ($claude + $copilot)
        queuedClaude   = $claude
        queuedCopilot  = $copilot
        queuePath      = $queuePath
        oldestQueuedAt = $(if ($null -ne $oldestQueuedAt) { $oldestQueuedAt.ToUniversalTime().ToString('o') } else { $null })
    }
}
