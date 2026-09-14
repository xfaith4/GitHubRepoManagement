### BEGIN FILE: Build-DocReviewQueue.ps1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter()]
    [string]$OutDir = (Join-Path $PSScriptRoot '..\output\queue'),

    [Parameter()]
    [int]$MaxFilesPerBatch = 5,

    [Parameter()]
    [switch]$IncludeLowPriority,

    # Optional path to per-repo notes injected into copilot packets.
    # Defaults to config/repo-overrides.json relative to the script if it exists.
    [Parameter()]
    [string]$RepoOverridesPath = (Join-Path $PSScriptRoot '..\config\repo-overrides.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Load repo overrides ------------------------------------------------------
$script:RepoOverrides = @{}
if ($RepoOverridesPath -and (Test-Path -LiteralPath $RepoOverridesPath)) {
    $overridesJson = Get-Content -LiteralPath $RepoOverridesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($overridesJson.PSObject.Properties.Name -contains 'repo_overrides') {
        foreach ($prop in $overridesJson.repo_overrides.PSObject.Properties) {
            $script:RepoOverrides[$prop.Name] = $prop.Value
        }
    }
    Write-Host "Loaded repo overrides for $($script:RepoOverrides.Count) repo(s) from: $RepoOverridesPath" -ForegroundColor DarkCyan
}

function New-NormalizedDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $null = New-Item -ItemType Directory -Path $Path -Force
    return (Resolve-Path -LiteralPath $Path).Path
}

function ConvertTo-SafeFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = $Name
    foreach ($char in $invalidChars) {
        $safe = $safe.Replace($char, '_')
    }

    $safe = $safe -replace '\s+', '_'
    $safe = $safe -replace '_+', '_'
    return $safe.Trim('_')
}

function Get-StringArray {
    param(
        [Parameter(Mandatory = $false)]
        $Value
    )

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { [string]$_ })
    }

    return @([string]$Value)
}

function Get-RepoMarkdownFiles {
    param(
        [Parameter(Mandatory = $true)]
        $Repo
    )

    if ($Repo.PSObject.Properties.Name -contains 'MarkdownFiles') {
        $markdownFiles = @(Get-StringArray -Value $Repo.MarkdownFiles)
        if ($markdownFiles.Count -gt 0) {
            return @($markdownFiles | Sort-Object -Unique)
        }
    }

    if ($Repo.PSObject.Properties.Name -contains 'ClassifiedFiles') {
        $fromClassified = @(
            foreach ($item in @($Repo.ClassifiedFiles)) {
                if ($null -ne $item -and $item.PSObject.Properties.Name -contains 'Path') {
                    [string]$item.Path
                }
            }
        )
        return @($fromClassified | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    }

    return @()
}

function Test-PathMatchAny {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($Path -match $pattern) {
            return $true
        }
    }

    return $false
}

function Get-DocBatchType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $p = $RelativePath.ToLowerInvariant()

    $corePatterns = @(
        '(^|\\)readme\.md$',
        '(^|\\)docs\\index\.md$',
        '(^|\\)contributing\.md$',
        'setup',
        'install',
        'getting-started',
        'get-started',
        'quickstart',
        'architecture',
        'design'
    )

    $operationalPatterns = @(
        'runbook',
        'playbook',
        'troubleshoot',
        'troubleshooting',
        'faq',
        'workflow',
        'operations',
        'operational',
        'standards?'
    )

    $referencePatterns = @(
        'api',
        'reference',
        'schema',
        'configuration',
        'config',
        'commands?',
        'cli',
        'parameters?'
    )

    $archivalPatterns = @(
        'roadmap',
        'changelog',
        'release',
        'history',
        'notes?',
        'backlog',
        'ideas?',
        'draft',
        'rfc',
        'proposal'
    )

    if (Test-PathMatchAny -Path $p -Patterns $corePatterns) {
        return 'core'
    }

    if (Test-PathMatchAny -Path $p -Patterns $operationalPatterns) {
        return 'operational'
    }

    if (Test-PathMatchAny -Path $p -Patterns $referencePatterns) {
        return 'reference'
    }

    if (Test-PathMatchAny -Path $p -Patterns $archivalPatterns) {
        return 'archival'
    }

    return 'general'
}

