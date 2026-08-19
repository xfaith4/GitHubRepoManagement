<#
.SYNOPSIS
    Release 2.7 Phase B — scheduled documentation-refinement automation.

.DESCRIPTION
    Preview-first, curated-subset automation. It selects favorite /
    portfolio-candidate repositories with weak README/ROADMAP, generates
    doc-improve PREVIEWS (it never applies them), records an append-only run
    history, and builds a digest payload for operator approval.

    Guardrails (Release 2.7 out-of-scope contract):
      * Archived/ignored repos are never in scope.
      * No function here mutates a repo, applies a doc change, or merges.
      * Every run reports appliedCount = 0; Write-AutomationRunRecord refuses to
        persist a run that claims otherwise (defense in depth).

    Requires Invoke-AiDocImprovePreview (AiDocImprovement.ps1) to be available
    in the session for the preview step.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AutomationRunsRelPath = 'output/automation/automation-runs.jsonl'

function _Auto_GetField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return $Default
    }
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $Default
}

function Get-AutomationScopeStates {
    # The curated subset automation is allowed to act on (never archived-ignore).
    return @('favorite', 'portfolio-candidate')
}

function Test-AutomationDocWeakness {
    <#
    .SYNOPSIS
        Returns the weak doc types ('readme' and/or 'roadmap') for an assessment
        entry, or an empty array when its docs are healthy enough to skip.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter()][int]$ReadmeMinScore = 60,
        [Parameter()][int]$RoadmapMinScore = 60
    )

    $weak = [System.Collections.Generic.List[string]]::new()

    $readmeScore = [int](_Auto_GetField -Obj $Entry -Name 'readmeScore' -Default 0)
    $dispatch = [string](_Auto_GetField -Obj $Entry -Name 'dispatchReadiness' -Default '')
    if ($readmeScore -lt $ReadmeMinScore -or $dispatch -in @('missing-readme', 'needs-doc-standardization')) {
        $weak.Add('readme') | Out-Null
    }

    $roadmapState = [string](_Auto_GetField -Obj $Entry -Name 'roadmapState' -Default '')
    $roadmapScore = [int](_Auto_GetField -Obj $Entry -Name 'roadmapScore' -Default 0)
    if ($roadmapState -in @('missing', 'parse-error') -or $roadmapScore -lt $RoadmapMinScore) {
        $weak.Add('roadmap') | Out-Null
    }

    return @($weak | Select-Object -Unique)
}

function Select-AutomationDocTargets {
    <#
    .SYNOPSIS
        Pure scope selector — from assessment entries, pick favorite/candidate
        repos with weak docs. Archived/ignored and non-curated repos are dropped.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter()][hashtable]$CurationMap = @{},
        [Parameter()][string[]]$ScopeStates = @('favorite', 'portfolio-candidate'),
        [Parameter()][int]$ReadmeMinScore = 60,
        [Parameter()][int]$RoadmapMinScore = 60
    )

    $targets = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }

        $repoId = [string](_Auto_GetField -Obj $entry -Name 'repoId' -Default '')
        $curationState = [string](_Auto_GetField -Obj $entry -Name 'curationState' -Default '')
        if ([string]::IsNullOrWhiteSpace($curationState) -and -not [string]::IsNullOrWhiteSpace($repoId) -and $CurationMap.ContainsKey($repoId)) {
            $curationState = [string]$CurationMap[$repoId].curationState
        }

        if ($curationState -eq 'archived-ignore') { continue }   # never touched
        if ($curationState -notin $ScopeStates) { continue }      # curated subset only

        $weakTypes = Test-AutomationDocWeakness -Entry $entry -ReadmeMinScore $ReadmeMinScore -RoadmapMinScore $RoadmapMinScore
        foreach ($docType in $weakTypes) {
            $targets.Add([pscustomobject]@{
                repoId        = $repoId
                repoName      = [string](_Auto_GetField -Obj $entry -Name 'repoName' -Default ([string](_Auto_GetField -Obj $entry -Name 'name' -Default '')))
                repoPath      = [string](_Auto_GetField -Obj $entry -Name 'repoPath' -Default ([string](_Auto_GetField -Obj $entry -Name 'localPath' -Default '')))
                curationState = $curationState
                docType       = $docType
                reason        = "curated=$curationState weak-$docType"
            }) | Out-Null
        }
    }

    return $targets.ToArray()
}

