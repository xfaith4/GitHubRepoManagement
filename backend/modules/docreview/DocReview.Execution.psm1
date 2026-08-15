Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Git utilities (formerly DocReview.Git.psm1)
# ---------------------------------------------------------------------------

function Test-DocReviewGitRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
        return $false
    }

    try {
        $null = (& git -C $RepoPath rev-parse --is-inside-work-tree 2>$null)
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Get-DocReviewWorkingTreeDirtyCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    $output = (& git -C $RepoPath status --porcelain 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect git status for '$RepoPath': $output"
    }

    $lines = @($output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return [int]$lines.Count
}

function Ensure-DocReviewBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,

        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    $null = (& git -C $RepoPath rev-parse --verify --quiet ("refs/heads/{0}" -f $BranchName) 2>&1) | Out-String
    $exists = ($LASTEXITCODE -eq 0)

    if ($exists) {
        $checkoutOutput = (& git -C $RepoPath checkout $BranchName 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to checkout existing branch '$BranchName' in '$RepoPath': $checkoutOutput"
        }
    }
    else {
        $createOutput = (& git -C $RepoPath checkout -b $BranchName 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create branch '$BranchName' in '$RepoPath': $createOutput"
        }
    }
}

# ---------------------------------------------------------------------------
# Path/file validation utilities (formerly DocReview.Validation.psm1)
# ---------------------------------------------------------------------------

function Test-DocReviewPathContainsArchiveOrExample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Files
    )

    $patterns = @(
        '\\archive\\',
        '\\_Archive\\',
        '\\examples\\',
        'run-ui-validate-',
        'ui-auto-validate-'
    )

    foreach ($file in @($Files)) {
        $normalized = ($file ?? '').Replace('/', '\')
        foreach ($pattern in $patterns) {
            if ($normalized -imatch [regex]::Escape($pattern)) {
                return $true
            }
        }
    }

    return $false
}

function Test-DocReviewPacketExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PacketPath
    )

    return (Test-Path -LiteralPath $PacketPath -PathType Leaf)
}

function Get-DocReviewMissingTargetFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Files
    )

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($relativePath in @($Files)) {
        $fullPath = Join-Path -Path $RepoPath -ChildPath $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $missing.Add($relativePath)
        }
    }
    return @($missing)
}

function Get-DocReviewIsoNow {
    return (Get-Date).ToString('o')
}

function Get-DocReviewDefaultConfig {
    return [ordered]@{
        branchPrefix = 'docs/review'
        allowDirtyWorkingTree = $false
        allowOutOfScopeChanges = $false
        allowMissingFilesAtStart = $false
        preferNonArchiveFirst = $true
        deprioritizeExamples = $true
        runMarkdownLint = $true
        runLinkCheck = $false
        openVSCode = $true
        requireApprovalBeforeCommit = $true
        autoCommit = $false
        maxRetries = 2
        defaultCooldownSeconds = 180
    }
}

function Read-DocReviewJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "JSON file is empty: $Path"
    }

    return ($raw | ConvertFrom-Json -Depth 50)
}

function Write-DocReviewJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Data
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }

    ($Data | ConvertTo-Json -Depth 50) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-DocReviewConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $defaults = Get-DocReviewDefaultConfig
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        Write-DocReviewJsonFile -Path $ConfigPath -Data $defaults
        return ([pscustomobject]$defaults)
    }

    $loaded = Read-DocReviewJsonFile -Path $ConfigPath
    foreach ($name in $defaults.Keys) {
        if ($null -eq $loaded.PSObject.Properties[$name]) {
            Add-Member -InputObject $loaded -NotePropertyName $name -NotePropertyValue $defaults[$name]
        }
    }
    return $loaded
}

function Get-QueueFieldValue {
    param(
        [Parameter(Mandatory = $true)] [object]$Item,
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter()] [object]$Default = $null
    )

    if ($Item.PSObject.Properties.Name -contains $Name) {
        return $Item.$Name
    }
    return $Default
}

