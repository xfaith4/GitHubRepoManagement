#Requires -Version 7.0
<#
.SYNOPSIS
    The session briefing and the handoff issue, proved offline.

.DESCRIPTION
    Proves that the briefing's parsers read this repository's own ROADMAP.md
    and operator queue; that a pending check is never counted as failed; that
    there is exactly one handoff issue or the briefing says why not; that a
    handoff body missing a section, with an empty "Next action" or over the
    length limit is refused; that notes left under output/ are found at the top
    two levels; that the briefing runs end to end without GitHub and says the
    GitHub sections are unavailable rather than empty; and that AGENTS.md names
    the briefing and the handoff issue.

.EXAMPLE
    pwsh ./tests/Test-SessionBriefing.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
. (Join-Path $WorkspaceRoot 'tools/SessionHandoff.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

# 1. roadmap focus: order, state and check per open item; [x] skipped; stops at ---
$fixture = @'
## Current Status (Agent Context)

**Last updated:** 2026-10-19

**Current focus - Must work now, in order.** Take the first open item.

- [x] **Done already.** Finished. _(state: verified)_
- [ ] **First open item.** Wraps onto
      a second line. _(state: built)_
      `check: pwsh ./tests/Test-A.ps1 -FailOnError`
- [ ] **Second open item.** _(state: planned)_

---

- [ ] **Outside the focus block.** _(state: planned)_
'@
$focus = Get-RoadmapFocus -Text $fixture
Assert-That ($focus.lastUpdated -eq '2026-10-19') 'Last updated is read'
Assert-That (@($focus.openItems).Count -eq 2) "two open focus items, not the checked one or the one after --- (got $(@($focus.openItems).Count))"
Assert-That ($focus.openItems[0].title -eq 'First open item.' -and $focus.openItems[0].state -eq 'built') 'the first open item keeps its title and state'
Assert-That ($focus.openItems[0].check -eq 'pwsh ./tests/Test-A.ps1 -FailOnError') 'a check on a wrapped continuation line is read'
Assert-That ($focus.openItems[1].state -eq 'planned' -and $null -eq $focus.openItems[1].check) 'an item with no check reads null, not the next item''s'

# 2. the real roadmap still matches the parser (a format change fails here, not in a fresh session)
$real = Get-RoadmapFocus -Text (Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'ROADMAP.md') -Raw)
Assert-That ($real.lastUpdated -match '^\d{4}-\d{2}-\d{2}$') 'ROADMAP.md carries a parseable "Last updated" date'
Assert-That (@($real.openItems).Count -ge 1) 'ROADMAP.md Current focus has at least one open item the briefing can read'
Assert-That (@($real.openItems | Where-Object { -not $_.state }).Count -eq 0) 'every open Current-focus item in ROADMAP.md names its state'

# 3. the real operator queue parses
$queue = @(Get-OperatorQueueRow -Text (Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'docs/governance/operator-queue.md') -Raw))
Assert-That ($queue.Count -ge 1 -and @($queue | Where-Object { $_.id -notmatch '^OQ-\d+$' }).Count -eq 0) 'operator-queue rows parse with OQ-n ids'
Assert-That (@($queue | Where-Object { -not $_.action }).Count -eq 0) 'every operator-queue row has an action'

# 4. check rollup: pending is never failed
$rollup = @(
    [pscustomobject]@{ name = 'smoke'; status = 'IN_PROGRESS'; conclusion = '' },
    [pscustomobject]@{ name = 'review'; status = 'COMPLETED'; conclusion = 'SUCCESS' },
    [pscustomobject]@{ name = 'skipped'; status = 'COMPLETED'; conclusion = 'SKIPPED' }
)
$pending = Get-CheckRollupSummary -Rollup $rollup
Assert-That ($pending.verdict -eq 'pending' -and $pending.fail -eq 0 -and $pending.pending -eq 1 -and $pending.pass -eq 2) 'an in-progress check is pending, not failed'
$red = Get-CheckRollupSummary -Rollup @($rollup[1], [pscustomobject]@{ name = 'smoke'; status = 'COMPLETED'; conclusion = 'FAILURE' })
Assert-That ($red.verdict -eq 'failing' -and @($red.failed) -contains 'smoke') 'a failed check is named'
$ctx = Get-CheckRollupSummary -Rollup @([pscustomobject]@{ context = 'legacy'; state = 'PENDING' }, [pscustomobject]@{ context = 'ci'; state = 'SUCCESS' })
Assert-That ($ctx.verdict -eq 'pending' -and $ctx.pass -eq 1) 'status contexts classify by state'
Assert-That ((Get-CheckRollupSummary -Rollup @()).verdict -eq 'none') 'no checks reads none, not green'

