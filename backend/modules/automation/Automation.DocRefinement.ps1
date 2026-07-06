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
            $proposals.Add([pscustomobject]@{
                repoName    = $repoName
                docType     = $docType
                previewId   = [string](_Auto_GetField -Obj $preview -Name 'previewId' -Default '')
                providerId  = [string](_Auto_GetField -Obj $preview -Name 'providerId' -Default '')
                scoreDelta  = [int](_Auto_GetField -Obj $estimated -Name 'delta' -Default 0)
                changeCount = @(_Auto_GetField -Obj $preview -Name 'changeSummary' -Default @()).Count
                reason      = [string](_Auto_GetField -Obj $t -Name 'reason' -Default '')
                applied     = $false
            }) | Out-Null
        } catch {
            $errors.Add([pscustomobject]@{ repoName = $repoName; docType = $docType; error = $_.Exception.Message }) | Out-Null
        }
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
        proposals     = $proposals.ToArray()
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

function New-AutomationDigestPayload {
    <#
    .SYNOPSIS
        Build a webhook-ready digest of a run's proposals for operator approval.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Run)

    $proposals = @(_Auto_GetField -Obj $Run -Name 'proposals' -Default @())
    return [pscustomobject]@{
        runId         = [string](_Auto_GetField -Obj $Run -Name 'runId' -Default '')
        kind          = [string](_Auto_GetField -Obj $Run -Name 'kind' -Default 'doc-refinement')
        generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
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
