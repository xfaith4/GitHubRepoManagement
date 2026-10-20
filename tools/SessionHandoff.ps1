<#
.SYNOPSIS
    Shared functions for the session briefing and the session handoff issue.

.DESCRIPTION
    Dot-sourced by tools/Get-SessionBriefing.ps1, tools/Publish-SessionHandoff.ps1
    and tests/Test-SessionBriefing.ps1. Everything here is a pure parser over
    text or JSON already fetched, so the gate can prove it offline.

    The split this file encodes: state that can be read live (branches, PRs,
    checks, worktrees, issues, dirty files) is never written into a handoff,
    because a written copy goes stale within minutes. The handoff issue holds
    only what cannot be derived: the next action, intent, decisions, traps and
    parked questions.
#>

Set-StrictMode -Version Latest

$script:SessionHandoffLabel = 'handoff'
$script:SessionHandoffMaxLines = 60
$script:SessionHandoffHeadings = @(
    '## Next action',
    '## In flight',
    '## Decisions',
    '## Traps',
    '## Parked'
)
# Required reading for every session, by heading, so a renamed or moved section
# fails tests/Test-SessionBriefing.ps1 instead of silently shifting line numbers.
# Everything else is read on demand (AGENTS.md "Authority and document roles").
$script:SessionRequiredReading = @(
    @{ path = 'AGENTS.md'; label = 'the operating contract, whole'; start = $null; end = $null },
    @{ path = 'docs/governance/steering.md'; label = 'steering 1-2: purpose and the contracts'; start = '^## 1\. '; end = '^## 3\. ' },
    @{ path = 'docs/governance/steering.md'; label = 'steering 5-6: working rules, false progress'; start = '^## 5\. '; end = $null },
    @{ path = 'ROADMAP.md'; label = 'roadmap Current Status: the focus items in order'; start = '^## Current Status'; end = '^## 1\. ' }
)
$script:SessionOnDemandReading = 'steering 3-4 (proof ladder, direction) before choosing what to build or claiming proof; the rest of ROADMAP.md when a section is named; docs/history/completed-releases.md when an item seems absent'

# Files a session has historically left under output/ as a "handoff". They are
# evidence at best; the briefing names them so nobody mistakes one for the record.
$script:StrayNoteNames = @('HANDOFF.md', 'progress.md', 'task_plan.md', 'findings.md')

function ConvertFrom-JsonArray {
    <#
    .SYNOPSIS
        Parses a JSON array into its items on both PowerShell editions.
    .DESCRIPTION
        Windows PowerShell 5.1 emits a parsed JSON array as ONE pipeline object,
        so `@($json | ConvertFrom-Json) | ForEach-Object` sees the whole array as
        a single item. Assigning first and enumerating with foreach does not.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter()][AllowEmptyString()][AllowNull()][string]$Json)

    $items = [System.Collections.Generic.List[object]]::new()
    if (-not $Json -or -not $Json.Trim()) { return $items.ToArray() }
    $parsed = $Json | ConvertFrom-Json
    foreach ($item in $parsed) { if ($null -ne $item) { $items.Add($item) } }
    $items.ToArray()
}

function ConvertTo-LocalTimestamp {
    <#
    .SYNOPSIS
        Renders a gh timestamp as local time with its offset on both editions.
    .DESCRIPTION
        pwsh 7 parses an ISO `updatedAt` into a UTC DateTime that prints in the
        culture's format with no zone; 5.1 leaves the string. Either way the
        result is `yyyy-MM-dd HH:mm zzz`, never a bare culture date.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object]$Value)

    $when = $Value
    if ($when -isnot [datetime]) {
        $when = [datetime]::Parse([string]$when, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
    }
    $when.ToLocalTime().ToString('yyyy-MM-dd HH:mm zzz')
}

