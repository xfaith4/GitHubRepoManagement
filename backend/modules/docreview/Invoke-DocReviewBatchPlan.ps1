### BEGIN FILE: Invoke-DocReviewBatchPlan.ps1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\output\inventory\doc-review-manifest.json'),

    [Parameter()]
    [string]$TargetRepo = "AIToolbox",

    [Parameter()]
    [string]$OutDir = (Join-Path $PSScriptRoot '..\output\workitems'),

    # Optional path to a per-repo JSON file defining custom batch rules.
    # Format: { "rules": [ { "pattern": "regex", "order": int, "label": "Label", "slug": "slug" } ] }
    # Rules are evaluated first, before generic fallback logic.
    # Defaults to batch-rules.json in the repo workitem folder if it exists.
    [Parameter()]
    [string]$BatchRulesPath = "",

    # Optional path to repo-overrides.json containing per-repo reviewer notes.
    # Notes are injected into every prompt packet for this repo.
    # Defaults to config/repo-overrides.json relative to the script if it exists.
    [Parameter()]
    [string]$RepoOverridesPath = (Join-Path $PSScriptRoot '..\config\repo-overrides.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Load custom batch rules ─────────────────────────────────────────────────
# If $BatchRulesPath is not provided, check for batch-rules.json in the repo workitem folder.
$script:CustomBatchRules = $null
if (-not $BatchRulesPath) {
    $repoWorkitemDir = Join-Path -Path $OutDir -ChildPath $TargetRepo
    $defaultRulesPath = Join-Path -Path $repoWorkitemDir -ChildPath 'batch-rules.json'
    if (Test-Path -LiteralPath $defaultRulesPath) {
        $BatchRulesPath = $defaultRulesPath
    }
}
if ($BatchRulesPath -and (Test-Path -LiteralPath $BatchRulesPath)) {
    $rulesJson = Get-Content -LiteralPath $BatchRulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:CustomBatchRules = $rulesJson.rules
    Write-Host "Loaded $($script:CustomBatchRules.Count) custom batch rule(s) from: $BatchRulesPath" -ForegroundColor DarkCyan
}

# ─── Load repo-specific reviewer notes ───────────────────────────────────────
$script:RepoNotes = @()
if ($RepoOverridesPath -and (Test-Path -LiteralPath $RepoOverridesPath)) {
    $overridesJson = Get-Content -LiteralPath $RepoOverridesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($overridesJson.PSObject.Properties.Name -contains 'repo_overrides') {
        $repoKey = $overridesJson.repo_overrides.PSObject.Properties | Where-Object { $_.Name -eq $TargetRepo }
        if ($repoKey -and $repoKey.Value.PSObject.Properties.Name -contains 'notes') {
            $script:RepoNotes = @($repoKey.Value.notes | ForEach-Object { [string]$_ })
            if ($script:RepoNotes.Count -gt 0) {
                Write-Host "Loaded $($script:RepoNotes.Count) repo note(s) for '$TargetRepo'" -ForegroundColor DarkCyan
            }
        }
    }
}

# ─── Copilot prompt template ────────────────────────────────────────────────
$CopilotPromptTemplate = @'
You are performing a documentation modernization pass for a specific batch of Markdown files in this repository.

Objective:
Revise the selected documents so they are concise, accurate, professional, consistent, and elegant by design. Improve structure, information hierarchy, scannability, terminology consistency, and cross-linking. Treat the docs as part of a cohesive documentation system.

Scope:
Work only on the files listed in this batch.
Do not edit files outside the batch.
When needed, reference adjacent docs only to improve consistency and linking.

Editing standards:
- Remove fluff, repetition, vague wording, and internal-note style writing.
- Preserve technical correctness and engineering nuance.
- Improve opening summaries so each file clearly states what it covers, who it is for, and when to use it.
- Improve heading quality and section flow.
- Use tree diagrams where they materially improve understanding of nested structures, directory layouts, component hierarchies, workflows, or layered systems.
- Standardize terminology and formatting across the batch.
- Add cross-links where they help the repository feel like a coherent doc set.
- Do not invent implementation details.
- Do not remove important warnings, constraints, setup steps, or prerequisites.
- Do not over-format for cosmetic reasons.

Special handling:
- For reference docs, prioritize precision and navigability.
- For onboarding/setup docs, prioritize sequence clarity and prerequisites.
- For ADRs, preserve original decision intent and historical context; improve consistency and readability with a light editorial touch only.

Required output:
1. Brief assessment of the batch:
   - purpose of each file
   - major issues found
   - structural improvements recommended
2. Revised Markdown for each file
3. Short summary of:
   - major structural changes made
   - tree diagrams added
   - cross-links added or recommended
   - any content requiring human verification
'@

# ─── Batch assignment ────────────────────────────────────────────────────────
function Get-FileBatchInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $p     = $RelativePath.ToLowerInvariant()
    $depth = ($p.Trim('\') -split '[\\/]').Count - 1

    # Custom repo rules loaded from BatchRulesPath, evaluated before generic logic.
    if ($script:CustomBatchRules) {
        foreach ($rule in $script:CustomBatchRules) {
            if ($p -match $rule.pattern) {
                return @{ Order = [int]$rule.order; Label = [string]$rule.label; Slug = [string]$rule.slug }
            }
        }
    }

    # Batch 5 — ADRs
    if ($p -match '(^|\\)(adr|adrs|architecture[-_]decision)(\\|$)') {
        return @{ Order = 5; Label = 'ADRs'; Slug = 'adrs' }
    }

    # Batch 6 — Repo support / meta (root-adjacent only)
    if ($depth -le 1 -and $p -match '(^|\\)(changelog|agents|security|code[-_]of[-_]conduct|codeowners)\.md$') {
        return @{ Order = 6; Label = 'Repo Support'; Slug = 'repo-support' }
    }
    if ($p -match '(^|\\)(release[-_]?notes.*)\.md$') {
        return @{ Order = 6; Label = 'Repo Support'; Slug = 'repo-support' }
    }

    # Batch 1 — Entrypoint: root README/CONTRIBUTING + top docs-folder navigation
    if ($depth -eq 0 -and $p -match '(readme|contributing)\.md$') {
        return @{ Order = 1; Label = 'Entrypoint Core'; Slug = 'entrypoint-core' }
    }
    if ($p -match '(^|\\)docs\\getting-started\.md$') {
        return @{ Order = 1; Label = 'Entrypoint Core'; Slug = 'entrypoint-core' }
    }
    if ($p -match '(^|\\)docs\\(readme|index|architecture|api[-_]reference|faq|overview)\.md$') {
        return @{ Order = 2; Label = 'Entrypoint Navigation'; Slug = 'entrypoint-navigation' }
    }
    if ($p -match '(^|\\)docs\\(frontend|incident-response|integrations|orchestration|prompts|providers)\.md$') {
        return @{ Order = 2; Label = 'Entrypoint Navigation'; Slug = 'entrypoint-navigation' }
    }

    # Batch 2 — Onboarding / development flow
    if ($p -match '(^|\\)(development)(\\|\.md$)') {
        return @{ Order = 3; Label = 'Onboarding'; Slug = 'onboarding' }
    }
    if ($p -match '(setup|install|getting[-_]started|onboarding|backend[-_]guide|frontend[-_]guide|testing[-_]guide|debugging[-_]guide|performance[-_]guide|architecture[-_]deep[-_]dive)') {
        return @{ Order = 3; Label = 'Onboarding'; Slug = 'onboarding' }
    }

    # Batch 3 — Advanced / system behavior
    if ($p -match '(^|\\)(advanced)(\\|$)') {
        return @{ Order = 4; Label = 'Advanced'; Slug = 'advanced' }
    }
    if ($depth -le 2 -and $p -match '(agents|backend|deployment|hardening|pipeline|parallel|requirement[-_]wizard)\.md$') {
        return @{ Order = 4; Label = 'Advanced'; Slug = 'advanced' }
    }

    # Batch 4 — Domain-specific (deep specialized subdirectory, not already matched)
    if ($depth -ge 2) {
        return @{ Order = 11; Label = 'Domain'; Slug = 'domain' }
    }

    # Fallback: shallow docs stay in Entrypoint
    return @{ Order = 2; Label = 'Entrypoint Navigation'; Slug = 'entrypoint-navigation' }
}

# ─── File sort key ───────────────────────────────────────────────────────────
function Get-FileSortKey {
    param([string]$Path)
    $p = $Path.ToLowerInvariant()
    if ($p -match '(^|\\)readme\.md$')      { return '0_' + $Path }
    if ($p -match '(^|\\)contributing\.md$') { return '1_' + $Path }
    if ($p -match '(^|\\)index\.md$')        { return '2_' + $Path }
    return '3_' + $Path
}

function Get-BatchAcceptanceCriteria {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BatchLabel
    )

    switch ($BatchLabel) {
        'Entrypoint Core' {
            return @(
                'Primary entry docs explain purpose, audience, and navigation clearly',
                'Getting-started path is explicit and non-duplicative',
                'Root and docs-level entrypoints link to the same information architecture'
            )
        }
        'Entrypoint Navigation' {
            return @(
                'Top-level docs are cross-linked and non-overlapping',
                'Architecture and reference navigation are discoverable from entry docs',
                'User can find the next document without guesswork'
            )
        }
        'Onboarding' {
            return @(
                'Contributor setup and development flow are sequential',
                'Prerequisites and verification steps are explicit',
                'Development guides avoid duplicated setup instructions'
            )
        }
        'Advanced' {
            return @(
                'Advanced topics assume prior context and link back to it',
                'Operational and system behavior details remain technically precise',
                'Niche topics are separated cleanly from general onboarding'
            )
        }
        'ADRs' {
            return @(
                'Decision intent and historical context are preserved',
                'ADR formatting is consistent across the set',
                'No decision rationale is rewritten beyond editorial cleanup'
            )
        }
        'Repo Support' {
            return @(
                'Meta-docs clearly state status and maintenance expectations',
                'Release and support docs are not presented as onboarding material',
                'Repository governance docs are easy to locate'
            )
        }
        default {
            return @(
                'Documents in the batch are internally consistent',
                'Cross-links are added where they reduce navigation friction',
                'Content requiring human verification is called out explicitly'
            )
        }
    }
}

# ─── Load Phase 1 manifest ──────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Phase 1 manifest not found: $ManifestPath  Run Invoke-DocReviewInventory.ps1 first."
}