function New-DocReviewStateItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$QueueItem
    )

    return [ordered]@{
        queueId = [string](Get-QueueFieldValue -Item $QueueItem -Name 'QueueId')
        status = 'pending'
        repoName = [string](Get-QueueFieldValue -Item $QueueItem -Name 'RepoName')
        repoPath = [string](Get-QueueFieldValue -Item $QueueItem -Name 'RepoPath')
        branchName = $null
        attemptCount = 0
        startedAt = $null
        lastUpdatedAt = $null
        completedAt = $null
        runPath = $null
        changedFiles = @()
        outOfScopeFiles = @()
        expectedButUnchanged = @()
        validation = [ordered]@{
            markdownLintPassed = $null
            packetExists = $null
            repoCleanAtStart = $null
            filesExistAtStart = $null
        }
        notes = @()
    }
}

function Get-DocReviewQueueItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$QueuePath
    )

    $loaded = Read-DocReviewJsonFile -Path $QueuePath
    if ($loaded -is [System.Array]) {
        return @($loaded)
    }
    if ($loaded.PSObject.Properties.Name -contains 'items') {
        return @($loaded.items)
    }
    throw "Queue JSON format is unsupported in '$QueuePath'. Expected array or object with 'items'."
}

function Get-DocReviewState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$QueueItems
    )

    $now = Get-DocReviewIsoNow
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        $newState = [ordered]@{
            version = 1
            generatedAt = $now
            items = @($QueueItems | ForEach-Object { [pscustomobject](New-DocReviewStateItem -QueueItem $_) })
        }
        Write-DocReviewJsonFile -Path $StatePath -Data $newState
        return [pscustomobject]$newState
    }

    $state = Read-DocReviewJsonFile -Path $StatePath
    if (-not ($state.PSObject.Properties.Name -contains 'items')) {
        throw "State file '$StatePath' is missing required 'items' property."
    }

    $existingById = @{}
    foreach ($item in @($state.items)) {
        $existingById[[string]$item.queueId] = $item
    }

    foreach ($queueItem in @($QueueItems)) {
        $queueId = [string](Get-QueueFieldValue -Item $queueItem -Name 'QueueId')
        if (-not $existingById.ContainsKey($queueId)) {
            $state.items += [pscustomobject](New-DocReviewStateItem -QueueItem $queueItem)
        }
    }

    return $state
}

function Save-DocReviewState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath,

        [Parameter(Mandatory = $true)]
        [object]$State
    )

    if (-not ($State.PSObject.Properties.Name -contains 'generatedAt')) {
        Add-Member -InputObject $State -NotePropertyName generatedAt -NotePropertyValue (Get-DocReviewIsoNow)
    }
    $State.generatedAt = Get-DocReviewIsoNow
    Write-DocReviewJsonFile -Path $StatePath -Data $State
}

function Get-DocReviewBatchOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$QueueItem
    )

    $batchOrder = Get-QueueFieldValue -Item $QueueItem -Name 'BatchOrder' -Default $null
    if ($null -ne $batchOrder) { return [int]$batchOrder }

    $batchType = [string](Get-QueueFieldValue -Item $QueueItem -Name 'BatchType' -Default '')
    $map = @{
        core = 1
        operational = 2
        reference = 3
        general = 4
        archival = 5
    }
    if ($map.ContainsKey($batchType)) { return [int]$map[$batchType] }
    return 99
}