function _Auto_ReadDoc {
    param([string]$RepoPath, [string]$DocType)
    if ([string]::IsNullOrWhiteSpace($RepoPath)) { return '' }
    $fileName = if ($DocType -eq 'roadmap') { 'ROADMAP.md' } else { 'README.md' }
    $path = Join-Path $RepoPath $fileName
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8) } catch { return '' }
    }
    return ''
}

function Invoke-ScheduledDocRefinement {
    <#
    .SYNOPSIS
        Generate doc-improve PREVIEWS for each target. Never applies anything.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][AllowEmptyCollection()][object[]]$Targets = @(),
        [Parameter()][object]$Settings = $null,
        [Parameter()][string]$Provider = 'heuristic',
        [Parameter()][string]$RunId = '',
        [Parameter()][string]$TriggeredBy = 'scheduler'
    )

    if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = [guid]::NewGuid().ToString('n') }
    $startedAt = (Get-Date).ToUniversalTime().ToString('o')
    $proposals = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[object]]::new()

    foreach ($t in @($Targets)) {
        if ($null -eq $t) { continue }
        $repoName = [string](_Auto_GetField -Obj $t -Name 'repoName' -Default '')
        $docType = [string](_Auto_GetField -Obj $t -Name 'docType' -Default 'readme')
        $repoPath = [string](_Auto_GetField -Obj $t -Name 'repoPath' -Default '')
        if ([string]::IsNullOrWhiteSpace($repoName)) { continue }

        try {
            $current = _Auto_ReadDoc -RepoPath $repoPath -DocType $docType
            # PREVIEW ONLY — this is the whole point of Phase B. No apply call exists here.
            $preview = Invoke-AiDocImprovePreview `
                -WorkspaceRoot $WorkspaceRoot `
                -RepoName $repoName `
                -DocType $docType `
                -CurrentContent $current `
                -Provider $Provider `
                -Settings $Settings

            $estimated = _Auto_GetField -Obj $preview -Name 'estimatedScore' -Default $null
            $usage = _Auto_GetField -Obj $preview -Name 'usage' -Default $null
            $proposals.Add([pscustomobject]@{
                repoName    = $repoName
                docType     = $docType
                previewId   = [string](_Auto_GetField -Obj $preview -Name 'previewId' -Default '')
                providerId  = [string](_Auto_GetField -Obj $preview -Name 'providerId' -Default '')
                scoreDelta  = [int](_Auto_GetField -Obj $estimated -Name 'delta' -Default 0)
                changeCount = @(_Auto_GetField -Obj $preview -Name 'changeSummary' -Default @()).Count
                reason      = [string](_Auto_GetField -Obj $t -Name 'reason' -Default '')
                # Null means unmeasured, never zero — usageSource says which kind.
                tokenUsage  = _Auto_GetField -Obj $usage -Name 'totalTokens' -Default $null
                apiSpendUsd = _Auto_GetField -Obj $usage -Name 'costUsd' -Default $null
                usageSource = [string](_Auto_GetField -Obj $usage -Name 'source' -Default 'absent')
                applied     = $false
            }) | Out-Null
        } catch {
            $errors.Add([pscustomobject]@{ repoName = $repoName; docType = $docType; error = $_.Exception.Message }) | Out-Null
        }
    }

    $proposalArray = $proposals.ToArray()

    # Run-level roll-up. A sum over a mix of measured and unmeasured proposals
    # would read as a total while silently omitting the unmeasured ones, so the
    # counts travel with the sum and the sum is null when nothing was measured.
    $measured = @($proposalArray | Where-Object { $null -ne $_.tokenUsage })
    $priced = @($proposalArray | Where-Object { $null -ne $_.apiSpendUsd })
    $usageSummary = [pscustomobject]@{
        measuredProposals   = $measured.Count
        unmeasuredProposals = ($proposalArray.Count - $measured.Count)
        totalTokens         = if ($measured.Count -gt 0) { [int](($measured | Measure-Object -Property tokenUsage -Sum).Sum) } else { $null }
        pricedProposals     = $priced.Count
        totalCostUsd        = if ($priced.Count -gt 0) { [Math]::Round([double](($priced | Measure-Object -Property apiSpendUsd -Sum).Sum), 6) } else { $null }
    }

    return [pscustomobject]@{
        runId         = $RunId
        kind          = 'doc-refinement'
        triggeredBy   = $TriggeredBy
        startedAt     = $startedAt
        finishedAt    = (Get-Date).ToUniversalTime().ToString('o')
        targetCount   = @($Targets).Count
        proposalCount = $proposals.Count
        appliedCount  = 0   # INVARIANT — preview-first; nothing is ever applied here
        provider      = $Provider
        usage         = $usageSummary
        proposals     = $proposalArray
        errors        = $errors.ToArray()
    }
}

