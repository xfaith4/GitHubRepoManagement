<#
.SYNOPSIS
    Bounded git invocation for the portfolio sweep: per-command timeout,
    per-sweep concurrency cap, order preserved.

.DESCRIPTION
    Release 3.2. The inventory sweep used to make its git calls bare -- nine
    sequential unbounded process launches per repository, ~675 on the real
    75-repo workspace -- so one repository with a hung object store or a dead
    network mapping stalled the whole sweep until the request-deadline guard
    killed the host. (The roadmap said seven calls / ~525 launches; counting
    them found nine.)

    Three functions:

    - Invoke-BoundedGitCommand: one git call with a hard timeout. On timeout
      the process is killed and the call reports TimedOut rather than hanging
      the sweep. The executable is overridable so the smoke test can prove
      abandonment against a deliberately hanging shim.
    - Get-RepoGitFactSet: the eight metadata reads the inventory needs for one
      repository, each bounded. Returns raw values; every parsing decision
      stays with the caller so parallel and sequential output cannot drift.
    - Invoke-BoundedRepoFactSweep: fans Get-RepoGitFactSet across repositories
      on a runspace pool capped at MaxConcurrency, returning results in input
      order. A per-repo completion callback runs on the caller's thread so the
      operation heartbeat can tick from inside the loop it describes.

    The cap must not reorder or drop repositories -- output identical to
    sequential is asserted by the module smoke, not hoped for. Runspace pools
    are the 5.1-safe parallelism this host already uses (RequestDeadline.ps1);
    ForEach-Object -Parallel and Start-ThreadJob are PS7-only and off the
    table here.
#>

Set-StrictMode -Version Latest

