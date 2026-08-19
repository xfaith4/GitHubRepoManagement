<#
.SYNOPSIS
    Release 2.7 Phase C — scheduled roadmap-item packaging.

.DESCRIPTION
    Phase B keeps the curated subset's docs healthy. Phase C is the prize: for
    each favorite / portfolio-candidate repo whose roadmap is contract-ready
    (L3+), select the single highest-value pending item using the settled
    scoring semantics (MAX within a dimension + the effortFit floor, already
    encoded in Portfolio.ValueScorer.ps1), build a review-ready task packet plus
    the repair-PR plan that carries its result back, and queue it for approval.

    Guardrails, each asserted rather than assumed:
      * Archived/ignored repos are never in scope; neither is an uncurated one.
        Scope opts in — an unrecognized curation state is excluded, not admitted.
      * A scheduled run NEVER dispatches. `dispatchedCount` is a hard invariant
        of the run record and Write-PackagingRunRecord refuses to persist a run
        that claims otherwise (the same defense-in-depth Phase B applies to
        `appliedCount`).
      * Every packaged item passes the Release 2.0 quota/budget guard first.
        A repo that is over budget is SKIPPED WITH A NAMED REASON, never
        silently dropped — and when the guard itself cannot be evaluated the
        item is refused, not admitted. A guard you cannot run is not a pass.
      * Dispatch happens only through an explicit operator approval action, and
        only from `pending-approval`. Test-PackagedItemTransition is the single
        definition of what may follow what; the route turns a refusal into a
        409 with a named reason rather than a 200 that reads like success.

    Dispatch target. `gh agent-task` needs an OAuth token the LocalSystem
    service structurally cannot hold (Release 3.0), so approval enqueues to the
    Release 2.8 operator-runner queue — the one dispatch path that works from a
    service today. The runner claims it in the operator's session.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PackagingRunsRelPath  = 'output/automation/packaging-runs.jsonl'
$script:PackagedItemsRelPath  = 'output/automation/packaged-items.jsonl'
$script:PackagingPacketVersion = '1.0'

function _Pack_GetField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return $Default
    }
    if ($null -ne $Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $Name)) { return $Obj.$Name }
    return $Default
}

function _Pack_AsDouble {
    param([object]$Value, [double]$Default = 0.0)
    if ($null -eq $Value) { return $Default }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }
    $number = 0.0
    if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return [double]$number
    }
    return $Default
}

function _Pack_UtcNow {
    return (Get-Date).ToUniversalTime().ToString('o')
}

function _Pack_ToUtc {
    <#
        Parse a timestamp to UTC without double-converting.

        ConvertFrom-Json returns Kind=Unspecified for a round-trip string that
        already holds the UTC instant; calling ToUniversalTime() on that shifts
        it again by the local offset, which puts `lastRunAt` in the future and
        makes overdue detection silently impossible. That bug was found and
        fixed in _Auto_ToUtc — this mirrors the fixed behaviour rather than
        reintroducing it in a second reader.
    #>
    param([object]$Value)

    if ($null -eq $Value) { return $null }

    $dt = [datetime]::MinValue
    if ($Value -is [datetime]) {
        $dt = [datetime]$Value
    }
    else {
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        if (-not [datetime]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$dt)) {
            return $null
        }
    }

    if ($dt.Kind -eq [System.DateTimeKind]::Unspecified) {
        return [datetime]::SpecifyKind($dt, [System.DateTimeKind]::Utc)
    }
    return $dt.ToUniversalTime()
}

function _Pack_NewId {
    param([string]$Prefix = 'pkt')
    return ("{0}-{1}-{2}" -f $Prefix, (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8)))
}

function _Pack_Slug {
    param([string]$Text, [int]$MaxLength = 40)
    $slug = ([string]$Text).ToLowerInvariant()
    $slug = $slug -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ($slug.Length -gt $MaxLength) { $slug = $slug.Substring(0, $MaxLength).Trim('-') }
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'roadmap-item' }
    return $slug
}

# ---------------------------------------------------------------------------
# Scope — who may be packaged, and the named reason when they may not
# ---------------------------------------------------------------------------

function Get-RoadmapPackagingScopeStates {
    # The curated subset automation may act on. `archived-ignore` is never here.
    return @('favorite', 'portfolio-candidate')
}

function Get-RoadmapPackagingReadyMaturityLevels {
    # Dispatch readiness gate, identical to POST /api/roadmap/dispatch/check.
    return @('L3-Contract-Ready', 'L4-Orchestration-Ready')
}

function Select-TopValueRoadmapItem {
    <#
    .SYNOPSIS
        Pure — the highest-value pending item for one assessment/index entry.
    .DESCRIPTION
        Prefers the entry's full ranked list when it carries one, otherwise the
        precomputed `topValueItem`. Both come from Invoke-PortfolioValueScores,
        so the settled aggregation semantics apply either way. Ties break on
        roadmap order (earlier first) — the same rule _SelectTopValueItem uses,
        so a packet and the dashboard never disagree about "the top item".

        An unscored item is deliberately NOT selected: packaging work that never
        went through the scorer would defeat the point of ranking it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Entry)

    $ranked = @(_Pack_GetField -Obj $Entry -Name 'valueRankedItems' -Default @())
    if (@($ranked).Count -gt 0) {
        $sorted = @(@($ranked) | Where-Object { $null -ne $_ } | Sort-Object `
            @{ Expression = { [int](_Pack_GetField -Obj $_ -Name 'valueScore' -Default 0) }; Descending = $true }, `
            @{ Expression = { [int](_Pack_GetField -Obj $_ -Name 'roadmapOrder' -Default 999999) }; Ascending = $true })
        if ($sorted.Count -gt 0) { return $sorted[0] }
    }

    $top = _Pack_GetField -Obj $Entry -Name 'topValueItem' -Default $null
    if ($null -ne $top -and -not [string]::IsNullOrWhiteSpace([string](_Pack_GetField -Obj $top -Name 'text' -Default ''))) {
        return $top
    }

    return $null
}