function Get-DocReviewEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object]$QueueItem,
        [Parameter(Mandatory = $true)] [object]$StateItem,
        [Parameter(Mandatory = $true)] [object]$Config,
        [Parameter()] [switch]$Force
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    $status = [string]$StateItem.status
    $attemptCount = [int]$StateItem.attemptCount
    $maxRetries = [int]$Config.maxRetries

    if ($status -notin @('pending', 'deferred', 'ready_for_prompt')) {
        $reasons.Add("state status '$status' is not start-eligible")
    }
    if ($attemptCount -ge $maxRetries) {
        $reasons.Add("retry exhausted ($attemptCount/$maxRetries)")
    }

    $repoPath = [string](Get-QueueFieldValue -Item $QueueItem -Name 'RepoPath')
    $packetPath = [string](Get-QueueFieldValue -Item $QueueItem -Name 'PacketPath')
    $files = @([string[]](Get-QueueFieldValue -Item $QueueItem -Name 'Files' -Default @()))

    if (-not (Test-Path -LiteralPath $repoPath -PathType Container)) {
        $reasons.Add('repo path does not exist')
    }
    if (-not (Test-DocReviewPacketExists -PacketPath $packetPath)) {
        $reasons.Add('packet path does not exist')
    }
    if (Test-Path -LiteralPath $repoPath -PathType Container) {
        if (-not (Test-DocReviewGitRepo -RepoPath $repoPath)) {
            $reasons.Add('repo is not a valid git worktree')
        }
        if (-not [bool]$Config.allowMissingFilesAtStart) {
            $missingFiles = @(Get-DocReviewMissingTargetFiles -RepoPath $repoPath -Files $files)
            if ($missingFiles.Count -gt 0) {
                $reasons.Add("missing target files: $($missingFiles.Count)")
            }
        }
        if (-not [bool]$Config.allowDirtyWorkingTree -and -not $Force.IsPresent) {
            try {
                $dirtyCount = Get-DocReviewWorkingTreeDirtyCount -RepoPath $repoPath
                if ($dirtyCount -gt 0) {
                    $reasons.Add("working tree is dirty ($dirtyCount)")
                }
            }
            catch {
                $reasons.Add("unable to inspect working tree: $($_.Exception.Message)")
            }
        }
    }

    return [pscustomobject]@{
        eligible = ($reasons.Count -eq 0)
        reasons = @($reasons)
    }
}