function Invoke-BoundedGitCommand {
    <#
    .SYNOPSIS
        Run one git command with a hard timeout; kill it if it exceeds it.
    .OUTPUTS
        [pscustomobject] Value (first non-empty output line or $null),
        Lines (string[]), ExitCode, TimedOut, DurationMs, StartError.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)][string[]]$GitArgumentList,
        [Parameter()][ValidateRange(1, 600)][int]$TimeoutSeconds = 20,
        # Overridable so the smoke test can point this at a hanging shim and
        # prove the timeout actually abandons the process. Production callers
        # never pass it.
        [Parameter()][string]$FileName = 'git'
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $renderedArgs = New-Object System.Collections.Generic.List[string]
    foreach ($argument in (@('-C', $RepoPath) + @($GitArgumentList))) {
        $text = [string]$argument
        if ($text -match '[\s"]' -or $text -eq '') {
            $renderedArgs.Add('"' + ($text -replace '"', '\"') + '"')
        }
        else {
            $renderedArgs.Add($text)
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.Arguments = ($renderedArgs -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = $null
    try {
        $process = [System.Diagnostics.Process]::Start($psi)
    }
    catch {
        $stopwatch.Stop()
        return [pscustomobject]@{
            Value      = $null
            Lines      = @()
            ExitCode   = -1
            TimedOut   = $false
            DurationMs = $stopwatch.ElapsedMilliseconds
            StartError = $_.Exception.Message
        }
    }

    $timedOut = $false
    try {
        # Async reads before the wait, or a child filling its pipe deadlocks
        # against a parent that is not draining it.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            # Kill can race a process that exited between the wait and here;
            # either way the outcome we need (process gone) holds.
            try { $process.Kill() } catch { $null = $_ }
            $null = $process.WaitForExit(5000)
        }

        # Bounded drain: after exit or kill the streams close and these
        # complete; the timeout is a backstop, never the expected path.
        $null = [System.Threading.Tasks.Task]::WaitAll(@($stdoutTask, $stderrTask), 5000)

        $stdout = ''
        if ($stdoutTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
            $stdout = [string]$stdoutTask.Result
        }

        $lines = @($stdout -split "\r?\n" | Where-Object { $_ -ne '' })
        $firstLine = $null
        if (@($lines).Count -gt 0) { $firstLine = $lines[0] }

        $exitCode = -1
        if (-not $timedOut -and $process.HasExited) { $exitCode = $process.ExitCode }

        $stopwatch.Stop()
        return [pscustomobject]@{
            Value      = $firstLine
            Lines      = $lines
            ExitCode   = $exitCode
            TimedOut   = $timedOut
            DurationMs = $stopwatch.ElapsedMilliseconds
            StartError = $null
        }
    }
    finally {
        if ($null -ne $process) { $process.Dispose() }
    }
}

function Get-RepoGitFactSet {
    <#
    .SYNOPSIS
        The eight bounded metadata reads the inventory sweep needs for one repo.
    .DESCRIPTION
        Raw values only. Exit-code fallbacks mirror the sweep's historical
        inline calls exactly ($null on failure, empty array for status); the
        owner regex, dirty-count parse and integer conversion stay with the
        caller so there is a single place those semantics live.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter()][ValidateRange(1, 600)][int]$TimeoutSeconds = 20,
        [Parameter()][string]$FileName = 'git'
    )

    $timedOutNames = New-Object System.Collections.Generic.List[string]
    $totalMs = [long]0

    $factSpecs = @(
        @{ Name = 'Branch';            ArgumentList = @('branch', '--show-current');                        Shape = 'single' }
        @{ Name = 'OriginUrl';         ArgumentList = @('remote', 'get-url', 'origin');                     Shape = 'single' }
        @{ Name = 'LastCommitDate';    ArgumentList = @('log', '-1', '--format=%cI');                       Shape = 'single' }
        @{ Name = 'StatusLines';       ArgumentList = @('status', '--short');                               Shape = 'lines' }
        @{ Name = 'LastCommitMessage'; ArgumentList = @('log', '-1', '--format=%s');                        Shape = 'single' }
        @{ Name = 'LastCommitAuthor';  ArgumentList = @('log', '-1', '--format=%an');                       Shape = 'single' }
        @{ Name = 'WeekCountRaw';      ArgumentList = @('rev-list', '--count', '--since=7 days ago', 'HEAD');  Shape = 'single' }
        @{ Name = 'MonthCountRaw';     ArgumentList = @('rev-list', '--count', '--since=30 days ago', 'HEAD'); Shape = 'single' }
    )

    $facts = @{}
    $shortCircuited = $false
    foreach ($spec in $factSpecs) {
        # Two timeouts in one repo mean the repo itself is hung -- a dead
        # network mapping or a wedged object store hangs all eight reads the
        # same way. Paying the timeout six more times tells us nothing new,
        # so the remaining facts are recorded as unavailable immediately.
        if ($shortCircuited) {
            if ($spec.Shape -eq 'lines') { $facts[$spec.Name] = @() } else { $facts[$spec.Name] = $null }
            continue
        }

        $result = Invoke-BoundedGitCommand -RepoPath $RepoPath -GitArgumentList $spec.ArgumentList -TimeoutSeconds $TimeoutSeconds -FileName $FileName
        $totalMs += [long]$result.DurationMs
        if ($result.TimedOut) { $timedOutNames.Add($spec.Name) }
        if ($timedOutNames.Count -ge 2) { $shortCircuited = $true }

        if ($spec.Shape -eq 'lines') {
            if ($result.ExitCode -eq 0) { $facts[$spec.Name] = @($result.Lines) } else { $facts[$spec.Name] = @() }
        }
        else {
            if ($result.ExitCode -eq 0) { $facts[$spec.Name] = $result.Value } else { $facts[$spec.Name] = $null }
        }
    }

    return [pscustomobject]@{
        RepoPath             = $RepoPath
        Branch               = $facts['Branch']
        OriginUrl            = $facts['OriginUrl']
        LastCommitDate       = $facts['LastCommitDate']
        StatusLines          = @($facts['StatusLines'])
        LastCommitMessage    = $facts['LastCommitMessage']
        LastCommitAuthor     = $facts['LastCommitAuthor']
        WeekCountRaw         = $facts['WeekCountRaw']
        MonthCountRaw        = $facts['MonthCountRaw']
        TimedOutCommandNames = $timedOutNames.ToArray()
        ShortCircuited       = $shortCircuited
        TotalDurationMs      = $totalMs
    }
}

