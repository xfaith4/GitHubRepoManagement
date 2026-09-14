#Requires -Version 7.0
<#
.SYNOPSIS
    Property checks over the foundation-conclusion model, selected by -Assert.

.DESCRIPTION
    One script, one assertion family per -Assert value, each a property the
    model must hold - never a distribution target over the cohort (steering
    section 6). The trial cohort (-Cohort) and the local index, where present,
    are assessed as real data; CI has neither and says so.

      lifecycle-consistency  (steering extension 3, Rung 1)
        lifecycleState and conclusion are two verdicts over the same signals
        and may not disagree without saying why. Asserts: every lifecycle
        state the assessment can emit is in lifecycleConsistency.allowed;
        every exception names states and conclusions from the vocabularies and
        carries a pattern that compiles; fixtures reach each agreement class
        (allowed, explained) and the validator goes red on a manufactured
        contradiction and on an unlisted lifecycle state; every record in the
        local index and every cohort repository holds.

      applicability          (3.7 M4b)
        The limiting foundation is chosen only among the domains that apply
        to the repository's kind. Asserts, for every kind in the config forced
        against an all-gaps fixture: each not-applicable domain renders its
        configured reason and never appears in limitingFoundation; every
        applicable gap does; missing outranks weak and config order holds
        within a status; a strengthen's next action answers the lead; an
        appropriate-as-is has no limiting foundation. A config-only
        applicability row moves a domain out of the limiting foundation with
        no code change. The validator goes red on a hand-built record that
        names a not-applicable domain as limiting. Every kind with
        applicability rows says where they were observed. The local index and
        cohort hold where present.

      action-routing         (3.7 M4c)
        Each kind of gap reaches its own previewable action. Asserts: every
        configured action names a kind, label, method and a route the console
        can run (read from frontend/lib/foundationConclusion.ts); every
        actionsByCase entry says where it was observed; the planning cases
        the evaluator emits over fixtures are exactly the cases the config
        maps, each record carries its case and that case's action, and the
        cases do not collapse onto one route; a config-only change reroutes a
        case with no code change; the validator goes red on a record carrying
        the wrong action and on a case the config does not map. No one-click
        egress: every host route that reaches an AI provider is one the console
        asks about first (AI_EGRESS_ROUTES), and the module sends nothing
        without a confirmation naming the provider and the file, nothing for a
        private-scope repository, and exactly once when confirmed. The trial
        cohort, replayed from evidence/trials/release-3.7/cohort-entries.json
        (keyed by index SHA, so CI runs it too), routes to more than one
        action - and the snapshot carries every field the model reads.

.EXAMPLE
    pwsh ./tests/Test-FoundationConclusions.ps1 -Cohort evidence/trials/release-3.7/cohort.json -Assert lifecycle-consistency -FailOnError
.EXAMPLE
    pwsh ./tests/Test-FoundationConclusions.ps1 -Cohort evidence/trials/release-3.7/cohort.json -Assert applicability -FailOnError
.EXAMPLE
    pwsh ./tests/Test-FoundationConclusions.ps1 -Cohort evidence/trials/release-3.7/cohort.json -Assert action-routing -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][string]$Cohort = '',
    [Parameter()][string]$IndexPath = '',
    [Parameter(Mandatory = $true)][ValidateSet('lifecycle-consistency', 'applicability', 'action-routing')][string]$Assert,
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$portfolioRoot = Join-Path $WorkspaceRoot 'backend\modules\portfolio'
. (Join-Path $portfolioRoot 'Portfolio.Conclusion.ps1')
$configPath = Join-Path $WorkspaceRoot 'backend\config\foundation-domains.json'
$config = Get-FoundationDomainsConfig -ConfigPath $configPath
if ($null -eq $config) { throw 'foundation-domains.json did not load' }

$failures = [System.Collections.Generic.List[string]]::new()
$notes = [System.Collections.Generic.List[string]]::new()

function ConvertTo-Entry([hashtable]$Overrides) {
    $base = @{ repoId = 'repo:x'; repoName = 'x'; sourceCoverage = 'local'; localPath = (Join-Path $WorkspaceRoot 'output\foundation-conclusions\x'); lastScanStatus = 'ok'
        lifecycleState = 'discovered'; curationState = 'none'; hasReadme = $true; readmeScore = 80; docFindingCount = 0; hasRoadmap = $true; roadmapState = 'pending'
        maturityLevel = 'L3-Contract-Ready'; pendingCount = 2; repoType = 'other'; structureFindings = @(); hasCiSignal = $false; hasTestSignal = $false
        latestWorkflowRunConclusion = $null; localCommitsLastMonth = 0; technologies = @(); kindSignals = $null }
    foreach ($k in $Overrides.Keys) { $base[$k] = $Overrides[$k] }
    $base['repoId'] = 'repo:' + [string]$base['repoName']
    return [pscustomobject]$base
}

# The local index and the cohort, where present. CI has neither and says so.
if ([string]::IsNullOrWhiteSpace($IndexPath)) { $IndexPath = Join-Path $WorkspaceRoot 'output\index\repos.index.json' }
$cohortNames = @()
if (-not [string]::IsNullOrWhiteSpace($Cohort)) {
    $cohortPath = if ([System.IO.Path]::IsPathRooted($Cohort)) { $Cohort } else { Join-Path $WorkspaceRoot $Cohort }
    if (-not (Test-Path -LiteralPath $cohortPath)) { $failures.Add("cohort file not found: $cohortPath") }
    else { $cohortNames = @((ConvertFrom-Json -InputObject (Get-Content -LiteralPath $cohortPath -Raw -Encoding UTF8)).records | Where-Object { [string]$_.selectionStatus -eq 'selected' } | ForEach-Object { [string]$_.repository }) }
}
$live = $null
$liveGenerated = ''
if (Test-Path -LiteralPath $IndexPath) {
    $index = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $IndexPath -Raw -Encoding UTF8)
    $rows = @($index.repos)
    $live = Get-PortfolioConclusionsPayload -Entries $rows -Config $config
    $liveGenerated = $index.generatedAt
    if ($liveGenerated -is [datetime]) { $liveGenerated = $liveGenerated.ToUniversalTime().ToString('o') }
} else {
    $notes.Add("no local index at $IndexPath - index and cohort passes skipped (CI has no portfolio; the fixtures and the config checks ran)")
}

