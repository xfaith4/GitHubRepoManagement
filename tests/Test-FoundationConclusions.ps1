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

      action-routing         (3.7 M4c - not implemented yet; exits 1)

.EXAMPLE
    pwsh ./tests/Test-FoundationConclusions.ps1 -Cohort evidence/trials/release-3.7/cohort.json -Assert lifecycle-consistency -FailOnError
.EXAMPLE
    pwsh ./tests/Test-FoundationConclusions.ps1 -Cohort evidence/trials/release-3.7/cohort.json -Assert applicability -FailOnError
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

if ($Assert -eq 'action-routing') {
    Write-Host "  FAIL: -Assert $Assert is not implemented yet (3.7 M4c); nothing is proved" -ForegroundColor Red
    exit 1
}

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
Write-Host $headline
foreach ($n in $notes) { Write-Host "  $n" }
if ($failures.Count -eq 0) {
    Write-Host "  $okLine" -ForegroundColor Green
    exit 0
}
foreach ($f in $failures) { Write-Host "  FAIL: $f" -ForegroundColor Red }
if ($FailOnError) { exit 1 }
exit 0
