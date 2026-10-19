<#
.SYNOPSIS
    The first command of every session: live repository state plus the handoff.

.DESCRIPTION
    Replaces re-discovery. In one screen it reports what a fresh agent otherwise
    spends its context finding: the checkout and its distance from origin/main,
    every worktree, dirty files, open PRs with the checks on their head, open
    defects by triage label, the operator queue, the roadmap's open Current-focus
    items and how old that section is, the one open handoff issue, and any
    handoff-shaped notes left under output/ (evidence, never the record).

    Everything except the handoff issue body is read live, so nothing here can be
    stale. A section that cannot be read says "unavailable" and why; it is never
    silently empty.

.PARAMETER WorkspaceRoot
    Repository root. Defaults to this script's parent directory.

.PARAMETER NoFetch
    Skip `git fetch origin`. The ahead/behind figures are then against the last
    fetched origin/main and say so.

.PARAMETER SkipGitHub
    Skip every gh call (offline use, and the gate's end-to-end run).

.PARAMETER AsJson
    Emit the briefing as JSON instead of text.

.EXAMPLE
    pwsh ./tools/Get-SessionBriefing.ps1

.EXAMPLE
    pwsh ./tools/Get-SessionBriefing.ps1 -AsJson -NoFetch
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot,
    [Parameter()][switch]$NoFetch,
    [Parameter()][switch]$SkipGitHub,
    [Parameter()][switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $PSScriptRoot is empty inside param() defaults on Windows PowerShell 5.1.
if (-not $WorkspaceRoot) { $WorkspaceRoot = Split-Path -Parent $PSScriptRoot }
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
. (Join-Path $PSScriptRoot 'SessionHandoff.ps1')

function Invoke-NativeText {
    # Runs a native command; returns @{ ok; text; error } instead of throwing, so
    # one unreadable source degrades its own section rather than the briefing.
    param([string]$FilePath, [string[]]$ArgumentList)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $FilePath @ArgumentList 2>&1
        $code = $LASTEXITCODE
    } catch {
        return [pscustomobject]@{ ok = $false; text = ''; error = $_.Exception.Message }
    } finally {
        $ErrorActionPreference = $previous
    }
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() }) -join ' '
    if ($code -ne 0) {
        $reason = $stderr
        if (-not $reason) { $reason = "exit code $code" }
        return [pscustomobject]@{ ok = $false; text = $stdout; error = $reason.Trim() }
    }
    [pscustomobject]@{ ok = $true; text = $stdout; error = $null }
}

function Get-GitSection {
    param([string]$Root, [bool]$Fetch)
    $fetchNote = 'not fetched this run'
    if ($Fetch) {
        $f = Invoke-NativeText git @('-C', $Root, 'fetch', 'origin', '--quiet')
        if ($f.ok) { $fetchNote = 'fetched' } else { $fetchNote = "fetch failed: $($f.error)" }
    }
    $branch = (Invoke-NativeText git @('-C', $Root, 'branch', '--show-current')).text.Trim()
    $head = (Invoke-NativeText git @('-C', $Root, 'rev-parse', '--short', 'HEAD')).text.Trim()
    $originMain = Invoke-NativeText git @('-C', $Root, 'rev-parse', '--short', 'origin/main')
    $counts = Invoke-NativeText git @('-C', $Root, 'rev-list', '--left-right', '--count', 'origin/main...HEAD')
    $behind = $null; $ahead = $null
    if ($counts.ok -and $counts.text -match '^(\d+)\s+(\d+)') { $behind = [int]$Matches[1]; $ahead = [int]$Matches[2] }
    $status = Invoke-NativeText git @('-C', $Root, 'status', '--porcelain')
    $dirty = @()
    if ($status.ok -and $status.text) { $dirty = @($status.text -split "`n" | Where-Object { $_.Trim() }) }

    $worktrees = [System.Collections.Generic.List[object]]::new()
    $wt = Invoke-NativeText git @('-C', $Root, 'worktree', 'list', '--porcelain')
    if ($wt.ok) {
        $entry = $null
        foreach ($line in ($wt.text -split "`n")) {
            if ($line -match '^worktree (.+)$') {
                if ($null -ne $entry) { $worktrees.Add($entry) }
                $entry = [ordered]@{ path = $Matches[1].Trim(); branch = '(detached)'; head = $null; dirty = $null }
            } elseif ($null -ne $entry -and $line -match '^HEAD ([0-9a-f]{7})') {
                $entry.head = $Matches[1]
            } elseif ($null -ne $entry -and $line -match '^branch refs/heads/(.+)$') {
                $entry.branch = $Matches[1].Trim()
            }
        }
        if ($null -ne $entry) { $worktrees.Add($entry) }
        $rootKey = ($Root -replace '\\', '/').TrimEnd('/')
        foreach ($w in $worktrees) {
            $w['current'] = ($w.path.TrimEnd('/') -ieq $rootKey)
            if ($w.current -or (Test-Path -LiteralPath $w.path) -eq $false) { continue }
            $ws = Invoke-NativeText git @('-C', $w.path, 'status', '--porcelain')
            if ($ws.ok) { $w.dirty = @($ws.text -split "`n" | Where-Object { $_.Trim() }).Count }
        }
    }

    [pscustomobject]@{
        branch     = $branch
        head       = $head
        originMain = $(if ($originMain.ok) { $originMain.text.Trim() } else { $null })
        behind     = $behind
        ahead      = $ahead
        fetch      = $fetchNote
        dirty      = $dirty
        worktrees  = @($worktrees | ForEach-Object { [pscustomobject]$_ })
    }
}

