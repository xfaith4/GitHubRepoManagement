<#
.SYNOPSIS
    Roadmap repair planner and preview generator.
.DESCRIPTION
    Provides two exported functions:

      Invoke-PlanRoadmapRepair
        Maps a normalized, audited RoadmapContract (from Invoke-AuditRoadmapContract)
        to a list of concrete repair actions. Returns a repair plan with a
        previewState of 'repair-preview-ready', 'repair-blocked', or
        'rewrite-not-recommended'.

      Invoke-GenerateRepairPreview
        Applies the repair plan to generate a proposed normalized roadmap markdown
        string using the canonical ROADMAP_TEMPLATE.md structure.
        Preserves all checked items (-[x]) and restructures pending work into
        release-scoped sections with acceptance criteria and out-of-scope boundaries.

.NOTES
    Dot-source this file after Roadmap.Parser.ps1 and Roadmap.Auditor.ps1:
        . (Join-Path $moduleRoot 'Roadmap.Parser.ps1')
        . (Join-Path $moduleRoot 'Roadmap.Auditor.ps1')
        . (Join-Path $moduleRoot 'Roadmap.Repairer.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Invoke-PlanRoadmapRepair
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Map a normalized, audited roadmap contract to a list of concrete repair actions.
.PARAMETER Contract
    Output of Invoke-AuditRoadmapContract. Must have maturityLevel and auditFindings.
.OUTPUTS
    [pscustomobject] with:
      previewState   string  'repair-preview-ready' | 'repair-blocked' | 'rewrite-not-recommended'
      blockReason    string or $null
      actions        array of { actionId, description, affectsSection, severity }
      canAddHistory  bool
      targetLevel    string  desired maturity level after repair
#>
function Invoke-PlanRoadmapRepair {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Contract
    )

    $actions = [System.Collections.Generic.List[pscustomobject]]::new()

    # Cannot repair what isn't there
    if ($Contract.roadmapState -eq 'missing') {
        return [pscustomobject]@{
            previewState = 'repair-blocked'
            blockReason  = 'No roadmap file found. Create a ROADMAP.md first using the canonical template.'
            actions      = @()
            canAddHistory = $false
            targetLevel  = 'L2-Structured'
        }
    }

    # Cannot repair a file that cannot be parsed
    if ($Contract.roadmapState -eq 'parse-error') {
        return [pscustomobject]@{
            previewState = 'repair-blocked'
            blockReason  = "Roadmap cannot be parsed. Parse error: $($Contract.parseError)"
            actions      = @()
            canAddHistory = $false
            targetLevel  = 'L2-Structured'
        }
    }

    # Rewrite not recommended for already-complete roadmaps (no pending work)
    if ($Contract.roadmapState -eq 'complete') {
        return [pscustomobject]@{
            previewState = 'rewrite-not-recommended'
            blockReason  = 'Roadmap is marked complete with no pending items. Repair is not recommended unless adding a new release.'
            actions      = @()
            canAddHistory = $true
            targetLevel  = $Contract.maturityLevel
        }
    }

    # Already at L3 or L4 — minor augmentation only
    if ($Contract.maturityLevel -in @('L3-Contract-Ready', 'L4-Orchestration-Ready')) {
        return [pscustomobject]@{
            previewState = 'rewrite-not-recommended'
            blockReason  = "Roadmap is already at $($Contract.maturityLevel). Only minor augmentation may be needed."
            actions      = @()
            canAddHistory = $true
            targetLevel  = $Contract.maturityLevel
        }
    }

    # Map audit findings to repair actions
    $findings = if ($null -ne $Contract.auditFindings) { @($Contract.auditFindings) } else { @() }

    foreach ($finding in $findings) {
        $ruleId = [string]$finding.ruleId
        switch ($ruleId) {
            'ROADMAP-004' {
                $actions.Add([pscustomobject]@{
                    actionId       = 'ADD-PRODUCT-INTENT'
                    description    = 'Add a Product Intent section at the top describing what the product does, who it serves, and what problem it solves.'
                    affectsSection = 'Header'
                    severity       = [string]$finding.severity
                })
            }
            'ROADMAP-005' {
                $actions.Add([pscustomobject]@{
                    actionId       = 'ADD-RELEASE-SECTIONS'
                    description    = 'Reorganize pending checklist items into bounded release sections (## Release X.Y — Title) with goal statements.'
                    affectsSection = 'Release Roadmap'
                    severity       = [string]$finding.severity
                })
            }
            'ROADMAP-006' {
                $actions.Add([pscustomobject]@{
                    actionId       = 'ADD-ACCEPTANCE-CRITERIA'
                    description    = 'Add Acceptance Criteria subsections to each release section.'
                    affectsSection = 'Release Sections'
                    severity       = [string]$finding.severity
                })
            }
            'ROADMAP-007' {
                $actions.Add([pscustomobject]@{
                    actionId       = 'ADD-OUT-OF-SCOPE'
                    description    = 'Add Out of Scope subsections to each release section to set explicit boundaries.'
                    affectsSection = 'Release Sections'
                    severity       = [string]$finding.severity
                })
            }
            'ROADMAP-008' {
                $actions.Add([pscustomobject]@{
                    actionId       = 'EXPAND-PENDING-ITEMS'
                    description    = 'Add more concrete, testable pending checklist items (currently fewer than 3).'
                    affectsSection = 'Engineering Milestones'
                    severity       = [string]$finding.severity
                })
            }
            'ROADMAP-009' {
                $actions.Add([pscustomobject]@{
                    actionId       = 'ADD-RELEASE-SECTIONS'
                    description    = 'Add at least two release sections to establish a forward-looking roadmap structure.'
                    affectsSection = 'Release Roadmap'
                    severity       = [string]$finding.severity
                })
            }
            'ROADMAP-010' {
                $actions.Add([pscustomobject]@{
                    actionId       = 'REWRITE-VAGUE-ITEMS'
                    description    = "Rewrite $($Contract.vagueItemCount) vague checklist item(s) into concrete, testable, implementation-specific steps."
                    affectsSection = 'Checklist Items'
                    severity       = [string]$finding.severity
                })
            }
        }
    }

    # Deduplicate actions by actionId
    $seen = @{}
    $deduplicated = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($a in $actions) {
        if (-not $seen.ContainsKey($a.actionId)) {
            $seen[$a.actionId] = $true
            $deduplicated.Add($a)
        }
    }

    if ($deduplicated.Count -eq 0) {
        return [pscustomobject]@{
            previewState = 'rewrite-not-recommended'
            blockReason  = 'No repair actions identified for current audit findings.'
            actions      = @()
            canAddHistory = $true
            targetLevel  = $Contract.maturityLevel
        }
    }

    return [pscustomobject]@{
        previewState = 'repair-preview-ready'
        blockReason  = $null
        actions      = @($deduplicated)
        canAddHistory = $true
        targetLevel  = 'L3-Contract-Ready'
    }
}