function Get-RoadmapFocus {
    <#
    .SYNOPSIS
        Reads "Last updated" and the open Current-focus items from ROADMAP.md text.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $lines = $Text -split '\r?\n'
    $lastUpdated = $null
    foreach ($line in $lines) {
        if ($line -match '^\*\*Last updated:\*\*\s*(\d{4}-\d{2}-\d{2})') { $lastUpdated = $Matches[1]; break }
    }

    $items = [System.Collections.Generic.List[object]]::new()
    $inFocus = $false
    $current = $null
    foreach ($line in $lines) {
        if (-not $inFocus) {
            if ($line -match '^\*\*Current focus') { $inFocus = $true }
            continue
        }
        if ($line -match '^---\s*$' -or $line -match '^#{1,3} ') { break }
        if ($line -match '^- \[( |x|X)\]\s*(.*)$') {
            if ($null -ne $current) { $items.Add($current) }
            $current = [pscustomobject]@{ open = ($Matches[1] -eq ' '); text = $Matches[2] }
            continue
        }
        if ($null -ne $current) { $current.text = $current.text + ' ' + $line.Trim() }
    }
    if ($null -ne $current) { $items.Add($current) }

    $open = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $items) {
        if (-not $item.open) { continue }
        $title = $item.text
        if ($item.text -match '^\*\*(.+?)\*\*') { $title = $Matches[1] }
        $state = $null
        if ($item.text -match '\(state:\s*([A-Za-z-]+)') { $state = $Matches[1] }
        $check = $null
        if ($item.text -match '`check:\s*([^`]+)`') { $check = $Matches[1].Trim() }
        $open.Add([pscustomobject]@{ title = $title.Trim(); state = $state; check = $check })
    }

    [pscustomobject]@{
        lastUpdated = $lastUpdated
        openItems   = $open.ToArray()
    }
}

function Get-ReadingRange {
    <#
    .SYNOPSIS
        Resolves one required-reading entry to 1-based start and end lines.
    .DESCRIPTION
        No start pattern means the whole file. The end is the line before the
        end pattern's first match after the start, less trailing blank and
        `---` lines; no end pattern means the end of the file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter()][AllowNull()][string]$StartPattern,
        [Parameter()][AllowNull()][string]$EndPattern
    )

    $start = 1
    if ($StartPattern) {
        $start = 0
        for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match $StartPattern) { $start = $i + 1; break } }
        if ($start -eq 0) { return [pscustomobject]@{ found = $false; start = $null; end = $null } }
    }
    $end = $Lines.Count
    if ($EndPattern) {
        for ($i = $start; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match $EndPattern) { $end = $i; break } }
    }
    while ($end -gt $start -and ($Lines[$end - 1].Trim() -eq '' -or $Lines[$end - 1].Trim() -eq '---')) { $end-- }
    [pscustomobject]@{ found = $true; start = $start; end = $end }
}

function Get-BriefingSource {
    <#
    .SYNOPSIS
        Where the briefing reads tracked files (roadmap, operator queue, required
        reading) from: 'origin/main' when the checkout is behind it, else 'checkout'.
    .DESCRIPTION
        #353. The live checkout is the running service and is left behind
        origin/main on purpose (OQ-16), so its ROADMAP.md is not the state a
        session builds on. Ahead-only, level, or no origin/main reads the
        checkout as before: there is nothing newer to read.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()][AllowNull()][object]$Behind,
        [Parameter()][bool]$OriginMainKnown
    )
    if ($OriginMainKnown -and $null -ne $Behind -and [int]$Behind -gt 0) { return 'origin/main' }
    'checkout'
}