$manifest  = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$repoEntry = @($manifest | Where-Object { $_.RepoName -eq $TargetRepo }) | Select-Object -First 1

if (-not $repoEntry) {
    $available = ($manifest | Select-Object -ExpandProperty RepoName) -join ', '
    throw "Repo '$TargetRepo' not found in manifest. Available repos: $available"
}

$allClassified = @($repoEntry.ClassifiedFiles)
if ($allClassified.Count -eq 0) {
    throw "No ClassifiedFiles found for '$TargetRepo'. Re-run Phase 1 to regenerate the manifest."
}

# ─── Assign batches ─────────────────────────────────────────────────────────
# Include Active, Operational, Reference — skip Archive and Generated
$batchableClasses = @('Active', 'Operational', 'Reference')

$annotated = @(
    foreach ($cf in $allClassified) {
        if ($cf.DocClass -notin $batchableClasses) { continue }
        $info = Get-FileBatchInfo -RelativePath $cf.Path
        [pscustomobject]@{
            Path        = $cf.Path
            DocClass    = $cf.DocClass
            BatchOrder  = $info.Order
            BatchLabel  = $info.Label
            BatchSlug   = $info.Slug
            SortKey     = Get-FileSortKey -Path $cf.Path
        }
    }
)

if ($annotated.Count -eq 0) {
    throw "No batchable files (Active/Operational/Reference) found for '$TargetRepo'."
}