function Split-IntoChunks {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items,

        [Parameter(Mandatory = $true)]
        [int]$ChunkSize
    )

    $chunks = New-Object System.Collections.Generic.List[object[]]

    if ($null -eq $Items -or $Items.Count -eq 0) {
        return @()
    }

    for ($i = 0; $i -lt $Items.Count; $i += $ChunkSize) {
        $endIndex = [Math]::Min(($i + $ChunkSize - 1), ($Items.Count - 1))
        $slice = @()

        for ($j = $i; $j -le $endIndex; $j++) {
            $slice += $Items[$j]
        }

        $chunks.Add($slice)
    }

    return ,$chunks
}

function Get-BatchBaseWeight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BatchType
    )

    switch ($BatchType) {
        'core' { return 40 }
        'operational' { return 28 }
        'reference' { return 20 }
        'archival' { return 8 }
        'general' { return 12 }
        default { return 10 }
    }
}

function Get-BatchOrder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BatchType
    )

    switch ($BatchType) {
        'core' { return 1 }
        'operational' { return 2 }
        'reference' { return 3 }
        'general' { return 4 }
        'archival' { return 5 }
        default { return 9 }
    }
}

function Get-EstimatedComplexity {
    param(
        [Parameter(Mandatory = $true)]
        [int]$FileCount,

        [Parameter(Mandatory = $true)]
        [bool]$HasLargeReadme,

        [Parameter(Mandatory = $true)]
        [string]$BatchType
    )

    if ($BatchType -eq 'core' -and ($FileCount -ge 4 -or $HasLargeReadme)) {
        return 'high'
    }

    if ($FileCount -ge 5) {
        return 'high'
    }

    if ($FileCount -ge 3) {
        return 'medium'
    }

    return 'low'
}

function Get-RecommendedCooldownSeconds {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Complexity
    )

    switch ($Complexity) {
        'high' { return 300 }
        'medium' { return 180 }
        'low' { return 90 }
        default { return 180 }
    }
}

function Get-BatchGoals {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BatchType
    )

    switch ($BatchType) {
        'core' {
            return @(
                'Improve first-use readability and onboarding clarity',
                'Tighten headings, structure, and opening summaries',
                'Clarify architecture, setup, and contributor guidance',
                'Strengthen cross-linking among high-value docs'
            )
        }
        'operational' {
            return @(
                'Make procedures easier to follow and verify',
                'Clarify troubleshooting steps, warnings, and prerequisites',
                'Reduce ambiguity in operational flows and runbooks',
                'Improve scanability for maintenance and support use'
            )
        }
        'reference' {
            return @(
                'Normalize structure and terminology across reference docs',
                'Improve scanability with disciplined headings and tables where useful',
                'Reduce ambiguity while preserving technical precision',
                'Keep formatting consistent and easy to navigate'
            )
        }
        'archival' {
            return @(
                'Clarify status and intent of planning or historical docs',
                'Trim noise and improve readability without over-investing',
                'Flag stale or speculative content for review',
                'Preserve useful historical context while reducing clutter'
            )
        }
        default {
            return @(
                'Improve structure and readability',
                'Reduce repetition and vague wording',
                'Standardize formatting and headings',
                'Make content more deliberate and maintainable'
            )
        }
    }
}

function Get-PromptFlavorName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BatchType
    )

    switch ($BatchType) {
        'core' { return 'core-doc-modernization' }
        'operational' { return 'operational-doc-clarification' }
        'reference' { return 'reference-doc-normalization' }
        'archival' { return 'archival-doc-tidy-pass' }
        default { return 'general-doc-improvement' }
    }
}