function Select-DocReviewNextQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$QueueItems,
        [Parameter(Mandatory = $true)] [object]$State,
        [Parameter(Mandatory = $true)] [object]$Config,
        [Parameter()] [switch]$Force
    )

    $stateById = @{}
    foreach ($stateItem in @($State.items)) {
        $stateById[[string]$stateItem.queueId] = $stateItem
    }

    $eligibleRows = New-Object System.Collections.Generic.List[object]
    foreach ($queueItem in @($QueueItems)) {
        $queueId = [string](Get-QueueFieldValue -Item $queueItem -Name 'QueueId')
        if (-not $stateById.ContainsKey($queueId)) { continue }
        $stateItem = $stateById[$queueId]
        $eligibility = Get-DocReviewEligibility -QueueItem $queueItem -StateItem $stateItem -Config $Config -Force:$Force
        if (-not $eligibility.eligible) { continue }

        $files = @([string[]](Get-QueueFieldValue -Item $queueItem -Name 'Files' -Default @()))
        $containsArchiveOrExample = Test-DocReviewPathContainsArchiveOrExample -Files $files
        $eligibleRows.Add([pscustomobject]@{
            queueItem = $queueItem
            stateItem = $stateItem
            containsArchiveOrExample = $containsArchiveOrExample
            batchOrder = Get-DocReviewBatchOrder -QueueItem $queueItem
            queueScore = [int](Get-QueueFieldValue -Item $queueItem -Name 'QueueScore' -Default 0)
            gitDirty = [int](Get-QueueFieldValue -Item $queueItem -Name 'GitDirty' -Default 0)
            batchChunkIndex = [int](Get-QueueFieldValue -Item $queueItem -Name 'BatchChunkIndex' -Default 0)
        })
    }

    if ($eligibleRows.Count -eq 0) {
        return $null
    }

    $sorted = @($eligibleRows)
    if ([bool]$Config.preferNonArchiveFirst -or [bool]$Config.deprioritizeExamples) {
        $sorted = @($sorted | Sort-Object `
            @{Expression = { if ($_.containsArchiveOrExample) { 1 } else { 0 } }; Ascending = $true}, `
            @{Expression = { $_.batchOrder }; Ascending = $true}, `
            @{Expression = { $_.queueScore }; Descending = $true}, `
            @{Expression = { $_.gitDirty }; Ascending = $true}, `
            @{Expression = { $_.batchChunkIndex }; Ascending = $true}
        )
    }
    else {
        $sorted = @($sorted | Sort-Object `
            @{Expression = { $_.batchOrder }; Ascending = $true}, `
            @{Expression = { $_.queueScore }; Descending = $true}, `
            @{Expression = { $_.gitDirty }; Ascending = $true}, `
            @{Expression = { $_.batchChunkIndex }; Ascending = $true}
        )
    }

    return $sorted[0]
}

function Update-DocReviewStateItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object]$StateItem,
        [Parameter(Mandatory = $true)] [string]$Status,
        [Parameter()] [string]$Note
    )

    $StateItem.status = $Status
    $StateItem.lastUpdatedAt = Get-DocReviewIsoNow
    if ($Note) {
        $notes = @($StateItem.notes)
        $notes += ("[{0}] {1}" -f (Get-DocReviewIsoNow), $Note)
        $StateItem.notes = @($notes)
    }
}

function New-DocReviewRunFolderArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$RunRoot,
        [Parameter(Mandatory = $true)] [object]$QueueItem,
        [Parameter(Mandatory = $true)] [string]$BranchName
    )

    $queueId = [string](Get-QueueFieldValue -Item $QueueItem -Name 'QueueId')
    $repoPath = [string](Get-QueueFieldValue -Item $QueueItem -Name 'RepoPath')
    $packetPath = [string](Get-QueueFieldValue -Item $QueueItem -Name 'PacketPath')

    $dateFolder = (Get-Date).ToString('yyyy-MM-dd')
    $runPath = Join-Path -Path $RunRoot -ChildPath (Join-Path -Path $dateFolder -ChildPath $queueId)
    $null = New-Item -ItemType Directory -Path $runPath -Force

    Copy-Item -LiteralPath $packetPath -Destination (Join-Path $runPath 'packet-snapshot.md') -Force

    $runJson = [ordered]@{
        queueId = $queueId
        repoPath = $repoPath
        branchName = $BranchName
        startedAt = Get-DocReviewIsoNow
        mode = 'Start'
        packetPath = $packetPath
    }
    Write-DocReviewJsonFile -Path (Join-Path $runPath 'run.json') -Data $runJson

    $validationSeed = [ordered]@{
        queueId = $queueId
        generatedAt = Get-DocReviewIsoNow
        checks = [ordered]@{
            packetExists = $true
            repoExists = (Test-Path -LiteralPath $repoPath -PathType Container)
            targetFilesExist = $null
            gitRepoValid = $null
            repoCleanAtStart = $null
        }
    }
    Write-DocReviewJsonFile -Path (Join-Path $runPath 'validation.json') -Data $validationSeed

    $notesPath = Join-Path $runPath 'notes.md'
    if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) {
        Set-Content -LiteralPath $notesPath -Value ("# Notes`n`nQueue: {0}`n" -f $queueId) -Encoding UTF8
    }

    return $runPath
}