function Test-RoadmapPackagingCandidate {
    <#
    .SYNOPSIS
        Pure — decide whether one entry may be packaged, and say why not.
    .OUTPUTS
        [pscustomobject] repoId, repoName, selected, reason, item
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter()][hashtable]$CurationMap = @{},
        [Parameter()][string[]]$ScopeStates = @('favorite', 'portfolio-candidate'),
        [Parameter()][string[]]$ReadyMaturityLevels = @('L3-Contract-Ready', 'L4-Orchestration-Ready')
    )

    $repoId = [string](_Pack_GetField -Obj $Entry -Name 'repoId' -Default '')
    $repoName = [string](_Pack_GetField -Obj $Entry -Name 'repoName' -Default ([string](_Pack_GetField -Obj $Entry -Name 'name' -Default '')))
    $repoPath = [string](_Pack_GetField -Obj $Entry -Name 'localPath' -Default ([string](_Pack_GetField -Obj $Entry -Name 'repoPath' -Default '')))
    $roadmapPath = [string](_Pack_GetField -Obj $Entry -Name 'roadmapPath' -Default '')
    $maturityLevel = [string](_Pack_GetField -Obj $Entry -Name 'maturityLevel' -Default 'L0-Absent')

    $curationState = [string](_Pack_GetField -Obj $Entry -Name 'curationState' -Default '')
    if ([string]::IsNullOrWhiteSpace($curationState) -and -not [string]::IsNullOrWhiteSpace($repoId) -and $CurationMap.ContainsKey($repoId)) {
        $curationState = [string](_Pack_GetField -Obj $CurationMap[$repoId] -Name 'curationState' -Default '')
    }

    $decision = [pscustomobject]@{
        repoId             = $repoId
        repoName           = $repoName
        repoPath           = $repoPath
        roadmapPath        = $roadmapPath
        curationState      = $curationState
        maturityLevel      = $maturityLevel
        selected           = $false
        reason             = ''
        item               = $null
    }

    if ([string]::IsNullOrWhiteSpace($repoName)) {
        $decision.reason = 'missing-repo-name'
        return $decision
    }
    if ($curationState -eq 'archived-ignore') {
        $decision.reason = 'archived-ignore'
        return $decision
    }
    if ($curationState -notin $ScopeStates) {
        # Scope opts in. An unrecognized state is excluded, never admitted.
        $decision.reason = 'not-curated'
        return $decision
    }
    if ($maturityLevel -notin $ReadyMaturityLevels) {
        $decision.reason = 'roadmap-not-ready'
        return $decision
    }
    if ([int](_Pack_GetField -Obj $Entry -Name 'pendingItemCount' -Default 0) -le 0) {
        $decision.reason = 'no-pending-work'
        return $decision
    }

    $item = Select-TopValueRoadmapItem -Entry $Entry
    if ($null -eq $item) {
        $decision.reason = 'no-scored-item'
        return $decision
    }
    if ([string]::IsNullOrWhiteSpace($repoPath)) {
        # A packet whose local path is unknown produces a task nothing can run.
        $decision.reason = 'missing-local-path'
        return $decision
    }

    $decision.item = $item
    $decision.selected = $true
    $decision.reason = ("curated={0} maturity={1} topValue={2}" -f $curationState, $maturityLevel, [int](_Pack_GetField -Obj $item -Name 'valueScore' -Default 0))
    return $decision
}

function Resolve-AutomationPackagingScope {
    <#
    .SYNOPSIS
        Pure — one decision per entry, selected or refused with a named reason.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter()][hashtable]$CurationMap = @{},
        [Parameter()][string[]]$ScopeStates = @('favorite', 'portfolio-candidate'),
        [Parameter()][string[]]$ReadyMaturityLevels = @('L3-Contract-Ready', 'L4-Orchestration-Ready')
    )

    $decisions = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        $decisions.Add((Test-RoadmapPackagingCandidate `
            -Entry $entry `
            -CurationMap $CurationMap `
            -ScopeStates $ScopeStates `
            -ReadyMaturityLevels $ReadyMaturityLevels)) | Out-Null
    }
    return $decisions.ToArray()
}

# ---------------------------------------------------------------------------
# Packet + repair-PR plan
# ---------------------------------------------------------------------------

function New-RoadmapItemPrompt {
    <#
    .SYNOPSIS
        Pure — the agent prompt for ONE roadmap item.
    .DESCRIPTION
        Deliberately narrower than Build-ReleaseDispatchPacket's release-wide
        prompt: Phase C ranks and packages a single item, so the prompt has to
        forbid the "while I'm here" sprawl that would make the value score,
        the work-unit estimate, and the review all describe different work.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter()][AllowEmptyString()][string]$GitHubRepo = '',
        [Parameter()][AllowEmptyString()][string]$RepoPath = '',
        [Parameter()][AllowEmptyString()][string]$RoadmapPath = '',
        [Parameter()][AllowEmptyString()][string]$MaturityLevel = '',
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter()][AllowEmptyString()][string]$Branch = '',
        [Parameter()][AllowEmptyString()][string]$BaseBranch = 'main'
    )

    $itemText = [string](_Pack_GetField -Obj $Item -Name 'text' -Default '')
    $section = [string](_Pack_GetField -Obj $Item -Name 'section' -Default '')
    $valueScore = [int](_Pack_GetField -Obj $Item -Name 'valueScore' -Default 0)
    $valueTier = [string](_Pack_GetField -Obj $Item -Name 'valueTier' -Default 'unscored')
    $rationale = @(_Pack_GetField -Obj $Item -Name 'valueRationale' -Default @())

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Roadmap Task: $RepoName") | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Repository context') | Out-Null
    $lines.Add('') | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($GitHubRepo)) { $lines.Add("Repository: $GitHubRepo") | Out-Null }
    else { $lines.Add("Repository: $RepoName") | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($RepoPath)) { $lines.Add("Local path: $RepoPath") | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($RoadmapPath)) { $lines.Add("Roadmap:    $RoadmapPath") | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($MaturityLevel)) { $lines.Add("Maturity:   $MaturityLevel") | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($Branch)) { $lines.Add("Branch:     $Branch (base: $BaseBranch)") | Out-Null }

    $lines.Add('') | Out-Null
    $lines.Add('## The one item to implement') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add("- [ ] $itemText") | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($section)) { $lines.Add("      Roadmap section: $section") | Out-Null }
    $lines.Add(("      Auto-ranked value: {0} ({1})" -f $valueScore, $valueTier)) | Out-Null
    foreach ($r in @($rationale)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$r)) { $lines.Add("      - $r") | Out-Null }
    }

    $lines.Add('') | Out-Null
    $lines.Add('## Execution requirements') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('1. Implement ONLY the item above. It was selected by value rank; widening the') | Out-Null
    $lines.Add('   scope invalidates the ranking, the work-unit estimate, and the review.') | Out-Null
    $lines.Add('2. Run the repository''s own gates and report their real result.') | Out-Null
    $lines.Add('3. Mark the item `[x]` in ROADMAP.md with an evidence note naming the test or') | Out-Null
    $lines.Add('   artifact that proves it — never on the strength of code churn alone.') | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($Branch)) {
        $lines.Add("4. Commit on ``$Branch``. Do not commit to ``$BaseBranch``.") | Out-Null
    }

    $lines.Add('') | Out-Null
    $lines.Add('## Guardrails (out of scope)') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('- Do not touch other roadmap items, releases, or unrelated files.') | Out-Null
    $lines.Add('- Do not merge, and do not force-push.') | Out-Null
    $lines.Add('- The PR opens for review; a human approves the merge.') | Out-Null

    return ($lines -join "`n")
}