function Get-PromptFlavorText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BatchType
    )

    switch ($BatchType) {
        'core' {
            @"
You are performing a high-value documentation modernization pass for this repository's core docs.

Priorities:
- improve first impression and onboarding clarity
- tighten structure, summaries, and section hierarchy
- clarify architecture, setup, and contributor expectations
- make the documentation feel intentionally designed, not accumulated
- add tree diagrams only when they materially improve understanding of architecture, directory layout, or nested concepts

Rules:
- preserve technical accuracy
- do not invent implementation details
- prioritize structural improvements over cosmetic rewrites
- strengthen cross-links among related core documents
- keep changes concise, professional, and reviewable
"@
        }
        'operational' {
            @"
You are performing an operational documentation improvement pass.

Priorities:
- improve procedural clarity
- tighten troubleshooting and runbook flows
- surface prerequisites, warnings, and failure modes clearly
- improve scanability for support and maintenance readers
- use tables or tree diagrams only where they materially improve comprehension

Rules:
- preserve technical correctness
- do not remove important cautions or constraints
- prefer stepwise clarity over prose density
- keep procedures easy to verify and follow
"@
        }
        'reference' {
            @"
You are performing a reference documentation normalization pass.

Priorities:
- improve consistency and scanability
- normalize terminology, headings, and formatting
- use tables where appropriate for options, parameters, and comparisons
- reduce ambiguity while preserving technical precision
- use tree diagrams only when a nested structure is genuinely hard to explain in prose

Rules:
- do not invent APIs, commands, schemas, or configuration facts
- keep formatting disciplined and predictable
- prefer concise, high-signal writing
"@
        }
        'archival' {
            @"
You are performing a light archival documentation cleanup pass.

Priorities:
- clarify status, purpose, and historical context
- trim avoidable noise
- improve readability without over-engineering the document
- flag stale, speculative, or unverifiable material where appropriate

Rules:
- preserve useful historical meaning
- avoid spending excessive effort polishing low-value documents
- do not invent missing context
"@
        }
        default {
            @"
You are performing a general documentation improvement pass.

Priorities:
- improve clarity, structure, and professionalism
- reduce repetition and vague wording
- standardize headings and formatting
- make the documentation easier to navigate and maintain

Rules:
- preserve technical accuracy
- do not invent facts
- keep revisions concise and reviewable
"@
        }
    }
}

function Get-RepoWarnings {
    param(
        [Parameter(Mandatory = $true)]
        $Repo,

        [Parameter(Mandatory = $true)]
        [string[]]$MarkdownFiles
    )

    $warnings = New-Object System.Collections.Generic.List[string]

    $hasDocsFolder = $false
    if ($Repo.PSObject.Properties.Name -contains 'HasDocsFolder') {
        $hasDocsFolder = [bool]$Repo.HasDocsFolder
    }

    $hasDocsIndex = $false
    if ($Repo.PSObject.Properties.Name -contains 'HasDocsIndex') {
        $hasDocsIndex = [bool]$Repo.HasDocsIndex
    }

    $hasReadme = $false
    if ($Repo.PSObject.Properties.Name -contains 'HasReadme') {
        $hasReadme = [bool]$Repo.HasReadme
    }

    if (-not $hasReadme) {
        $warnings.Add('Repository has markdown docs but no README.md')
    }

    if ($hasDocsFolder -and -not $hasDocsIndex) {
        $warnings.Add('docs folder exists without docs/index.md')
    }

    $generalCount = 0
    foreach ($file in $MarkdownFiles) {
        if ((Get-DocBatchType -RelativePath $file) -eq 'general') {
            $generalCount++
        }
    }

    if ($generalCount -ge 6) {
        $warnings.Add('Many markdown files fall into general or unclear categories')
    }

    $readmePaths = @($MarkdownFiles | Where-Object { $_ -match '(^|\\)README\.md$' })
    if ($readmePaths.Count -gt 1) {
        $warnings.Add('Multiple README.md files detected across the repo')
    }

    $setupDocs = @($MarkdownFiles | Where-Object {
            $_ -match 'setup|install|getting-started|get-started|quickstart'
        })
    if ($setupDocs.Count -ge 3) {
        $warnings.Add('Multiple setup-oriented docs may indicate overlap or duplication')
    }

    # Git freshness
    if ($Repo.PSObject.Properties.Name -contains 'GitUncommittedChanges') {
        $uncommitted = [int]$Repo.GitUncommittedChanges
        if ($uncommitted -gt 0) {
            $warnings.Add("Repo has $uncommitted uncommitted change(s) - may be mid-surgery; verify before reviewing")
        }
    }

    if ($Repo.PSObject.Properties.Name -contains 'GitLastCommitDate') {
        $lastCommit = [string]$Repo.GitLastCommitDate
        if ($lastCommit) {
            try {
                $commitDate = [datetime]::Parse($lastCommit)
                $daysSince  = ([datetime]::Now - $commitDate).Days
                if ($daysSince -gt 365) {
                    $warnings.Add("Last commit was $daysSince days ago - verify repo is still active before investing in doc review")
                }
            } catch { }
        }
    }

    return @($warnings)
}