function Start-DocReviewQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object]$QueueItem,
        [Parameter(Mandatory = $true)] [object]$StateItem,
        [Parameter(Mandatory = $true)] [object]$Config,
        [Parameter(Mandatory = $true)] [string]$RunRoot,
        [Parameter()] [switch]$Force,
        [Parameter()] [switch]$OpenVSCode
    )

    $queueId = [string](Get-QueueFieldValue -Item $QueueItem -Name 'QueueId')
    $repoName = [string](Get-QueueFieldValue -Item $QueueItem -Name 'RepoName')
    $repoPath = [string](Get-QueueFieldValue -Item $QueueItem -Name 'RepoPath')
    $packetPath = [string](Get-QueueFieldValue -Item $QueueItem -Name 'PacketPath')
    $files = @([string[]](Get-QueueFieldValue -Item $QueueItem -Name 'Files' -Default @()))
    $branchPrefix = [string]$Config.branchPrefix
    $branchName = '{0}/{1}' -f $branchPrefix, $queueId

    $eligibility = Get-DocReviewEligibility -QueueItem $QueueItem -StateItem $StateItem -Config $Config -Force:$Force
    if (-not $eligibility.eligible) {
        $reason = "Queue item '$queueId' is not eligible: $($eligibility.reasons -join '; ')"
        throw $reason
    }

    Ensure-DocReviewBranch -RepoPath $repoPath -BranchName $branchName
    $runPath = New-DocReviewRunFolderArtifacts -RunRoot $RunRoot -QueueItem $QueueItem -BranchName $branchName

    $dirtyCount = Get-DocReviewWorkingTreeDirtyCount -RepoPath $repoPath
    $missingFiles = @(Get-DocReviewMissingTargetFiles -RepoPath $repoPath -Files $files)

    $StateItem.status = 'in_progress'
    $StateItem.attemptCount = [int]$StateItem.attemptCount + 1
    $StateItem.branchName = $branchName
    $StateItem.startedAt = Get-DocReviewIsoNow
    $StateItem.lastUpdatedAt = $StateItem.startedAt
    $StateItem.runPath = $runPath
    $StateItem.validation.packetExists = $true
    $StateItem.validation.filesExistAtStart = ($missingFiles.Count -eq 0)
    $StateItem.validation.repoCleanAtStart = ($dirtyCount -eq 0)
    $StateItem.validation.markdownLintPassed = $null

    $runSummary = [pscustomobject]@{
        queueId = $queueId
        repoName = $repoName
        repoPath = $repoPath
        branchName = $branchName
        runPath = $runPath
        packetPath = $packetPath
        files = @($files)
        warnings = @([string[]](Get-QueueFieldValue -Item $QueueItem -Name 'Warnings' -Default @()))
    }

    if ($OpenVSCode.IsPresent -or [bool]$Config.openVSCode) {
        $codeCmd = Get-Command code -ErrorAction SilentlyContinue
        if ($codeCmd) {
            try {
                & $codeCmd.Source $repoPath | Out-Null
            }
            catch {
                # Non-fatal: operator can open manually.
            }
        }
    }

    return $runSummary
}


function Get-DocReviewWorkItemPromptText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$PacketContent
    )

    $match = [regex]::Match($PacketContent, '## Suggested Copilot Prompt\s+```text\s*(?<prompt>[\s\S]*?)\s*```', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        return ($match.Groups['prompt'].Value).Trim()
    }

    return $PacketContent.Trim()
}

function Publish-DocReviewCopilotWorkItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$QueueItems,
        [Parameter(Mandatory = $true)] [object]$State,
        [Parameter(Mandatory = $true)] [string]$OutputRoot,
        [Parameter()] [int]$PageSize = 25,
        [Parameter()] [int]$PageNumber = 1
    )

    if ($PageSize -lt 1) { throw 'PageSize must be >= 1.' }
    if ($PageNumber -lt 1) { throw 'PageNumber must be >= 1.' }

    $null = New-Item -ItemType Directory -Path $OutputRoot -Force

    $stateById = @{}
    foreach ($stateItem in @($State.items)) {
        $stateById[[string]$stateItem.queueId] = $stateItem
    }

    $eligible = New-Object System.Collections.Generic.List[object]
    foreach ($queueItem in @($QueueItems)) {
        $queueId = [string](Get-QueueFieldValue -Item $queueItem -Name 'QueueId')
        if (-not $stateById.ContainsKey($queueId)) { continue }

        $stateItem = $stateById[$queueId]
        if ([string]$stateItem.status -notin @('pending', 'deferred', 'ready_for_prompt', 'in_progress')) { continue }

        $packetPath = [string](Get-QueueFieldValue -Item $queueItem -Name 'PacketPath')
        if (-not (Test-Path -LiteralPath $packetPath -PathType Leaf)) { continue }

        $eligible.Add([pscustomobject]@{
            queueItem = $queueItem
            stateItem = $stateItem
        })
    }

    $ordered = @($eligible | Sort-Object {
        [int](Get-QueueFieldValue -Item $_.queueItem -Name 'BatchOrder' -Default 999)
    }, {
        -[int](Get-QueueFieldValue -Item $_.queueItem -Name 'QueueScore' -Default 0)
    }, {
        [int](Get-QueueFieldValue -Item $_.queueItem -Name 'BatchChunkIndex' -Default 0)
    })

    $totalEligible = @($ordered).Count
    $pageCount = if ($totalEligible -eq 0) { 0 } else { [int][Math]::Ceiling($totalEligible / [double]$PageSize) }
    $start = ($PageNumber - 1) * $PageSize
    $pageItems = @()
    if ($start -lt $totalEligible) {
        $pageItems = @($ordered | Select-Object -Skip $start -First $PageSize)
    }

    $preparedItems = New-Object System.Collections.Generic.List[object]

    foreach ($entry in @($pageItems)) {
        $queueItem = $entry.queueItem
        $stateItem = $entry.stateItem
        $queueId = [string](Get-QueueFieldValue -Item $queueItem -Name 'QueueId')
        $packetPath = [string](Get-QueueFieldValue -Item $queueItem -Name 'PacketPath')
        $repoPath = [string](Get-QueueFieldValue -Item $queueItem -Name 'RepoPath')
        $files = @([string[]](Get-QueueFieldValue -Item $queueItem -Name 'Files' -Default @()))
        $objectives = @([string[]](Get-QueueFieldValue -Item $queueItem -Name 'Goals' -Default @()))
        $warnings = @([string[]](Get-QueueFieldValue -Item $queueItem -Name 'Warnings' -Default @()))

        $packetContent = Get-Content -LiteralPath $packetPath -Raw -Encoding UTF8
        $promptText = Get-DocReviewWorkItemPromptText -PacketContent $packetContent

        $workItemPath = Join-Path -Path $OutputRoot -ChildPath $queueId
        $null = New-Item -ItemType Directory -Path $workItemPath -Force

        Copy-Item -LiteralPath $packetPath -Destination (Join-Path -Path $workItemPath -ChildPath 'packet.md') -Force
        Set-Content -LiteralPath (Join-Path -Path $workItemPath -ChildPath 'prompt.txt') -Value $promptText -Encoding UTF8

        $instructions = @(
            "# Copilot Workitem: $queueId",
            '',
            "- Repo: $([string](Get-QueueFieldValue -Item $queueItem -Name 'RepoName'))",
            "- Repo Path: $repoPath",
            "- Batch: $([string](Get-QueueFieldValue -Item $queueItem -Name 'BatchType'))",
            "- Queue Score: $([int](Get-QueueFieldValue -Item $queueItem -Name 'QueueScore' -Default 0))",
            '',
            '## Scope files',
            ''
        )
        foreach ($f in $files) {
            $instructions += "- $f"
        }

        if ($objectives.Count -gt 0) {
            $instructions += @('', '## Objectives', '')
            foreach ($goal in $objectives) {
                $instructions += "- $goal"
            }
        }

        if ($warnings.Count -gt 0) {
            $instructions += @('', '## Warnings', '')
            foreach ($warning in $warnings) {
                $instructions += "- $warning"
            }
        }

        $instructions += @('', '## Prompt', '', '```text', $promptText, '```', '')
        Set-Content -LiteralPath (Join-Path -Path $workItemPath -ChildPath 'workitem.md') -Value $instructions -Encoding UTF8

        $workItemJson = [ordered]@{
            queueId = $queueId
            generatedAt = Get-DocReviewIsoNow
            repoName = [string](Get-QueueFieldValue -Item $queueItem -Name 'RepoName')
            repoPath = $repoPath
            batchType = [string](Get-QueueFieldValue -Item $queueItem -Name 'BatchType')
            queueScore = [int](Get-QueueFieldValue -Item $queueItem -Name 'QueueScore' -Default 0)
            packetPath = $packetPath
            promptPath = (Join-Path -Path $workItemPath -ChildPath 'prompt.txt')
            files = @($files)
            objectives = @($objectives)
            warnings = @($warnings)
            stateStatus = [string]$stateItem.status
        }
        Write-DocReviewJsonFile -Path (Join-Path -Path $workItemPath -ChildPath 'workitem.json') -Data $workItemJson

        if ([string]$stateItem.status -eq 'pending') {
            $stateItem.status = 'ready_for_prompt'
            $stateItem.lastUpdatedAt = Get-DocReviewIsoNow
            $notes = @($stateItem.notes)
            $notes += ("[{0}] prompt workitem prepared" -f (Get-DocReviewIsoNow))
            $stateItem.notes = @($notes)
        }

        $preparedItems.Add([pscustomobject]@{
            queueId = $queueId
            workItemPath = $workItemPath
            promptPath = (Join-Path -Path $workItemPath -ChildPath 'prompt.txt')
        })
    }

    $manifest = [ordered]@{
        generatedAt = Get-DocReviewIsoNow
        outputRoot = $OutputRoot
        page = [ordered]@{
            pageNumber = $PageNumber
            pageSize = $PageSize
            pageCount = $pageCount
            totalEligible = $totalEligible
            selectedCount = @($preparedItems).Count
            hasNextPage = ($PageNumber -lt $pageCount)
        }
        items = @($preparedItems)
    }

    Write-DocReviewJsonFile -Path (Join-Path -Path $OutputRoot -ChildPath 'copilot-workitems.json') -Data $manifest

    return [pscustomobject]$manifest
}