# ---------------------------------------------------------------------------
# Internal helpers for repair generation
# ---------------------------------------------------------------------------

function _EscapeMarkdown {
    param([string]$Text)
    # No escaping needed — just return as-is for markdown generation
    return $Text
}

function _BuildProductIntentSection {
    param([string]$RepoName)
    return @"
## 1. Product Intent

$RepoName provides tools and workflows to manage repositories. Describe what the product does,
who it serves, and what problem it solves. Replace this placeholder with accurate product context.

---
"@
}

function _BuildPrinciplesSection {
    return @"
## 2. Product Principles

- **Roadmap-first workflow** — roadmap files are a primary source of truth for next work.
- **Explainable automation** — every audit, readiness score, and dispatch decision should be inspectable.
- **Human review before irreversible action** — preview changes before applying them.

---
"@
}

function _BuildCompletedSection {
    param([array]$Sections)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('## 3. Recently Completed')
    $lines.Add('')
    $addedAny = $false
    foreach ($sec in $Sections) {
        foreach ($item in @($sec.completedItems)) {
            $lines.Add("- [x] $item")
            $addedAny = $true
        }
    }
    if (-not $addedAny) {
        $lines.Add('- [x] (No completed items recorded yet)')
    }
    $lines.Add('')
    $lines.Add('---')
    return $lines -join "`n"
}

