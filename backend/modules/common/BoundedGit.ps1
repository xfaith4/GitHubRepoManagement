# Bounded per-repository git work (Release 3.2).
#
# Why this file exists: the portfolio sweep ran SEVEN sequential `git` calls per
# repository (branch, remote get-url, log x3, status, rev-list x2) with no
# timeout on any of them — roughly 525 process launches across the real 75-repo
# workspace, one after another. A single pathological repository was therefore
# able to stall the entire sweep indefinitely: a stale `index.lock`, a repo on a
# disconnected network share, a filesystem filter driver mid-scan, or a `git`
# that simply never returns. Nothing bounded that wait except the Lane 0.4
# request deadline, and that "bound" is `Environment.FailFast` — the guard
# destroying the host it exists to protect, which is the outage Lane 0.9 records
# three separate times.
#
# So the contract here is: no single repository can consume more than its
# timeout, and no sweep can run more git processes at once than its cap.
#
# Dot-sourced and dependency-free on purpose. It is loaded into worker runspaces
# by Get-LocalFolderInventory, so it must not require the reconcile module (or
# anything else) to already be in scope.
#
# PowerShell 5.1 compatible, deliberately:
#  - `ProcessStartInfo.ArgumentList` is .NET Core only, so arguments are quoted
#    into `.Arguments` by hand.
#  - Output is drained with `ReadToEndAsync()` BEFORE waiting for exit. Reading
#    after `WaitForExit` deadlocks the moment a child fills the ~4KB pipe
#    buffer, and `git status --short` on a very dirty repository does exactly
#    that — which would turn a hang-prevention feature into a new hang.
#
# Known limitation, stated rather than hidden: `Process.Kill()` on .NET
# Framework terminates only the process, not its tree. If the killed child has
# itself spawned something that inherited the redirected pipes, the drain tasks
# wait out their own 2s bound before this returns — so the effective ceiling is
# roughly `TimeoutSeconds + 4`, not `TimeoutSeconds`. That overshoot is measured
# and accounted for in the worst-case budget assertion in the module smoke
# (which checks the total stays under the watchdog's 120s tolerance). It matters
# little for the probes here — `git rev-parse`/`log`/`status` do not fork
# long-lived helpers, and output redirection already suppresses the pager — but
# it is the reason the budget, not the per-call timeout, is what actually bounds
# a repository.

# A timeout below this cannot be met by a cold `git` invocation on Windows
# (process start alone is tens of ms, and a first call into a large repo pays
# for the filesystem cache), so a misconfigured 0 would report every repo as
# timed out. The ceiling keeps a per-repo bound well inside the 900s scan-route
# request deadline.
$script:BoundedGitTimeoutFloorSeconds   = 2
$script:BoundedGitTimeoutCeilingSeconds = 120
$script:BoundedGitDefaultTimeoutSeconds = 20

# Concurrency is capped rather than unbounded because each unit is a real OS
# process doing disk I/O; past a small multiple of the core count, more workers
# make a sweep slower, not faster, and can starve the host's own request loop.
$script:BoundedGitConcurrencyFloor   = 1
$script:BoundedGitConcurrencyCeiling = 16

