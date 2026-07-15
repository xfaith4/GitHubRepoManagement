#Requires -Version 7.0
<#
.SYNOPSIS
    Local runner: execute queued roadmap tasks with Claude Code on the LOCAL repo.

.DESCRIPTION
    Run this AS YOURSELF (your Claude Code auth + your `claude` on PATH) — never as
    the portal service. It watches output/roadmap-task-queue.jsonl for tasks the
    portal enqueued (status='queued' in their run summary) and, for each:

      claim (status='running') -> create branch roadmap/<runId> -> launch `claude`
      in the target repo with the task prompt -> best-effort verify -> commit any
      changes on the branch -> status='awaiting-review'.

    It STOPS there. Nothing is pushed to GitHub — you review the branch and push /
    open a PR yourself. Status flows back to the portal via the existing run
    summary (Get-RoadmapTaskHistory), so the ROADMAP modal reflects progress.

.PARAMETER Once
    Process the currently-queued tasks and exit (default is a poll loop).

.PARAMETER Headless
    Run `claude -p "<prompt>"` non-interactively instead of an interactive session.
    Tasks that run commands may need -PermissionMode bypassPermissions to avoid
    stalling on a prompt that headless mode cannot answer.

.PARAMETER PermissionMode
    Claude Code permission mode. Default 'acceptEdits' (auto-accept file edits).

.PARAMETER DryRun
    Show what would happen for each queued task without claiming, branching,
    launching claude, or committing. Safe to demo.

.PARAMETER LoadFunctionsOnly
    Dot-source the pure functions without running (used by the module smoke).

.EXAMPLE
    pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1 -Once
.EXAMPLE
    pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1 -Headless -PermissionMode bypassPermissions
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [string]$QueuePath,
    [switch]$Once,
    [switch]$Headless,
    [string]$PermissionMode = 'acceptEdits',
    [int]$PollSeconds = 15,
    [switch]$DryRun,
    [switch]$LoadFunctionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) { $WorkspaceRoot = Split-Path -Parent $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($QueuePath)) { $QueuePath = Join-Path $WorkspaceRoot 'output\roadmap-task-queue.jsonl' }
$runsDir = Join-Path $WorkspaceRoot 'output\roadmap-task-history\runs'

# ── Pure / testable helpers (module smoke covers these; no git, no claude) ────
function Get-QueueEntries {
    param([Parameter(Mandatory)][string]$QueuePath)
    $entries = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $QueuePath)) { return $entries.ToArray() }
    foreach ($line in (Get-Content -LiteralPath $QueuePath -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entries.Add(($line | ConvertFrom-Json)) } catch { }
    }
    return $entries.ToArray()
}

function New-TaskCommitMessage {
    param([Parameter(Mandatory)][string]$SelectedTask, [Parameter(Mandatory)][string]$RunId)
    $t = $SelectedTask.Trim()
    if ($t.Length -gt 68) { $t = $t.Substring(0, 68) }
    return "roadmap: $t`n`nRun: $RunId (queued via portal, executed by the local runner)."
}

function Resolve-VerifyCommand {
    <# Best-effort detection of a per-repo check. Returns a scriptblock-friendly
       command string or $null. Non-blocking — a failing verify is recorded, not
       fatal. #>
    param([Parameter(Mandatory)][string]$RepoPath)
    $pkg = Join-Path $RepoPath 'package.json'
    if (Test-Path -LiteralPath $pkg) {
        try {
            $j = Get-Content -LiteralPath $pkg -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.PSObject.Properties.Name -contains 'scripts' -and $j.scripts.PSObject.Properties.Name -contains 'test') {
                return 'npm test'
            }
        }
        catch { }
    }
    if (Test-Path -LiteralPath (Join-Path $RepoPath 'scripts\Invoke-TestSuite.ps1')) { return 'pwsh -NoProfile -File scripts/Invoke-TestSuite.ps1' }
    return $null
}

function Get-TaskSummaryStatus {
    param([Parameter(Mandatory)][string]$SummaryPath)
    if (-not (Test-Path -LiteralPath $SummaryPath)) { return $null }
    try { return [string]((Get-Content -LiteralPath $SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json).status) } catch { return $null }
}