# ============================================================================
if ($Assert -eq 'lifecycle-consistency') {
    $table = $config.lifecycleConsistency
    if ($null -eq $table) { throw 'foundation-domains.json carries no lifecycleConsistency table' }

    # --- The table covers the assessment's whole vocabulary ---------------
    # The list the assessment reports by (Portfolio.Assessment.ps1 byLifecycle);
    # read from the source so a new state cannot be added without a row here.
    $assessmentSource = Get-Content -LiteralPath (Join-Path $portfolioRoot 'Portfolio.Assessment.ps1') -Raw -Encoding UTF8
    $vocabMatch = [regex]::Match($assessmentSource, '(?s)\$byLifecycle\s*=\s*@\{\}\s*foreach\s*\(\$state in @\((.*?)\)\)')
    if (-not $vocabMatch.Success) { throw 'could not read the lifecycle vocabulary from Portfolio.Assessment.ps1 ($byLifecycle list)' }
    $lifecycleVocabulary = @([regex]::Matches($vocabMatch.Groups[1].Value, "'([a-z-]+)'") | ForEach-Object { $_.Groups[1].Value })
    $conclusionVocabulary = @($config.conclusions.PSObject.Properties.Name)
    $allowedStates = @($table.allowed.PSObject.Properties.Name)
    foreach ($state in $lifecycleVocabulary) {
        if ($state -notin $allowedStates) { $failures.Add("lifecycle state '$state' (assessment vocabulary) has no lifecycleConsistency.allowed row") }
    }
    foreach ($state in $allowedStates) {
        if ($state -notin $lifecycleVocabulary) { $failures.Add("lifecycleConsistency.allowed lists '$state', which the assessment never emits") }
        foreach ($c in @($table.allowed.$state)) { if ([string]$c -notin $conclusionVocabulary) { $failures.Add("allowed['$state'] names conclusion '$c' outside the configured set") } }
    }
    foreach ($ex in @($table.exceptions)) {
        $st = [string]$ex.lifecycleState; $co = [string]$ex.conclusion
        if ($st -ne '*' -and $st -notin $lifecycleVocabulary) { $failures.Add("exception names lifecycle state '$st' outside the vocabulary") }
        if ($co -ne '*' -and $co -notin $conclusionVocabulary) { $failures.Add("exception names conclusion '$co' outside the configured set") }
        if ([string]::IsNullOrWhiteSpace([string]$ex.explanation)) { $failures.Add("exception ($st, $co) carries no explanation") }
        try { $null = [regex]::new([string]$ex.requires) } catch { $failures.Add("exception ($st, $co) pattern does not compile: $($ex.requires)") }
    }

    # --- Fixtures: each agreement class, then the validator proved red ------
    $fixtures = @(
        (ConvertTo-Entry @{ repoName = 'archived-ok'; lifecycleState = 'archived' }),
        (ConvertTo-Entry @{ repoName = 'no-checklist'; lifecycleState = 'no-checklist'; roadmapState = 'no-checklist' }),
        (ConvertTo-Entry @{ repoName = 'needs-roadmap'; lifecycleState = 'needs-roadmap'; hasRoadmap = $false; roadmapState = 'missing'; maturityLevel = 'L0-Absent'; pendingCount = 0 }),
        (ConvertTo-Entry @{ repoName = 'completed-fine'; lifecycleState = 'completed'; roadmapState = 'complete'; pendingCount = 0 }),
        # explained: the lifecycle model does not read curation; the kind rule does
        (ConvertTo-Entry @{ repoName = 'curated-archive'; lifecycleState = 'needs-roadmap-repair'; curationState = 'archived-ignore'; maturityLevel = 'L0-Absent' }),
        # explained: no local checkout - the lifecycle reads the missing README, the conclusion names the need
        (ConvertTo-Entry @{ repoName = 'github-only'; lifecycleState = 'needs-readme'; sourceCoverage = 'github'; localPath = ''; hasReadme = $false; readmeScore = 0 })
    )
    $expectedAgreement = @{ 'archived-ok' = 'allowed'; 'no-checklist' = 'allowed'; 'needs-roadmap' = 'allowed'; 'completed-fine' = 'allowed'; 'curated-archive' = 'explained'; 'github-only' = 'explained' }
    $payload = Get-PortfolioConclusionsPayload -Entries $fixtures -Config $config
    if (-not $payload.contract.holds) { $failures.Add("fixture set violates the contract: $($payload.contract.violations -join '; ')") }
    foreach ($item in @($payload.items)) {
        $name = [string]$item.repoName
        $c = $item.consistency
        if ($null -eq $c) { $failures.Add("${name} carries no consistency record"); continue }
        if ([string]$c.agreement -ne $expectedAgreement[$name]) { $failures.Add("${name}: agreement '$($c.agreement)' expected '$($expectedAgreement[$name])' (lifecycle=$($c.lifecycleState) conclusion=$($c.conclusion): $($c.explanation))") }
        if ([string]$c.agreement -eq 'explained' -and @($c.evidence).Count -eq 0) { $failures.Add("$name is explained but cites no evidence") }
        Write-Host ('  {0,-16} {1,-21} + {2,-25} -> {3}{4}' -f $name, $c.lifecycleState, $c.conclusion, $c.agreement, $(if (@($c.evidence).Count -gt 0) { " (evidence: $($c.evidence[0]))" } else { '' }))
    }

    # Red first: the validator must reject a contradiction and an unlisted
    # state before its green verdict on real data means anything.
    $contradiction = Get-RepositoryFoundationConclusion -Entry (ConvertTo-Entry @{ repoName = 'contradiction'; lifecycleState = 'needs-readme'; readmeScore = 95 }) -Config $config
    $red = @(Test-FoundationConclusion -Conclusion $contradiction -Config $config)
    if ([string]$contradiction.consistency.agreement -ne 'contradiction') { $failures.Add("the manufactured contradiction (needs-readme + $($contradiction.conclusion)) was classified '$($contradiction.consistency.agreement)'") }
    if (@($red | Where-Object { $_ -match 'disagree and nothing in the basis explains it' }).Count -eq 0) { $failures.Add("validator did not go red on the contradiction (violations: $($red -join '; '))") }
    $unlisted = Get-RepositoryFoundationConclusion -Entry (ConvertTo-Entry @{ repoName = 'unlisted'; lifecycleState = 'bogus-state' }) -Config $config
    if (@(Test-FoundationConclusion -Conclusion $unlisted -Config $config | Where-Object { $_ -match 'not in lifecycleConsistency.allowed' }).Count -eq 0) { $failures.Add('validator did not go red on a lifecycle state the table does not list') }

    # --- Real data ----------------------------------------------------------
    if ($null -ne $live) {
        $counts = $live.byConsistency
        $notes.Add(('local index {0}: {1} repositories - allowed {2}, explained {3}, contradiction {4}, unknown-lifecycle {5}' -f [string]$liveGenerated, @($live.items).Count, $counts.allowed, $counts.explained, $counts.contradiction, $counts.'unknown-lifecycle'))
        foreach ($item in @($live.items)) {
            $c = $item.consistency
            if ($null -eq $c -or -not $c.holds) { $failures.Add(("index: {0} ({1} + {2}): {3}" -f $item.repoName, $item.lifecycleState, $item.conclusion, $(if ($null -eq $c) { 'no consistency record' } else { $c.explanation }))) }
        }
        $seen = 0
        foreach ($name in $cohortNames) {
            $item = @($live.items | Where-Object { [string]$_.repoName -eq $name } | Select-Object -First 1)
            if ($item.Count -eq 0) { $notes.Add("cohort: $name is not in the local index"); continue }
            $seen++
            $c = $item[0].consistency
            Write-Host ('  cohort {0,-27} {1,-21} + {2,-25} -> {3}' -f $name, $c.lifecycleState, $c.conclusion, $c.agreement)
        }
        if ($cohortNames.Count -gt 0) { $notes.Add("cohort: $seen of $($cohortNames.Count) repositories assessed from the local index") }
    }

    $headline = 'Lifecycle/conclusion consistency (steering extension 3):'
    $okLine = "ok: {0} lifecycle states covered, {1} exceptions well-formed, {2} fixtures across allowed/explained, validator red on a contradiction and an unlisted state" -f $lifecycleVocabulary.Count, @($table.exceptions).Count, $fixtures.Count
}