function Get-GitHubSection {
    param()
    $section = [ordered]@{ available = $true; reason = $null; pullRequests = @(); defects = @(); handoff = $null }

    $prs = Invoke-NativeText gh @('pr', 'list', '--state', 'open', '--limit', '30',
        '--json', 'number,title,headRefName,headRefOid,isDraft,author,statusCheckRollup')
    if (-not $prs.ok) {
        $section.available = $false
        $section.reason = "gh pr list failed: $($prs.error)"
        return [pscustomobject]$section
    }
    $section.pullRequests = @(@(ConvertFrom-JsonArray -Json $prs.text) | ForEach-Object {
        [pscustomobject]@{
            number = $_.number
            title  = $_.title
            branch = $_.headRefName
            head   = ([string]$_.headRefOid).Substring(0, [Math]::Min(7, ([string]$_.headRefOid).Length))
            draft  = [bool]$_.isDraft
            author = $_.author.login
            checks = Get-CheckRollupSummary -Rollup @($_.statusCheckRollup)
        }
    })

    $bugs = Invoke-NativeText gh @('issue', 'list', '--label', 'bug', '--state', 'open', '--limit', '100', '--json', 'number,title,labels')
    if ($bugs.ok) {
        $section.defects = @(@(ConvertFrom-JsonArray -Json $bugs.text) | ForEach-Object {
            $triage = @($_.labels | Where-Object { $_.name -like 'triage:*' } | ForEach-Object { $_.name -replace '^triage:', '' })
            [pscustomobject]@{ number = $_.number; title = $_.title; triage = $(if ($triage.Count) { $triage -join ',' } else { 'untriaged' }) }
        })
    } else {
        $section.defects = $null
        $section.reason = "gh issue list (bug) failed: $($bugs.error)"
    }

    $handoff = Invoke-NativeText gh @('issue', 'list', '--label', $script:SessionHandoffLabel, '--state', 'open',
        '--json', 'number,title,body,updatedAt,url')
    if ($handoff.ok) {
        $section.handoff = Resolve-SessionHandoffIssue -Issues @(ConvertFrom-JsonArray -Json $handoff.text)
    } else {
        $section.handoff = [pscustomobject]@{ status = 'unavailable'; issue = $null; detail = "gh issue list (handoff) failed: $($handoff.error)" }
    }
    [pscustomobject]$section
}

function Get-SessionBriefingData {
    param([string]$Root, [bool]$Fetch, [bool]$IncludeGitHub)

    $roadmapPath = Join-Path $Root 'ROADMAP.md'
    $roadmap = $null
    if (Test-Path -LiteralPath $roadmapPath) {
        $roadmap = Get-RoadmapFocus -Text (Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8)
        $age = $null
        if ($roadmap.lastUpdated) { $age = [int]((Get-Date).Date - [datetime]::ParseExact($roadmap.lastUpdated, 'yyyy-MM-dd', $null)).TotalDays }
        $roadmap | Add-Member -NotePropertyName ageDays -NotePropertyValue $age
    }

    $queuePath = Join-Path $Root 'docs/governance/operator-queue.md'
    $queue = @()
    if (Test-Path -LiteralPath $queuePath) { $queue = @(Get-OperatorQueueRow -Text (Get-Content -LiteralPath $queuePath -Raw -Encoding UTF8)) }

    $github = [pscustomobject]@{ available = $false; reason = 'skipped (-SkipGitHub)'; pullRequests = @(); defects = @(); handoff = $null }
    if ($IncludeGitHub) { $github = Get-GitHubSection }

    [pscustomobject]@{
        generatedAt   = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        workspaceRoot = $Root
        git           = Get-GitSection -Root $Root -Fetch $Fetch
        github        = $github
        roadmap       = $roadmap
        operatorQueue = $queue
        strayNotes    = @(Get-StrayNote -OutputRoot (Join-Path $Root 'output'))
    }
}