function New-RoadmapItemRepairPlan {
    <#
    .SYNOPSIS
        Pure — how this packet's result becomes a PR nobody opens by hand.
    .DESCRIPTION
        The plan names the Phase A write path (`POST /api/roadmap/repair/submit-pr`,
        Roadmap.PrSubmitter.ps1), the branch, the base, and the PR framing. It is
        a PLAN: `submitted` is false and stays false until an operator approves
        and the work actually exists. Nothing here opens a PR.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter()][AllowEmptyString()][string]$RepoSlug = '',
        [Parameter(Mandatory = $true)][string]$Branch,
        [Parameter()][AllowEmptyString()][string]$BaseBranch = 'main',
        [Parameter(Mandatory = $true)][object]$Item
    )

    $itemText = [string](_Pack_GetField -Obj $Item -Name 'text' -Default '')
    $title = $itemText
    if ($title.Length -gt 68) { $title = $title.Substring(0, 68).TrimEnd() + '…' }

    return [pscustomobject]@{
        route            = 'POST /api/roadmap/repair/submit-pr'
        module           = 'backend/modules/roadmap/Roadmap.PrSubmitter.ps1'
        repoName         = $RepoName
        repoSlug         = $RepoSlug
        branch           = $Branch
        baseBranch       = $BaseBranch
        prTitle          = ("roadmap: {0}" -f $title)
        prBody           = ("Auto-packaged top-value roadmap item for ``{0}``.`n`n- [ ] {1}`n`nPackaged by Release 2.7 Phase C scheduled packaging; opened only after an explicit operator approval. No auto-merge." -f $RepoName, $itemText)
        createPr         = $true
        requiresApproval = $true
        submitted        = $false
        note             = 'Plan only. The PR is opened through the Phase A submit-PR path after the packaged work exists and an operator approves it.'
    }
}

