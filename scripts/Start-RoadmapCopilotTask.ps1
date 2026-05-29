[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Repository = "OWNER/REPO",

    [Parameter()]
    [string]$BaseBranch = "",

    [Parameter()]
    [string]$CustomAgent = "",

    [Parameter()]
    [switch]$Follow,

    [Parameter()]
    [switch]$PreviewOnly,

    [Parameter()]
    [string]$HistoryRoot = "",

    [Parameter()]
    [string]$RoadmapPath = "",

    [Parameter()]
    [string[]]$RoadmapPathCandidates = @(
        "ROADMAP.md",
        "Roadmap.md",
        "docs/planning/roadmap.md",
        "docs/ROADMAP.md",
        "roadmap.md"
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-HistoryStore {
    param(
        [Parameter()]
        [string]$RootPath
    )

    $repoRoot = Split-Path -Parent $PSScriptRoot
    $effectiveRoot = $RootPath
    if ([string]::IsNullOrWhiteSpace($effectiveRoot)) {
        $effectiveRoot = Join-Path $repoRoot 'output\roadmap-task-history'
    }

    $runsPath = Join-Path $effectiveRoot 'runs'
    New-Item -ItemType Directory -Path $effectiveRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $runsPath -Force | Out-Null

    $runId = "{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    return [pscustomobject]@{
        RootPath = $effectiveRoot
        RunsPath = $runsPath
        RunId = $runId
        HistoryPath = (Join-Path $effectiveRoot 'history.jsonl')
        RunEventsPath = (Join-Path $runsPath ("{0}.events.jsonl" -f $runId))
        RunSummaryPath = (Join-Path $runsPath ("{0}.summary.json" -f $runId))
    }
}

function Write-HistoryEvent {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Store,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter()]
        [hashtable]$Data = @{}
    )

    $entry = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        runId = $Store.RunId
        type = $Type
        data = $Data
    }

    $line = $entry | ConvertTo-Json -Depth 10 -Compress
    Add-Content -LiteralPath $Store.HistoryPath -Value $line
    Add-Content -LiteralPath $Store.RunEventsPath -Value $line
}

function Test-CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Resolve-GhCommandPath {
    $command = Get-Command -Name 'gh' -ErrorAction SilentlyContinue
    if ($command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
        return $command.Source
    }

    $candidatePaths = @(
        $env:GH_CLI_PATH,
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe' }),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'GitHub CLI\gh.exe' }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe' }),
        $(if ($env:ChocolateyInstall) { Join-Path $env:ChocolateyInstall 'bin\gh.exe' }),
        $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'scoop\shims\gh.exe' })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path -LiteralPath $candidatePath) {
            return $candidatePath
        }
    }

    return $null
}

function Resolve-GitHubToken {
    if (-not [string]::IsNullOrWhiteSpace($env:GitHub_Token)) {
        return $env:GitHub_Token
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        return $env:GITHUB_TOKEN
    }

    throw "GitHub token not found. Set either GitHub_Token or GITHUB_TOKEN in your environment."
}

function Get-LocalRoadmapContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    if ($script:HistoryStore) {
        Write-HistoryEvent -Store $script:HistoryStore -Type 'local_roadmap_read_started' -Data @{
            path = $Path
        }
    }

    $resolvedPath = [string](Resolve-Path -LiteralPath $Path -ErrorAction Stop)
    $text = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8 -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Local roadmap file '$resolvedPath' is empty."
    }

    if ($script:HistoryStore) {
        Write-HistoryEvent -Store $script:HistoryStore -Type 'local_roadmap_read_completed' -Data @{
            path = $resolvedPath
            contentLength = $text.Length
        }
    }

    return [pscustomobject]@{
        Path = $resolvedPath
        Content = $text
    }
}