function Get-DocReviewStatusReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$QueueItems,
        [Parameter(Mandatory = $true)] [object]$State,
        [Parameter(Mandatory = $true)] [object]$Config
    )

    $stateById = @{}
    foreach ($stateItem in @($State.items)) {
        $stateById[[string]$stateItem.queueId] = $stateItem
    }

    $totals = @{}
    foreach ($stateItem in @($State.items)) {
        $k = [string]$stateItem.status
        if (-not $totals.ContainsKey($k)) { $totals[$k] = 0 }
        $totals[$k]++
    }

    $blockedDirty = New-Object System.Collections.Generic.List[object]
    $retryExhausted = New-Object System.Collections.Generic.List[object]
    foreach ($queueItem in @($QueueItems)) {
        $queueId = [string](Get-QueueFieldValue -Item $queueItem -Name 'QueueId')
        if (-not $stateById.ContainsKey($queueId)) { continue }
        $stateItem = $stateById[$queueId]
        $eligibility = Get-DocReviewEligibility -QueueItem $queueItem -StateItem $stateItem -Config $Config
        foreach ($reason in @($eligibility.reasons)) {
            if ($reason -like 'working tree is dirty*') {
                $blockedDirty.Add([pscustomobject]@{ queueId = $queueId; reason = $reason })
            }
            if ($reason -like 'retry exhausted*') {
                $retryExhausted.Add([pscustomobject]@{ queueId = $queueId; reason = $reason })
            }
        }
    }

    $nextCandidates = New-Object System.Collections.Generic.List[object]
    $sorted = New-Object System.Collections.Generic.List[object]
    foreach ($queueItem in @($QueueItems)) {
        $queueId = [string](Get-QueueFieldValue -Item $queueItem -Name 'QueueId')
        if (-not $stateById.ContainsKey($queueId)) { continue }
        $stateItem = $stateById[$queueId]
        $eligibility = Get-DocReviewEligibility -QueueItem $queueItem -StateItem $stateItem -Config $Config
        if ($eligibility.eligible) {
            $sorted.Add([pscustomobject]@{
                queueId = $queueId
                repoName = [string](Get-QueueFieldValue -Item $queueItem -Name 'RepoName')
                batchType = [string](Get-QueueFieldValue -Item $queueItem -Name 'BatchType')
                queueScore = [int](Get-QueueFieldValue -Item $queueItem -Name 'QueueScore' -Default 0)
                containsArchiveOrExample = Test-DocReviewPathContainsArchiveOrExample -Files @([string[]](Get-QueueFieldValue -Item $queueItem -Name 'Files' -Default @()))
                batchOrder = Get-DocReviewBatchOrder -QueueItem $queueItem
                gitDirty = [int](Get-QueueFieldValue -Item $queueItem -Name 'GitDirty' -Default 0)
                batchChunkIndex = [int](Get-QueueFieldValue -Item $queueItem -Name 'BatchChunkIndex' -Default 0)
            })
        }
    }

    $ordered = @($sorted | Sort-Object `
        @{Expression = { if ($_.containsArchiveOrExample) { 1 } else { 0 } }; Ascending = $true}, `
        @{Expression = { $_.batchOrder }; Ascending = $true}, `
        @{Expression = { $_.queueScore }; Descending = $true}, `
        @{Expression = { $_.gitDirty }; Ascending = $true}, `
        @{Expression = { $_.batchChunkIndex }; Ascending = $true}
    )
    foreach ($candidate in @($ordered | Select-Object -First 10)) {
        $nextCandidates.Add($candidate)
    }

    $inProgress = @($State.items | Where-Object { $_.status -eq 'in_progress' })

    return [pscustomobject]@{
        totals = $totals
        nextEligible = [object[]]($nextCandidates.ToArray())
        blockedDirty = [object[]](@($blockedDirty | Select-Object -First 25))
        retryExhausted = [object[]](@($retryExhausted | Select-Object -First 25))
        inProgress = @($inProgress)
    }
}

function Set-DocReviewItemStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object]$State,
        [Parameter(Mandatory = $true)] [string]$QueueId,
        [Parameter(Mandatory = $true)] [ValidateSet('skipped', 'deferred')] [string]$Status,
        [Parameter(Mandatory = $true)] [string]$Reason
    )

    $target = @($State.items | Where-Object { $_.queueId -eq $QueueId } | Select-Object -First 1)
    if ($target.Count -eq 0) {
        throw "QueueId '$QueueId' not found in state."
    }

    $item = $target[0]
    if ($item.status -eq 'completed') {
        throw "Cannot transition completed item '$QueueId' to '$Status'."
    }

    $item.status = $Status
    $item.lastUpdatedAt = Get-DocReviewIsoNow
    $notes = @($item.notes)
    $notes += ("[{0}] {1}: {2}" -f (Get-DocReviewIsoNow), $Status, $Reason)
    $item.notes = @($notes)
    return $item
}

Export-ModuleMember -Function @(
    'Get-DocReviewConfig',
    'Get-DocReviewQueueItems',
    'Get-DocReviewState',
    'Save-DocReviewState',
    'Select-DocReviewNextQueueItem',
    'Start-DocReviewQueueItem',
    'Update-DocReviewStateItem',
    'Get-DocReviewStatusReport',
    'Set-DocReviewItemStatus',
    'Publish-DocReviewCopilotWorkItems',
    'Get-DocReviewEligibility',
    'Get-QueueFieldValue',
    'Test-DocReviewGitRepo',
    'Get-DocReviewWorkingTreeDirtyCount',
    'Ensure-DocReviewBranch',
    'Test-DocReviewPathContainsArchiveOrExample',
    'Test-DocReviewPacketExists',
    'Get-DocReviewMissingTargetFiles'
)
