<#
.SYNOPSIS
    Report or apply safe branch hygiene cleanup for this repository.

.DESCRIPTION
    Helps keep local branch/worktree sprawl under control with one repeatable
    workflow:
    - fetch/prune from the selected remote
    - detect local branches already merged into remote default branch
    - detect branches whose upstream is gone
    - detect linked worktrees that block branch deletion
    - optionally remove safe targets

    Default mode is report-only. Use -Apply to perform deletions.

.PARAMETER RepoPath
    Path to the repository root. Defaults to this script's parent directory.

.PARAMETER Remote
    Remote name to compare against. Defaults to origin.

.PARAMETER DefaultBranch
    Default branch name fallback when remote HEAD is unavailable.

.PARAMETER StaleDays
    Age threshold used in report output to label stale branches.

.PARAMETER Apply
    Perform cleanup actions instead of report-only mode.

.PARAMETER RemoveLinkedWorktrees
    When -Apply is set, remove linked worktrees for cleanup candidates only if
    that linked worktree is clean.

.PARAMETER NoFetch
    Skip fetch/prune before analysis.

.PARAMETER OutputPath
    Optional JSON report path. Defaults to reports/branch-hygiene-latest.json.

.PARAMETER AsJson
    Emit JSON to stdout instead of a table.

.EXAMPLE
    pwsh ./tools/Invoke-BranchHygiene.ps1

.EXAMPLE
    pwsh ./tools/Invoke-BranchHygiene.ps1 -Apply -RemoveLinkedWorktrees
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()][string]$RepoPath,
    [Parameter()][string]$Remote = 'origin',
    [Parameter()][string]$DefaultBranch = 'main',
    [Parameter()][int]$StaleDays = 14,
    [Parameter()][switch]$Apply,
    [Parameter()][switch]$RemoveLinkedWorktrees,
    [Parameter()][switch]$NoFetch,
    [Parameter()][string]$OutputPath,
    [Parameter()][switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoPath) { $RepoPath = Split-Path -Parent $PSScriptRoot }
$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
    throw "Not a git repository: $RepoPath"
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $RepoPath 'reports/branch-hygiene-latest.json'
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter()][switch]$AllowFailure
    )

    $output = & git -C $RepoPath @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE
    $text = (@($output) -join "`n").Trim()

    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "git $($ArgumentList -join ' ') failed (exit $exitCode): $text"
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Text = $text
    }
}

function Get-RemoteDefaultBranch {
    param([string]$RemoteName, [string]$Fallback)

    $res = Invoke-Git -ArgumentList @('symbolic-ref', '--quiet', '--short', ("refs/remotes/{0}/HEAD" -f $RemoteName)) -AllowFailure
    if ($res.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($res.Text)) {
        $fullRef = $res.Text.Trim()
        if ($fullRef -like ("{0}/*" -f $RemoteName)) {
            return ($fullRef -replace ("^{0}/" -f [regex]::Escape($RemoteName)), '')
        }
    }

    return $Fallback
}

function Get-LinkedWorktreesByBranch {
    $map = @{}
    $res = Invoke-Git -ArgumentList @('worktree', 'list', '--porcelain') -AllowFailure
    if ($res.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($res.Text)) {
        return $map
    }

    $currentPath = ''
    foreach ($line in ($res.Text -split "`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -like 'worktree *') {
            $currentPath = $trimmed.Substring(9)
            continue
        }
        if ($trimmed -like 'branch refs/heads/*') {
            $branchName = $trimmed.Substring(18)
            $map[$branchName] = $currentPath
        }
    }

    return $map
}

function Test-WorktreeClean {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    $out = & git -C $Path status --porcelain 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { return $false }

    return [string]::IsNullOrWhiteSpace((@($out) -join "`n").Trim())
}

if (-not $NoFetch) {
    Invoke-Git -ArgumentList @('fetch', '--prune', $Remote) | Out-Null
}

$effectiveDefaultBranch = Get-RemoteDefaultBranch -RemoteName $Remote -Fallback $DefaultBranch
$comparisonRef = "{0}/{1}" -f $Remote, $effectiveDefaultBranch

$mergedOutput = Invoke-Git -ArgumentList @('branch', '--format=%(refname:short)', '--merged', $comparisonRef)
$mergedSet = @{}
foreach ($line in ($mergedOutput.Text -split "`n")) {
    $name = $line.Trim()
    if (-not [string]::IsNullOrWhiteSpace($name)) {
        $mergedSet[$name] = $true
    }
}

$currentBranch = (Invoke-Git -ArgumentList @('rev-parse', '--abbrev-ref', 'HEAD')).Text.Trim()
$worktreeMap = Get-LinkedWorktreesByBranch

$format = "%(refname:short)|%(upstream:short)|%(upstream:track)|%(committerdate:iso8601-strict)|%(objectname:short)|%(subject)"
$branchesText = (Invoke-Git -ArgumentList @('for-each-ref', '--sort=-committerdate', ("--format={0}" -f $format), 'refs/heads')).Text

