#Requires -Version 7.0
<#
.SYNOPSIS
    Only actionable roadmap lines become work (Lane 0.22, loop step 1), proved offline.

.DESCRIPTION
    Proves that every open roadmap line is classified actionable | done-statement |
    deferred | guidance | fragment from the rules in
    backend/config/roadmap-item-rules.json; that look-alike actionable lines are not
    swept up; that a missing or broken model throws instead of ranking everything;
    that the item hash ignores case and wrapping but not rewording; that the
    portfolio assessment ranks only actionable lines and keeps the rest, each with
    its reason, on the entry ("Excluded (n)"); and that the dispatch script's own
    picker uses the same model.

.EXAMPLE
    pwsh ./tests/Test-WorkItemQuality.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
. (Join-Path $WorkspaceRoot 'backend/modules/roadmap/Roadmap.ItemQuality.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

$configPath = Join-Path $WorkspaceRoot 'backend/config/roadmap-item-rules.json'
$cfg = Get-RoadmapItemRuleConfig -ConfigPath $configPath

# 1. the committed model loads, versioned
Assert-That ($cfg.schemaVersion -eq 'v1') 'the model carries schemaVersion v1'
Assert-That (-not [string]::IsNullOrWhiteSpace($cfg.modelVersion)) 'the model carries a modelVersion'
Assert-That ((@($cfg.classes | ForEach-Object { $_.name }) -join ',') -eq 'fragment,deferred,guidance,done-statement') 'the four exclusion classes load in their declared order'
Assert-That ($cfg.cooldownHours -gt 0) 'the model declares a dispatch cooldown'
$default = Get-RoadmapItemRuleConfig
Assert-That ($default.modelVersion -eq $cfg.modelVersion) 'omitting -ConfigPath resolves the committed model'

# 2. each class, and the look-alikes that must stay actionable
$cases = @(
    @{ t = 'Add retry with backoff to the uploader'; s = 'Near-term'; g = @(); want = 'actionable' }
    @{ t = 'Add CI'; s = 'Next'; g = @(); want = 'actionable' }
    @{ t = 'Fixed-width font for the report tables'; s = 'Next'; g = @(); want = 'actionable' }
    @{ t = 'Ensure the cache invalidation is implemented'; s = 'Next'; g = @(); want = 'actionable' }
    @{ t = 'Build the weekly delivery report command'; s = 'Weekly delivery report'; g = @(); want = 'actionable' }
    @{ t = 'Keep the API contract tests green on every PR'; s = 'Next'; g = @(); want = 'actionable' }
    @{ t = '**Only actionable roadmap lines become work (Lane 0.22; loop step 1).**'; s = 'Current Status'; g = @(); want = 'actionable' }
    # calibration look-alikes, each observed misfiring on a real roadmap (see the config's evidence)
    @{ t = 'Add `Assert-HasProperty` for required config keys'; s = 'Phase 2 ' + [char]0x2014 + ' Guardrails'; g = @(); want = 'actionable' }
    @{ t = 'Create `backend/src/types/agent-executor.ts` with AgentExecutor interface:'; s = 'Phase 1'; g = @(); want = 'actionable' }
    @{ t = 'Add newsletter/mailing-list opt-in:'; s = 'Next'; g = @(); want = 'actionable' }
    @{ t = 'Verify behavior on PowerShell 7+ after each phase (Phase 3: ' + [char]0x2705 + ' passed, Phase 4 pending)'; s = 'Testing'; g = @(); want = 'actionable' }
    @{ t = 'Resolve the RTK and tk hook collision: both rewrite the same commands, so pick one owner and make sure the other is disabled and the fallback path is implemented'; s = 'Next'; g = @(); want = 'actionable' }
    @{ t = 'Tests'; s = 'Next'; g = @(); want = 'fragment'; rule = 'fragment-min-words' }
    @{ t = 'Remaining hardening:'; s = 'Next'; g = @(); want = 'fragment'; rule = 'fragment-lead-in' }
    @{ t = '[docs/setup.md](docs/setup.md)'; s = 'Next'; g = @(); want = 'fragment'; rule = 'fragment-link-only' }
    @{ t = 'Cache the parsed config between requests'; s = 'Next'; g = @('non-blocker'); want = 'deferred'; rule = 'deferred-tag' }
    @{ t = 'Deferred: migrate the store to SQLite'; s = 'Next'; g = @(); want = 'deferred'; rule = 'deferred-prefix' }
    @{ t = 'Add dark mode to the settings page'; s = 'Backlog'; g = @(); want = 'deferred'; rule = 'deferred-section' }
    @{ t = 'Done: the export route returns CSV'; s = 'Next'; g = @(); want = 'done-statement'; rule = 'done-prefix' }
    @{ t = 'Merged in #42, the retry wrapper'; s = 'Next'; g = @(); want = 'done-statement'; rule = 'done-prefix' }
    @{ t = 'Export route returns CSV ' + [char]0x2705; s = 'Next'; g = @(); want = 'done-statement'; rule = 'done-check-mark' }
    @{ t = '~~Add the legacy importer~~'; s = 'Next'; g = @(); want = 'done-statement'; rule = 'done-strikethrough' }
    @{ t = 'Retry wrapper for the uploader (state: verified)'; s = 'Next'; g = @(); want = 'done-statement'; rule = 'done-state-verified' }
    @{ t = 'The retry wrapper has been implemented.'; s = 'Next'; g = @(); want = 'done-statement'; rule = 'done-passive-past' }
    @{ t = 'All checks pass before merge'; s = 'Definition of Done'; g = @(); want = 'guidance'; rule = 'guidance-section' }
    @{ t = 'Code is implemented'; s = 'Global Definition of Done'; g = @(); want = 'guidance'; rule = 'guidance-section' }
    @{ t = 'Retry wrapper ' + [char]0x2714; s = 'Next'; g = @(); want = 'done-statement'; rule = 'done-check-mark' }
    @{ t = 'Review open dependency alerts'; s = 'Weekly'; g = @(); want = 'guidance'; rule = 'guidance-recurring-section' }
    @{ t = 'Update the changelog'; s = 'On every feature merge'; g = @(); want = 'guidance'; rule = 'guidance-recurring-section' }
    @{ t = 'Never commit generated output'; s = 'Next'; g = @(); want = 'guidance'; rule = 'guidance-imperative-rule' }
)
foreach ($c in $cases) {
    $v = Get-RoadmapItemClass -Text $c.t -Section $c.s -Tags $c.g -Config $cfg
    Assert-That ($v.itemClass -eq $c.want) ("'{0}' in '{1}' classifies {2}, got {3} ({4})" -f $c.t, $c.s, $c.want, $v.itemClass, $v.ruleId)
    if ($c.ContainsKey('rule')) {
        Assert-That ($v.ruleId -eq $c.rule) ("'{0}' is excluded by {1}, got {2}" -f $c.t, $c.rule, $v.ruleId)
        Assert-That (-not [string]::IsNullOrWhiteSpace($v.reason)) ("'{0}' carries a reason" -f $c.t)
    }
    Assert-That ($v.modelVersion -eq $cfg.modelVersion) ("'{0}' names the model that judged it" -f $c.t)
}
# the first matching class wins: a done statement in a Backlog section reads as deferred
$order = Get-RoadmapItemClass -Text 'Done: wire the retry' -Section 'Backlog' -Tags @() -Config $cfg
Assert-That ($order.itemClass -eq 'deferred') 'classes are tested in declared order (deferred before done-statement)'

# 3. a missing or broken model throws; it never degrades to "everything is actionable"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wiq-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $threw = $false; try { Get-RoadmapItemRuleConfig -ConfigPath (Join-Path $tmp 'absent.json') | Out-Null } catch { $threw = $true }
    Assert-That $threw 'a missing model throws'

    $base = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $broken = @{
        'bad-schema.json'  = { param($j) $j.schemaVersion = 'v2' }
        'no-model.json'    = { param($j) $j.modelVersion = '' }
        'bad-regex.json'   = { param($j) $j.classes[0].rules[0].pattern = '([unclosed' }
        'bad-class.json'   = { param($j) $j.classes[0].class = 'actionable' }
        'bad-field.json'   = { param($j) $j.classes[0].rules[0].field = 'body' }
        'no-reason.json'   = { param($j) $j.classes[0].rules[0].reason = '' }
    }
    foreach ($name in $broken.Keys) {
        $copy = $base | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        & $broken[$name] $copy
        $path = Join-Path $tmp $name
        $copy | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
        $threw = $false; try { Get-RoadmapItemRuleConfig -ConfigPath $path | Out-Null } catch { $threw = $true }
        Assert-That $threw "a model with $name throws at load"
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# 4. the item hash: stable across case and wrapping, not across rewording or repository
$h1 = Get-RoadmapItemHash -RepoName 'Alpha' -Text 'Add retry  to the uploader'
$h2 = Get-RoadmapItemHash -RepoName 'alpha' -Text "add retry`nto the Uploader "
$h3 = Get-RoadmapItemHash -RepoName 'Alpha' -Text 'Add a retry to the uploader'
$h4 = Get-RoadmapItemHash -RepoName 'Beta' -Text 'Add retry to the uploader'
Assert-That ($h1 -match '^[0-9a-f]{16}$') 'the item hash is 16 hex characters'
Assert-That ($h1 -eq $h2) 'case and whitespace do not change the item hash'
Assert-That ($h1 -ne $h3) 'rewording changes the item hash'
Assert-That ($h1 -ne $h4) 'the same text in another repository is another item'

# 5. the split preserves order and passes actionable items through unchanged
$items = @(
    [pscustomobject]@{ text = 'Add the export route'; section = 'Next'; tags = @(); marker = 1 }
    [pscustomobject]@{ text = 'Done: the import route'; section = 'Next'; tags = @(); marker = 2 }
    [pscustomobject]@{ text = 'Wire the retry wrapper'; section = 'Next'; tags = @(); marker = 3 }
    [pscustomobject]@{ text = 'Cache the config'; section = 'Next'; tags = @('non-blocker'); marker = 4 }
)
$split = Split-RoadmapItemByQuality -Items $items -RepoName 'Alpha' -Config $cfg
Assert-That ((@($split.actionable | ForEach-Object { $_.marker }) -join ',') -eq '1,3') 'actionable items keep their order and identity'
Assert-That ((@($split.excluded | ForEach-Object { $_.itemClass }) -join ',') -eq 'done-statement,deferred') 'excluded items keep their order and class'
Assert-That (@($split.excluded | Where-Object { [string]::IsNullOrWhiteSpace($_.reason) -or [string]::IsNullOrWhiteSpace($_.ruleId) -or $_.itemHash -notmatch '^[0-9a-f]{16}$' }).Count -eq 0) 'every excluded item carries its rule, reason and hash'
$empty = Split-RoadmapItemByQuality -Items @() -Config $cfg
Assert-That (@($empty.actionable).Count -eq 0 -and @($empty.excluded).Count -eq 0) 'no items split into two empty lists'

# 6. the portfolio assessment ranks only actionable lines and keeps the rest with reasons
. (Join-Path $WorkspaceRoot 'backend/modules/roadmap/Roadmap.Parser.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/roadmap/Roadmap.Dependencies.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/portfolio/Portfolio.ValueScorer.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/portfolio/Portfolio.Assessment.ps1')
$scoring = Get-PortfolioValueScoringConfig -ConfigPath (Join-Path $WorkspaceRoot 'backend/config/value-scoring.json')

function Invoke-AssessmentFixture {
    param([string]$Name, [string]$Content)
    $parsed = Invoke-ParseRoadmapContent -Content $Content -SourcePath "C:\fixture\$Name\ROADMAP.md"
    $entry = [pscustomobject]@{
        repoName        = $Name
        roadmapPath     = "C:\fixture\$Name\ROADMAP.md"
        roadmapState    = 'pending'
        pendingCount    = [int]$parsed.pendingCount
        nextPendingItem = $parsed.nextPendingItem
        sections        = @($parsed.sections)
        items           = @($parsed.items)
    }
    $repo = [pscustomobject]@{ name = $Name; localPath = "C:\fixture\$Name"; isArchived = $false; htmlUrl = ''; branch = 'main'; status = 'clean' }
    return @(Invoke-PortfolioAssessment -LocalRepos @($repo) -RoadmapEntries @($entry) -ValueScoringConfig $scoring)[0]
}

$mixed = @'
# Roadmap

## Next

- [ ] Done: the import route returns JSON
- [ ] Add retry with backoff to the uploader
- [ ] Remaining hardening:
- [ ] Wire the export route to the CSV writer
- [ ] Cache the parsed config between requests [non-blocker]

## Definition of Done

- [ ] All checks pass before merge
'@
$a = Invoke-AssessmentFixture -Name 'wiq-mixed' -Content $mixed
$rankedTexts = @($a.pendingItems | ForEach-Object { [string]$_.text })
Assert-That ($rankedTexts.Count -eq 2) ("only the two actionable lines are ranked, got {0}: {1}" -f $rankedTexts.Count, ($rankedTexts -join ' | '))
Assert-That (($rankedTexts -contains 'Add retry with backoff to the uploader') -and ($rankedTexts -contains 'Wire the export route to the CSV writer')) 'the ranked lines are the actionable ones'
Assert-That ($a.excludedItemCount -eq 4) ("four lines are excluded, got {0}" -f $a.excludedItemCount)
$byText = @{}; foreach ($x in @($a.excludedItems)) { $byText[[string]$x.text] = $x }
Assert-That ($byText.ContainsKey('Done: the import route returns JSON') -and $byText['Done: the import route returns JSON'].itemClass -eq 'done-statement') 'the done statement is excluded as done-statement'
Assert-That ($byText.ContainsKey('Remaining hardening:') -and $byText['Remaining hardening:'].itemClass -eq 'fragment') 'the lead-in is excluded as a fragment'
Assert-That ($byText.ContainsKey('Cache the parsed config between requests') -and $byText['Cache the parsed config between requests'].itemClass -eq 'deferred') 'a [non-blocker] that is not the next item is still read as deferred (tags recovered from items)'
Assert-That ($byText.ContainsKey('All checks pass before merge') -and $byText['All checks pass before merge'].itemClass -eq 'guidance') 'a Definition of Done line is excluded as guidance'
Assert-That (@($a.excludedItems | Where-Object { [string]::IsNullOrWhiteSpace($_.reason) }).Count -eq 0) 'every excluded line on the entry carries its reason'
Assert-That ($null -ne $a.topDispatchableItem -and $rankedTexts -contains [string]$a.topDispatchableItem.text) 'the top dispatchable item is an actionable line'
Assert-That ($null -ne $a.topValueItem -and $rankedTexts -contains [string]$a.topValueItem.text) 'the top value item is an actionable line'
Assert-That ($a.itemQualityModelVersion -eq $cfg.modelVersion) 'the entry names the item-quality model that judged it'

$allExcluded = @'
# Roadmap

## Next

- [ ] Done: the import route returns JSON
- [ ] Never commit generated output
'@
$b = Invoke-AssessmentFixture -Name 'wiq-none' -Content $allExcluded
Assert-That (@($b.pendingItems).Count -eq 0) 'a roadmap of only excluded lines ranks nothing'
Assert-That ($null -eq $b.topDispatchableItem -and $null -eq $b.topValueItem) 'a roadmap of only excluded lines offers nothing for dispatch'
Assert-That ($b.excludedItemCount -eq 2) 'and shows both lines as excluded'

# 7. the dispatch script's own picker uses the same model, with no private skip list
$scriptPath = Join-Path $WorkspaceRoot 'scripts/Start-RoadmapCopilotTask.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-NextRoadmapTask' }, $true)
Assert-That ($null -ne $fn) 'Start-RoadmapCopilotTask.ps1 still defines Get-NextRoadmapTask'
if ($null -ne $fn) {
    $script:ItemRuleConfig = $cfg
    $script:ValueScorerLoaded = $false
    . ([scriptblock]::Create($fn.Extent.Text))
    $pick = Get-NextRoadmapTask -RoadmapContent $mixed
    Assert-That ($pick.Next.TaskText -eq 'Add retry with backoff to the uploader') ("the picker skips excluded lines, got '{0}'" -f $pick.Next.TaskText)
    Assert-That (@($pick.Additional | Where-Object { $_.TaskText -match 'non-blocker|^Done:|:$|All checks pass' }).Count -eq 0) 'no excluded line appears among the picker''s alternatives'
    $threw = $null; try { Get-NextRoadmapTask -RoadmapContent $allExcluded | Out-Null } catch { $threw = $_.Exception.Message }
    Assert-That ($null -ne $threw -and $threw -match 'No actionable unchecked roadmap tasks' -and $threw -match '2 open line') 'a roadmap of only excluded lines fails by saying how many were excluded'
    Assert-That ($fn.Extent.Text -notmatch 'skipHeadingPatterns') 'the picker carries no private skip-heading list'
}