# 4b. gh JSON arrays enumerate item by item (Windows PowerShell 5.1 emits a parsed array as one object)
$parsed = @(ConvertFrom-JsonArray -Json '[{"number":1},{"number":2}]')
Assert-That ($parsed.Count -eq 2 -and $parsed[1].number -eq 2) 'a two-item JSON array yields two items'
Assert-That (@(ConvertFrom-JsonArray -Json '[]').Count -eq 0 -and @(ConvertFrom-JsonArray -Json '').Count -eq 0) 'an empty array or empty text yields no items'
$ps51 = Get-Command powershell.exe -ErrorAction Ignore
if ($ps51) {
    $lib = Join-Path $WorkspaceRoot 'tools/SessionHandoff.ps1'
    $count = & $ps51.Source -NoProfile -Command ". '$lib'; @(ConvertFrom-JsonArray -Json '[{""n"":1},{""n"":2}]').Count"
    Assert-That ("$count".Trim() -eq '2') "Windows PowerShell 5.1 also yields two items (got '$count')"
}

# 4c. timestamps render as local ISO with an offset, from a string or a DateTime
$iso = '2026-10-19T11:36:54Z'
$expected = ([datetime]::Parse($iso, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)).ToLocalTime().ToString('yyyy-MM-dd HH:mm zzz')
Assert-That ((ConvertTo-LocalTimestamp -Value $iso) -eq $expected) 'an ISO string renders as local time with its offset'
Assert-That ((ConvertTo-LocalTimestamp -Value ('[{"t":"' + $iso + '"}]' | ConvertFrom-Json)[0].t) -eq $expected) 'a DateTime parsed by ConvertFrom-Json renders the same'

# 5. exactly one handoff issue
Assert-That ((Resolve-SessionHandoffIssue -Issues @()).status -eq 'missing') 'no handoff issue is reported missing'
$one = Resolve-SessionHandoffIssue -Issues @([pscustomobject]@{ number = 7; updatedAt = '2026-10-19T10:00:00Z'; body = 'x' })
Assert-That ($one.status -eq 'ok' -and $one.issue.number -eq 7) 'one handoff issue is used'
$two = Resolve-SessionHandoffIssue -Issues @(
    [pscustomobject]@{ number = 7; updatedAt = '2026-10-18T10:00:00Z'; body = 'old' },
    [pscustomobject]@{ number = 9; updatedAt = '2026-10-19T10:00:00Z'; body = 'new' })
Assert-That ($two.status -eq 'duplicate' -and $two.issue.number -eq 9 -and $two.detail -match '#7' -and $two.detail -match '#9') 'two handoff issues are flagged, newest shown, both named'

# 6. handoff body validation
$template = Get-SessionHandoffTemplate
$empty = Test-SessionHandoffBody -Body $template
Assert-That ((-not $empty.ok) -and (@($empty.problems) -match 'Next action').Count -ge 1) 'the unfilled template is refused for an empty Next action'
$good = $template -replace '(?m)^(## Next action)\s*$', "`$1`n`nMerge-ready: confirm #346 merged, then run tools/Get-SessionBriefing.ps1."
Assert-That ((Test-SessionHandoffBody -Body $good).ok) 'a filled template is accepted'
$noTraps = $good -replace '(?m)^## Traps.*$', ''
Assert-That ((@((Test-SessionHandoffBody -Body $noTraps).problems) -match 'Traps').Count -ge 1) 'a missing section is named'
$long = $good + ("`n- line" * 80)
Assert-That ((@((Test-SessionHandoffBody -Body $long).problems) -match 'limit').Count -ge 1) 'an over-long body is refused'

# 7. stray notes: top two levels of output/ only
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("session-briefing-" + [guid]::NewGuid().ToString('n'))
try {
    $null = New-Item -ItemType Directory -Path (Join-Path $tmp 'run-a') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $tmp 'agent-workspaces/clone/docs') -Force
    Set-Content -LiteralPath (Join-Path $tmp 'run-a/HANDOFF.md') -Value 'x'
    Set-Content -LiteralPath (Join-Path $tmp 'run-a/data.json') -Value '{}'
    Set-Content -LiteralPath (Join-Path $tmp 'agent-workspaces/clone/docs/progress.md') -Value 'x'
    $notes = @(Get-StrayNote -OutputRoot $tmp)
    Assert-That ($notes.Count -eq 1 -and $notes[0].path -like '*run-a*HANDOFF.md') "only the top-level handoff note is found (got $($notes.Count))"
    Assert-That (@(Get-StrayNote -OutputRoot (Join-Path $tmp 'absent')).Count -eq 0) 'a missing output root yields no notes, not an error'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# 8. end to end, offline: GitHub sections say unavailable, never empty
$briefing = Join-Path $WorkspaceRoot 'tools/Get-SessionBriefing.ps1'
$json = & $briefing -WorkspaceRoot $WorkspaceRoot -NoFetch -SkipGitHub -AsJson | Out-String
$data = $json | ConvertFrom-Json
Assert-That ([bool]$data.git.head) 'the briefing reads the checkout head'
Assert-That ($data.github.available -eq $false -and $data.github.reason -match 'skipped') 'skipped GitHub is reported with its reason'
Assert-That (@($data.roadmap.openItems).Count -ge 1) 'the briefing carries the open focus items'
$text = (& $briefing -WorkspaceRoot $WorkspaceRoot -NoFetch -SkipGitHub) -join "`n"
Assert-That ($text -match '(?m)^## Handoff\r?\nunavailable: skipped') 'the text briefing says the handoff is unavailable, not missing'
Assert-That ($text -match '(?m)^## Open PRs\r?\nunavailable:') 'the text briefing says PRs are unavailable, not "None."'
$order = @('## Handoff', '## Read next', '## Checkout', '## Open PRs') | ForEach-Object { $text.IndexOf($_) }
Assert-That ((@($order | Where-Object { $_ -lt 0 }).Count -eq 0) -and ($order[0] -lt $order[1]) -and ($order[1] -lt $order[2]) -and ($order[2] -lt $order[3])) 'the handoff prints first, then the reading list, then live state'