$rows = @()
foreach ($record in ($branchesText -split "`n")) {
    if ([string]::IsNullOrWhiteSpace($record)) { continue }

    # Split only the first 5 delimiters so commit subjects can contain '|'.
    $fields = $record -split '\|', 6
    if ($fields.Count -lt 6) { continue }

    $branchName = $fields[0].Trim()
    if ([string]::IsNullOrWhiteSpace($branchName)) { continue }

    $upstream = $fields[1].Trim()
    $track = $fields[2].Trim()
    $commitDateRaw = $fields[3].Trim()
    $shaShort = $fields[4].Trim()
    $subject = $fields[5].Trim()

    $isProtected = ($branchName -eq $effectiveDefaultBranch -or $branchName -eq 'main' -or $branchName -eq 'master')
    $isCurrent = ($branchName -eq $currentBranch)
    $isMerged = $mergedSet.ContainsKey($branchName)
    $upstreamGone = ($track -match '\[gone\]')

    $linkedWorktree = ''
    if ($worktreeMap.ContainsKey($branchName)) {
        $linkedWorktree = [string]$worktreeMap[$branchName]
    }

    $linkedClean = $null
    if (-not [string]::IsNullOrWhiteSpace($linkedWorktree)) {
        $linkedClean = Test-WorktreeClean -Path $linkedWorktree
    }

    $ageDays = $null
    if (-not [string]::IsNullOrWhiteSpace($commitDateRaw)) {
        [datetime]$parsedDate = [datetime]::MinValue
        if ([datetime]::TryParse($commitDateRaw, [ref]$parsedDate)) {
            $ageDays = [int]((Get-Date) - $parsedDate).TotalDays
        }
    }

    $isStale = $false
    if ($null -ne $ageDays -and $ageDays -ge $StaleDays) {
        $isStale = $true
    }

    $plannedAction = 'keep'
    if ($isMerged -and -not $isProtected -and -not $isCurrent) {
        if (-not [string]::IsNullOrWhiteSpace($linkedWorktree)) {
            $plannedAction = 'requires-worktree-removal'
        } else {
            $plannedAction = 'delete-local-branch'
        }
    }

    $rows += [pscustomobject]@{
        Branch = $branchName
        Sha = $shaShort
        Merged = $isMerged
        Upstream = $upstream
        UpstreamGone = $upstreamGone
        AgeDays = $ageDays
        Stale = $isStale
        LinkedWorktree = $linkedWorktree
        LinkedClean = $linkedClean
        IsCurrent = $isCurrent
        Protected = $isProtected
        PlannedAction = $plannedAction
        LastCommitSubject = $subject
    }
}

$actions = @()
if ($Apply) {
    $targets = @($rows | Where-Object { $_.PlannedAction -ne 'keep' })

    foreach ($target in $targets) {
        $branchName = [string]$target.Branch
        $linkedPath = [string]$target.LinkedWorktree

        if (-not [string]::IsNullOrWhiteSpace($linkedPath)) {
            if (-not $RemoveLinkedWorktrees) {
                $actions += [pscustomobject]@{ branch = $branchName; action = 'skip'; reason = 'linked worktree exists; rerun with -RemoveLinkedWorktrees' }
                continue
            }
            if (-not $target.LinkedClean) {
                $actions += [pscustomobject]@{ branch = $branchName; action = 'skip'; reason = 'linked worktree is not clean' }
                continue
            }

            if ($PSCmdlet.ShouldProcess($linkedPath, 'git worktree remove')) {
                $worktreeRemove = Invoke-Git -ArgumentList @('worktree', 'remove', $linkedPath) -AllowFailure
                if ($worktreeRemove.ExitCode -ne 0) {
                    $actions += [pscustomobject]@{ branch = $branchName; action = 'skip'; reason = ("worktree removal failed: {0}" -f $worktreeRemove.Text) }
                    continue
                }
                $actions += [pscustomobject]@{ branch = $branchName; action = 'worktree-removed'; reason = $linkedPath }
            }
        }

        if ($PSCmdlet.ShouldProcess($branchName, 'git branch -d')) {
            $branchDelete = Invoke-Git -ArgumentList @('branch', '-d', $branchName) -AllowFailure
            if ($branchDelete.ExitCode -eq 0) {
                $actions += [pscustomobject]@{ branch = $branchName; action = 'branch-deleted'; reason = '' }
            } else {
                $actions += [pscustomobject]@{ branch = $branchName; action = 'skip'; reason = ("branch delete failed: {0}" -f $branchDelete.Text) }
            }
        }
    }
}

$mode = 'report'
if ($Apply) { $mode = 'apply' }

$mergedCandidates = @($rows | Where-Object { $_.PlannedAction -ne 'keep' })
$upstreamGone = @($rows | Where-Object { $_.UpstreamGone })
$staleBranches = @($rows | Where-Object { $_.Stale })

$report = [ordered]@{
    generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    repository = $RepoPath
    remote = $Remote
    defaultBranch = $effectiveDefaultBranch
    comparedTo = $comparisonRef
    mode = $mode
    staleDays = $StaleDays
    summary = [ordered]@{
        localBranches = @($rows).Count
        mergedCandidates = @($mergedCandidates).Count
        upstreamGone = @($upstreamGone).Count
        stale = @($staleBranches).Count
    }
    branches = @($rows)
    actions = @($actions)
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$reportJson = $report | ConvertTo-Json -Depth 6
$reportJson | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($AsJson) {
    Write-Output $reportJson
    exit 0
}

Write-Host ("Branch hygiene mode: {0}" -f $report.mode) -ForegroundColor Cyan
Write-Host ("Compared to: {0}" -f $report.comparedTo) -ForegroundColor Cyan
Write-Host ("Report path: {0}" -f $OutputPath) -ForegroundColor DarkCyan

$rows |
    Select-Object Branch, Merged, UpstreamGone, AgeDays, Stale, LinkedWorktree, PlannedAction |
    Format-Table -AutoSize

if ($Apply) {
    Write-Host ''
    Write-Host 'Actions:' -ForegroundColor Yellow
    if (@($actions).Count -eq 0) {
        Write-Host '  (no actions taken)'
    } else {
        $actions | Format-Table -AutoSize
    }
}