$batches = @(
    $annotated |
        Group-Object -Property BatchOrder |
        Sort-Object  -Property { [int]$_.Name } |
        ForEach-Object {
            $firstItem  = $_.Group | Select-Object -First 1
            $sortedFiles = @(
                $_.Group |
                    Sort-Object -Property SortKey |
                    Select-Object -ExpandProperty Path
            )
            [pscustomobject]@{
                BatchNumber      = [int]$_.Name
                Label            = $firstItem.BatchLabel
                Slug             = $firstItem.BatchSlug
                BranchSuggestion = 'docs/review-batch' + $_.Name + '-' + $firstItem.BatchSlug
                FileCount        = $sortedFiles.Count
                Files            = $sortedFiles
            }
        }
)

$batchStatusItems = @(
    foreach ($batch in $batches) {
        [pscustomobject]@{
            BatchNumber         = $batch.BatchNumber
            Label               = $batch.Label
            Slug                = $batch.Slug
            Status              = 'Not Started'
            Owner               = 'TBD'
            Branch              = $batch.BranchSuggestion
            Files               = @($batch.Files)
            AcceptanceCriteria  = @(Get-BatchAcceptanceCriteria -BatchLabel $batch.Label)
            VerificationNotes   = @()
            FollowUpIssues      = @()
        }
    }
)

# ─── Output directory ────────────────────────────────────────────────────────
$repoOutDir = Join-Path -Path $OutDir -ChildPath $TargetRepo
$null = New-Item -ItemType Directory -Path $repoOutDir -Force -ErrorAction Stop