function Get-SessionReadingPlan {
    <#
    .SYNOPSIS
        The required reading with live line ranges, plus the on-demand note.
    .PARAMETER TextByPath
        File text by repository-relative path, read from somewhere other than
        the checkout (origin/main, #353). A path it names is ranged over that
        text and marked with -TextSource; any other path is read from $Root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter()][hashtable]$TextByPath = @{},
        [Parameter()][string]$TextSource = 'origin/main'
    )

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($spec in $script:SessionRequiredReading) {
        $full = Join-Path $Root $spec.path
        $range = [pscustomobject]@{ found = $false; start = $null; end = $null }
        $source = 'checkout'
        if ($TextByPath.ContainsKey($spec.path)) {
            $source = $TextSource
            $range = Get-ReadingRange -Lines @([string]$TextByPath[$spec.path] -split '\r?\n') -StartPattern $spec.start -EndPattern $spec.end
        } elseif (Test-Path -LiteralPath $full) {
            $range = Get-ReadingRange -Lines @(Get-Content -LiteralPath $full -Encoding UTF8) -StartPattern $spec.start -EndPattern $spec.end
        }
        $items.Add([pscustomobject]@{
            path   = $spec.path
            label  = $spec.label
            found  = $range.found
            start  = $range.start
            end    = $range.end
            lines  = $(if ($range.found) { $range.end - $range.start + 1 } else { 0 })
            source = $source
        })
    }
    [pscustomobject]@{ required = $items.ToArray(); onDemand = $script:SessionOnDemandReading }
}

function Get-OperatorQueueRow {
    <#
    .SYNOPSIS
        Reads the OQ-n rows from docs/governance/operator-queue.md text.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -notmatch '^\|\s*(OQ-\d+)\s*\|') { continue }
        $cells = @($line.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 3) { continue }
        $rows.Add([pscustomobject]@{
            id     = $cells[0]
            needs  = $cells[1]
            action = $cells[2]
        })
    }
    $rows.ToArray()
}

function Get-CheckRollupSummary {
    <#
    .SYNOPSIS
        Classifies a PR's statusCheckRollup into pass, fail and pending counts.
    .DESCRIPTION
        A check that has not completed is pending, never failed: a BLOCKED merge
        state covers both, so only per-check conclusions decide.
    #>
    [CmdletBinding()]
    param([Parameter()][AllowNull()][object[]]$Rollup)

    $pass = 0; $fail = 0; $pending = 0
    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($check in @($Rollup)) {
        if ($null -eq $check) { continue }
        $name = $null
        foreach ($field in @('name', 'context')) {
            if ($check.PSObject.Properties[$field] -and $check.$field) { $name = [string]$check.$field; break }
        }
        $outcome = $null
        if ($check.PSObject.Properties['state'] -and $check.state -and -not $check.PSObject.Properties['status']) {
            # StatusContext: SUCCESS | FAILURE | ERROR | PENDING | EXPECTED
            $outcome = switch ([string]$check.state) {
                'SUCCESS' { 'pass' }
                { $_ -in @('FAILURE', 'ERROR') } { 'fail' }
                default { 'pending' }
            }
        } elseif ($check.PSObject.Properties['status'] -and [string]$check.status -ne 'COMPLETED') {
            $outcome = 'pending'
        } else {
            $conclusion = ''
            if ($check.PSObject.Properties['conclusion']) { $conclusion = [string]$check.conclusion }
            $outcome = switch ($conclusion) {
                { $_ -in @('SUCCESS', 'NEUTRAL', 'SKIPPED') } { 'pass' }
                { $_ -in @('', $null) } { 'pending' }
                default { 'fail' }
            }
        }
        switch ($outcome) {
            'pass' { $pass++ }
            'fail' { $fail++; if ($name) { $failed.Add($name) } }
            default { $pending++ }
        }
    }

    $verdict = 'none'
    if ($fail -gt 0) { $verdict = 'failing' }
    elseif ($pending -gt 0) { $verdict = 'pending' }
    elseif ($pass -gt 0) { $verdict = 'green' }

    [pscustomobject]@{
        verdict = $verdict
        pass    = $pass
        fail    = $fail
        pending = $pending
        failed  = $failed.ToArray()
    }
}