function Get-BoundedGitPolicy {
    <# Pure: resolve the timeout and concurrency cap for a sweep.

       Both are clamped rather than rejected, so a typo degrades to a usable
       bound instead of disabling the protection. The concurrency default is
       derived from the machine (cores, capped) because a fixed number is wrong
       on both a 4-core laptop and a 32-core workstation. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][object]$Settings = $null,
        [Parameter()][int]$ProcessorCount = 0
    )

    $cores = if ($ProcessorCount -gt 0) { $ProcessorCount } else { [Environment]::ProcessorCount }
    if ($cores -lt 1) { $cores = 1 }

    $timeout = $script:BoundedGitDefaultTimeoutSeconds
    # Half the cores: the sweep is I/O bound, but the host process still has to
    # answer its own request loop and publish progress while this runs.
    $concurrency = [math]::Max(2, [math]::Floor($cores / 2))

    if ($null -ne $Settings -and $Settings -is [System.Collections.IDictionary] -and $Settings.Contains('inventory')) {
        $inv = $Settings['inventory']
        if ($null -ne $inv -and $inv -is [System.Collections.IDictionary]) {
            if ($inv.Contains('gitTimeoutSeconds')) {
                $parsedTimeout = 0
                if ([int]::TryParse([string]$inv['gitTimeoutSeconds'], [ref]$parsedTimeout)) { $timeout = $parsedTimeout }
            }
            if ($inv.Contains('gitMaxConcurrency')) {
                $parsedConcurrency = 0
                if ([int]::TryParse([string]$inv['gitMaxConcurrency'], [ref]$parsedConcurrency)) { $concurrency = $parsedConcurrency }
            }
        }
    }

    if ($timeout -lt $script:BoundedGitTimeoutFloorSeconds) { $timeout = $script:BoundedGitTimeoutFloorSeconds }
    if ($timeout -gt $script:BoundedGitTimeoutCeilingSeconds) { $timeout = $script:BoundedGitTimeoutCeilingSeconds }
    if ($concurrency -lt $script:BoundedGitConcurrencyFloor) { $concurrency = $script:BoundedGitConcurrencyFloor }
    if ($concurrency -gt $script:BoundedGitConcurrencyCeiling) { $concurrency = $script:BoundedGitConcurrencyCeiling }

    return [pscustomobject]@{
        TimeoutSeconds = [int]$timeout
        MaxConcurrency = [int]$concurrency
    }
}

function ConvertTo-GitArgumentString {
    <# Quote an argument vector into a single command line for PS 5.1, whose
       ProcessStartInfo has no ArgumentList. Only arguments containing spaces or
       quotes are quoted, so the resulting line stays greppable in a log. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()][AllowEmptyCollection()][string[]]$Arguments = @())

    $parts = foreach ($item in @($Arguments)) {
        $value = [string]$item
        if ($value -match '[\s"]') {
            '"' + ($value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
        } else {
            $value
        }
    }
    return ($parts -join ' ')
}

function Invoke-BoundedGit {
    <# Run one `git` command with a hard wall-clock bound.

       Returns a result object rather than throwing, because every caller here
       treats a failed metadata probe as "unknown", not as fatal — but a TIMEOUT
       is reported distinctly from a non-zero exit, since they mean different
       things: a non-zero exit is usually a legitimate answer ("no upstream",
       "not a repo"), while a timeout means the repository is pathological and
       the operator should be told which one. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter()][int]$TimeoutSeconds = 20,
        # Overridable so the timeout path is provable. A guard that only ever
        # runs against `git` — which does not hang on demand — could never be
        # adversarially tested, and an untested timeout is one that has never
        # fired. The module smoke substitutes a process that sleeps.
        [Parameter()][string]$Executable = 'git',
        [Parameter()][switch]$NoRepoPathArgument
    )

    $fullArgs = if ($NoRepoPathArgument) { @($Arguments) } else { @('-C', $RepoPath) + $Arguments }
    $argLine = ConvertTo-GitArgumentString -Arguments $fullArgs
    $commandText = $Executable + ' ' + $argLine
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Executable
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try {
        [void]$proc.Start()
    } catch {
        $sw.Stop()
        # git missing from PATH, or the path unreachable. Named, never swallowed.
        return [pscustomobject]@{
            Ok          = $false
            TimedOut    = $false
            ExitCode    = -1
            Stdout      = ''
            Stderr      = $_.Exception.Message
            DurationMs  = [int]$sw.ElapsedMilliseconds
            Command     = $commandText
            StartFailed = $_.Exception.Message
        }
    }

    $stdout = ''
    $stderr = ''
    $timedOut = $false
    $exitCode = -1

    try {
        # Drain BEFORE waiting. A synchronous read after WaitForExit deadlocks
        # as soon as the child fills the pipe buffer.
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()

        if ($proc.WaitForExit($TimeoutSeconds * 1000)) {
            $exitCode = $proc.ExitCode
        } else {
            $timedOut = $true
            # Best-effort by design, but never silent: a kill that fails still
            # leaves TimedOut=$true, so the caller's verdict is unchanged and
            # the reason is recoverable from the verbose stream.
            try { $proc.Kill() } catch { Write-Verbose ("Kill failed for '{0}': {1}" -f $commandText, $_.Exception.Message) }
            # Let the pipes close so the drain tasks complete; whatever the
            # child produced before the kill is still useful evidence.
            try { [void]$proc.WaitForExit(2000) } catch { Write-Verbose ("Post-kill wait failed for '{0}': {1}" -f $commandText, $_.Exception.Message) }
        }

        try { if ($outTask.Wait(2000)) { $stdout = [string]$outTask.Result } } catch { Write-Verbose ("stdout drain failed for '{0}': {1}" -f $commandText, $_.Exception.Message) }
        try { if ($errTask.Wait(2000)) { $stderr = [string]$errTask.Result } } catch { Write-Verbose ("stderr drain failed for '{0}': {1}" -f $commandText, $_.Exception.Message) }
    }
    finally {
        try { $proc.Dispose() } catch { Write-Verbose ("Dispose failed for '{0}': {1}" -f $commandText, $_.Exception.Message) }
        $sw.Stop()
    }

    return [pscustomobject]@{
        Ok          = (-not $timedOut) -and ($exitCode -eq 0)
        TimedOut    = $timedOut
        ExitCode    = $exitCode
        Stdout      = $stdout
        Stderr      = $stderr
        DurationMs  = [int]$sw.ElapsedMilliseconds
        Command     = $commandText
        StartFailed = ''
    }
}