# ─── batch-manifest.json ─────────────────────────────────────────────────────
$batchManifest = [pscustomobject]@{
    Repo             = $TargetRepo
    RepoPath         = $repoEntry.RepoPath
    GeneratedAt      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    TotalFiles       = $annotated.Count
    BatchCount       = $batches.Count
    DocsIndexPresent = [bool]$repoEntry.HasDocsIndex
    Batches          = $batches
    BatchStatus      = $batchStatusItems
}

$manifestOut = Join-Path -Path $repoOutDir -ChildPath 'batch-manifest.json'
$batchManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestOut -Encoding UTF8

# ─── Per-batch files ─────────────────────────────────────────────────────────
foreach ($batch in $batches) {
    $paddedNum = $batch.BatchNumber.ToString('00')
    $prefix    = "batch-$paddedNum-$($batch.Slug)"

    # ── Prompt packet ────────────────────────────────────────────────────────
    $promptLines = New-Object System.Collections.Generic.List[string]
    $promptLines.Add('# Batch ' + $batch.BatchNumber + ' — ' + $batch.Label)
    $promptLines.Add('')
    $promptLines.Add('**Repo:** `' + $TargetRepo + '`')
    $promptLines.Add('**Branch:** `' + $batch.BranchSuggestion + '`')
    $promptLines.Add('**Files in batch:** ' + $batch.FileCount)
    $promptLines.Add('')
    $promptLines.Add('## Files')
    $promptLines.Add('')
    foreach ($f in $batch.Files) {
        $promptLines.Add('- `' + $f + '`')
    }
    $promptLines.Add('')
    $promptLines.Add('---')
    $promptLines.Add('')
    if ($script:RepoNotes.Count -gt 0) {
        $promptLines.Add('## Repo-Specific Notes')
        $promptLines.Add('')
        $promptLines.Add('Apply these considerations throughout the review:')
        $promptLines.Add('')
        foreach ($note in $script:RepoNotes) {
            $promptLines.Add('- ' + $note)
        }
        $promptLines.Add('')
        $promptLines.Add('---')
        $promptLines.Add('')
    }
    $promptLines.Add('## Copilot Prompt')
    $promptLines.Add('')
    $promptLines.Add($CopilotPromptTemplate.Trim())
    $promptLines.Add('')
    $promptLines.Add('---')
    $promptLines.Add('')
    $promptLines.Add('## File List (paste into Copilot context)')
    $promptLines.Add('')
    foreach ($f in $batch.Files) {
        $promptLines.Add('- `' + $f + '`')
    }

    $promptPath = Join-Path -Path $repoOutDir -ChildPath "$prefix-prompt.md"
    Set-Content -LiteralPath $promptPath -Value $promptLines -Encoding UTF8

    # ── Review checklist ─────────────────────────────────────────────────────
    $checkLines = New-Object System.Collections.Generic.List[string]
    $checkLines.Add('# Review Checklist — Batch ' + $batch.BatchNumber + ': ' + $batch.Label)
    $checkLines.Add('')
    $checkLines.Add('**Repo:** `' + $TargetRepo + '`')
    $checkLines.Add('**Branch:** `' + $batch.BranchSuggestion + '`')
    $checkLines.Add('')
    $checkLines.Add('## File Sign-off')
    $checkLines.Add('')
    foreach ($f in $batch.Files) {
        $checkLines.Add('- [ ] `' + $f + '`')
    }
    $checkLines.Add('')
    $checkLines.Add('## Editing Standards')
    $checkLines.Add('')
    $checkLines.Add('- [ ] Opening summary: purpose, audience, and when to use — present in each file')
    $checkLines.Add('- [ ] Headings clear and logically sequenced')
    $checkLines.Add('- [ ] Fluff, repetition, and internal-note writing removed')
    $checkLines.Add('- [ ] Technical correctness and nuance preserved')
    $checkLines.Add('- [ ] Terminology consistent across the batch')
    $checkLines.Add('- [ ] Prerequisites and warnings retained')
    $checkLines.Add('- [ ] No invented implementation details')
    $checkLines.Add('- [ ] Not over-formatted for cosmetic reasons')
    $checkLines.Add('')
    $checkLines.Add('## Structural Improvements')
    $checkLines.Add('')
    $checkLines.Add('- [ ] Cross-links added or recommended')
    $checkLines.Add('- [ ] Tree diagrams added where useful')
    $checkLines.Add('- [ ] Section flow improved')
    $checkLines.Add('- [ ] Batch feels consistent as a set')

    if ($batch.Label -eq 'ADRs') {
        $checkLines.Add('')
        $checkLines.Add('## ADR-specific')
        $checkLines.Add('')
        $checkLines.Add('- [ ] Original decision intent preserved')
        $checkLines.Add('- [ ] Historical context intact')
        $checkLines.Add('- [ ] Editorial touch is light — not rewritten')
    }

    $checkLines.Add('')
    $checkLines.Add('## Copilot Output Verification')
    $checkLines.Add('')
    $checkLines.Add('- [ ] Assessment reviewed and agreed with')
    $checkLines.Add('- [ ] All revised files accepted or further edited by hand')
    $checkLines.Add('- [ ] Stale content flagged for human verification actioned')
    $checkLines.Add('- [ ] Cross-link recommendations evaluated')
    $checkLines.Add('- [ ] PR ready for merge')
    $checkLines.Add('')
    $checkLines.Add('## Notes')
    $checkLines.Add('')
    $checkLines.Add('> _Add review notes here._')

    $checkPath = Join-Path -Path $repoOutDir -ChildPath "$prefix-checklist.md"
    Set-Content -LiteralPath $checkPath -Value $checkLines -Encoding UTF8
}

