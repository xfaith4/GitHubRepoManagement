Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'DocReview.Git.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'DocReview.Validation.psm1') -Force

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

    if ($status -notin @('pending', 'deferred')) {
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
    'Get-DocReviewEligibility',
    'Get-QueueFieldValue'
)