function Update-TaskSummary {
    param([Parameter(Mandatory)][string]$SummaryPath, [Parameter(Mandatory)][hashtable]$Set)
    $obj = @{}
    if (Test-Path -LiteralPath $SummaryPath) {
        try { $obj = Get-Content -LiteralPath $SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable } catch { $obj = @{} }
    }
    foreach ($k in $Set.Keys) { $obj[$k] = $Set[$k] }
    ($obj | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
}

if ($LoadFunctionsOnly) { return }

# ── Execution ─────────────────────────────────────────────────────────────────
function Invoke-QueuedTask {
    param([object]$Entry)
    $runId = [string]$Entry.runId
    $repo = [string]$Entry.localRepoPath
    $branch = if ($Entry.PSObject.Properties.Name -contains 'branch' -and $Entry.branch) { [string]$Entry.branch } else { "roadmap/$runId" }
    $prompt = [string]$Entry.prompt
    $summaryPath = Join-Path $runsDir ("{0}.summary.json" -f $runId)

    Write-Host ("`n[task] runId={0} repo={1}" -f $runId, $repo) -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "  [DRYRUN] would: claim -> git switch -c $branch -> launch claude -> verify -> commit -> awaiting-review" -ForegroundColor Yellow
        Write-Host ("  [DRYRUN] claude {0} (cwd={1})" -f $(if ($Headless) { "-p <prompt> --permission-mode $PermissionMode" } else { "--permission-mode $PermissionMode <prompt>" }), $repo) -ForegroundColor Yellow
        return
    }

    Update-TaskSummary -SummaryPath $summaryPath -Set @{ status = 'running'; runnerStartedAt = (Get-Date).ToString('o') }
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { throw "Not a git repo: $repo" }

        # Working branch (create, or switch if it already exists).
        & git -C $repo switch -c $branch 2>$null
        if ($LASTEXITCODE -ne 0) {
            & git -C $repo switch $branch 2>$null
            if ($LASTEXITCODE -ne 0) { throw "Failed to switch to branch '$branch' in repo '$repo'." }
        }

        # Launch Claude Code in the repo.
        if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { throw "'claude' not found on PATH. Run this as the operator with Claude Code installed." }
        Push-Location $repo
        try {
            if ($Headless) { & claude -p $prompt --permission-mode $PermissionMode }
            else { & claude --permission-mode $PermissionMode $prompt }
            if ($LASTEXITCODE -ne 0) { throw "Claude Code execution failed with exit code $LASTEXITCODE." }
        }
        finally { Pop-Location }

        # Best-effort verify.
        $verifyResult = 'skipped'
        $verifyCmd = Resolve-VerifyCommand -RepoPath $repo
        if ($verifyCmd) {
            Write-Host ("  verify: {0}" -f $verifyCmd) -ForegroundColor DarkGray
            Push-Location $repo
            try { Invoke-Expression $verifyCmd | Out-Null; $verifyResult = if ($LASTEXITCODE -eq 0) { 'passed' } else { 'failed' } }
            catch { $verifyResult = 'error' }
            finally { Pop-Location }
        }

        # Commit any changes on the branch (operator may have already committed inside the session).
        $dirty = @(& git -C $repo status --porcelain)
        $filesChanged = $dirty.Count
        if ($filesChanged -gt 0) {
            & git -C $repo add -A
            & git -C $repo commit -m (New-TaskCommitMessage -SelectedTask ([string]$Entry.selectedTask) -RunId $runId) | Out-Null
        }
        $commitSha = (& git -C $repo rev-parse --short HEAD 2>$null)

        Update-TaskSummary -SummaryPath $summaryPath -Set @{
            status          = 'awaiting-review'
            branch          = $branch
            commitSha       = "$commitSha"
            filesChanged    = $filesChanged
            verifyResult    = $verifyResult
            runnerCompletedAt = (Get-Date).ToString('o')
        }
        Write-Host ("  [awaiting-review] branch={0} commit={1} files={2} verify={3}" -f $branch, $commitSha, $filesChanged, $verifyResult) -ForegroundColor Green
        Write-Host "  Review the branch, then push / open a PR yourself." -ForegroundColor DarkGray
    }
    catch {
        Update-TaskSummary -SummaryPath $summaryPath -Set @{ status = 'failed'; error = $_.Exception.Message; runnerCompletedAt = (Get-Date).ToString('o') }
        Write-Host ("  [failed] {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ("Roadmap task runner — queue: {0}" -f $QueuePath) -ForegroundColor White
Write-Host ("  mode: {0}{1}  permission: {2}" -f $(if ($Headless) { 'headless' } else { 'interactive' }), $(if ($DryRun) { ' (dry-run)' } else { '' }), $PermissionMode) -ForegroundColor DarkGray

do {
    $claimable = @(Get-QueueEntries -QueuePath $QueuePath | Where-Object {
            (Get-TaskSummaryStatus -SummaryPath (Join-Path $runsDir ("{0}.summary.json" -f $_.runId))) -eq 'queued'
        })
    if ($claimable.Count -eq 0) {
        if ($Once) { Write-Host 'No queued tasks.' -ForegroundColor DarkGray; break }
        Start-Sleep -Seconds $PollSeconds
        continue
    }
    foreach ($entry in $claimable) { Invoke-QueuedTask -Entry $entry }
    if ($Once) { break }
    Start-Sleep -Seconds $PollSeconds
} while ($true)