# ─── Human-readable index ────────────────────────────────────────────────────
$indexLines = New-Object System.Collections.Generic.List[string]
$indexLines.Add('# Phase 2 Batch Plan — ' + $TargetRepo)
$indexLines.Add('')
$indexLines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$indexLines.Add("Repo path: $($repoEntry.RepoPath)")
$indexLines.Add("Total files: $($annotated.Count)")
$indexLines.Add('')
$indexLines.Add('## Status')
$indexLines.Add('')
$indexLines.Add('- Docs index present: `' + [string]([bool]$repoEntry.HasDocsIndex) + '`')
$indexLines.Add('- Execution state: planning complete, review not started')
$indexLines.Add('- Default status values are placeholders and should be updated during execution')
$indexLines.Add('')
$indexLines.Add('## Execution Tracking')
$indexLines.Add('')
$indexLines.Add('| Batch | Status | Owner | Branch | Files |')
$indexLines.Add('| --- | --- | --- | --- | ---: |')
foreach ($statusItem in $batchStatusItems) {
    $indexLines.Add('| ' + $statusItem.BatchNumber + ' - ' + $statusItem.Label + ' | ' + $statusItem.Status + ' | ' + $statusItem.Owner + ' | `' + $statusItem.Branch + '` | ' + $statusItem.Files.Count + ' |')
}
$indexLines.Add('')
$indexLines.Add('## Batches')
$indexLines.Add('')

foreach ($batch in $batches) {
    $paddedNum = $batch.BatchNumber.ToString('00')
    $prefix    = "batch-$paddedNum-$($batch.Slug)"
    $indexLines.Add('### Batch ' + $batch.BatchNumber + ' — ' + $batch.Label)
    $indexLines.Add('')
    $indexLines.Add('**Branch:** `' + $batch.BranchSuggestion + '`  ')
    $indexLines.Add('**Files:** ' + $batch.FileCount + '  ')
    $indexLines.Add('**Prompt:** `' + "$prefix-prompt.md" + '`  ')
    $indexLines.Add('**Checklist:** `' + "$prefix-checklist.md" + '`')
    $indexLines.Add('')
    $indexLines.Add('**Acceptance criteria:**')
    foreach ($criterion in (Get-BatchAcceptanceCriteria -BatchLabel $batch.Label)) {
        $indexLines.Add('- ' + $criterion)
    }
    $indexLines.Add('')
    foreach ($f in $batch.Files) {
        $indexLines.Add('- `' + $f + '`')
    }
    $indexLines.Add('')
}

$indexPath = Join-Path -Path $repoOutDir -ChildPath 'index.md'
Set-Content -LiteralPath $indexPath -Value $indexLines -Encoding UTF8

# ─── Console summary ─────────────────────────────────────────────────────────
Write-Host ''
Write-Host "Phase 2 batch plan: $TargetRepo" -ForegroundColor Green
Write-Host ''
foreach ($batch in $batches) {
    Write-Host ('  Batch {0:00}  {1,-22}  {2,3} files   {3}' -f `
        $batch.BatchNumber, $batch.Label, $batch.FileCount, $batch.BranchSuggestion) -ForegroundColor Cyan
}
Write-Host ''
Write-Host "Output  : $repoOutDir"
Write-Host "Index   : $indexPath"
Write-Host "Manifest: $manifestOut"
### END FILE: Invoke-DocReviewPhase2.ps1