function Get-QueueItemWarnings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BatchType,

        [Parameter(Mandatory = $true)]
        [string[]]$Files,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$RepoWarnings
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    foreach ($warning in $RepoWarnings) {
        $warnings.Add($warning)
    }

    if ($BatchType -eq 'core' -and -not (@($Files | Where-Object { $_ -match '(^|\\)README\.md$' }).Count -gt 0)) {
        $warnings.Add('Core batch does not include README.md; verify this is intended')
    }

    if ($BatchType -eq 'archival' -and $Files.Count -ge 4) {
        $warnings.Add('Archival batch is relatively large; avoid over-investing in polish')
    }

    if ($Files.Count -gt 4) {
        $warnings.Add('Batch contains many files; keep changes bounded and reviewable')
    }

    return @($warnings | Sort-Object -Unique)
}

function Build-BatchMap {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$MarkdownFiles
    )

    $map = @{
        core        = New-Object System.Collections.Generic.List[string]
        operational = New-Object System.Collections.Generic.List[string]
        reference   = New-Object System.Collections.Generic.List[string]
        archival    = New-Object System.Collections.Generic.List[string]
        general     = New-Object System.Collections.Generic.List[string]
    }

    foreach ($file in ($MarkdownFiles | Sort-Object -Unique)) {
        $batchType = Get-DocBatchType -RelativePath $file
        $map[$batchType].Add($file)
    }

    return $map
}