function New-RoadmapItemTaskPacket {
    <#
    .SYNOPSIS
        Pure — a review-ready task packet for one auto-ranked roadmap item.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter()][AllowEmptyString()][string]$RepoId = '',
        [Parameter()][AllowEmptyString()][string]$RepoPath = '',
        [Parameter()][AllowEmptyString()][string]$RoadmapPath = '',
        [Parameter()][AllowEmptyString()][string]$GitHubRepo = '',
        [Parameter()][AllowEmptyString()][string]$BaseBranch = 'main',
        [Parameter()][AllowEmptyString()][string]$MaturityLevel = '',
        [Parameter()][AllowEmptyString()][string]$CurationState = '',
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter()][double]$EstimatedWorkUnits = 0,
        [Parameter()][AllowEmptyString()][string]$RunId = '',
        [Parameter()][AllowEmptyString()][string]$PacketId = ''
    )

    if ([string]::IsNullOrWhiteSpace($PacketId)) { $PacketId = _Pack_NewId -Prefix 'pkt' }
    if ([string]::IsNullOrWhiteSpace($BaseBranch)) { $BaseBranch = 'main' }

    $itemText = [string](_Pack_GetField -Obj $Item -Name 'text' -Default '')
    $branch = ("roadmap-item/{0}-{1}" -f (_Pack_Slug -Text $itemText -MaxLength 40), $PacketId.Substring([math]::Max(0, $PacketId.Length - 8)))

    $prompt = New-RoadmapItemPrompt `
        -RepoName $RepoName `
        -GitHubRepo $GitHubRepo `
        -RepoPath $RepoPath `
        -RoadmapPath $RoadmapPath `
        -MaturityLevel $MaturityLevel `
        -Item $Item `
        -Branch $branch `
        -BaseBranch $BaseBranch

    $repairPlan = New-RoadmapItemRepairPlan `
        -RepoName $RepoName `
        -RepoSlug $GitHubRepo `
        -Branch $branch `
        -BaseBranch $BaseBranch `
        -Item $Item

    return [pscustomobject]@{
        packetVersion      = $script:PackagingPacketVersion
        packetId           = $PacketId
        runId              = $RunId
        createdAt          = (_Pack_UtcNow)
        repoId             = $RepoId
        repoName           = $RepoName
        repoPath           = $RepoPath
        roadmapPath        = $RoadmapPath
        githubRepo         = $GitHubRepo
        baseBranch         = $BaseBranch
        branch             = $branch
        curationState      = $CurationState
        maturityLevel      = $MaturityLevel
        itemText           = $itemText
        itemSection        = [string](_Pack_GetField -Obj $Item -Name 'section' -Default '')
        roadmapOrder       = [int](_Pack_GetField -Obj $Item -Name 'roadmapOrder' -Default 0)
        valueScore         = [int](_Pack_GetField -Obj $Item -Name 'valueScore' -Default 0)
        valueTier          = [string](_Pack_GetField -Obj $Item -Name 'valueTier' -Default 'unscored')
        valueRationale     = @(_Pack_GetField -Obj $Item -Name 'valueRationale' -Default @())
        estimatedWorkUnits = [double]$EstimatedWorkUnits
        generatedPrompt    = $prompt
        repairPlan         = $repairPlan
        dispatchTarget     = 'operator-runner'
        dispatched         = $false
    }
}

# ---------------------------------------------------------------------------
# Quota gate
# ---------------------------------------------------------------------------

function Get-PackagingWorkUnitEstimate {
    <#
    .SYNOPSIS
        Pure — the work-unit estimate the quota guard evaluates for one entry.
    .DESCRIPTION
        Prefers the roadmap's own annotated phase estimate when it carries one;
        otherwise the configured per-item default. Zero and negative annotations
        fall back too — an item that claims to cost nothing would sail past a
        guard whose whole job is to price it.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter()][object]$Entry,
        [Parameter()][double]$DefaultWorkUnits = 3.0
    )

    $annotated = _Pack_AsDouble (_Pack_GetField -Obj $Entry -Name 'estimatedSessionWorkUnits' -Default $null) 0.0
    if ($annotated -gt 0) { return [double]$annotated }
    if ($DefaultWorkUnits -gt 0) { return [double]$DefaultWorkUnits }
    return 3.0
}

function Test-PackagingQuota {
    <#
    .SYNOPSIS
        Run the Release 2.0 quota/budget guard for one packaged item.
    .DESCRIPTION
        Delegates to Test-AgentDispatchQuota (BudgetLedger.ps1). When that module
        is not loaded the item is REFUSED with `quota-guard-unavailable` rather
        than admitted: a budget guard that cannot be evaluated is not a pass, and
        an unpriced packet is exactly what the guardrail exists to stop.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter(Mandatory = $true)][double]$EstimatedWorkUnits,
        [Parameter()][object]$Settings = $null,
        [Parameter()][hashtable]$BudgetConfig = $null
    )

    if (-not (Get-Command -Name 'Test-AgentDispatchQuota' -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            allowed            = $false
            blockedCode        = 'quota-guard-unavailable'
            message            = 'The budget/quota guard (BudgetLedger.ps1) is not loaded, so this item cannot be priced. Refusing to package unpriced work.'
            warnings           = @()
            estimatedWorkUnits = [double]$EstimatedWorkUnits
            usage              = $null
        }
    }

    $config = $BudgetConfig
    if ($null -eq $config) {
        $settingsTable = @{}
        if ($Settings -is [hashtable]) { $settingsTable = $Settings }
        elseif ($null -ne $Settings) {
            foreach ($p in @($Settings.PSObject.Properties)) { $settingsTable[$p.Name] = $p.Value }
        }
        $config = Get-AgentBudgetLedgerConfig -WorkspaceRoot $WorkspaceRoot -Settings $settingsTable
    }

    $result = Test-AgentDispatchQuota `
        -WorkspaceRoot $WorkspaceRoot `
        -RepoName $RepoName `
        -EstimatedWorkUnits $EstimatedWorkUnits `
        -BudgetConfig $config

    return [pscustomobject]@{
        allowed            = [bool]$result.allowed
        blockedCode        = $result.blockedCode
        message            = [string]$result.message
        warnings           = @($result.warnings)
        estimatedWorkUnits = [double]$EstimatedWorkUnits
        usage              = $result.usage
    }
}

# ---------------------------------------------------------------------------
# The scheduled run
# ---------------------------------------------------------------------------

function Invoke-ScheduledRoadmapPackaging {
    <#
    .SYNOPSIS
        Rank, price, and package the top-value item per in-scope repo. Never
        dispatches — packets land in the approval queue and stop there.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][AllowEmptyCollection()][object[]]$Entries = @(),
        [Parameter()][hashtable]$CurationMap = @{},
        [Parameter()][object]$Settings = $null,
        [Parameter()][hashtable]$BudgetConfig = $null,
        [Parameter()][double]$DefaultWorkUnits = 3.0,
        [Parameter()][AllowEmptyString()][string]$RunId = '',
        [Parameter()][string]$TriggeredBy = 'scheduler',
        [Parameter()][switch]$SkipQueueWrite
    )

    if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = _Pack_NewId -Prefix 'pkgrun' }
    $startedAt = _Pack_UtcNow

    $packets = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[object]]::new()

    $decisions = @(Resolve-AutomationPackagingScope -Entries $Entries -CurationMap $CurationMap)
    $candidates = @($decisions | Where-Object { $_.selected })

    foreach ($decision in @($decisions | Where-Object { -not $_.selected })) {
        $skipped.Add([pscustomobject]@{
            repoName = $decision.repoName
            stage    = 'scope'
            reason   = $decision.reason
            message  = ''
        }) | Out-Null
    }

    foreach ($decision in $candidates) {
        $repoName = [string]$decision.repoName
        try {
            $entry = @($Entries) | Where-Object {
                [string](_Pack_GetField -Obj $_ -Name 'repoName' -Default '') -eq $repoName
            } | Select-Object -First 1

            $estimate = Get-PackagingWorkUnitEstimate -Entry $entry -DefaultWorkUnits $DefaultWorkUnits
            $quota = Test-PackagingQuota `
                -WorkspaceRoot $WorkspaceRoot `
                -RepoName $repoName `
                -EstimatedWorkUnits $estimate `
                -Settings $Settings `
                -BudgetConfig $BudgetConfig

            if (-not $quota.allowed) {
                # Over budget: skipped and LOGGED with the guard's own code.
                $skipped.Add([pscustomobject]@{
                    repoName           = $repoName
                    stage              = 'quota'
                    reason             = [string]$quota.blockedCode
                    message            = [string]$quota.message
                    estimatedWorkUnits = [double]$estimate
                }) | Out-Null
                continue
            }

            $packet = New-RoadmapItemTaskPacket `
                -RepoName $repoName `
                -RepoId ([string]$decision.repoId) `
                -RepoPath ([string]$decision.repoPath) `
                -RoadmapPath ([string]$decision.roadmapPath) `
                -GitHubRepo ([string](_Pack_GetField -Obj $entry -Name 'githubFullName' -Default '')) `
                -BaseBranch ([string](_Pack_GetField -Obj $entry -Name 'defaultBranch' -Default 'main')) `
                -MaturityLevel ([string]$decision.maturityLevel) `
                -CurationState ([string]$decision.curationState) `
                -Item $decision.item `
                -EstimatedWorkUnits $estimate `
                -RunId $RunId

            if (-not $SkipQueueWrite) {
                $null = Write-PackagedItemRecord -WorkspaceRoot $WorkspaceRoot -Record ([pscustomobject]@{
                    schemaVersion = '1'
                    packetId      = $packet.packetId
                    runId         = $RunId
                    repoName      = $repoName
                    status        = 'pending-approval'
                    recordedAt    = (_Pack_UtcNow)
                    actor         = $TriggeredBy
                    note          = 'Auto-packaged top-value roadmap item awaiting operator approval.'
                    packet        = $packet
                })
            }

            $packets.Add($packet) | Out-Null
        } catch {
            $errors.Add([pscustomobject]@{ repoName = $repoName; error = $_.Exception.Message }) | Out-Null
        }
    }

    return [pscustomobject]@{
        runId          = $RunId
        kind           = 'roadmap-packaging'
        triggeredBy    = $TriggeredBy
        startedAt      = $startedAt
        finishedAt     = (_Pack_UtcNow)
        candidateCount = @($candidates).Count
        targetCount    = @($decisions).Count
        packagedCount  = $packets.Count
        proposalCount  = $packets.Count   # alias so shared outcome/health logic reads it
        skippedCount   = $skipped.Count
        dispatchedCount = 0   # INVARIANT — a scheduled run never dispatches
        appliedCount   = 0    # INVARIANT — a scheduled run never mutates a repo
        packets        = $packets.ToArray()
        skipped        = $skipped.ToArray()
        errors         = $errors.ToArray()
    }
}

function New-PackagingDigestPayload {
    <#
    .SYNOPSIS
        Webhook-ready digest: what was packaged, what was skipped and why.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Run)

    $packets = @(_Pack_GetField -Obj $Run -Name 'packets' -Default @())
    $skipped = @(_Pack_GetField -Obj $Run -Name 'skipped' -Default @())

    # Release 3.3 milestone 4 -- decision-grade framing over the RUN's window.
    if (-not (Get-Command New-DecisionGradeEnvelope -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot '..\common\DecisionGrade.ps1')
    }
    $packEnvelope = New-DecisionGradeEnvelope -Units 'roadmap packets' `
        -Headline $(if (@($packets).Count -eq 0) { "Nothing packaged; $(@($skipped).Count) candidates were skipped with a named reason." } else { "$(@($packets).Count) packets await approval; $(@($skipped).Count) candidates skipped." }) `
        -NextAction $(if (@($packets).Count -eq 0) { 'Review the skip reasons below; each names what would make that repository packageable.' } else { 'Approve a packet (POST /api/automation/packages/approve) to dispatch it to the operator runner.' }) `
        -WindowFrom ([string](_Pack_GetField -Obj $Run -Name 'startedAt' -Default '')) `
        -WindowTo ([string](_Pack_GetField -Obj $Run -Name 'finishedAt' -Default ''))
    # No coverage on this digest, deliberately: `candidateCount` counts repos
    # that passed curation, while `skipped` also holds repos refused BEFORE
    # candidacy, so neither is a denominator for the other. The constructor
    # caught the mismatch (9 assessed of 2) rather than letting a wrong ratio
    # ship -- which is the whole point of it refusing impossible metrics.

    return [pscustomobject]@{
        runId           = [string](_Pack_GetField -Obj $Run -Name 'runId' -Default '')
        kind            = 'roadmap-packaging'
        generatedAt     = (_Pack_UtcNow)
        dataWindow      = $packEnvelope.dataWindow
        units           = $packEnvelope.units
        headline        = $packEnvelope.headline
        nextAction      = $packEnvelope.nextAction
        coverage        = $packEnvelope.coverage
        packagedCount   = @($packets).Count
        skippedCount    = @($skipped).Count
        dispatchedCount = 0
        note            = 'Packaged for review only. Approve a packet (POST /api/automation/packages/approve) to dispatch it to the operator runner; nothing was dispatched or merged automatically.'
        packets         = @($packets | ForEach-Object {
            [pscustomobject]@{
                packetId           = [string](_Pack_GetField -Obj $_ -Name 'packetId' -Default '')
                repoName           = [string](_Pack_GetField -Obj $_ -Name 'repoName' -Default '')
                itemText           = [string](_Pack_GetField -Obj $_ -Name 'itemText' -Default '')
                valueScore         = [int](_Pack_GetField -Obj $_ -Name 'valueScore' -Default 0)
                valueTier          = [string](_Pack_GetField -Obj $_ -Name 'valueTier' -Default '')
                estimatedWorkUnits = [double](_Pack_GetField -Obj $_ -Name 'estimatedWorkUnits' -Default 0)
                branch             = [string](_Pack_GetField -Obj $_ -Name 'branch' -Default '')
            }
        })
        skipped         = @($skipped | ForEach-Object {
            [pscustomobject]@{
                repoName = [string](_Pack_GetField -Obj $_ -Name 'repoName' -Default '')
                stage    = [string](_Pack_GetField -Obj $_ -Name 'stage' -Default '')
                reason   = [string](_Pack_GetField -Obj $_ -Name 'reason' -Default '')
            }
        })
    }
}

# ---------------------------------------------------------------------------
# Append-only run history
# ---------------------------------------------------------------------------

function Get-PackagingRunsFilePath {
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    return (Join-Path $WorkspaceRoot ($script:PackagingRunsRelPath -replace '/', [System.IO.Path]::DirectorySeparatorChar))
}

function _Pack_AppendJsonl {
    param([string]$Path, [object]$Record)
    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    Add-Content -LiteralPath $Path -Value ($Record | ConvertTo-Json -Depth 12 -Compress) -Encoding UTF8
    return $Path
}

function _Pack_ReadJsonl {
    param([string]$Path)
    $records = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $records.ToArray() }
    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $records.Add((ConvertFrom-Json -InputObject $line)) | Out-Null } catch { }
    }
    return $records.ToArray()
}

function Write-PackagingRunRecord {
    <#
    .SYNOPSIS
        Append a packaging run to its append-only history.
    .DESCRIPTION
        Defense in depth for the two invariants a scheduled run must hold:
        it applies nothing and it dispatches nothing. A run claiming otherwise
        is refused rather than recorded — the history is the audit trail, so it
        must never carry a claim the design forbids.

        Packaging runs get their OWN file rather than sharing Phase B's. Phase D's
        overdue alerting reads the newest doc-refinement run to decide whether the
        doc scheduler is still alive; interleaving a differently-scheduled kind
        into that file would let a live packaging cron mask a dead doc cron.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][object]$Run
    )

    if ([int](_Pack_GetField -Obj $Run -Name 'appliedCount' -Default 0) -ne 0) {
        throw 'Packaging run reports appliedCount != 0; preview-first invariant violated — refusing to record.'
    }
    if ([int](_Pack_GetField -Obj $Run -Name 'dispatchedCount' -Default 0) -ne 0) {
        throw 'Packaging run reports dispatchedCount != 0; a scheduled run must stop at the approval gate — refusing to record.'
    }

    return (_Pack_AppendJsonl -Path (Get-PackagingRunsFilePath -WorkspaceRoot $WorkspaceRoot) -Record $Run)
}

function Get-PackagingRunHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][int]$Limit = 50
    )

    $ordered = @(_Pack_ReadJsonl -Path (Get-PackagingRunsFilePath -WorkspaceRoot $WorkspaceRoot))
    if ($ordered.Count -eq 0) { return @() }
    [array]::Reverse($ordered)   # newest first
    if ($Limit -gt 0 -and $ordered.Count -gt $Limit) { $ordered = @($ordered[0..($Limit - 1)]) }
    return $ordered
}

# ---------------------------------------------------------------------------
# The approval queue and its state machine
# ---------------------------------------------------------------------------

function Get-PackagingRunOutcome {
    <#
    .SYNOPSIS
        Classify one packaging run as ok / partial / failed.
    .DESCRIPTION
        Deliberately mirrors Get-AutomationRunOutcome's contract so the two
        schedulers cannot disagree about what "degraded" means: errors with no
        output is `failed`, errors alongside output is `partial`, and a run that
        packaged nothing because nothing was ready is `ok` — a clean portfolio
        must not alert every night.

        A skip is NOT an error. Over-budget and not-curated are the guard doing
        its job, and Phase C records them as named skips precisely so they read
        as decisions rather than failures.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][object]$Run)

    $errorCount = @(_Pack_GetField -Obj $Run -Name 'errors' -Default @()).Count
    $packagedCount = [int](_Pack_GetField -Obj $Run -Name 'packagedCount' -Default 0)

    if ($errorCount -eq 0) { return 'ok' }
    if ($packagedCount -gt 0) { return 'partial' }
    return 'failed'
}

function Get-PackagingHealth {
    <#
    .SYNOPSIS
        Reports whether the packaging scheduler is actually running.
    .DESCRIPTION
        Closes the Phase C non-blocker. `Get-AutomationHealth` reads the
        doc-refinement history alone — on purpose, because interleaving kinds
        would let a live packaging cron mask a dead doc cron — which left a
        packaging cron that stops completely invisible: the config still reads
        enabled, packaging-runs.jsonl simply stops growing, and no surface in
        the product changes.

        The fix is a SECOND reader over the second file, not a merged file. Each
        scheduler is then judged only by its own evidence, in both directions.

        Interval resolution falls back deliberately: a deployment that runs one
        cron hitting both routes configures `automation.intervalMinutes` only,
        and must not be reported as "never ran" for want of a second setting.
        `automation.packaging.intervalMinutes` overrides it when the two crons
        genuinely run at different cadences.
    .PARAMETER Settings
        Host settings; the `automation` / `automation.packaging` blocks supply
        enabled + intervalMinutes.
    .PARAMETER GraceFactor
        How many intervals may elapse before a missed run is called overdue.
        Two by default, matching Get-AutomationHealth: one skipped tick is
        tolerated, two is an alert.
    .PARAMETER Now
        Injectable clock for deterministic tests.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][object]$Settings = $null,
        [Parameter()][double]$GraceFactor = 2.0,
        [Parameter()][datetime]$Now = [datetime]::UtcNow
    )

    $auto = _Pack_GetField -Obj $Settings -Name 'automation' -Default $null
    $packagingConfig = _Pack_GetField -Obj $auto -Name 'packaging' -Default $null

    # `enabled` opts in the same way packaging scope does: an absent packaging
    # block inherits the parent automation switch rather than defaulting on.
    $enabled = [bool](_Pack_GetField -Obj $auto -Name 'enabled' -Default $false)
    $packagingEnabled = _Pack_GetField -Obj $packagingConfig -Name 'enabled' -Default $null
    if ($null -ne $packagingEnabled) { $enabled = [bool]$packagingEnabled }

    $intervalMinutes = [int](_Pack_AsDouble -Value (_Pack_GetField -Obj $auto -Name 'intervalMinutes' -Default 0))
    $packagingInterval = [int](_Pack_AsDouble -Value (_Pack_GetField -Obj $packagingConfig -Name 'intervalMinutes' -Default 0))
    if ($packagingInterval -gt 0) { $intervalMinutes = $packagingInterval }

    $history = @(Get-PackagingRunHistory -WorkspaceRoot $WorkspaceRoot -Limit 50)
    $lastRun = if ($history.Count -gt 0) { $history[0] } else { $null }

    $lastRunAt = $null
    $lastRunId = ''
    $lastOutcome = 'never'
    $lastErrorCount = 0
    $lastPackagedCount = 0
    $lastSkippedCount = 0
    if ($null -ne $lastRun) {
        $lastRunId = [string](_Pack_GetField -Obj $lastRun -Name 'runId' -Default '')
        $lastOutcome = Get-PackagingRunOutcome -Run $lastRun
        $lastErrorCount = @(_Pack_GetField -Obj $lastRun -Name 'errors' -Default @()).Count
        $lastPackagedCount = [int](_Pack_GetField -Obj $lastRun -Name 'packagedCount' -Default 0)
        $lastSkippedCount = [int](_Pack_GetField -Obj $lastRun -Name 'skippedCount' -Default 0)
        $lastRunAt = _Pack_ToUtc -Value (_Pack_GetField -Obj $lastRun -Name 'finishedAt' -Default $null)
    }
    $nowUtc = _Pack_ToUtc -Value $Now
    if ($null -eq $nowUtc) { $nowUtc = [datetime]::UtcNow }

    $consecutiveFailures = 0
    foreach ($record in $history) {
        if ((Get-PackagingRunOutcome -Run $record) -eq 'failed') { $consecutiveFailures++ } else { break }
    }

    $minutesSinceLastRun = $null
    if ($null -ne $lastRunAt) { $minutesSinceLastRun = [math]::Round(($nowUtc - $lastRunAt).TotalMinutes, 1) }

    $expectedNextRunAt = $null
    $overdue = $false
    if ($enabled -and $intervalMinutes -gt 0) {
        if ($null -eq $lastRunAt) {
            $overdue = $true
        }
        else {
            $expectedNextRunAt = $lastRunAt.AddMinutes($intervalMinutes)
            $overdue = ($nowUtc -gt $lastRunAt.AddMinutes($intervalMinutes * $GraceFactor))
        }
    }

    # Codes are packaging-specific so an alert names which scheduler stopped.
    # `automation-overdue` on both would be indistinguishable in a webhook.
    $alert = $null
    if ($enabled -and $intervalMinutes -gt 0 -and $null -eq $lastRunAt) {
        $alert = [pscustomobject]@{
            severity = 'warning'
            code     = 'packaging-never-ran'
            message  = ("Roadmap-item packaging is enabled on a {0}-minute interval but no packaging run has ever been recorded. Confirm the cron hitting POST /api/automation/package-run exists." -f $intervalMinutes)
        }
    }
    elseif ($overdue) {
        $alert = [pscustomobject]@{
            severity = 'error'
            code     = 'packaging-overdue'
            message  = ("No roadmap-item packaging run in {0} minutes; the configured interval is {1} minutes. The packaging trigger has probably stopped." -f $minutesSinceLastRun, $intervalMinutes)
        }
    }
    elseif ($consecutiveFailures -gt 0) {
        $alert = [pscustomobject]@{
            severity = 'error'
            code     = 'packaging-run-failed'
            message  = ("The last {0} packaging run(s) packaged nothing and only errored." -f $consecutiveFailures)
        }
    }
    elseif ($lastOutcome -eq 'partial') {
        $alert = [pscustomobject]@{
            severity = 'warning'
            code     = 'packaging-run-partial'
            message  = ("The last packaging run completed with {0} error(s)." -f $lastErrorCount)
        }
    }

    return [pscustomobject]@{
        kind                = 'roadmap-packaging'
        enabled             = $enabled
        intervalMinutes     = $intervalMinutes
        runCount            = $history.Count
        lastRunId           = $lastRunId
        lastRunAt           = if ($null -ne $lastRunAt) { $lastRunAt.ToString('o') } else { $null }
        lastOutcome         = $lastOutcome
        lastErrorCount      = $lastErrorCount
        lastPackagedCount   = $lastPackagedCount
        lastSkippedCount    = $lastSkippedCount
        minutesSinceLastRun = $minutesSinceLastRun
        expectedNextRunAt   = if ($null -ne $expectedNextRunAt) { $expectedNextRunAt.ToString('o') } else { $null }
        graceFactor         = $GraceFactor
        overdue             = $overdue
        consecutiveFailures = $consecutiveFailures
        healthy             = ($null -eq $alert)
        alert               = $alert
        evaluatedAt         = $nowUtc.ToString('o')
    }
}

function Get-PackagedItemsFilePath {
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    return (Join-Path $WorkspaceRoot ($script:PackagedItemsRelPath -replace '/', [System.IO.Path]::DirectorySeparatorChar))
}

function Write-PackagedItemRecord {
    <#
    .SYNOPSIS
        Append one status record for a packet. The file is append-only: a
        transition is a NEW line, never an edit of the line before it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][object]$Record
    )

    if ([string]::IsNullOrWhiteSpace([string](_Pack_GetField -Obj $Record -Name 'packetId' -Default ''))) {
        throw 'Packaged-item record is missing packetId; refusing to append an unattributable record.'
    }
    if ([string]::IsNullOrWhiteSpace([string](_Pack_GetField -Obj $Record -Name 'status' -Default ''))) {
        throw 'Packaged-item record is missing status; refusing to append an unattributable record.'
    }

    return (_Pack_AppendJsonl -Path (Get-PackagedItemsFilePath -WorkspaceRoot $WorkspaceRoot) -Record $Record)
}

function Get-PackagedItemQueue {
    <#
    .SYNOPSIS
        Fold the append-only records into the current state of each packet.
    .DESCRIPTION
        Last record wins for status; the packet body is kept from whichever
        record carried it (the first one). Every transition is preserved in
        `history`, so "who approved this and when" survives the fold.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][AllowEmptyString()][string]$Status = '',
        [Parameter()][int]$Limit = 100
    )

    $records = @(_Pack_ReadJsonl -Path (Get-PackagedItemsFilePath -WorkspaceRoot $WorkspaceRoot))
    $byPacket = [ordered]@{}

    foreach ($record in $records) {
        $packetId = [string](_Pack_GetField -Obj $record -Name 'packetId' -Default '')
        if ([string]::IsNullOrWhiteSpace($packetId)) { continue }

        $status_ = [string](_Pack_GetField -Obj $record -Name 'status' -Default '')
        $at = [string](_Pack_GetField -Obj $record -Name 'recordedAt' -Default '')
        $actor = [string](_Pack_GetField -Obj $record -Name 'actor' -Default '')
        $note = [string](_Pack_GetField -Obj $record -Name 'note' -Default '')
        $packet = _Pack_GetField -Obj $record -Name 'packet' -Default $null

        if (-not $byPacket.Contains($packetId)) {
            $byPacket[$packetId] = [pscustomobject]@{
                packetId     = $packetId
                runId        = [string](_Pack_GetField -Obj $record -Name 'runId' -Default '')
                repoName     = [string](_Pack_GetField -Obj $record -Name 'repoName' -Default '')
                status       = $status_
                packagedAt   = $at
                updatedAt    = $at
                updatedBy    = $actor
                note         = $note
                dispatchRunId = [string](_Pack_GetField -Obj $record -Name 'dispatchRunId' -Default '')
                packet       = $packet
                history      = @()
            }
        }

        $current = $byPacket[$packetId]
        $current.status = $status_
        $current.updatedAt = $at
        $current.updatedBy = $actor
        $current.note = $note
        if ($null -eq $current.packet -and $null -ne $packet) { $current.packet = $packet }
        $dispatchRunId = [string](_Pack_GetField -Obj $record -Name 'dispatchRunId' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($dispatchRunId)) { $current.dispatchRunId = $dispatchRunId }
        if ([string]::IsNullOrWhiteSpace([string]$current.repoName)) {
            $current.repoName = [string](_Pack_GetField -Obj $record -Name 'repoName' -Default '')
        }
        $current.history = @(@($current.history) + @([pscustomobject]@{
            status = $status_
            at     = $at
            actor  = $actor
            note   = $note
        }))
    }

    $items = @($byPacket.Values)
    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $items = @($items | Where-Object { [string]$_.status -eq $Status })
    }

    $ordered = @($items)
    [array]::Reverse($ordered)   # newest packet first
    if ($Limit -gt 0 -and $ordered.Count -gt $Limit) { $ordered = @($ordered[0..($Limit - 1)]) }
    return $ordered
}

function Get-PackagedItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$PacketId
    )

    return (@(Get-PackagedItemQueue -WorkspaceRoot $WorkspaceRoot -Limit 0) |
        Where-Object { [string]$_.packetId -eq $PacketId } | Select-Object -First 1)
}

function Test-PackagedItemTransition {
    <#
    .SYNOPSIS
        Pure — the single definition of which status may follow which.
    .DESCRIPTION
        The failure this exists to stop is a packet being dispatched twice, or
        dispatched without ever being approved. Callers turn a refusal into a
        409 with the named reason; nothing may reach the queue writer by
        deciding for itself that a transition looks reasonable.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string]$From = '',
        [Parameter(Mandatory = $true)][string]$To
    )

    $allowed = @{
        'pending-approval' = @('approved', 'rejected', 'pending-approval')
        'approved'         = @('dispatched', 'dispatch-failed')
        'dispatch-failed'  = @('approved', 'rejected')
        'dispatched'       = @()
        'rejected'         = @()
    }

    if ([string]::IsNullOrWhiteSpace($From)) {
        return [pscustomobject]@{
            allowed = $false
            reason  = 'packet-not-found'
            message = 'No packaged item with that id exists in the approval queue.'
        }
    }
    if (-not $allowed.ContainsKey($From)) {
        return [pscustomobject]@{
            allowed = $false
            reason  = 'unknown-state'
            message = ("Packet is in unrecognized state '{0}'; refusing to transition it." -f $From)
        }
    }
    if ($To -notin $allowed[$From]) {
        return [pscustomobject]@{
            allowed = $false
            reason  = ("invalid-transition:{0}->{1}" -f $From, $To)
            message = ("A packet in state '{0}' cannot move to '{1}'. Allowed: {2}." -f $From, $To, (@($allowed[$From]) -join ', '))
        }
    }

    return [pscustomobject]@{ allowed = $true; reason = ''; message = '' }
}

# ---------------------------------------------------------------------------
# Dispatch on approval — enqueue for the Release 2.8 operator runner
# ---------------------------------------------------------------------------

function New-PackagedItemDispatchRunId {
    # Same shape Initialize-HistoryStore mints, so the existing run history,
    # the runner's claim check, and the ROADMAP modal all recognize it.
    return ("{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8)))
}

function New-PackagedItemQueueEntry {
    <#
    .SYNOPSIS
        Pure — the roadmap-task-queue entry for an approved packet.
    .DESCRIPTION
        Mirrors New-RoadmapQueueEntry (Automation.RoadmapQueue.ps1); the
        module smoke asserts the two key sets stay identical, so a change to the
        queue contract fails a gate instead of producing entries the runner
        silently ignores.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][object]$Packet,
        [Parameter()][AllowEmptyString()][string]$QueuedAt = ''
    )

    if ([string]::IsNullOrWhiteSpace($QueuedAt)) { $QueuedAt = (Get-Date).ToString('o') }
    $branch = [string](_Pack_GetField -Obj $Packet -Name 'branch' -Default '')
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch = "roadmap/$RunId" }

    return [ordered]@{
        schemaVersion  = '1'
        runId          = $RunId
        status         = 'queued'
        repository     = [string](_Pack_GetField -Obj $Packet -Name 'repoName' -Default '')
        localRepoPath  = [string](_Pack_GetField -Obj $Packet -Name 'repoPath' -Default '')
        roadmapPath    = [string](_Pack_GetField -Obj $Packet -Name 'roadmapPath' -Default '')
        selectedTask   = [string](_Pack_GetField -Obj $Packet -Name 'itemText' -Default '')
        branch         = $branch
        prompt         = [string](_Pack_GetField -Obj $Packet -Name 'generatedPrompt' -Default '')
        # Release 3.0. A packaged item is always a LOCAL Claude Code task: the
        # packet's prompt names a working branch and a repo path, and its
        # repair-PR plan hands the result to the Phase A submit-PR route. Sending
        # that to a cloud agent would dispatch work with no local checkout to do
        # it in. Cloud dispatch reaches the queue only from the wizard.
        dispatchTarget = 'claude'
        baseBranch     = [string](_Pack_GetField -Obj $Packet -Name 'baseBranch' -Default '')
        queuedAt       = $QueuedAt
    }
}

function New-PackagedItemRunSummary {
    <#
    .SYNOPSIS
        Pure — the run summary the operator runner claims on.
    .DESCRIPTION
        Invoke-RoadmapTaskRunner claims a queue entry only when its run summary
        reads status='queued'. A queue line without this file is a task nothing
        ever picks up, so both are written together.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][object]$Packet,
        [Parameter()][AllowEmptyString()][string]$Actor = ''
    )

    $now = (Get-Date).ToString('o')
    return [ordered]@{
        runId         = $RunId
        status        = 'queued'
        startedAt     = $now
        completedAt   = $now
        repository    = [string](_Pack_GetField -Obj $Packet -Name 'repoName' -Default '')
        roadmapPath   = [string](_Pack_GetField -Obj $Packet -Name 'roadmapPath' -Default '')
        selectedTask  = [string](_Pack_GetField -Obj $Packet -Name 'itemText' -Default '')
        localRepoPath = [string](_Pack_GetField -Obj $Packet -Name 'repoPath' -Default '')
        branch        = [string](_Pack_GetField -Obj $Packet -Name 'branch' -Default '')
        source        = 'automation-packaging'
        packetId      = [string](_Pack_GetField -Obj $Packet -Name 'packetId' -Default '')
        approvedBy    = $Actor
    }
}

function Submit-PackagedItemToRunner {
    <#
    .SYNOPSIS
        Write the queue entry + run summary for an APPROVED packet.
    .DESCRIPTION
        This is the only function in the module that makes work runnable, and it
        takes an already-approved packet — it never decides approval for itself.

        Release 3.1 — because it is the only such function, it is also where the
        runner-presence gate belongs. The dispatch route got that gate first, but
        this is the *other* road to the same queue file, and it had none: the
        approve button was gated in the browser only, which is the same defect
        the release exists to fix moved one layer down. Gating the writer rather
        than its caller means a future second caller is covered by construction.
    .OUTPUTS
        On success, an object carrying runId/branch/queuePath/summaryPath.
        On refusal, an object with `refused = $true` and the named category —
        NOT an exception. A refusal is a state the caller should report, not a
        failure it should log as one; throwing here made the route record a
        `dispatch-failed` packet for work that was never attempted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][object]$Packet,
        [Parameter()][AllowEmptyString()][string]$Actor = '',
        [Parameter()][AllowEmptyString()][string]$RunId = '',
        # The operator saying "queue it anyway, I am about to start a runner".
        # Mirrors acknowledgeNoRunner on POST /api/roadmap/dispatch/execute.
        [Parameter()][switch]$AcknowledgeNoRunner
    )

    # A missing presence function is a wiring defect, not a runtime state, and
    # must not be read as "no evidence of absence, so proceed". A guard that
    # passes whenever it cannot run is worse than no guard: it moves the failure
    # away from its cause and looks like protection in a code review.
    if (-not (Get-Command -Name 'Get-RunnerPresence' -ErrorAction SilentlyContinue)) {
        throw 'Submit-PackagedItemToRunner cannot evaluate runner presence: Get-RunnerPresence is not loaded. Dot-source Automation.RunnerPresence.ps1 before making work runnable.'
    }

    $presence = Get-RunnerPresence -WorkspaceRoot $WorkspaceRoot
    if (-not $presence.present -and -not $AcknowledgeNoRunner) {
        $backlog = Get-QueuedTaskBacklog -WorkspaceRoot $WorkspaceRoot
        return [pscustomobject]@{
            refused       = $true
            category      = 'runner-absent'
            message       = ("No operator runner can claim this packet, so approving it into the queue would strand it. {0} Start one with: pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1" -f [string]$presence.message)
            runner        = $presence
            strandedCount = [int]$backlog.queuedTotal
            overrideField = 'acknowledgeNoRunner'
            queuedNothing = $true
        }
    }

    if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = New-PackagedItemDispatchRunId }

    $entry = New-PackagedItemQueueEntry -RunId $RunId -Packet $Packet
    $queuePath = Join-Path $WorkspaceRoot 'output\roadmap-task-queue.jsonl'
    $null = _Pack_AppendJsonl -Path $queuePath -Record ([pscustomobject]$entry)

    $summary = New-PackagedItemRunSummary -RunId $RunId -Packet $Packet -Actor $Actor
    $runsDir = Join-Path $WorkspaceRoot 'output\roadmap-task-history\runs'
    if (-not (Test-Path -LiteralPath $runsDir)) { $null = New-Item -ItemType Directory -Path $runsDir -Force }
    $summaryPath = Join-Path $runsDir ("{0}.summary.json" -f $RunId)
    ($summary | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    return [pscustomobject]@{
        # Uniform with the refusal shape above, so a caller can branch on one
        # property under StrictMode instead of testing for its existence.
        refused     = $false
        runId       = $RunId
        branch      = [string]$entry.branch
        queuePath   = $queuePath
        summaryPath = $summaryPath
    }
}