function Get-AutomationRunsFilePath {
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    return (Join-Path $WorkspaceRoot ($script:AutomationRunsRelPath -replace '/', [System.IO.Path]::DirectorySeparatorChar))
}

function Write-AutomationRunRecord {
    <#
    .SYNOPSIS
        Append a run to the append-only automation run history (JSONL).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][object]$Run
    )

    # Defense in depth for the preview-first guardrail: refuse to record a run
    # that claims to have applied anything.
    if ([int](_Auto_GetField -Obj $Run -Name 'appliedCount' -Default 0) -ne 0) {
        throw 'Automation run reports appliedCount != 0; preview-first invariant violated — refusing to record.'
    }

    $path = Get-AutomationRunsFilePath -WorkspaceRoot $WorkspaceRoot
    $dir = Split-Path -Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $line = ($Run | ConvertTo-Json -Depth 8 -Compress)
    Add-Content -LiteralPath $path -Value $line -Encoding UTF8
    return $path
}

function Get-AutomationRunHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][int]$Limit = 50
    )

    $path = Get-AutomationRunsFilePath -WorkspaceRoot $WorkspaceRoot
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($l in @(Get-Content -LiteralPath $path -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        try { $records.Add((ConvertFrom-Json -InputObject $l)) | Out-Null } catch { }
    }

    $ordered = @($records.ToArray())
    [array]::Reverse($ordered)   # newest first
    if ($Limit -gt 0 -and $ordered.Count -gt $Limit) { $ordered = @($ordered[0..($Limit - 1)]) }
    return $ordered
}

function _Auto_ToUtc {
    <#
    .SYNOPSIS
        Normalizes a run-record timestamp to UTC exactly once.
    .DESCRIPTION
        Run records are written with `(Get-Date).ToUniversalTime().ToString('o')`,
        but ConvertFrom-Json hands the value back as a [datetime] with
        Kind=Unspecified that already holds the UTC instant. Calling
        ToUniversalTime() on that shifts it again by the local offset — which
        put `lastRunAt` in the future and made overdue detection silently
        impossible. A kind-less value is therefore treated as already-UTC.
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

function Get-AutomationRunOutcome {
    <#
    .SYNOPSIS
        Classifies one recorded run as ok / partial / failed.
    .DESCRIPTION
        Release 2.7 Phase D. A run that produced no proposals and only errors is
        `failed`; one that produced some of each is `partial`. A run with zero
        targets is `ok` — "no favorite repo needed doc work" is a healthy
        outcome, not a failure, and treating it as one would alert every night
        on a clean portfolio.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][object]$Run)

    $errorCount = @(_Auto_GetField -Obj $Run -Name 'errors' -Default @()).Count
    $proposalCount = [int](_Auto_GetField -Obj $Run -Name 'proposalCount' -Default 0)

    if ($errorCount -eq 0) { return 'ok' }
    if ($proposalCount -gt 0) { return 'partial' }
    return 'failed'
}