function New-QueueItem {
    param(
        [Parameter(Mandatory = $true)]
        $Repo,

        [Parameter(Mandatory = $true)]
        [string]$BatchType,

        [Parameter(Mandatory = $true)]
        [int]$ChunkIndex,

        [Parameter(Mandatory = $true)]
        [string[]]$Files,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$RepoWarnings
    )

    $repoName = [string]$Repo.RepoName
    $repoPath = [string]$Repo.RepoPath
    $repoPriorityScore = [int]$Repo.PriorityScore
    $repoPriorityBand = [string]$Repo.PriorityBand

    # Git freshness from manifest
    $gitBranch     = if ($Repo.PSObject.Properties.Name -contains 'GitBranch')             { [string]$Repo.GitBranch }             else { '' }
    $gitLastCommit = if ($Repo.PSObject.Properties.Name -contains 'GitLastCommitDate')     { [string]$Repo.GitLastCommitDate }     else { '' }
    $gitDirty      = if ($Repo.PSObject.Properties.Name -contains 'GitUncommittedChanges') { [int]$Repo.GitUncommittedChanges }     else { 0 }

    # Per-repo custom notes from overrides config
    $repoNotes = @()
    if ($script:RepoOverrides.ContainsKey($repoName)) {
        $entry = $script:RepoOverrides[$repoName]
        if ($entry.PSObject.Properties.Name -contains 'notes') {
            $repoNotes = @($entry.notes | ForEach-Object { [string]$_ })
        }
    }

    $batchOrder = Get-BatchOrder -BatchType $BatchType
    $batchBaseWeight = Get-BatchBaseWeight -BatchType $BatchType

    $hasLargeReadme = $false
    $readmeFile = @($Files | Where-Object { $_ -match '(^|\\)README\.md$' })
    if ($readmeFile.Count -gt 0) {
        $readmeFullPath = Join-Path -Path $repoPath -ChildPath $readmeFile[0]
        if (Test-Path -LiteralPath $readmeFullPath) {
            try {
                $readmeLength = ([System.IO.FileInfo](Get-Item -LiteralPath $readmeFullPath)).Length
                if ($readmeLength -ge 20000) {
                    $hasLargeReadme = $true
                }
            }
            catch {
                $hasLargeReadme = $false
            }
        }
    }

    $complexity = Get-EstimatedComplexity -FileCount $Files.Count -HasLargeReadme $hasLargeReadme -BatchType $BatchType
    $cooldownSeconds = Get-RecommendedCooldownSeconds -Complexity $complexity

    $complexityWeight = 0
    switch ($complexity) {
        'high' { $complexityWeight = 6 }
        'medium' { $complexityWeight = 3 }
        default { $complexityWeight = 0 }
    }

    $queueScore = $repoPriorityScore + $batchBaseWeight + $complexityWeight - (($ChunkIndex - 1) * 2)

    $warnings = Get-QueueItemWarnings -BatchType $BatchType -Files $Files -RepoWarnings $RepoWarnings
    $goals = Get-BatchGoals -BatchType $BatchType
    $promptFlavor = Get-PromptFlavorName -BatchType $BatchType

    $queueId = '{0}.{1}.{2}' -f (ConvertTo-SafeFileName -Name $repoName), $BatchType, $ChunkIndex.ToString('000')

    return [pscustomobject]@{
        QueueId                    = $queueId
        RepoName                   = $repoName
        RepoPath                   = $repoPath
        RepoPriorityBand           = $repoPriorityBand
        RepoPriorityScore          = $repoPriorityScore
        BatchType                  = $BatchType
        BatchOrder                 = $batchOrder
        BatchChunkIndex            = $ChunkIndex
        EstimatedComplexity        = $complexity
        RecommendedCooldownSeconds = $cooldownSeconds
        QueueScore                 = $queueScore
        PromptFlavor               = $promptFlavor
        Goals                      = @($goals)
        Warnings                   = @($warnings)
        Files                      = @($Files | Sort-Object)
        GitBranch                  = $gitBranch
        GitLastCommit              = $gitLastCommit
        GitDirty                   = $gitDirty
        RepoNotes                  = @($repoNotes)
        PacketPath                 = $null
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "ManifestPath not found: $($ManifestPath)"
}

$outRoot = New-NormalizedDirectory -Path $OutDir
$packetDir = New-NormalizedDirectory -Path (Join-Path -Path $outRoot -ChildPath 'copilot-packets')

Write-Host "Loading manifest: $($ManifestPath)" -ForegroundColor Cyan
$manifestRaw = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
$repos = @((ConvertFrom-Json -InputObject $manifestRaw))

if ($repos.Count -eq 0) {
    throw "No repo entries found in manifest: $($ManifestPath)"
}

$queueItems = New-Object System.Collections.Generic.List[object]

foreach ($repo in $repos) {
    $repoName = [string]$repo.RepoName

    if (-not $IncludeLowPriority.IsPresent) {
        if ([string]$repo.PriorityBand -eq 'Low') {
            continue
        }
    }

    $markdownFiles = @(Get-RepoMarkdownFiles -Repo $repo)
    if ($markdownFiles.Count -eq 0) {
        continue
    }

    Write-Host "Planning repo: $($repoName)" -ForegroundColor Yellow

    $repoWarnings = Get-RepoWarnings -Repo $repo -MarkdownFiles $markdownFiles
    $batchMap = Build-BatchMap -MarkdownFiles $markdownFiles

    $batchSequence = @('core', 'operational', 'reference', 'general', 'archival')

    foreach ($batchType in $batchSequence) {
        $filesForBatch = @($batchMap[$batchType] | Sort-Object -Unique)
        if ($filesForBatch.Count -eq 0) {
            continue
        }

        # For "general", keep these later and chunk modestly.
        # For "archival", also keep chunks small to avoid wasting review effort.
        $chunkSize = $MaxFilesPerBatch
        switch ($batchType) {
            'core' {
                if ($MaxFilesPerBatch -lt 4) { $chunkSize = 4 } else { $chunkSize = [Math]::Min($MaxFilesPerBatch, 5) }
            }
            'operational' {
                $chunkSize = [Math]::Min($MaxFilesPerBatch, 5)
            }
            'reference' {
                $chunkSize = [Math]::Min($MaxFilesPerBatch, 6)
            }
            'general' {
                $chunkSize = [Math]::Min($MaxFilesPerBatch, 4)
            }
            'archival' {
                $chunkSize = [Math]::Min($MaxFilesPerBatch, 4)
            }
        }

        $chunks = Split-IntoChunks -Items $filesForBatch -ChunkSize $chunkSize
        $chunkCounter = 1

        foreach ($chunk in $chunks) {
            $queueItem = New-QueueItem -Repo $repo -BatchType $batchType -ChunkIndex $chunkCounter -Files $chunk -RepoWarnings @($repoWarnings)
            $queueItems.Add($queueItem)
            $chunkCounter++
        }
    }
}

$orderedQueue = @(
    $queueItems |
        Sort-Object -Property `
        @{ Expression = 'QueueScore'; Descending = $true }, `
        @{ Expression = 'BatchOrder'; Descending = $false }, `
        @{ Expression = 'RepoPriorityScore'; Descending = $true }, `
        @{ Expression = 'RepoName'; Descending = $false }, `
        @{ Expression = 'BatchChunkIndex'; Descending = $false }
)

foreach ($item in $orderedQueue) {
    $packetFileName = '{0}.md' -f $item.QueueId
    $packetPath = Join-Path -Path $packetDir -ChildPath $packetFileName

    $packetLines = New-Object System.Collections.Generic.List[string]
    $packetLines.Add("# Queue Item: $($item.QueueId)")
    $packetLines.Add('')
    $packetLines.Add('## Repo')
    $packetLines.Add("- Name: $($item.RepoName)")
    $packetLines.Add("- Path: $($item.RepoPath)")
    $packetLines.Add("- Repo Priority: $($item.RepoPriorityBand) ($($item.RepoPriorityScore))")
    $packetLines.Add('')
    $packetLines.Add('## Git State')
    $packetLines.Add("- Branch: $(if ($item.GitBranch) { $item.GitBranch } else { 'unknown' })")
    $packetLines.Add("- Last Commit: $(if ($item.GitLastCommit) { $item.GitLastCommit } else { 'unknown' })")
    $packetLines.Add("- Uncommitted Changes: $($item.GitDirty)")
    $packetLines.Add('')
    $packetLines.Add('## Batch')
    $packetLines.Add("- Type: $($item.BatchType)")
    $packetLines.Add("- Chunk: $($item.BatchChunkIndex)")
    $packetLines.Add("- Complexity: $($item.EstimatedComplexity)")
    $packetLines.Add("- Recommended Cooldown Seconds: $($item.RecommendedCooldownSeconds)")
    $packetLines.Add("- Queue Score: $($item.QueueScore)")
    $packetLines.Add("- Prompt Flavor: $($item.PromptFlavor)")
    $packetLines.Add('')
    $packetLines.Add('## Files in Scope')
    foreach ($file in $item.Files) {
        $packetLines.Add("- $file")
    }
    $packetLines.Add('')



    $packetLines.Add('## Objectives')
    foreach ($goal in $item.Goals) {
        $packetLines.Add("- $goal")
    }
    $packetLines.Add('')

    if ($item.Warnings.Count -gt 0) {
        $packetLines.Add('## Warnings / Review Notes')
        foreach ($warning in $item.Warnings) {
            $packetLines.Add("- $warning")
        }
        $packetLines.Add('')
    }

    if ($item.RepoNotes.Count -gt 0) {
        $packetLines.Add('## Repo-Specific Notes')
        $packetLines.Add('')
        $packetLines.Add('Apply these considerations throughout the review:')
        $packetLines.Add('')
        foreach ($note in $item.RepoNotes) {
            $packetLines.Add("- $note")
        }
        $packetLines.Add('')
    }

    $packetLines.Add('## Constraints')
    $packetLines.Add('- Preserve technical accuracy')
    $packetLines.Add('- Do not invent implementation details, APIs, commands, or architecture facts')
    $packetLines.Add('- Prefer structural improvements over cosmetic rewrites')
    $packetLines.Add('- Keep changes concise, professional, and reviewable')
    $packetLines.Add('- Use tree diagrams only where they materially improve understanding')
    $packetLines.Add('')

    $packetLines.Add('## Suggested Copilot Prompt')
    $packetLines.Add('')
    $packetLines.Add('```text')
    $packetLines.Add((Get-PromptFlavorText -BatchType $item.BatchType).Trim())
    $packetLines.Add('```')
    $packetLines.Add('')

    Set-Content -LiteralPath $packetPath -Value $packetLines -Encoding UTF8
    $item.PacketPath = $packetPath
}

$jsonPath = Join-Path -Path $outRoot -ChildPath 'doc-review-queue.json'
$csvPath = Join-Path -Path $outRoot -ChildPath 'doc-review-queue.csv'
$playbookPath = Join-Path -Path $outRoot -ChildPath 'doc-review-playbook.md'

$orderedQueue | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$orderedQueue |
    Select-Object `
        QueueId, `
        RepoName, `
        RepoPath, `
        RepoPriorityBand, `
        RepoPriorityScore, `
        BatchType, `
        BatchOrder, `
        BatchChunkIndex, `
        EstimatedComplexity, `
        RecommendedCooldownSeconds, `
        QueueScore, `
        PromptFlavor, `
    @{ Name = 'FileCount'; Expression = { @($_.Files).Count } },
    @{ Name = 'Files'; Expression = { ($_.Files -join '; ') } },
    @{ Name = 'Goals'; Expression = { ($_.Goals -join ' | ') } },
    @{ Name = 'Warnings'; Expression = { ($_.Warnings -join ' | ') } },
    PacketPath |
    Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$playbook = New-Object System.Collections.Generic.List[string]
$playbook.Add('# Documentation Review Queue Playbook')
$playbook.Add('')
$playbook.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$playbook.Add('')
$playbook.Add('## Summary')
$playbook.Add('')
$playbook.Add("- Queue items: $($orderedQueue.Count)")
$playbook.Add("- Repos represented: $((@($orderedQueue | Select-Object -ExpandProperty RepoName -Unique)).Count)")
$playbook.Add("- Core batches: $(($orderedQueue | Where-Object { $_.BatchType -eq 'core' }).Count)")
$playbook.Add("- Operational batches: $(($orderedQueue | Where-Object { $_.BatchType -eq 'operational' }).Count)")
$playbook.Add("- Reference batches: $(($orderedQueue | Where-Object { $_.BatchType -eq 'reference' }).Count)")
$playbook.Add("- General batches: $(($orderedQueue | Where-Object { $_.BatchType -eq 'general' }).Count)")
$playbook.Add("- Archival batches: $(($orderedQueue | Where-Object { $_.BatchType -eq 'archival' }).Count)")
$playbook.Add('')

$repoGroups = $orderedQueue | Group-Object -Property RepoName
foreach ($repoGroup in $repoGroups) {
    $repoQueueItems = @($repoGroup.Group | Sort-Object -Property BatchOrder, BatchChunkIndex)
    $first = $repoQueueItems[0]

    $playbook.Add("## $($repoGroup.Name)")
    $playbook.Add('')
    $playbook.Add("- **Path:** $($first.RepoPath)")
    $playbook.Add("- **Repo Priority:** $($first.RepoPriorityBand) ($($first.RepoPriorityScore))")
    $playbook.Add("- **Queue Items:** $($repoQueueItems.Count)")
    $playbook.Add('')

    foreach ($item in $repoQueueItems) {
        $playbook.Add("### $($item.QueueId)")
        $playbook.Add('')
        $playbook.Add("- **Batch Type:** $($item.BatchType)")
        $playbook.Add("- **Complexity:** $($item.EstimatedComplexity)")
        $playbook.Add("- **Cooldown Hint:** $($item.RecommendedCooldownSeconds) seconds")
        $playbook.Add("- **Prompt Flavor:** $($item.PromptFlavor)")
        $playbook.Add("- **Packet:** $($item.PacketPath)")
        $playbook.Add('')
        $playbook.Add('**Files:**')
        foreach ($file in $item.Files) {
            $playbook.Add("- $file")
        }
        $playbook.Add('')

        if ($item.Warnings.Count -gt 0) {
            $playbook.Add('**Warnings:**')
            foreach ($warning in $item.Warnings) {
                $playbook.Add("- $warning")
            }
            $playbook.Add('')
        }
    }
}

$playbook.Add('')
Set-Content -LiteralPath $playbookPath -Value $playbook -Encoding UTF8

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host "JSON   : $($jsonPath)"
Write-Host "CSV    : $($csvPath)"
Write-Host "MD     : $($playbookPath)"
Write-Host "Packets: $($packetDir)"
Write-Host ''
### END FILE: Build-DocReviewQueue.ps1