function Resolve-SessionHandoffIssue {
    <#
    .SYNOPSIS
        Picks the one open handoff issue, or says why there is not exactly one.
    #>
    [CmdletBinding()]
    param([Parameter()][AllowNull()][object[]]$Issues)

    $open = @($Issues | Where-Object { $null -ne $_ })
    if ($open.Count -eq 0) {
        return [pscustomobject]@{
            status = 'missing'; issue = $null
            detail = "No open issue labelled '$script:SessionHandoffLabel'. Create one with tools/Publish-SessionHandoff.ps1 -Create."
        }
    }
    if ($open.Count -gt 1) {
        $numbers = ($open | ForEach-Object { '#' + $_.number }) -join ', '
        return [pscustomobject]@{
            status = 'duplicate'; issue = ($open | Sort-Object { [datetime]$_.updatedAt } -Descending | Select-Object -First 1)
            detail = "$($open.Count) open '$script:SessionHandoffLabel' issues ($numbers); there must be one. Close all but the newest."
        }
    }
    [pscustomobject]@{ status = 'ok'; issue = $open[0]; detail = $null }
}

function Test-SessionHandoffBody {
    <#
    .SYNOPSIS
        Checks a handoff body has every section and stays short.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Body)

    $problems = [System.Collections.Generic.List[string]]::new()
    $lines = @($Body -split '\r?\n')
    foreach ($heading in $script:SessionHandoffHeadings) {
        $pattern = '^' + [regex]::Escape($heading) + '\b'
        if (-not ($lines | Where-Object { $_ -match $pattern })) { $problems.Add("missing section '$heading'") }
    }
    if ($lines.Count -gt $script:SessionHandoffMaxLines) {
        $problems.Add("body is $($lines.Count) lines; the limit is $script:SessionHandoffMaxLines. Move detail to the PR or issue it belongs to and link it.")
    }
    $nextAction = $false
    $inNext = $false
    foreach ($line in $lines) {
        if ($line -match '^## Next action') { $inNext = $true; continue }
        if ($inNext -and $line -match '^## ') { break }
        if ($inNext -and $line.Trim() -and $line.Trim() -notmatch '^<!--') { $nextAction = $true; break }
    }
    if (-not $nextAction) { $problems.Add("'## Next action' is empty; a fresh session must know what to do first") }

    [pscustomobject]@{ ok = ($problems.Count -eq 0); problems = $problems.ToArray() }
}

function Get-StrayNote {
    <#
    .SYNOPSIS
        Lists handoff-shaped notes left under output/ (top two levels only).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OutputRoot)

    if (-not (Test-Path -LiteralPath $OutputRoot)) { return }
    $found = [System.Collections.Generic.List[object]]::new()
    $candidates = @(Get-ChildItem -LiteralPath $OutputRoot -File -ErrorAction Stop) +
        @(Get-ChildItem -LiteralPath $OutputRoot -Directory -ErrorAction Stop |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction Stop })
    foreach ($file in $candidates) {
        if ($null -eq $file) { continue }
        if ($script:StrayNoteNames -notcontains $file.Name) { continue }
        $found.Add([pscustomobject]@{
            path          = $file.FullName
            lastWriteTime = $file.LastWriteTime
        })
    }
    $found.ToArray() | Sort-Object lastWriteTime -Descending
}

function Get-SessionHandoffTemplate {
    <#
    .SYNOPSIS
        The empty handoff body: only what a live read cannot tell the next session.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @'
<!-- Session handoff. Rewritten whole by every session that ends; the previous
body is kept as a comment by tools/Publish-SessionHandoff.ps1. Write only what
tools/Get-SessionBriefing.ps1 cannot read live: no branch heads, CI results, PR
lists or dirty-file lists - those go stale within minutes. -->

## Next action

<!-- The one thing a fresh session does first, and the command that proves it is done. -->

## In flight

<!-- Intent behind open work: which PR or branch is for what, and what "done" means for it. -->

## Decisions

<!-- Choices made this session that a fresh agent would otherwise re-open. Link the PR or issue. -->

## Traps

<!-- What cost this session time and will cost the next one too. -->

## Parked

<!-- Questions waiting on the operator, with a link to open-decisions.md or the operator queue. -->
'@
}