function Get-GitHubRoadmapContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repo,

        [Parameter(Mandatory = $true)]
        [string[]]$CandidatePaths
    )

    foreach ($candidate in $CandidatePaths) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        try {
            if ($script:HistoryStore) {
                Write-HistoryEvent -Store $script:HistoryStore -Type 'api_call_started' -Data @{
                    operation = 'github.contents.get'
                    candidatePath = $candidate
                    repository = $Repo
                }
            }

            $response = & $script:GhCommandPath api ("repos/{0}/contents/{1}" -f $Repo, $candidate) --jq '{ path: .path, encoding: .encoding, content: .content }' 2>$null | ConvertFrom-Json
            if ($null -eq $response) {
                if ($script:HistoryStore) {
                    Write-HistoryEvent -Store $script:HistoryStore -Type 'api_call_completed' -Data @{
                        operation = 'github.contents.get'
                        candidatePath = $candidate
                        repository = $Repo
                        outcome = 'empty'
                    }
                }
                continue
            }

            if ($response.encoding -ne 'base64' -or [string]::IsNullOrWhiteSpace($response.content)) {
                continue
            }

            $raw = ($response.content -replace "`n", '' -replace "`r", '')
            $bytes = [Convert]::FromBase64String($raw)
            $text = [Text.Encoding]::UTF8.GetString($bytes)

            if (-not [string]::IsNullOrWhiteSpace($text)) {
                if ($script:HistoryStore) {
                    Write-HistoryEvent -Store $script:HistoryStore -Type 'api_call_completed' -Data @{
                        operation = 'github.contents.get'
                        candidatePath = $candidate
                        repository = $Repo
                        outcome = 'success'
                        resolvedPath = [string]$response.path
                        contentLength = $text.Length
                    }
                }
                return [pscustomobject]@{
                    Path = [string]$response.path
                    Content = $text
                }
            }
        }
        catch {
            if ($script:HistoryStore) {
                Write-HistoryEvent -Store $script:HistoryStore -Type 'api_call_completed' -Data @{
                    operation = 'github.contents.get'
                    candidatePath = $candidate
                    repository = $Repo
                    outcome = 'error'
                    error = $_.Exception.Message
                }
            }
            continue
        }
    }

    throw "No roadmap markdown file found in repository '$Repo'. Tried: $($CandidatePaths -join ', ')"
}

function Get-NextRoadmapTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RoadmapContent
    )

    $priorityPatterns = @(
        'active\s*/\s*next',
        'active and next',
        'near-term',
        'near term',
        'must',
        'mid-term',
        'mid term',
        'long-term',
        'long term',
        'technical debt'
    )

    $skipHeadingPatterns = @(
        'operational review process',
        'definition of done',
        '^weekly$',
        '^monthly$',
        '^on every feature merge$'
    )

    $lines = $RoadmapContent -split "`r?`n"
    $currentHeading = ''
    $items = New-Object System.Collections.Generic.List[object]

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]

        if ($line -match '^\s*#{1,6}\s+(.+?)\s*$') {
            $currentHeading = $matches[1].Trim()
            continue
        }

        if ($line -match '^\s*-\s*\[\s\]\s+(.+?)\s*$') {
            $taskText = $matches[1].Trim()
            if ([string]::IsNullOrWhiteSpace($taskText)) {
                continue
            }

            $normalizedHeading = $currentHeading.ToLowerInvariant()
            $skip = $false
            foreach ($pattern in $skipHeadingPatterns) {
                if ($normalizedHeading -match $pattern) {
                    $skip = $true
                    break
                }
            }

            if ($skip) {
                continue
            }

            $priority = 999
            for ($priorityIndex = 0; $priorityIndex -lt $priorityPatterns.Count; $priorityIndex++) {
                if ($normalizedHeading -match $priorityPatterns[$priorityIndex]) {
                    $priority = $priorityIndex
                    break
                }
            }

            $items.Add([pscustomobject]@{
                    TaskText = $taskText
                    Heading = $currentHeading
                    LineNumber = $index + 1
                    Priority = $priority
                })
        }
    }

    if ($items.Count -eq 0) {
        throw "No unchecked roadmap tasks ('- [ ]') were found in eligible roadmap sections."
    }

    $ordered = $items | Sort-Object -Property Priority, LineNumber
    return [pscustomobject]@{
        Next = $ordered[0]
        Additional = @($ordered | Select-Object -Skip 1 -First 3)
    }
}