# ============================================================================
if ($Assert -eq 'applicability') {
    $domainIds = @($config.domains | ForEach-Object { [string]$_.id })
    $kinds = @($config.kinds)

    # --- Config: every row names a real domain with a reason, and every kind
    # with rows says where they were observed (steering section 5).
    foreach ($k in $kinds) {
        $rows = @($k.applicability.PSObject.Properties)
        foreach ($p in $rows) {
            if ([string]$p.Name -notin $domainIds) { $failures.Add("kind '$($k.id)' marks unknown domain '$($p.Name)' not applicable") }
            if ([string]::IsNullOrWhiteSpace([string]$p.Value)) { $failures.Add("kind '$($k.id)' marks '$($p.Name)' not applicable without a reason") }
        }
        if ($rows.Count -gt 0) {
            $basisProp = $k.PSObject.Properties['applicabilityBasis']
            if ($null -eq $basisProp -or $null -eq $k.applicabilityBasis.PSObject.Properties['observedOn']) { $failures.Add("kind '$($k.id)' has applicability rows but no applicabilityBasis.observedOn") }
            elseif (@($k.applicabilityBasis.observedOn).Count -eq 0 -and [string]::IsNullOrWhiteSpace([string]$k.applicabilityBasis.note)) { $failures.Add("kind '$($k.id)' applicability was observed on nothing and says nothing about why") }
        }
    }

    # --- Every kind against the same all-gaps fixture ------------------------
    # A config clone whose only detection rules pin the kind by fixture, so the
    # applicability under test is the kind's own and nothing else.
    $pinned = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $config -Depth 16)
    $pinned.kindDetection.rules = @($kinds | ForEach-Object { [pscustomobject]@{ kind = [string]$_.id; when = [pscustomobject]@{ repoType = ('kind:' + [string]$_.id) }; basis = ('pinned by fixture to ' + [string]$_.id) } })
    $allGaps = @{ hasReadme = $true; readmeScore = 20; hasRoadmap = $false; roadmapState = 'missing'; maturityLevel = 'L0-Absent'; pendingCount = 0
        structureFindings = @([pscustomobject]@{ kind = 'missing-root-file'; target = 'LICENSE'; severity = 'critical'; category = 'root'; recommendedAction = 'add' }) }
    $kindRows = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $kinds) {
        $kid = [string]$k.id
        $overrides = @{ repoName = "gaps-$kid"; repoType = "kind:$kid" } + $allGaps
        $entry = ConvertTo-Entry $overrides
        $c = Get-RepositoryFoundationConclusion -Entry $entry -Config $pinned
        if ([string]$c.kind -ne $kid) { $failures.Add("fixture for '$kid' resolved kind '$($c.kind)'"); continue }
        $naDomains = @($k.applicability.PSObject.Properties | ForEach-Object { [string]$_.Name })
        $limiting = @($c.limitingFoundation | ForEach-Object { [string]$_.domain })
        foreach ($d in $naDomains) {
            $rec = @($c.domains | Where-Object { [string]$_.domain -eq $d })[0]
            if ([string]$rec.status -ne 'not-applicable') { $failures.Add("kind '$kid': domain '$d' is configured not applicable but has status '$($rec.status)'") }
            if ([string]@($rec.evidence)[0] -ne [string]$k.applicability.$d) { $failures.Add("kind '$kid': domain '$d' does not render its configured reason") }
            if ($d -in $limiting) { $failures.Add("kind '$kid': not-applicable domain '$d' appears in limitingFoundation") }
        }
        # A kind whose rule concludes appropriate-as-is says nothing limits: its
        # applicable gaps stay in domains and are recorded in the basis instead.
        $kindConcluded = [string]$c.conclusion -eq 'appropriate-as-is' -and -not [string]::IsNullOrWhiteSpace([string]$k.PSObject.Properties['conclusion'].Value)
        foreach ($rec in @($c.domains)) {
            $d = [string]$rec.domain
            if ($d -in $naDomains) { continue }
            if ([string]$rec.status -in @('missing', 'weak') -and $d -notin $limiting) {
                if ($kindConcluded) {
                    $gapLine = @($c.basis | Where-Object { [string]$_ -like 'gaps recorded, not limiting:*' })
                    if ($gapLine.Count -eq 0 -or -not ([string]$gapLine[0]).Contains(('{0}={1}' -f $d, [string]$rec.status))) { $failures.Add("kind '$kid': gap '$d' ($($rec.status)) is neither limiting nor recorded in the basis (basis: $($c.basis -join ' | '))") }
                } else { $failures.Add("kind '$kid': applicable gap '$d' ($($rec.status)) is missing from limitingFoundation") }
            }
            if ([string]$rec.status -notin @('missing', 'weak') -and $d -in $limiting) { $failures.Add("kind '$kid': '$d' with status '$($rec.status)' appears in limitingFoundation") }
        }
        # Order: missing before weak; within a status, the config's domain order.
        $rank = @{}; for ($i = 0; $i -lt $domainIds.Count; $i++) { $rank[$domainIds[$i]] = $i }
        $expectedOrder = @(@($c.limitingFoundation | Where-Object { $_.status -eq 'missing' } | Sort-Object { $rank[[string]$_.domain] }) + @($c.limitingFoundation | Where-Object { $_.status -eq 'weak' } | Sort-Object { $rank[[string]$_.domain] }) | ForEach-Object { [string]$_.domain })
        if (($expectedOrder -join '>') -ne ($limiting -join '>')) { $failures.Add("kind '$kid': limitingFoundation order ($($limiting -join ' > ')) is not missing-first then config order ($($expectedOrder -join ' > '))") }
        if ([string]$c.conclusion -eq 'strengthen') {
            if ($limiting.Count -eq 0) { $failures.Add("kind '$kid': strengthen with an empty limitingFoundation") }
            elseif ($null -ne $c.nextAction -and [string]$c.nextAction.domain -ne $limiting[0]) { $failures.Add("kind '$kid': next action answers '$($c.nextAction.domain)', the lead is '$($limiting[0])'") }
        }
        if ([string]$c.conclusion -eq 'appropriate-as-is' -and $limiting.Count -gt 0) { $failures.Add("kind '$kid': appropriate-as-is with a limiting foundation ($($limiting -join ', '))") }
        $v = @(Test-FoundationConclusion -Conclusion $c -Config $pinned)
        if ($v.Count -gt 0) { $failures.Add("kind '$kid': contract violated: $($v -join '; ')") }
        $kindRows.Add(('  {0,-19} {1,-25} limiting: {2,-32} not applicable: {3}' -f $kid, $c.conclusion, $(if ($limiting.Count -gt 0) { $limiting -join ' > ' } else { '-' }), $(if ($naDomains.Count -gt 0) { $naDomains -join ', ' } else { '-' })))
    }
    foreach ($row in $kindRows) { Write-Host $row }

    # --- A data-only row moves a domain out of the limiting foundation --------
    $refined = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $pinned -Depth 16)
    $toolingDef = @($refined.kinds | Where-Object { [string]$_.id -eq 'tooling' })[0]
    $toolingDef.applicability | Add-Member -NotePropertyName 'structure' -NotePropertyValue 'fixture: a single-script utility is not reorganized' -Force
    $before = Get-RepositoryFoundationConclusion -Entry (ConvertTo-Entry (@{ repoName = 'gaps-tooling'; repoType = 'kind:tooling' } + $allGaps)) -Config $pinned
    $after = Get-RepositoryFoundationConclusion -Entry (ConvertTo-Entry (@{ repoName = 'gaps-tooling'; repoType = 'kind:tooling' } + $allGaps)) -Config $refined
    if ('structure' -notin @($before.limitingFoundation | ForEach-Object { [string]$_.domain })) { $failures.Add('the all-gaps tooling fixture should have structure among its limiting foundations before the row') }
    if ('structure' -in @($after.limitingFoundation | ForEach-Object { [string]$_.domain })) { $failures.Add('a config-only applicability row did not move structure out of the limiting foundation') }
    $afterStructure = @($after.domains | Where-Object { [string]$_.domain -eq 'structure' })[0]
    if ([string]$afterStructure.status -ne 'not-applicable' -or [string]@($afterStructure.evidence)[0] -ne 'fixture: a single-script utility is not reorganized') { $failures.Add('the data-only row did not render its reason') }
    if (@(Test-FoundationConclusion -Conclusion $after -Config $refined).Count -ne 0) { $failures.Add('the refined conclusion broke the contract') }

    # Red first: a record that names a not-applicable domain as limiting must
    # be rejected before the green verdict on real data means anything.
    $tampered = Get-RepositoryFoundationConclusion -Entry (ConvertTo-Entry (@{ repoName = 'tampered'; repoType = 'kind:archived' } + $allGaps)) -Config $pinned
    $planningRec = @($tampered.domains | Where-Object { [string]$_.domain -eq 'planning' })[0]
    if ([string]$planningRec.status -ne 'not-applicable') { $failures.Add("archived fixture: planning should be not-applicable, is '$($planningRec.status)'") }
    $tampered.limitingFoundation = @([pscustomobject]@{ domain = 'planning'; title = 'Planning'; status = 'missing'; evidence = @('tampered') })
    if (@(Test-FoundationConclusion -Conclusion $tampered -Config $pinned | Where-Object { $_ -match 'names not-applicable domain' }).Count -eq 0) { $failures.Add('validator did not go red on a limiting foundation that names a not-applicable domain') }

    # --- Real data ----------------------------------------------------------
    if ($null -ne $live) {
        $leads = @($live.byLimitingFoundation.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ' '
        $notes.Add(('local index {0}: {1} repositories - leading foundation {2} (a count, not a target)' -f [string]$liveGenerated, @($live.items).Count, $leads))
        foreach ($item in @($live.items)) {
            $kindDef = @($config.kinds | Where-Object { [string]$_.id -eq [string]$item.kind })[0]
            $naDomains = @($kindDef.applicability.PSObject.Properties | ForEach-Object { [string]$_.Name })
            $limiting = @($item.limitingFoundation | ForEach-Object { [string]$_.domain })
            foreach ($d in $naDomains) {
                if ($d -in $limiting) { $failures.Add("index: $($item.repoName) ($($item.kind)) names not-applicable '$d' as limiting") }
                $rec = @($item.domains | Where-Object { [string]$_.domain -eq $d })[0]
                if ([string]@($rec.evidence)[0] -ne [string]$kindDef.applicability.$d) { $failures.Add("index: $($item.repoName) ($($item.kind)) does not render the configured reason for '$d'") }
            }
            if ([string]$item.conclusion -eq 'strengthen' -and $null -ne $item.nextAction -and $limiting.Count -gt 0 -and [string]$item.nextAction.domain -ne $limiting[0]) { $failures.Add("index: $($item.repoName) next action answers '$($item.nextAction.domain)', lead is '$($limiting[0])'") }
        }
        $seen = 0
        foreach ($name in $cohortNames) {
            $item = @($live.items | Where-Object { [string]$_.repoName -eq $name } | Select-Object -First 1)
            if ($item.Count -eq 0) { $notes.Add("cohort: $name is not in the local index"); continue }
            $seen++
            $limiting = @($item[0].limitingFoundation | ForEach-Object { '{0} {1}' -f [string]$_.domain, [string]$_.status })
            Write-Host ('  cohort {0,-27} {1,-12} {2,-25} limiting: {3}' -f $name, $item[0].kind, $item[0].conclusion, $(if ($limiting.Count -gt 0) { $limiting -join ', ' } else { '-' }))
        }
        if ($cohortNames.Count -gt 0) { $notes.Add("cohort: $seen of $($cohortNames.Count) repositories assessed from the local index") }
    }

    $headline = 'Limiting foundation by kind applicability (3.7 M4b):'
    $okLine = "ok: {0} kinds each forced against the all-gaps fixture; not-applicable never limits and renders its reason; missing-first order; strengthen answers the lead; a data-only row moved a domain out; validator red on a tampered record" -f $kinds.Count
}