function Get-BoundedGitProbeText {
    <# A probe's trimmed stdout, or $null when it failed, timed out, or produced
       nothing. One helper so "failed" and "empty" collapse to the same $null the
       previous implementation produced, and no call site re-invents the check. #>
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter()][object]$Result)

    if ($null -eq $Result -or -not $Result.Ok) { return $null }
    $text = ([string]$Result.Stdout).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text
}

function Get-RepoGitDetail {
    <# The per-repository metadata probe: every `git` call the inventory sweep
       makes for one repo, each individually bounded.

       A failed or timed-out probe yields $null/0 for that field — the same
       shape the previous unbounded implementation produced on error — so
       downstream consumers need no change. What is NEW is that the result says
       so: `TimedOut` and `TimedOutCommands` make a pathological repository
       visible instead of letting it read as a repo that merely has no commits.
       Silence there would be the "0 repos scanned" class of bug this product
       exists to catch. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter()][int]$TimeoutSeconds = 20,
        # A per-call timeout alone is NOT enough, and this is the subtle part.
        # Eight probes at 20s each is a 160s worst case for one repository —
        # past the watchdog's 120s no-progress tolerance. Since progress may
        # only be published on real completions (never on a timer, or the
        # heartbeat would keep a wedged host alive), one pathological repo could
        # therefore starve the heartbeat and trigger the exact restart-loop
        # outage Lane 0.9 exists to prevent. A whole-repo budget caps the silent
        # window at roughly one timeout past the budget instead.
        [Parameter()][int]$TotalBudgetSeconds = 0,
        # Same reason as Invoke-BoundedGit's: without it the budget-exhaustion
        # path is untestable, because `git` cannot be made to hang on demand.
        # The module smoke points this at a shim that sleeps.
        [Parameter()][string]$Executable = 'git'
    )

    if ($TotalBudgetSeconds -le 0) { $TotalBudgetSeconds = $TimeoutSeconds * 2 }

    # One table, one loop: this list IS the contract for what the sweep asks of
    # each repository, so adding or removing a call is a visible edit here
    # rather than another copy of the try/catch block it replaces.
    $probes = @(
        @{ Key = 'branch'; Args = @('branch', '--show-current') }
        @{ Key = 'origin'; Args = @('remote', 'get-url', 'origin') }
        @{ Key = 'date';   Args = @('log', '-1', '--format=%cI') }
        @{ Key = 'status'; Args = @('status', '--short') }
        @{ Key = 'msg';    Args = @('log', '-1', '--format=%s') }
        @{ Key = 'author'; Args = @('log', '-1', '--format=%an') }
        @{ Key = 'week';   Args = @('rev-list', '--count', '--since=7 days ago', 'HEAD') }
        @{ Key = 'month';  Args = @('rev-list', '--count', '--since=30 days ago', 'HEAD') }
    )

    $timedOutCommands = New-Object System.Collections.Generic.List[string]
    $abandonedCommands = New-Object System.Collections.Generic.List[string]
    $results = @{}
    $totalMs = 0
    $budgetMs = $TotalBudgetSeconds * 1000
    $budgetExhausted = $false

    foreach ($probe in $probes) {
        if ($budgetExhausted) {
            # Abandoned, not silently skipped. A probe that never ran must not
            # be indistinguishable from one that ran and found nothing.
            [void]$abandonedCommands.Add(($probe.Args -join ' '))
            $results[$probe.Key] = $null
            continue
        }

        # Never let one probe's own timeout carry us past the whole-repo budget.
        $remainingSeconds = [math]::Ceiling(($budgetMs - $totalMs) / 1000)
        $probeTimeout = [math]::Min($TimeoutSeconds, [math]::Max(1, $remainingSeconds))

        $probeResult = Invoke-BoundedGit -RepoPath $RepoPath -Arguments $probe.Args -TimeoutSeconds $probeTimeout -Executable $Executable
        $totalMs += $probeResult.DurationMs
        if ($probeResult.TimedOut) { [void]$timedOutCommands.Add(($probe.Args -join ' ')) }
        $results[$probe.Key] = $probeResult

        if ($totalMs -ge $budgetMs) { $budgetExhausted = $true }
    }

    $branch            = Get-BoundedGitProbeText -Result $results['branch']
    $originUrl         = Get-BoundedGitProbeText -Result $results['origin']
    $lastCommitDate    = Get-BoundedGitProbeText -Result $results['date']
    $lastCommitMessage = Get-BoundedGitProbeText -Result $results['msg']
    $lastCommitAuthor  = Get-BoundedGitProbeText -Result $results['author']

    $statusShort = if ($null -ne $results['status'] -and $results['status'].Ok) {
        @(([string]$results['status'].Stdout) -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    } else { @() }

    $commitsLastWeek = 0
    $weekText = Get-BoundedGitProbeText -Result $results['week']
    if ($weekText -match '^\d+$') { $commitsLastWeek = [int]$weekText }

    $commitsLastMonth = 0
    $monthText = Get-BoundedGitProbeText -Result $results['month']
    if ($monthText -match '^\d+$') { $commitsLastMonth = [int]$monthText }

    # Owner/repo derivation stays with the metadata that produced it, so a
    # caller cannot pair an origin URL with a mismatched parse.
    $ownerGuess = $null
    $repoNameGuess = $null
    if ($originUrl -and ($originUrl -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)(\.git)?$')) {
        $ownerGuess = $Matches['owner']
        $repoNameGuess = $Matches['repo']
    }

    $modifiedCount = 0
    $untrackedCount = 0
    $otherStatusCount = 0
    foreach ($line in @($statusShort)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('??')) { $untrackedCount++ }
        elseif ($line.Length -ge 2) { $modifiedCount++ }
        else { $otherStatusCount++ }
    }

    return [pscustomobject]@{
        CurrentBranch     = $branch
        GitOriginUrl      = $originUrl
        GitOwnerGuess     = $ownerGuess
        GitRepoName       = $repoNameGuess
        LastCommitDate    = $lastCommitDate
        LastCommitMessage = $lastCommitMessage
        LastCommitAuthor  = $lastCommitAuthor
        CommitsLastWeek   = $commitsLastWeek
        CommitsLastMonth  = $commitsLastMonth
        ModifiedCount     = $modifiedCount
        UntrackedCount    = $untrackedCount
        OtherStatusCount  = $otherStatusCount
        TimedOut          = ($timedOutCommands.Count -gt 0)
        TimedOutCommands  = $timedOutCommands.ToArray()
        BudgetExhausted   = $budgetExhausted
        AbandonedCommands = $abandonedCommands.ToArray()
        GitDurationMs     = [int]$totalMs
    }
}