# 8. the wiring stays in place: classify before scoring; the host fallback honours exclusions
$assessSrc = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend/modules/portfolio/Portfolio.Assessment.ps1') -Raw
$splitAt = $assessSrc.IndexOf('Split-RoadmapItemByQuality -Items $pendingItemsAll')
$scoreAt = $assessSrc.IndexOf('_ScorePendingRoadmapItems -PendingItems $pendingItemsRaw')
Assert-That ($splitAt -gt 0 -and $scoreAt -gt $splitAt) 'the assessment classifies pending items before it scores them'
$hostSrc = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend/api-host/Start-RepoManagementApiHost.ps1') -Raw
Assert-That ($hostSrc -match "PropertyName 'excludedItems'") 'the host''s nextPendingItemText fallback consults excludedItems'
$second = @(Get-ChildItem -Path (Join-Path $WorkspaceRoot 'backend'), (Join-Path $WorkspaceRoot 'scripts') -Recurse -Filter *.ps1 |
    Where-Object { $_.Name -ne 'Roadmap.ItemQuality.ps1' } |
    Select-String -Pattern 'function\s+(Get-RoadmapItemClass|Split-RoadmapItemByQuality|Get-RoadmapItemHash)\b' -List)
Assert-That ($second.Count -eq 0) 'no second copy of the classifier exists'