function Format-SessionBriefing {
    param([object]$Data)
    $out = [System.Collections.Generic.List[string]]::new()
    $short = { param([string]$s, [int]$n) if ($s.Length -le $n) { $s } else { $s.Substring(0, $n - 3) + '...' } }

    $out.Add("# Session briefing - $($Data.generatedAt)")
    $out.Add('')
    $g = $Data.git
    $distance = 'distance from origin/main unknown'
    if ($null -ne $g.behind) { $distance = "behind origin/main $($g.behind), ahead $($g.ahead)" }
    $out.Add("## Checkout")
    $out.Add("$($Data.workspaceRoot) on $($g.branch) @ $($g.head); origin/main @ $($g.originMain); $distance ($($g.fetch))")
    if (@($g.dirty).Count) {
        $out.Add("Dirty ($(@($g.dirty).Count)): " + ((@($g.dirty) | Select-Object -First 8 | ForEach-Object { $_.Trim() }) -join '; '))
    } else { $out.Add('Clean.') }
    foreach ($w in @($g.worktrees | Where-Object { -not $_.current })) {
        $d = 'dirty unknown'; if ($null -ne $w.dirty) { $d = "$($w.dirty) dirty" }
        $out.Add("Worktree: $($w.path) on $($w.branch) @ $($w.head), $d")
    }

    $out.Add('')
    $out.Add('## Handoff')
    $gh = $Data.github
    if (-not $gh.available -and $null -eq $gh.handoff) {
        $out.Add("unavailable: $($gh.reason)")
    } elseif ($gh.handoff.status -eq 'ok' -or $gh.handoff.status -eq 'duplicate') {
        if ($gh.handoff.status -eq 'duplicate') { $out.Add("WARNING: $($gh.handoff.detail)") }
        $i = $gh.handoff.issue
        $out.Add("#$($i.number), updated $($i.updatedAt) - $($i.url)")
        $out.Add('')
        $body = ([string]$i.body -replace '(?s)<!--.*?-->', '').Trim()
        foreach ($line in ($body -split '\r?\n')) { $out.Add($line) }
    } else {
        $out.Add("$($gh.handoff.status): $($gh.handoff.detail)")
    }

    $out.Add('')
    $out.Add('## Open PRs')
    if (-not $gh.available) { $out.Add("unavailable: $($gh.reason)") }
    elseif (-not @($gh.pullRequests).Count) { $out.Add('None.') }
    foreach ($p in @($gh.pullRequests)) {
        $c = $p.checks
        $detail = "$($c.verdict) ($($c.pass) pass, $($c.fail) fail, $($c.pending) pending)"
        if (@($c.failed).Count) { $detail += ' failed: ' + (@($c.failed) -join ', ') }
        $draft = ''; if ($p.draft) { $draft = ' [draft]' }
        $out.Add("#$($p.number)$draft $($p.branch) @ $($p.head) - $detail - $(& $short $p.title 70)")
    }

    $out.Add('')
    $out.Add('## Open defects (label bug)')
    if (-not $gh.available) { $out.Add("unavailable: $($gh.reason)") }
    elseif ($null -eq $gh.defects) { $out.Add("unavailable: $($gh.reason)") }
    elseif (-not @($gh.defects).Count) { $out.Add('None.') }
    else {
        foreach ($group in (@($gh.defects) | Group-Object triage | Sort-Object Name)) {
            $out.Add("$($group.Name): " + ((@($group.Group) | ForEach-Object { "#$($_.number) $(& $short $_.title 60)" }) -join '; '))
        }
    }

    $out.Add('')
    $out.Add('## Roadmap Current focus (open items)')
    $r = $Data.roadmap
    if ($null -eq $r) { $out.Add('unavailable: ROADMAP.md not found') }
    else {
        $stale = ''
        if ($null -ne $r.ageDays -and $r.ageDays -gt 3) { $stale = ' - STALE: update "Last updated" when you advance an item' }
        $out.Add("Last updated $($r.lastUpdated) ($($r.ageDays) days ago)$stale")
        foreach ($item in @($r.openItems)) { $out.Add("[$($item.state)] $(& $short $item.title 110)") }
    }

    $out.Add('')
    $out.Add('## Operator queue (Ben only; never blocks agent work)')
    if (-not @($Data.operatorQueue).Count) { $out.Add('Empty.') }
    foreach ($row in @($Data.operatorQueue)) { $out.Add("$($row.id) [$($row.needs)] $(& $short $row.action 90)") }

    if (@($Data.strayNotes).Count) {
        $out.Add('')
        $out.Add('## Notes under output/ (evidence only, not the handoff)')
        foreach ($folder in (@($Data.strayNotes) | Group-Object { Split-Path -Parent $_.path })) {
            $newest = @($folder.Group | Sort-Object lastWriteTime -Descending)[0].lastWriteTime
            $names = (@($folder.Group) | ForEach-Object { Split-Path -Leaf $_.path }) -join ', '
            $out.Add("$($newest.ToString('yyyy-MM-dd HH:mm')) $($folder.Name) ($names)")
        }
    }
    $out.ToArray()
}

# gh resolves the repository from the current directory's remote.
Push-Location -LiteralPath $WorkspaceRoot
try {
    $data = Get-SessionBriefingData -Root $WorkspaceRoot -Fetch (-not $NoFetch) -IncludeGitHub (-not $SkipGitHub)
} finally {
    Pop-Location
}
if ($AsJson) {
    $data | ConvertTo-Json -Depth 8
} else {
    Format-SessionBriefing -Data $data
}
