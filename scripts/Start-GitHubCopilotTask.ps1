[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Repository = "OWNER/REPO",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TaskDescription = "Update and continue the repository roadmap: verify the latest completed roadmap items are truly complete in code/docs/tests, identify the next uncompleted roadmap tasks, and implement the next coherent task with tests and documentation updates.",

    [Parameter()]
    [string]$BaseBranch = "",

    [Parameter()]
    [string]$CustomAgent = "",

    [Parameter()]
    [switch]$Follow,

    [Parameter()]
    [string]$HistoryRoot = "",

    [Parameter()]
    [string]$ParentRunId = "",

    [Parameter()]
    [string]$InitiatedBy = "direct",

    [Parameter()]
    [string]$RoadmapSourcePath = "",

    [Parameter()]
    [string]$PrimaryRoadmapTask = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Invoke-GhCommand {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Store,

        [Parameter(Mandatory = $true)]
        [string[]]$Args,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter()]
        [switch]$AllowFailure
    )

    Write-HistoryEvent -Store $Store -Type 'api_call_started' -Data @{
        operation = $Operation
        command = $script:GhCommandPath
        args = @($Args)
    }

    $captured = @(& $script:GhCommandPath @Args 2>&1 | Tee-Object -Variable __commandOutput)
    $exitCode = $LASTEXITCODE
    $outputText = ($captured | ForEach-Object { $_.ToString() }) -join "`n"

    Write-HistoryEvent -Store $Store -Type 'api_call_completed' -Data @{
        operation = $Operation
        command = $script:GhCommandPath
        args = @($Args)
        exitCode = $exitCode
        output = $outputText
    }

    if (($exitCode -ne 0) -and (-not $AllowFailure.IsPresent)) {
        throw "gh $Operation failed with exit code $exitCode"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $outputText
        Lines = @($captured)
    }
}

$historyStore = Initialize-HistoryStore -RootPath $HistoryRoot
$startedAt = Get-Date

try {
    Write-HistoryEvent -Store $historyStore -Type 'run_started' -Data @{
        repository = $Repository
        baseBranch = $BaseBranch
        customAgent = $CustomAgent
        follow = $Follow.IsPresent
        initiatedBy = $InitiatedBy
        parentRunId = $ParentRunId
        roadmapSourcePath = $RoadmapSourcePath
        primaryRoadmapTask = $PrimaryRoadmapTask
        taskDescription = $TaskDescription
    }

    $token = $null
    if (-not [string]::IsNullOrWhiteSpace($env:GitHub_Token)) {
        $token = $env:GitHub_Token
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $token = $env:GITHUB_TOKEN
    }

    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "GitHub token not found. Set either GitHub_Token or GITHUB_TOKEN in your environment."
    }

    $script:GhCommandPath = Resolve-GhCommandPath
    if ([string]::IsNullOrWhiteSpace($script:GhCommandPath)) {
        throw "GitHub CLI 'gh' was not found. Install GitHub CLI or set GH_CLI_PATH to gh.exe."
    }

    $env:GH_TOKEN = $token

    $authResult = Invoke-GhCommand -Store $historyStore -Args @('auth', 'status') -Operation 'auth status' -AllowFailure
    if ($authResult.ExitCode -ne 0) {
        Write-Warning "Could not confirm gh auth status cleanly. Continuing with GH_TOKEN-based auth."
    }

    $ghArgs = New-Object System.Collections.Generic.List[string]
    $ghArgs.Add("agent-task")
    $ghArgs.Add("create")
    $ghArgs.Add($TaskDescription)
    $ghArgs.Add("--repo")
    $ghArgs.Add($Repository)

    if (-not [string]::IsNullOrWhiteSpace($BaseBranch)) {
        $ghArgs.Add("--base")
        $ghArgs.Add($BaseBranch)
    }

    if (-not [string]::IsNullOrWhiteSpace($CustomAgent)) {
        $ghArgs.Add("--custom-agent")
        $ghArgs.Add($CustomAgent)
    }

    if ($Follow.IsPresent) {
        $ghArgs.Add("--follow")
    }

    Write-Host "Starting Copilot task in repository: $Repository"
    Write-Host "Task description: $TaskDescription"

    $createResult = Invoke-GhCommand -Store $historyStore -Args @($ghArgs) -Operation 'agent-task create'

    Write-HistoryEvent -Store $historyStore -Type 'copilot_result' -Data @{
        repository = $Repository
        output = $createResult.Output
        follow = $Follow.IsPresent
    }

    $summary = [ordered]@{
        runId = $historyStore.RunId
        status = 'success'
        startedAt = $startedAt.ToString('o')
        completedAt = (Get-Date).ToString('o')
        repository = $Repository
        initiatedBy = $InitiatedBy
        parentRunId = $ParentRunId
        follow = $Follow.IsPresent
        historyEventsPath = $historyStore.RunEventsPath
    }

    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $historyStore.RunSummaryPath
    Write-HistoryEvent -Store $historyStore -Type 'run_completed' -Data @{ status = 'success'; summaryPath = $historyStore.RunSummaryPath }

    Write-Host "History run id: $($historyStore.RunId)"
    Write-Host "History summary: $($historyStore.RunSummaryPath)"
}
catch {
    $errorMessage = $_.Exception.Message

    Write-HistoryEvent -Store $historyStore -Type 'run_failed' -Data @{
        status = 'failed'
        error = $errorMessage
    }

    $summary = [ordered]@{
        runId = $historyStore.RunId
        status = 'failed'
        startedAt = $startedAt.ToString('o')
        completedAt = (Get-Date).ToString('o')
        repository = $Repository
        initiatedBy = $InitiatedBy
        parentRunId = $ParentRunId
        error = $errorMessage
        historyEventsPath = $historyStore.RunEventsPath
    }

    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $historyStore.RunSummaryPath
    throw
}