# 8b. required reading resolves to real, bounded slices of the real files
$plan = Get-SessionReadingPlan -Root $WorkspaceRoot
Assert-That (@($plan.required | Where-Object { -not $_.found }).Count -eq 0) ('every required-reading heading is found: ' + ((@($plan.required | Where-Object { -not $_.found }) | ForEach-Object { $_.label }) -join '; '))
Assert-That (@($plan.required | Where-Object { $_.found -and $_.end -lt $_.start }).Count -eq 0) 'every required-reading range ends at or after its start'
$steeringLines = @(Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'docs/governance/steering.md'))
$s12 = @($plan.required | Where-Object { $_.label -like 'steering 1-2*' })[0]
$s12Text = $steeringLines[($s12.start - 1)..($s12.end - 1)] -join "`n"
Assert-That ($s12Text -match '(?m)^## 2\. ' -and $s12Text -notmatch '(?m)^## 3\. ') 'steering 1-2 covers section 2 and stops before section 3'
$roadmapLines = @(Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'ROADMAP.md'))
$rs = @($plan.required | Where-Object { $_.path -eq 'ROADMAP.md' })[0]
$rsText = $roadmapLines[($rs.start - 1)..($rs.end - 1)] -join "`n"
Assert-That ($rsText -match '\*\*Current focus' -and $rsText -notmatch '(?m)^## 1\. ') 'the roadmap slice holds Current focus and stops before section 1'
$requiredLines = (@($plan.required) | Measure-Object -Property lines -Sum).Sum
$wholeLines = @('AGENTS.md', 'docs/governance/steering.md', 'ROADMAP.md') | ForEach-Object { @(Get-Content -LiteralPath (Join-Path $WorkspaceRoot $_)).Count } | Measure-Object -Sum
Assert-That ($requiredLines -lt (0.75 * $wholeLines.Sum)) "required reading stays well under the three whole files ($requiredLines of $($wholeLines.Sum) lines)"
Assert-That ((Get-ReadingRange -Lines @('# a', '## 1. x', 'body', '', '---', '## 3. y') -StartPattern '^## 1\. ' -EndPattern '^## 3\. ').end -eq 3) 'a range drops trailing blank and --- lines'
Assert-That (-not (Get-ReadingRange -Lines @('# a') -StartPattern '^## 9\. ' -EndPattern $null).found) 'a missing heading is reported as not found'

# 9. the contract, the provider overlay, the roadmap and the hook name the mechanism
$agents = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'AGENTS.md') -Raw
Assert-That ($agents -match 'tools/Get-SessionBriefing\.ps1') 'AGENTS.md tells a session to run the briefing'
Assert-That ($agents -match 'tools/Publish-SessionHandoff\.ps1') 'AGENTS.md names the handoff publisher'
Assert-That ($agents -match "label(led)? ``handoff``") 'AGENTS.md names the handoff issue label'
$claude = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'CLAUDE.md') -Raw
Assert-That ($claude -match 'tools/Get-SessionBriefing\.ps1' -and $claude -match "labelled ``handoff``") 'CLAUDE.md, which Claude Code loads automatically, points at the briefing and the handoff issue'
$roadmapHead = (Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'ROADMAP.md') -TotalCount 12) -join "`n"
Assert-That ($roadmapHead -match 'tools/Get-SessionBriefing\.ps1') 'the ROADMAP.md header names the briefing'
$settingsPath = Join-Path $WorkspaceRoot '.claude/settings.json'
Assert-That (Test-Path -LiteralPath $settingsPath) '.claude/settings.json exists'
if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $hooks = @()
    if ($settings.PSObject.Properties['hooks'] -and $settings.hooks.PSObject.Properties['SessionStart']) { $hooks = @($settings.hooks.SessionStart) }
    $briefingHook = @($hooks | Where-Object { $_.matcher -match 'startup' -and $_.matcher -match 'compact' } |
        ForEach-Object { @($_.hooks) } | Where-Object { $_.type -eq 'command' -and $_.command -match 'tools/Get-SessionBriefing\.ps1' })
    Assert-That ($briefingHook.Count -eq 1) 'a SessionStart hook on startup and compact runs the briefing'
}

Write-Host ("Session briefing: {0} passed, {1} failed" -f $passed, $failures.Count)
foreach ($f in $failures) { Write-Host "  FAIL: $f" -ForegroundColor Red }
if ($FailOnError -and $failures.Count -gt 0) { exit 1 }