function _BuildReleaseSection {
    param(
        [string]$ReleaseId,
        [string]$ReleaseTitle,
        [array]$PendingItems,
        [bool]$AddAcceptanceCriteria,
        [bool]$AddOutOfScope
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("## $ReleaseId — $ReleaseTitle")
    $lines.Add('')
    $lines.Add('**Goal:** Implement the next set of concrete, testable improvements for this repository.')
    $lines.Add('')
    $lines.Add('### Product outcomes')
    $lines.Add('')
    $lines.Add('- Operators can exercise the implemented functionality end-to-end.')
    $lines.Add('')
    $lines.Add('### Engineering milestones')
    $lines.Add('')
    foreach ($item in $PendingItems) {
        $lines.Add("- [ ] $item")
    }
    $lines.Add('')
    if ($AddAcceptanceCriteria) {
        $lines.Add('### Acceptance criteria')
        $lines.Add('')
        $lines.Add('- All engineering milestones in this release are implemented and verifiable.')
        $lines.Add('- No placeholder stubs or TODO comments remain in modified code.')
        $lines.Add('')
    }
    if ($AddOutOfScope) {
        $lines.Add('### Out of scope')
        $lines.Add('')
        $lines.Add('- Work items not listed in the Engineering milestones above.')
        $lines.Add('- Unreviewed automatic mutations of repository files.')
        $lines.Add('')
    }
    $lines.Add('---')
    return $lines -join "`n"
}

# ---------------------------------------------------------------------------
# Invoke-GenerateRepairPreview
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Generate a proposed normalized roadmap markdown preview from an existing roadmap contract.
.PARAMETER Contract
    Output of Invoke-AuditRoadmapContract.
.PARAMETER RepairPlan
    Output of Invoke-PlanRoadmapRepair.
.PARAMETER RawContent
    The raw markdown text of the current roadmap file (used to preserve original content).
.PARAMETER RepoName
    Short repository name used in generated sections.
.OUTPUTS
    [pscustomobject] with:
      previewId          string   stable preview identifier
      previewState       string   from the repair plan
      blockReason        string or $null
      currentContent     string   the original roadmap content
      proposedContent    string   the proposed normalized roadmap content (or $null if blocked)
      repairActions      array    the list of repair actions applied
      completedItemCount int      number of preserved completed items
      pendingItemCount   int      number of pending items restructured
      generatedAt        string   ISO 8601 timestamp
#>
function Invoke-GenerateRepairPreview {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Contract,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$RepairPlan,

        [Parameter()]
        [AllowEmptyString()]
        [string]$RawContent = '',

        [Parameter(Mandatory = $true)]
        [string]$RepoName
    )

    $generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    $previewId   = "{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))

    if ($RepairPlan.previewState -ne 'repair-preview-ready') {
        return [pscustomobject]@{
            previewId          = $previewId
            previewState       = $RepairPlan.previewState
            blockReason        = $RepairPlan.blockReason
            currentContent     = $RawContent
            proposedContent    = $null
            repairActions      = @($RepairPlan.actions)
            completedItemCount = [int]$Contract.completedCount
            pendingItemCount   = [int]$Contract.pendingCount
            generatedAt        = $generatedAt
        }
    }

    $actionIds = @($RepairPlan.actions | ForEach-Object { [string]$_.actionId })

    # Collect all sections from the parsed contract
    $sections = @($Contract.sections)

    # Gather all pending items in document order
    $allPendingItems = [System.Collections.Generic.List[string]]::new()
    foreach ($sec in $sections) {
        foreach ($item in @($sec.pendingItems)) {
            $allPendingItems.Add([string]$item)
        }
    }

    # Build the proposed markdown
    $output = [System.Collections.Generic.List[string]]::new()

    # -----------------------------------------------------------------------
    # Title
    # -----------------------------------------------------------------------
    $output.Add("# $RepoName — Product & Engineering Roadmap")
    $output.Add('')
    $output.Add('> Status: Active')
    $output.Add('>')
    $output.Add('> Product direction: Describe the product direction and goals here.')
    $output.Add('')

    # -----------------------------------------------------------------------
    # Section 1: Product Intent
    # -----------------------------------------------------------------------
    if ('ADD-PRODUCT-INTENT' -in $actionIds -or (-not $Contract.hasProductIntent)) {
        $output.Add('## 1. Product Intent')
        $output.Add('')
        $output.Add("$RepoName provides tooling and workflows for managing repositories.")
        $output.Add('Replace this section with accurate product context describing what the product does,')
        $output.Add('who it serves, and what problem it solves.')
        $output.Add('')
        $output.Add('---')
        $output.Add('')
    } elseif (-not [string]::IsNullOrWhiteSpace($RawContent)) {
        # Preserve existing product intent block (up to first ---)
        $intentMatch = [regex]::Match($RawContent, '(?is)(^#{1,3}\s*(?:product\s+intent|overview|about|purpose).+?)(\n---|\z)')
        if ($intentMatch.Success) {
            $output.Add($intentMatch.Groups[1].Value.Trim())
            $output.Add('')
            $output.Add('---')
            $output.Add('')
        }
    }

    # -----------------------------------------------------------------------
    # Section 2: Recently Completed
    # -----------------------------------------------------------------------
    $output.Add('## 2. Recently Completed')
    $output.Add('')
    $completedCount = 0
    foreach ($sec in $sections) {
        foreach ($item in @($sec.completedItems)) {
            $output.Add("- [x] $item")
            $completedCount++
        }
    }
    if ($completedCount -eq 0) {
        $output.Add('- [x] (No completed items recorded yet)')
    }
    $output.Add('')
    $output.Add('---')
    $output.Add('')

    # -----------------------------------------------------------------------
    # Section 3: Release Roadmap
    # -----------------------------------------------------------------------
    $output.Add('## 3. Release Roadmap')
    $output.Add('')
    $output.Add('---')
    $output.Add('')

    $needsReleaseSections = 'ADD-RELEASE-SECTIONS' -in $actionIds
    $addAcceptance        = 'ADD-ACCEPTANCE-CRITERIA' -in $actionIds -or (-not $Contract.hasAcceptanceCriteria)
    $addOutOfScope        = 'ADD-OUT-OF-SCOPE' -in $actionIds -or (-not $Contract.hasOutOfScope)

    if ($needsReleaseSections -or (-not $Contract.hasReleaseSections) -or $addAcceptance -or $addOutOfScope) {
        # Group pending items into release sections
        # If existing sections already look like releases, keep their names;
        # otherwise bucket everything into a single next release.
        $releaseSections = @($sections | Where-Object { $_.name -imatch 'release\s+\d' })
        $nonReleaseSections = @($sections | Where-Object { $_.name -notmatch 'release\s+\d' })

        # Collect pending from non-release sections to fold into a release
        $ungroupedPending = [System.Collections.Generic.List[string]]::new()
        foreach ($sec in $nonReleaseSections) {
            foreach ($item in @($sec.pendingItems)) {
                $ungroupedPending.Add([string]$item)
            }
        }

        # Emit existing release sections (preserving their items, adding missing subsections)
        $releaseIdx = 1
        foreach ($sec in $releaseSections) {
            $sectionContent = _BuildReleaseSection `
                -ReleaseId      "## Release $releaseIdx.0" `
                -ReleaseTitle   $sec.name `
                -PendingItems   @($sec.pendingItems) `
                -AddAcceptanceCriteria $addAcceptance `
                -AddOutOfScope  $addOutOfScope
            # Remove the leading ## since we already added Section header line
            $sectionContent = $sectionContent -replace '^## ', ''
            $output.Add("## $($sectionContent.TrimStart())")
            $output.Add('')
            $releaseIdx++
        }

        # Create a new release for ungrouped pending items
        if ($ungroupedPending.Count -gt 0) {
            $releaseLabel = "Release $releaseIdx.0"
            $output.Add("## $releaseLabel — Next Release")
            $output.Add('')
            $output.Add('**Goal:** Implement the next set of concrete, testable improvements.')
            $output.Add('')
            $output.Add('### Product outcomes')
            $output.Add('')
            $output.Add('- Operators can exercise the implemented functionality end-to-end.')
            $output.Add('')
            $output.Add('### Engineering milestones')
            $output.Add('')
            foreach ($item in $ungroupedPending) {
                $output.Add("- [ ] $item")
            }
            $output.Add('')
            if ($addAcceptance) {
                $output.Add('### Acceptance criteria')
                $output.Add('')
                $output.Add('- All engineering milestones in this release are implemented and verifiable.')
                $output.Add('- No placeholder stubs or TODO comments remain in modified code.')
                $output.Add('')
            }
            if ($addOutOfScope) {
                $output.Add('### Out of scope')
                $output.Add('')
                $output.Add('- Work items not listed in the Engineering milestones above.')
                $output.Add('')
            }
            $output.Add('---')
            $output.Add('')
        } elseif ($releaseSections.Count -eq 0 -and $allPendingItems.Count -gt 0) {
            # No release sections and no ungrouped items found but there are pending items
            $output.Add("## Release 1.0 — First Release")
            $output.Add('')
            $output.Add('**Goal:** Deliver the first set of concrete, testable milestones.')
            $output.Add('')
            $output.Add('### Engineering milestones')
            $output.Add('')
            foreach ($item in $allPendingItems) {
                $output.Add("- [ ] $item")
            }
            $output.Add('')
            if ($addAcceptance) {
                $output.Add('### Acceptance criteria')
                $output.Add('')
                $output.Add('- All engineering milestones in this release are implemented and verifiable.')
                $output.Add('')
            }
            if ($addOutOfScope) {
                $output.Add('### Out of scope')
                $output.Add('')
                $output.Add('- Work items not listed above.')
                $output.Add('')
            }
            $output.Add('---')
            $output.Add('')
        }
    } else {
        # Structure is mostly OK — preserve existing release section text from RawContent
        if (-not [string]::IsNullOrWhiteSpace($RawContent)) {
            $releaseBlock = [regex]::Match($RawContent, '(?is)(^#{1,3}\s+release\s+.+)')
            if ($releaseBlock.Success) {
                $output.Add($releaseBlock.Value.Trim())
                $output.Add('')
            }
        }
    }

    # -----------------------------------------------------------------------
    # Footer sections
    # -----------------------------------------------------------------------
    $output.Add('## 4. Definition of Done')
    $output.Add('')
    $output.Add('A release should not be marked complete unless:')
    $output.Add('')
    $output.Add('- All checklist items for that release are truly implemented or explicitly blocked.')
    $output.Add('- UI elements are connected to real behavior rather than placeholders.')
    $output.Add('- Affected docs are updated where workflow or product behavior changed.')
    $output.Add('- Logging and error handling are sufficient to diagnose failures.')
    $output.Add('')

    $proposedContent = $output -join "`n"

    return [pscustomobject]@{
        previewId          = $previewId
        previewState       = $RepairPlan.previewState
        blockReason        = $RepairPlan.blockReason
        currentContent     = $RawContent
        proposedContent    = $proposedContent
        repairActions      = @($RepairPlan.actions)
        completedItemCount = $completedCount
        pendingItemCount   = $allPendingItems.Count
        generatedAt        = $generatedAt
    }
}