$historyStore = Initialize-HistoryStore -RootPath $HistoryRoot
$script:HistoryStore = $historyStore
$startedAt = Get-Date

try {
    Write-HistoryEvent -Store $historyStore -Type 'run_started' -Data @{
        repository = $Repository
        baseBranch = $BaseBranch
        customAgent = $CustomAgent
        follow = $Follow.IsPresent
        previewOnly = $PreviewOnly.IsPresent
        roadmapPath = $RoadmapPath
        roadmapPathCandidates = @($RoadmapPathCandidates)
    }

    $resolvedRoadmap = $null
    if (-not [string]::IsNullOrWhiteSpace($RoadmapPath)) {
        $resolvedRoadmap = Get-LocalRoadmapContent -Path $RoadmapPath
    }

    if ($null -eq $resolvedRoadmap) {
        $script:GhCommandPath = Resolve-GhCommandPath
        if ([string]::IsNullOrWhiteSpace($script:GhCommandPath)) {
            throw "GitHub CLI 'gh' was not found. Install GitHub CLI or set GH_CLI_PATH to gh.exe."
        }

        $env:GH_TOKEN = Resolve-GitHubToken

        $candidatePaths = @()
        if (-not [string]::IsNullOrWhiteSpace($RoadmapPath)) {
            $candidatePaths += $RoadmapPath
        }
        $candidatePaths += $RoadmapPathCandidates

        $resolvedRoadmap = Get-GitHubRoadmapContent -Repo $Repository -CandidatePaths $candidatePaths
    }

    $taskSelection = Get-NextRoadmapTask -RoadmapContent $resolvedRoadmap.Content

    $nextTask = $taskSelection.Next
    $additionalTasks = $taskSelection.Additional

    $taskDescription = @(
    "Continue roadmap execution for $Repository.",
    "Roadmap source: $($resolvedRoadmap.Path) (line $($nextTask.LineNumber), section '$($nextTask.Heading)').",
    "Primary task: $($nextTask.TaskText)",
    "",
    "Execution requirements:",
    "1) Verify the most recently completed roadmap entries are truly complete across code, tests, and docs.",
    "2) Implement the primary task end-to-end with production-safe changes.",
    "3) Update docs and roadmap status for completed work.",
    "4) Run the repo's relevant tests/quality gates before finalizing."
    )

    if ($additionalTasks.Count -gt 0) {
    $taskDescription += ""
    $taskDescription += "Follow-up candidates if the primary task is completed in this run:"
    foreach ($candidate in $additionalTasks) {
        $taskDescription += "- $($candidate.TaskText)"
    }
    }

    Write-HistoryEvent -Store $historyStore -Type 'roadmap_selection' -Data @{
        roadmapPath = $resolvedRoadmap.Path
        selectedTask = @{
            heading = $nextTask.Heading
            lineNumber = $nextTask.LineNumber
            text = $nextTask.TaskText
        }
        additionalTaskCount = @($additionalTasks).Count
    }

    $startScriptPath = Join-Path $PSScriptRoot 'Start-GitHubCopilotTask.ps1'
    if (-not (Test-Path -LiteralPath $startScriptPath)) {
        throw "Expected launcher script was not found: $startScriptPath"
    }

    $startParams = @{
        Repository = $Repository
        TaskDescription = ($taskDescription -join "`n")
        HistoryRoot = $historyStore.RootPath
        ParentRunId = $historyStore.RunId
        InitiatedBy = 'roadmap-script'
        RoadmapSourcePath = $resolvedRoadmap.Path
        PrimaryRoadmapTask = $nextTask.TaskText
    }

    if (-not [string]::IsNullOrWhiteSpace($BaseBranch)) {
        $startParams.BaseBranch = $BaseBranch
    }

    if (-not [string]::IsNullOrWhiteSpace($CustomAgent)) {
        $startParams.CustomAgent = $CustomAgent
    }

    if ($Follow.IsPresent) {
        $startParams.Follow = $true
    }

    Write-Host "Roadmap file resolved: $($resolvedRoadmap.Path)"
    Write-Host "Selected next task: $($nextTask.TaskText)"

    if ($PreviewOnly.IsPresent) {
        $previewPayload = [pscustomobject]@{
            runId = $historyStore.RunId
            repository = $Repository
            roadmapPath = $resolvedRoadmap.Path
            selectedTask = [pscustomobject]@{
                heading = $nextTask.Heading
                lineNumber = $nextTask.LineNumber
                text = $nextTask.TaskText
            }
            followUpCandidates = @(
                $additionalTasks | ForEach-Object {
                    [pscustomobject]@{
                        heading = $_.Heading
                        lineNumber = $_.LineNumber
                        text = $_.TaskText
                    }
                }
            )
            generatedTaskDescription = ($taskDescription -join "`n")
            history = [pscustomobject]@{
                rootPath = $historyStore.RootPath
                runEventsPath = $historyStore.RunEventsPath
                runSummaryPath = $historyStore.RunSummaryPath
                historyPath = $historyStore.HistoryPath
            }
        }

        Write-HistoryEvent -Store $historyStore -Type 'preview_generated' -Data @{
            selectedTask = $nextTask.TaskText
            roadmapPath = $resolvedRoadmap.Path
        }

        $summary = [ordered]@{
            runId = $historyStore.RunId
            status = 'preview'
            startedAt = $startedAt.ToString('o')
            completedAt = (Get-Date).ToString('o')
            repository = $Repository
            roadmapPath = $resolvedRoadmap.Path
            selectedTask = $nextTask.TaskText
            historyEventsPath = $historyStore.RunEventsPath
        }
        $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $historyStore.RunSummaryPath
        Write-HistoryEvent -Store $historyStore -Type 'run_completed' -Data @{ status = 'preview'; summaryPath = $historyStore.RunSummaryPath }

        Write-Output ($previewPayload | ConvertTo-Json -Depth 8)
        return
    }

    Write-HistoryEvent -Store $historyStore -Type 'copilot_task_start_requested' -Data @{
        repository = $Repository
        baseBranch = $BaseBranch
        customAgent = $CustomAgent
        follow = $Follow.IsPresent
        launcherScriptPath = $startScriptPath
    }

    & $startScriptPath @startParams

    $summary = [ordered]@{
        runId = $historyStore.RunId
        status = 'started'
        startedAt = $startedAt.ToString('o')
        completedAt = (Get-Date).ToString('o')
        repository = $Repository
        roadmapPath = $resolvedRoadmap.Path
        selectedTask = $nextTask.TaskText
        historyEventsPath = $historyStore.RunEventsPath
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $historyStore.RunSummaryPath
    Write-HistoryEvent -Store $historyStore -Type 'run_completed' -Data @{ status = 'started'; summaryPath = $historyStore.RunSummaryPath }
}
catch {
    $errorMessage = $_.Exception.Message
    if ($historyStore) {
        Write-HistoryEvent -Store $historyStore -Type 'run_failed' -Data @{ error = $errorMessage }
        $summary = [ordered]@{
            runId = $historyStore.RunId
            status = 'failed'
            startedAt = $startedAt.ToString('o')
            completedAt = (Get-Date).ToString('o')
            repository = $Repository
            error = $errorMessage
            historyEventsPath = $historyStore.RunEventsPath
        }
        $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $historyStore.RunSummaryPath
    }
    Write-Output $errorMessage
    exit 1
}