function Invoke-BoundedRepoFactSweep {
    <#
    .SYNOPSIS
        Gather git fact sets for many repos on a capped runspace pool,
        preserving input order.
    .DESCRIPTION
        Returns an array aligned index-for-index with RepoPathList. A worker
        that fails outright yields $null at its index -- the caller treats that
        exactly like a repo whose every git call failed. OnRepoComplete (if
        given) is invoked on the caller's thread with the completed count each
        time a repo finishes, so a heartbeat can tick from inside the sweep.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter()][AllowEmptyCollection()][string[]]$RepoPathList = @(),
        [Parameter()][ValidateRange(1, 600)][int]$TimeoutSeconds = 20,
        [Parameter()][ValidateRange(1, 16)][int]$MaxConcurrency = 4,
        [Parameter()][string]$FileName = 'git',
        [Parameter()][scriptblock]$OnRepoComplete
    )

    $paths = @($RepoPathList)
    if ($paths.Count -eq 0) { return @() }

    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($functionName in @('Invoke-BoundedGitCommand', 'Get-RepoGitFactSet')) {
        $definition = (Get-Command $functionName -CommandType Function).Definition
        $entry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($functionName, $definition)
        $sessionState.Commands.Add($entry)
    }

    $pool = [runspacefactory]::CreateRunspacePool(1, $MaxConcurrency, $sessionState, $Host)
    $pool.Open()

    $resultByIndex = New-Object object[] $paths.Count
    $jobs = New-Object System.Collections.Generic.List[object]

    try {
        for ($i = 0; $i -lt $paths.Count; $i++) {
            $worker = [powershell]::Create()
            $worker.RunspacePool = $pool
            $null = $worker.AddCommand('Get-RepoGitFactSet').
                AddParameter('RepoPath', $paths[$i]).
                AddParameter('TimeoutSeconds', $TimeoutSeconds).
                AddParameter('FileName', $FileName)
            $jobs.Add([pscustomobject]@{
                Index     = $i
                Worker    = $worker
                Handle    = $worker.BeginInvoke()
                Collected = $false
            })
        }

        $completedCount = 0
        while ($completedCount -lt $jobs.Count) {
            $progressed = $false
            foreach ($job in $jobs) {
                if ($job.Collected -or -not $job.Handle.IsCompleted) { continue }
                try {
                    $output = $job.Worker.EndInvoke($job.Handle)
                    if (@($output).Count -gt 0) { $resultByIndex[$job.Index] = @($output)[0] }
                }
                catch {
                    # A failed worker is a repo whose facts are unavailable,
                    # not a failed sweep. The null is the caller's signal.
                    $resultByIndex[$job.Index] = $null
                }
                finally {
                    $job.Worker.Dispose()
                    $job.Collected = $true
                    $completedCount++
                    $progressed = $true
                }
                if ($OnRepoComplete) {
                    # A failing heartbeat tick must not abort the sweep it is
                    # only describing.
                    try { & $OnRepoComplete $completedCount } catch { $null = $_ }
                }
            }
            if (-not $progressed -and $completedCount -lt $jobs.Count) {
                Start-Sleep -Milliseconds 50
            }
        }
    }
    finally {
        foreach ($job in $jobs) {
            if (-not $job.Collected) {
                # Best-effort teardown on the abnormal path; a worker that
                # cannot stop cleanly must not mask the original failure.
                try { $job.Worker.Stop() } catch { $null = $_ }
                try { $job.Worker.Dispose() } catch { $null = $_ }
            }
        }
        $pool.Close()
        $pool.Dispose()
    }

    return ,$resultByIndex
}