# 9. dispatch records come from claimed runs only; the cooldown is per repo and per item
$runsRoot = Join-Path ([IO.Path]::GetTempPath()) ('wiq-runs-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runsRoot -Force | Out-Null
try {
    $now = [datetime]::new(2026, 11, 11, 12, 0, 0, [DateTimeKind]::Utc)
    $repoA = 'C:\Repos\Alpha'
    function Write-RunSummary { param([string]$Id, [hashtable]$Body) $Body['runId'] = $Id; ($Body | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $runsRoot "$Id.summary.json") -Encoding UTF8 }
    Write-RunSummary -Id 'r-recent' -Body @{ localRepoPath = $repoA; selectedTask = 'Add retry with backoff to the uploader'; runnerStartedAt = $now.AddHours(-2).ToString('o'); status = 'completed' }
    Write-RunSummary -Id 'r-old' -Body @{ localRepoPath = $repoA; selectedTask = 'Wire the export route to the CSV writer'; runnerStartedAt = $now.AddHours(-30).ToString('o'); status = 'completed' }
    Write-RunSummary -Id 'r-queued' -Body @{ localRepoPath = $repoA; selectedTask = 'Wire the export route to the CSV writer'; status = 'queued' }
    Write-RunSummary -Id 'r-packet' -Body @{ localRepoPath = $repoA; selectedTask = ''; runnerStartedAt = $now.AddHours(-1).ToString('o'); status = 'running' }
    Set-Content -LiteralPath (Join-Path $runsRoot 'r-broken.summary.json') -Value '{ not json' -Encoding UTF8

    $records = Get-RoadmapItemDispatchRecord -RunsDir $runsRoot
    Assert-That ($records.Count -eq 2) ("only runs the runner claimed for a roadmap item count, got {0}" -f $records.Count)
    $recent = @($records | Where-Object { $_.runId -eq 'r-recent' })
    Assert-That ($recent.Count -eq 1 -and $recent[0].startedAtUtc -eq $now.AddHours(-2)) 'a claimed run keeps its start time in UTC'
    Assert-That ((Get-RoadmapItemDispatchRecord -RunsDir (Join-Path $runsRoot 'missing')).Count -eq 0) 'a missing runs directory yields no records'

    $v = Test-RoadmapItemCooldown -RepoPath $repoA -Text 'Add retry with backoff to the uploader' -Records $records -Config $cfg -NowUtc $now
    Assert-That ($v.coolingDown -and $v.lastRunId -eq 'r-recent') 'an item launched two hours ago is cooling down'
    Assert-That ($v.reason -match 'r-recent' -and $v.reason -match '-OverrideCooldown') 'the cooldown reason names the prior run and the override'
    $v = Test-RoadmapItemCooldown -RepoPath 'c:/repos/alpha/' -Text "add retry with`n  backoff to the UPLOADER" -Records $records -Config $cfg -NowUtc $now
    Assert-That ($v.coolingDown) 'a re-cased, re-wrapped line and a differently spelled path are the same item'
    $v = Test-RoadmapItemCooldown -RepoPath $repoA -Text 'Wire the export route to the CSV writer' -Records $records -Config $cfg -NowUtc $now
    Assert-That (-not $v.coolingDown -and $v.lastRunId -eq 'r-old') 'an item launched outside the window is free again'
    $v = Test-RoadmapItemCooldown -RepoPath 'C:\Repos\Beta' -Text 'Add retry with backoff to the uploader' -Records $records -Config $cfg -NowUtc $now
    Assert-That (-not $v.coolingDown) 'the same line in another repository is a different item'
    $v = Test-RoadmapItemCooldown -RepoPath $repoA -Text 'Add retry with backoff to the uploader' -Records $records -Config $cfg -NowUtc $now -ExcludeRunId 'r-recent'
    Assert-That (-not $v.coolingDown) 'the run being decided never cools itself down'
    $zero = [pscustomobject]@{ cooldownHours = 0 }
    $v = Test-RoadmapItemCooldown -RepoPath $repoA -Text 'Add retry with backoff to the uploader' -Records $records -Config $zero -NowUtc $now
    Assert-That (-not $v.coolingDown) 'a zero-hour cooldown never holds an item'

    # 10. the runner refuses before the claim; override and remediation are honoured
    $runnerPath = Join-Path $WorkspaceRoot 'scripts/Invoke-RoadmapTaskRunner.ps1'
    $runnerAst = [System.Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$null, [ref]$null)
    $gate = $runnerAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Resolve-QueuedTaskItemCooldown' }, $true)
    Assert-That ($null -ne $gate) 'the runner defines Resolve-QueuedTaskItemCooldown'
    if ($null -ne $gate) {
        $script:ItemRuleConfig = $cfg
        . ([scriptblock]::Create($gate.Extent.Text))
        $entry = [pscustomobject]@{ runId = 'r-new'; localRepoPath = $repoA; selectedTask = 'Add retry with backoff to the uploader' }
        $g = Resolve-QueuedTaskItemCooldown -Entry $entry -RunId 'r-new' -RunsDirectory $runsRoot -NowUtc $now
        Assert-That ($g.refuse -and -not $g.overridden) 'the runner refuses an item still cooling down'
        $entryOv = [pscustomobject]@{ runId = 'r-new'; localRepoPath = $repoA; selectedTask = 'Add retry with backoff to the uploader'; overrideCooldown = $true }
        $g = Resolve-QueuedTaskItemCooldown -Entry $entryOv -RunId 'r-new' -RunsDirectory $runsRoot -NowUtc $now
        Assert-That ($g.overridden -and -not $g.refuse) 'an operator override launches the item and is reported'
        $g = Resolve-QueuedTaskItemCooldown -Entry ([pscustomobject]@{ runId = 'r-new'; localRepoPath = $repoA; selectedTask = '' }) -RunId 'r-new' -RunsDirectory $runsRoot -NowUtc $now
        Assert-That (-not $g.refuse) 'an entry with no roadmap item is never held'
        function Test-WorkPacketIsRemediation { param($Packet) return ($null -ne $Packet) }
        $g = Resolve-QueuedTaskItemCooldown -Entry $entry -RunId 'r-new' -RunsDirectory $runsRoot -WorkPacket ([pscustomobject]@{ kind = 'remediation' }) -NowUtc $now
        Assert-That ($g.exempt -and -not $g.refuse) 'a remediation re-runs its item under its own cap and is exempt'
        Remove-Item Function:\Test-WorkPacketIsRemediation
    }
    $runnerSrc = Get-Content -LiteralPath $runnerPath -Raw
    $taskFn = $runnerAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-QueuedTask' }, $true)
    $taskSrc = if ($null -ne $taskFn) { $taskFn.Extent.Text } else { '' }
    $refuseAt = $taskSrc.IndexOf("refusalCategory = 'item-cooldown'")
    $claimAt = $taskSrc.IndexOf("status = 'running'")
    Assert-That ($refuseAt -gt 0 -and ($claimAt -lt 0 -or $refuseAt -lt $claimAt)) 'Invoke-QueuedTask refuses a cooling item before it claims the entry'
    Assert-That ($runnerSrc -match 'Roadmap\.ItemQuality\.ps1') 'the runner loads the shared item-quality module'

    # 11. the picker passes over cooling items; the override reaches the queue entry
    if ($null -ne $fn) {
        $pick = Get-NextRoadmapTask -RoadmapContent $mixed -RepoPath $repoA -DispatchRecords $records
        Assert-That ($pick.Next.TaskText -eq 'Wire the export route to the CSV writer') ("the picker passes over a cooling item, got '{0}'" -f $pick.Next.TaskText)
        $onlyCooling = "# Roadmap`n`n## Next`n`n- [ ] Add retry with backoff to the uploader`n"
        $threw = $null; try { Get-NextRoadmapTask -RoadmapContent $onlyCooling -RepoPath $repoA -DispatchRecords $records | Out-Null } catch { $threw = $_.Exception.Message }
        Assert-That ($null -ne $threw -and $threw -match '1 actionable item\(s\) were dispatched' -and $threw -match '-OverrideCooldown') 'when every actionable item is cooling, the picker says so and names the override'
    }
    $queueSrc = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'scripts/Add-RoadmapTaskToQueue.ps1') -Raw
    Assert-That ($queueSrc.Contains("if (`$OverrideCooldown) { `$entry['overrideCooldown'] = `$true }")) 'the queue entry carries overrideCooldown only when asked for'
    $startSrc = Get-Content -LiteralPath $scriptPath -Raw
    Assert-That ($startSrc.Contains('-OverrideCooldown:$OverrideCooldown')) 'the dispatch script forwards the override to the queue'
    Assert-That ($hostSrc.Contains("[bool]`$body.overrideCooldown) { `$scriptArgs += '-OverrideCooldown' }")) 'the start route forwards overrideCooldown from the request body'
}
finally {
    Remove-Item -LiteralPath $runsRoot -Recurse -Force
}

Write-Host ("Test-WorkItemQuality: {0} passed, {1} failed" -f $passed, $failures.Count)
foreach ($f in $failures) { Write-Host "  FAIL: $f" -ForegroundColor Red }
if ($failures.Count -gt 0 -and $FailOnError) { exit 1 }