function Get-AutomationHealth {
    <#
    .SYNOPSIS
        Reports whether scheduled automation is actually running, not merely
        configured.
    .DESCRIPTION
        Release 2.7 Phase D. The failure mode this closes is silence: interval
        firing is delegated to an external cron hitting POST /api/automation/run,
        so if that cron stops, nothing in the product changes — the config still
        reads "enabled" and the history simply stops growing. This derives an
        alert from the gap between the configured interval and the newest run
        record, so a scheduler that stopped is visible instead of absent.
    .PARAMETER Settings
        Host settings; the `automation` block supplies enabled/intervalMinutes.
    .PARAMETER GraceFactor
        How many intervals may elapse before a missed run is called overdue.
        Two by default, so one skipped tick is tolerated and two is an alert.
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

    $auto = _Auto_GetField -Obj $Settings -Name 'automation' -Default $null
    $enabled = [bool](_Auto_GetField -Obj $auto -Name 'enabled' -Default $false)
    $intervalMinutes = [int](_Auto_GetField -Obj $auto -Name 'intervalMinutes' -Default 0)

    $history = @(Get-AutomationRunHistory -WorkspaceRoot $WorkspaceRoot -Limit 50)
    $lastRun = if ($history.Count -gt 0) { $history[0] } else { $null }

    $lastRunAt = $null
    $lastRunId = ''
    $lastOutcome = 'never'
    $lastErrorCount = 0
    if ($null -ne $lastRun) {
        $lastRunId = [string](_Auto_GetField -Obj $lastRun -Name 'runId' -Default '')
        $lastOutcome = Get-AutomationRunOutcome -Run $lastRun
        $lastErrorCount = @(_Auto_GetField -Obj $lastRun -Name 'errors' -Default @()).Count
        $lastRunAt = _Auto_ToUtc -Value (_Auto_GetField -Obj $lastRun -Name 'finishedAt' -Default $null)
    }
    $nowUtc = _Auto_ToUtc -Value $Now

    # Consecutive failures from newest backwards. `partial` does not reset the
    # streak (it is still degraded) but does not extend it either.
    $consecutiveFailures = 0
    foreach ($record in $history) {
        if ((Get-AutomationRunOutcome -Run $record) -eq 'failed') { $consecutiveFailures++ } else { break }
    }

    $minutesSinceLastRun = $null
    if ($null -ne $lastRunAt) {
        $minutesSinceLastRun = [math]::Round(($nowUtc - $lastRunAt).TotalMinutes, 1)
    }

    $expectedNextRunAt = $null
    $overdue = $false
    if ($enabled -and $intervalMinutes -gt 0) {
        if ($null -eq $lastRunAt) {
            # Enabled with an interval but no run has ever been recorded.
            $overdue = $true
        }
        else {
            $expectedNextRunAt = $lastRunAt.AddMinutes($intervalMinutes)
            $deadline = $lastRunAt.AddMinutes($intervalMinutes * $GraceFactor)
            $overdue = ($nowUtc -gt $deadline)
        }
    }

    $alert = $null
    if ($enabled -and $intervalMinutes -gt 0 -and $null -eq $lastRunAt) {
        $alert = [pscustomobject]@{
            severity = 'warning'
            code     = 'automation-never-ran'
            message  = ("Automation is enabled on a {0}-minute interval but no run has ever been recorded. Confirm the cron hitting POST /api/automation/run exists." -f $intervalMinutes)
        }
    }
    elseif ($overdue) {
        $alert = [pscustomobject]@{
            severity = 'error'
            code     = 'automation-overdue'
            message  = ("No automation run in {0} minutes; the configured interval is {1} minutes. The scheduled trigger has probably stopped." -f $minutesSinceLastRun, $intervalMinutes)
        }
    }
    elseif ($consecutiveFailures -gt 0) {
        $alert = [pscustomobject]@{
            severity = 'error'
            code     = 'automation-run-failed'
            message  = ("The last {0} automation run(s) produced no proposals and only errors." -f $consecutiveFailures)
        }
    }
    elseif ($lastOutcome -eq 'partial') {
        $alert = [pscustomobject]@{
            severity = 'warning'
            code     = 'automation-run-partial'
            message  = ("The last automation run completed with {0} error(s)." -f $lastErrorCount)
        }
    }

    return [pscustomobject]@{
        enabled             = $enabled
        intervalMinutes     = $intervalMinutes
        runCount            = $history.Count
        lastRunId           = $lastRunId
        lastRunAt           = if ($null -ne $lastRunAt) { $lastRunAt.ToString('o') } else { $null }
        lastOutcome         = $lastOutcome
        lastErrorCount      = $lastErrorCount
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

function New-AutomationDigestPayload {
    <#
    .SYNOPSIS
        Build a webhook-ready digest of a run's proposals for operator approval.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Run)

    $proposals = @(_Auto_GetField -Obj $Run -Name 'proposals' -Default @())

    # Release 3.3 milestone 4 -- decision-grade framing. The window is the
    # RUN's, not the digest's: a reader needs to know when the work happened,
    # not when someone asked about it.
    if (-not (Get-Command New-DecisionGradeEnvelope -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot '..\common\DecisionGrade.ps1')
    }
    $runStarted = [string](_Auto_GetField -Obj $Run -Name 'startedAt' -Default '')
    $runFinished = [string](_Auto_GetField -Obj $Run -Name 'finishedAt' -Default '')
    $docEnvelope = New-DecisionGradeEnvelope -Units 'documentation proposals' `
        -Headline $(if (@($proposals).Count -eq 0) { 'No documentation proposals in this run.' } else { "$(@($proposals).Count) documentation proposals await approval; none were applied." }) `
        -NextAction $(if (@($proposals).Count -eq 0) { 'Nothing to review from this run.' } else { 'Open the AI Docs panel and approve or reject each proposal; nothing changes until you do.' }) `
        -WindowFrom $runStarted -WindowTo $runFinished

    return [pscustomobject]@{
        runId         = [string](_Auto_GetField -Obj $Run -Name 'runId' -Default '')
        kind          = [string](_Auto_GetField -Obj $Run -Name 'kind' -Default 'doc-refinement')
        generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
        dataWindow    = $docEnvelope.dataWindow
        units         = $docEnvelope.units
        headline      = $docEnvelope.headline
        nextAction    = $docEnvelope.nextAction
        coverage      = $docEnvelope.coverage
        proposalCount = @($proposals).Count
        appliedCount  = 0
        note          = 'Preview-only. Approve each proposal from the AI Docs panel to apply; nothing was changed automatically.'
        proposals     = @($proposals | ForEach-Object {
            [pscustomobject]@{
                repoName    = [string](_Auto_GetField -Obj $_ -Name 'repoName' -Default '')
                docType     = [string](_Auto_GetField -Obj $_ -Name 'docType' -Default '')
                previewId   = [string](_Auto_GetField -Obj $_ -Name 'previewId' -Default '')
                scoreDelta  = [int](_Auto_GetField -Obj $_ -Name 'scoreDelta' -Default 0)
                changeCount = [int](_Auto_GetField -Obj $_ -Name 'changeCount' -Default 0)
            }
        })
    }
}