# ============================================================================
if ($Assert -eq 'action-routing') {
    # --- Every configured action is one the console can run -----------------
    $frontendSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'frontend\lib\foundationConclusion.ts') -Raw -Encoding UTF8
    $routesMatch = [regex]::Match($frontendSource, '(?s)RUNNABLE_NEXT_ACTION_ROUTES:\s*readonly string\[\]\s*=\s*\[(.*?)\];')
    if (-not $routesMatch.Success) { throw 'could not read RUNNABLE_NEXT_ACTION_ROUTES from frontend/lib/foundationConclusion.ts' }
    $runnable = @([regex]::Matches($routesMatch.Groups[1].Value, "'(/api/[^']+)'") | ForEach-Object { $_.Groups[1].Value })
    $planningDef = @($config.domains | Where-Object { [string]$_.id -eq 'planning' })[0]
    if ($null -eq $planningDef.PSObject.Properties['actionsByCase']) { throw 'the planning domain carries no actionsByCase map' }
    $caseNames = @($planningDef.actionsByCase.PSObject.Properties | Where-Object { $_.Name -ne 'note' } | ForEach-Object { [string]$_.Name })
    foreach ($domain in @($config.domains)) {
        $defs = [System.Collections.Generic.List[object]]::new()
        foreach ($slot in @('nextAction', 'pendingWorkAction')) {
            if ($null -ne $domain.PSObject.Properties[$slot]) { $defs.Add([pscustomobject]@{ name = "$($domain.id).$slot"; def = $domain.$slot; byCase = $false }) | Out-Null }
        }
        if ($null -ne $domain.PSObject.Properties['actionsByCase']) {
            foreach ($p in @($domain.actionsByCase.PSObject.Properties | Where-Object { $_.Name -ne 'note' })) { $defs.Add([pscustomobject]@{ name = "$($domain.id).actionsByCase.$($p.Name)"; def = $p.Value; byCase = $true }) | Out-Null }
        }
        foreach ($d in $defs) {
            foreach ($field in @('kind', 'label', 'method', 'route')) {
                if ($null -eq $d.def.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$d.def.$field)) { $failures.Add("$($d.name) names no $field") }
            }
            if ($null -ne $d.def.PSObject.Properties['route'] -and [string]$d.def.route -notin $runnable) { $failures.Add("$($d.name) routes to '$($d.def.route)', which the console cannot run (RUNNABLE_NEXT_ACTION_ROUTES)") }
            if ($d.byCase) {
                if ($null -eq $d.def.PSObject.Properties['observedOn']) { $failures.Add("$($d.name) carries no observedOn") }
                elseif (@($d.def.observedOn).Count -eq 0 -and ($null -eq $d.def.PSObject.Properties['observedNote'] -or [string]::IsNullOrWhiteSpace([string]$d.def.observedNote))) { $failures.Add("$($d.name) was observed on nothing and says nothing about why") }
            }
        }
    }
    $caseKinds = @($caseNames | ForEach-Object { [string]$planningDef.actionsByCase.$_.kind })
    if (@($caseKinds | Select-Object -Unique).Count -ne $caseKinds.Count) { $failures.Add("planning cases share an action kind ($($caseKinds -join ', ')); each kind of gap needs its own action") }

    # --- An action that reaches an AI provider asks before it sends ---------
    # No one-click egress (Ben, 2026-09-14). Which host routes send a file to a
    # provider is read from the host, not listed here: a route clause whose
    # body calls Invoke-AiDocImprovePreview. The console must ask before every
    # one of them, and the module must send nothing without a confirmation
    # naming the provider and the file, and nothing at all for private scope.
    $hostSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw -Encoding UTF8
    $clauseMatches = [regex]::Matches($hostSource, "(?m)^\s*'(?:GET|POST|PUT|PATCH|DELETE) (/api/[^']+)'\s*\{")
    $egressRoutes = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $clauseMatches.Count; $i++) {
        $clauseEnd = if ($i + 1 -lt $clauseMatches.Count) { $clauseMatches[$i + 1].Index } else { $hostSource.Length }
        $clauseText = $hostSource.Substring($clauseMatches[$i].Index, $clauseEnd - $clauseMatches[$i].Index)
        if ($clauseText -match 'Invoke-AiDocImprovePreview') {
            $egressRoutes.Add($clauseMatches[$i].Groups[1].Value) | Out-Null
            if ($clauseText -notmatch '-EgressConfirmation') { $failures.Add("$($clauseMatches[$i].Groups[1].Value) calls Invoke-AiDocImprovePreview without passing the operator's confirmation, so no request through it can ever be confirmed") }
        }
    }
    if ($egressRoutes.Count -eq 0) { $failures.Add('no host route calls Invoke-AiDocImprovePreview; the egress property has lost its scope') }
    $egressListMatch = [regex]::Match($frontendSource, '(?s)AI_EGRESS_ROUTES:\s*readonly string\[\]\s*=\s*\[(.*?)\];')
    if (-not $egressListMatch.Success) { throw 'could not read AI_EGRESS_ROUTES from frontend/lib/foundationConclusion.ts' }
    $consoleEgress = @([regex]::Matches($egressListMatch.Groups[1].Value, "'(/api/[^']+)'") | ForEach-Object { $_.Groups[1].Value })
    foreach ($route in $egressRoutes) {
        if ($route -notin $consoleEgress) { $failures.Add("$route sends a file to an AI provider, but the console does not ask before sending (AI_EGRESS_ROUTES)") }
    }

    $egressProbe = & {
        . (Join-Path $WorkspaceRoot 'backend\modules\ai\AiDocImprovement.ps1')
        $providerCalls = [System.Collections.Generic.List[string]]::new()
        # Stand-ins for the two adapters: a call is recorded, nothing is sent.
        function Invoke-AnthropicDocProvider { param($ApiKey, $Model, $SystemPrompt, $UserPrompt, $MaxTokens) $null = $ApiKey, $SystemPrompt, $UserPrompt, $MaxTokens; $providerCalls.Add('anthropic') | Out-Null; [pscustomobject]@{ providerId = 'anthropic'; modelId = $Model; proposedContent = "# stand-in`n"; changeSummary = @(); warnings = @(); error = ''; usage = (New-AiDocUsage -Source 'absent') } }
        function Invoke-OpenAiDocProvider { param($ApiKey, $Model, $SystemPrompt, $UserPrompt, $MaxTokens) $null = $ApiKey, $SystemPrompt, $UserPrompt, $MaxTokens; $providerCalls.Add('openai') | Out-Null; [pscustomobject]@{ providerId = 'openai'; modelId = $Model; proposedContent = "# stand-in`n"; changeSummary = @(); warnings = @(); error = ''; usage = (New-AiDocUsage -Source 'absent') } }
        $keyVar = 'REPO_MGMT_EGRESS_CHECK_PLACEHOLDER'
        [Environment]::SetEnvironmentVariable($keyVar, 'placeholder-not-a-key', 'Process')
        try {
            $file = 'C:\fixture\open-repo\ROADMAP.md'
            $settings = @{ ai = @{ provider = 'auto'; anthropic = @{ apiKeyEnvVar = $keyVar; model = 'check-model' }; openai = @{ apiKeyEnvVar = 'REPO_MGMT_EGRESS_CHECK_UNSET' }; privateScopeRepos = @('Private-Repo') } }
            $run = {
                param($RepoName, $Provider, $Confirmation)
                $before = $providerCalls.Count
                $p = Invoke-AiDocImprovePreview -WorkspaceRoot $WorkspaceRoot -RepoName $RepoName -DocType 'roadmap' -CurrentContent "# plan`n" -Provider $Provider -Settings $settings -DocPath $file -EgressConfirmation $Confirmation
                [pscustomobject]@{ preview = $p; sent = ($providerCalls.Count - $before) }
            }
            [pscustomobject]@{
                file         = $file
                unconfirmed  = & $run 'open-repo' '' $null
                otherFile    = & $run 'open-repo' '' @{ providerId = 'anthropic'; file = 'C:\fixture\other\ROADMAP.md' }
                otherProv    = & $run 'open-repo' '' @{ providerId = 'openai'; file = $file }
                privateScope = & $run 'private-repo' '' @{ providerId = 'anthropic'; file = $file }
                offline      = & $run 'private-repo' 'heuristic' $null
                confirmed    = & $run 'open-repo' '' @{ providerId = 'anthropic'; file = $file }
            }
        }
        finally { [Environment]::SetEnvironmentVariable($keyVar, $null, 'Process') }
    }
    $stateOf = { param($r) [string]$(if ($r.preview.PSObject.Properties.Name -contains 'previewState') { $r.preview.previewState } else { 'preview' }) }
    foreach ($case in @(
            @{ name = 'unconfirmed'; expect = 'ai-egress-confirmation-required' },
            @{ name = 'otherFile'; expect = 'ai-egress-confirmation-required' },
            @{ name = 'otherProv'; expect = 'ai-egress-confirmation-required' },
            @{ name = 'privateScope'; expect = 'ai-egress-blocked' })) {
        $r = $egressProbe.($case.name)
        if ($r.sent -ne 0) { $failures.Add("egress: the $($case.name) request reached the provider $($r.sent) time(s); nothing may be sent without a matching confirmation, and nothing for private scope") }
        if ((& $stateOf $r) -ne $case.expect) { $failures.Add("egress: the $($case.name) request answered '$(& $stateOf $r)', expected '$($case.expect)'") }
        if ($r.preview.PSObject.Properties.Name -contains 'proposedContent') { $failures.Add("egress: the $($case.name) request produced proposed content without sending, which cannot be") }
    }
    if ([string]$egressProbe.unconfirmed.preview.egress.providerId -ne 'anthropic' -or [string]$egressProbe.unconfirmed.preview.egress.file -ne $egressProbe.file) { $failures.Add('egress: the confirmation request must name the provider and the file it would send') }
    if ([string]::IsNullOrWhiteSpace([string]$egressProbe.privateScope.preview.blockReason)) { $failures.Add('egress: a private-scope refusal must say why') }
    if ($egressProbe.offline.sent -ne 0 -or [string]$egressProbe.offline.preview.egress.state -ne 'local') { $failures.Add('egress: the offline provider sends nothing and needs no confirmation, private scope or not') }
    if ($egressProbe.confirmed.sent -ne 1 -or [string]$egressProbe.confirmed.preview.egress.state -ne 'confirmed') { $failures.Add("egress: a confirmation naming the provider and file must send exactly once (sent $($egressProbe.confirmed.sent), state '$($egressProbe.confirmed.preview.egress.state)')") }

    # --- Fixtures: every planning case the evaluator can emit ----------------
    $planningFixtures = [ordered]@{
        'no-roadmap'                    = @{ repoName = 'no-roadmap'; hasRoadmap = $false; roadmapState = 'missing'; maturityLevel = 'L0-Absent'; pendingCount = 0 }
        'prose-roadmap'                 = @{ repoName = 'prose-roadmap'; roadmapState = 'no-checklist'; maturityLevel = 'L0-Absent'; pendingCount = 0 }
        'parse-error'                   = @{ repoName = 'empty-roadmap'; roadmapState = 'parse-error'; maturityLevel = 'L0-Absent'; pendingCount = 0 }
        'below-contract-ready'          = @{ repoName = 'informal-roadmap'; roadmapState = 'pending'; maturityLevel = 'L1-Informal'; pendingCount = 3 }
        'below-contract-ready:L0'       = @{ repoName = 'absent-contract'; roadmapState = 'pending'; maturityLevel = 'L0-Absent'; pendingCount = 3 }
        'complete-below-contract-ready' = @{ repoName = 'finished-informal'; roadmapState = 'complete'; maturityLevel = 'L0-Absent'; pendingCount = 0 }
    }
    $emitted = [System.Collections.Generic.HashSet[string]]::new()
    $routedTo = [System.Collections.Generic.HashSet[string]]::new()
    $fixtureRows = [System.Collections.Generic.List[string]]::new()
    foreach ($label in $planningFixtures.Keys) {
        $expectedCase = ($label -split ':')[0]
        $c = Get-RepositoryFoundationConclusion -Entry (ConvertTo-Entry $planningFixtures[$label]) -Config $config
        $rec = @($c.domains | Where-Object { [string]$_.domain -eq 'planning' })[0]
        $null = $emitted.Add([string]$rec.case)
        if ([string]$rec.case -ne $expectedCase) { $failures.Add("fixture '$label': planning case is '$($rec.case)', expected '$expectedCase'"); continue }
        $want = $planningDef.actionsByCase.$expectedCase
        if ($null -eq $rec.nextAction) { $failures.Add("fixture '$label': planning gap carries no action"); continue }
        if ([string]$rec.nextAction.kind -ne [string]$want.kind -or [string]$rec.nextAction.route -ne [string]$want.route -or [string]$rec.nextAction.case -ne $expectedCase) { $failures.Add("fixture '$label': carries $($rec.nextAction.kind) -> $($rec.nextAction.route) (case '$($rec.nextAction.case)'), configured $($want.kind) -> $($want.route)") }
        if ([string]$rec.nextAction.body.repoName -ne [string]$planningFixtures[$label].repoName) { $failures.Add("fixture '$label': action body does not name the repository") }
        if ($null -ne $want.PSObject.Properties['bodyValues']) {
            foreach ($bv in $want.bodyValues.PSObject.Properties) { if ([string]$rec.nextAction.body.($bv.Name) -ne [string]$bv.Value) { $failures.Add("fixture '$label': body $($bv.Name) is '$($rec.nextAction.body.($bv.Name))', configured '$($bv.Value)'") } }
        }
        if ($null -eq $c.nextAction -or [string]$c.nextAction.kind -ne [string]$want.kind) { $failures.Add("fixture '$label': the conclusion ($($c.conclusion)) offers '$(if ($null -ne $c.nextAction) { $c.nextAction.kind })', not the planning case's action") }
        $v = @(Test-FoundationConclusion -Conclusion $c -Config $config)
        if ($v.Count -gt 0) { $failures.Add("fixture '$label': contract violated: $($v -join '; ')") }
        $null = $routedTo.Add([string]$rec.nextAction.route)
        $fixtureRows.Add(('  {0,-32} {1,-26} -> {2,-34} {3}' -f $label, $c.conclusion, $rec.nextAction.kind, $rec.nextAction.route)) | Out-Null
    }
    foreach ($row in $fixtureRows) { Write-Host $row }
    foreach ($cn in $caseNames) { if (-not $emitted.Contains($cn)) { $failures.Add("actionsByCase maps '$cn', which no planning fixture emits - a dead route or a missing fixture") } }
    foreach ($e in $emitted) { if ($e -notin $caseNames) { $failures.Add("the evaluator emits planning case '$e', which actionsByCase does not map") } }
    if ($routedTo.Count -lt 2) { $failures.Add("the planning cases collapse onto one route ($($routedTo -join ', '))") }

    # --- A data-only change reroutes a case -----------------------------------
    $rerouted = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $config -Depth 16)
    $rrPlanning = @($rerouted.domains | Where-Object { [string]$_.id -eq 'planning' })[0]
    $rrPlanning.actionsByCase.'below-contract-ready'.kind = 'fixture-rerouted-preview'
    $rrPlanning.actionsByCase.'below-contract-ready'.route = '/api/repo/evaluate'
    $rr = Get-RepositoryFoundationConclusion -Entry (ConvertTo-Entry $planningFixtures['below-contract-ready']) -Config $rerouted
    if ([string]$rr.nextAction.kind -ne 'fixture-rerouted-preview' -or [string]$rr.nextAction.route -ne '/api/repo/evaluate') { $failures.Add("a config-only reroute did not change the action (got $($rr.nextAction.kind) -> $($rr.nextAction.route))") }
    if (@(Test-FoundationConclusion -Conclusion $rr -Config $rerouted).Count -ne 0) { $failures.Add('the rerouted conclusion broke the contract') }

    # --- Red first: the wrong action, and a case nothing routes ----------------
    $wrong = Get-RepositoryFoundationConclusion -Entry (ConvertTo-Entry $planningFixtures['prose-roadmap']) -Config $config
    $wrongPlanning = @($wrong.domains | Where-Object { [string]$_.domain -eq 'planning' })[0]
    $wrongPlanning.nextAction.kind = 'roadmap-repair-preview'
    if (@(Test-FoundationConclusion -Conclusion $wrong -Config $config | Where-Object { $_ -match "carries action 'roadmap-repair-preview'" }).Count -eq 0) { $failures.Add('validator did not go red on a prose roadmap carrying the repair action') }
    $unmappedConfig = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $config -Depth 16)
    $umPlanning = @($unmappedConfig.domains | Where-Object { [string]$_.id -eq 'planning' })[0]
    $umPlanning.actionsByCase.PSObject.Properties.Remove('prose-roadmap')
    $unmapped = Get-RepositoryFoundationConclusion -Entry (ConvertTo-Entry $planningFixtures['prose-roadmap']) -Config $unmappedConfig
    if (@(Test-FoundationConclusion -Conclusion $unmapped -Config $unmappedConfig | Where-Object { $_ -match "case 'prose-roadmap', which actionsByCase does not route" }).Count -eq 0) { $failures.Add('validator did not go red on a planning case the config does not route') }

    # --- The trial cohort, replayed from its snapshot (runs in CI) -------------
    $snapshotPath = Join-Path $WorkspaceRoot 'evidence\trials\release-3.7\cohort-entries.json'
    if (-not (Test-Path -LiteralPath $snapshotPath)) { $failures.Add("cohort snapshot not found at $snapshotPath") }
    else {
        $snapshot = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $snapshotPath -Raw -Encoding UTF8)
        if ([string]$snapshot.sourceIndexSha256 -notmatch '^[0-9a-f]{64}$') { $failures.Add('cohort snapshot does not record the SHA-256 of the index it came from') }
        # The snapshot must carry every field the model reads, or the replay
        # silently defaults one and proves nothing about the real cohort.
        $moduleSource = Get-Content -LiteralPath (Join-Path $portfolioRoot 'Portfolio.Conclusion.ps1') -Raw -Encoding UTF8
        $readFields = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($m in [regex]::Matches($moduleSource, "-Obj \`$Entry -Name '([A-Za-z]+)'")) { $null = $readFields.Add($m.Groups[1].Value) }
        foreach ($rule in @($config.kindDetection.rules)) {
            if ($null -ne $rule.PSObject.Properties['when']) { foreach ($p in $rule.when.PSObject.Properties) { $null = $readFields.Add($p.Name) } }
            if ($null -ne $rule.PSObject.Properties['whenAny']) { foreach ($p in $rule.whenAny.PSObject.Properties) { $null = $readFields.Add(($p.Name -split '\.')[0]) } }
        }
        $snapRecords = @($snapshot.records)
        foreach ($f in $readFields) {
            foreach ($r in $snapRecords) { if ($null -eq $r.PSObject.Properties[$f]) { $failures.Add("cohort snapshot record $($r.repoName) lacks '$f', which the model reads"); break } }
        }
        if ($cohortNames.Count -gt 0) {
            $snapNames = @($snapRecords | ForEach-Object { [string]$_.repoName })
            foreach ($n in $cohortNames) { if ($n -notin $snapNames) { $failures.Add("cohort repository $n is not in the snapshot") } }
        }
        $replay = Get-PortfolioConclusionsPayload -Entries $snapRecords -Config $config
        if (-not $replay.contract.holds) { $failures.Add("cohort replay violates the contract: $($replay.contract.violations -join '; ')") }
        $cohortRoutes = [System.Collections.Generic.HashSet[string]]::new()
        $cohortKinds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($item in @($replay.items)) {
            $na = $item.nextAction
            if ($null -ne $na) { $null = $cohortRoutes.Add([string]$na.route); $null = $cohortKinds.Add([string]$na.kind) }
            $leadCase = if (@($item.limitingFoundation).Count -gt 0) { '{0}:{1}' -f $item.limitingFoundation[0].domain, $item.limitingFoundation[0].case } else { '-' }
            Write-Host ('  cohort {0,-27} {1,-26} {2,-38} -> {3}' -f $item.repoName, $item.conclusion, $leadCase, $(if ($null -ne $na) { "$($na.kind) $($na.route)" } else { 'no action' }))
        }
        if ($cohortRoutes.Count -le 1) { $failures.Add("the cohort routes to $($cohortRoutes.Count) route(s) ($($cohortRoutes -join ', ')); it must route to more than one") }
        $snapGenerated = $snapshot.sourceIndexGeneratedAt
        if ($snapGenerated -is [datetime]) { $snapGenerated = $snapGenerated.ToUniversalTime().ToString('o') }
        $notes.Add(('cohort snapshot (index {0}, generated {1}): {2} repositories -> {3} distinct actions over {4} distinct routes' -f ([string]$snapshot.sourceIndexSha256).Substring(0, 12), [string]$snapGenerated, $snapRecords.Count, $cohortKinds.Count, $cohortRoutes.Count))
    }

    # --- The local index, where present ----------------------------------------
    if ($null -ne $live) {
        $routed = @($live.byNextAction.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ' '
        $notes.Add(('local index {0}: {1} repositories routed {2} (a count, not a target)' -f [string]$liveGenerated, @($live.items).Count, $routed))
        foreach ($violation in @($live.contract.violations | Where-Object { $_ -match 'actionsByCase|configured action' })) { $failures.Add("index: $violation") }
    }

    $headline = 'Next-action routing by the kind of gap (3.7 M4c):'
    $okLine = "ok: {0} planning cases each routed to their own runnable action; evaluator and config agree both ways; a data-only reroute took effect; validator red on a wrong action and an unrouted case; the cohort routes to more than one action; AI egress: {1} host route(s) ask first, sends without a matching confirmation {2}, for private scope {3}, when confirmed {4}" -f $caseNames.Count, $egressRoutes.Count, ($egressProbe.unconfirmed.sent + $egressProbe.otherFile.sent + $egressProbe.otherProv.sent), $egressProbe.privateScope.sent, $egressProbe.confirmed.sent
}

# ============================================================================
Write-Host $headline
foreach ($n in $notes) { Write-Host "  $n" }
if ($failures.Count -eq 0) {
    Write-Host "  $okLine" -ForegroundColor Green
    exit 0
}
foreach ($f in $failures) { Write-Host "  FAIL: $f" -ForegroundColor Red }
if ($FailOnError) { exit 1 }
exit 0
