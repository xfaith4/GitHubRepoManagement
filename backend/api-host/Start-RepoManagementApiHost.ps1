[CmdletBinding()]
param(
    [Parameter()]
    [string]$BindAddress = '127.0.0.1',

    [Parameter()]
    [int]$Port = 7071,

    [Parameter()]
    # Derived from this script's location (backend/api-host -> repo root) rather
    # than a hardcoded drive letter, so the host starts from any clone location
    # (ROADMAP Lane 0.3). The installed service always passes -WorkspaceRoot
    # explicitly; this default is what makes a bare interactive launch work.
    [string]$WorkspaceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [Parameter()]
    [string]$LogPath,

    [Parameter()]
    [string]$ShutdownSignalPath,

    [Parameter()]
    [int]$RequestTimeoutSeconds = 180,

    [Parameter()]
    [int]$ScanRequestTimeoutSeconds = 900,

    # Load every function and setting, then return WITHOUT binding the port or
    # entering the accept loop. The background cache-refresh worker
    # (scripts\Invoke-StatusCacheRefresh.ps1) uses this so its scan runs the
    # host's own code rather than a second implementation that could drift.
    #
    # Dot-sourcing a script with param() assigns those parameters in the
    # CALLER's scope - the defect that cost Release 3.0 its dispatch route
    # (PR #119). The worker therefore passes -WorkspaceRoot and -LogPath through
    # with the values it already holds, so the assignment is a no-op rather than
    # a clobber. The module smoke's dot-source sweep asserts that.
    [Parameter()]
    [switch]$LoadDefinitionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$adapterRoot = Join-Path $WorkspaceRoot 'backend\adapters'
$commonRoot = Join-Path $WorkspaceRoot 'backend\modules\common'
$roadmapModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\roadmap'
$docAuditModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\docaudit'
$executionModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\execution'
. (Join-Path $commonRoot 'Metrics.ps1')
. (Join-Path $adapterRoot 'Adapters.ps1')
. (Join-Path $roadmapModuleRoot 'Roadmap.Parser.ps1')
. (Join-Path $roadmapModuleRoot 'Roadmap.Auditor.ps1')
. (Join-Path $roadmapModuleRoot 'Roadmap.Repairer.ps1')
. (Join-Path $roadmapModuleRoot 'Roadmap.PrSubmitter.ps1')
. (Join-Path $roadmapModuleRoot 'Roadmap.WriteBack.ps1')
. (Join-Path $docAuditModuleRoot 'DocAudit.Scanner.ps1')
. (Join-Path $docAuditModuleRoot 'RepositoryImprovement.Workflow.ps1')
. (Join-Path $executionModuleRoot 'Execution.Ledger.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\auth\GitHubApp.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\auth\SessionAuth.ps1')
$docStdModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\docstandardization'
. (Join-Path $roadmapModuleRoot 'Roadmap.Linter.ps1')
. (Join-Path $roadmapModuleRoot 'MaturityDrift.Monitor.ps1')
. (Join-Path $roadmapModuleRoot 'Roadmap.DependencyTracker.ps1')
. (Join-Path $roadmapModuleRoot 'Roadmap.Evaluator.ps1')
. (Join-Path $roadmapModuleRoot 'Roadmap.Dispatcher.ps1')
$gitModuleRoot    = Join-Path $WorkspaceRoot 'backend\modules\git'
. (Join-Path $gitModuleRoot 'Git.StatusDetail.ps1')
. (Join-Path $gitModuleRoot 'Git.Staleness.ps1')
. (Join-Path $gitModuleRoot 'Git.BaseFreshness.ps1')
# Release 3.4 — must load AFTER Git.BaseFreshness.ps1: Sync-RepoDefaultBranch
# calls Get-RepoBaseFreshness through Get-Command, so an unloaded freshness
# module degrades the sync to "unverifiable" rather than failing loudly.
. (Join-Path $gitModuleRoot 'Git.DefaultBranchSync.ps1')
# Release 3.4 milestone 5 — branch cleanup with proof of the merge it follows.
. (Join-Path $gitModuleRoot 'Git.BranchCleanup.ps1')
$readmeModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\readme'
. (Join-Path $readmeModuleRoot 'Readme.Generator.ps1')
. (Join-Path $docStdModuleRoot 'DocStandardization.Previewer.ps1')
$portfolioModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\portfolio'
. (Join-Path $portfolioModuleRoot 'Portfolio.ValueScorer.ps1')
. (Join-Path $portfolioModuleRoot 'Portfolio.Assessment.ps1')
. (Join-Path $portfolioModuleRoot 'Portfolio.Analytics.ps1')
. (Join-Path $portfolioModuleRoot 'Portfolio.Report.ps1')
. (Join-Path $portfolioModuleRoot 'Portfolio.Curation.ps1')
$aiModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\ai'
. (Join-Path $aiModuleRoot 'AiDocImprovement.ps1')
$automationModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\automation'
. (Join-Path $automationModuleRoot 'Automation.DocRefinement.ps1')
. (Join-Path $automationModuleRoot 'Automation.RoadmapPackaging.ps1')
. (Join-Path $automationModuleRoot 'Automation.RunnerPresence.ps1')
# The roadmap-queue contract, loaded here with every other library rather than
# mid-request. Dot-sourcing runs the target in the CALLER'S scope and assigns
# its `param()` variables there, so the dispatch route's old in-route
# dot-source of `scripts\Add-RoadmapTaskToQueue.ps1` blanked its own `$runId`
# and `$baseBranch`. Everything on this list is a param-less library; the
# module smoke asserts that over this file's source.
. (Join-Path $automationModuleRoot 'Automation.RoadmapQueue.ps1')
# Absent-owner memory for the GitHub sweep. Loaded here, with every other
# param-less library, for the same reason the queue contract above is.
$githubModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\github'
. (Join-Path $githubModuleRoot 'GitHub.OwnerCache.ps1')
$agentRunsModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\agent-runs'
. (Join-Path $agentRunsModuleRoot 'BudgetLedger.ps1')
. (Join-Path $agentRunsModuleRoot 'AgentRuns.ps1')
. (Join-Path $agentRunsModuleRoot 'MergeReadiness.ps1')
# Release 3.1 — the work-item trace joins the stage ledgers above, so it loads
# after all of them (packaging, agent runs, merge readiness).
. (Join-Path $executionModuleRoot 'Execution.Trace.ps1')
$persistenceModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\persistence'
. (Join-Path $persistenceModuleRoot 'Persistence.Store.ps1')
. (Join-Path $commonRoot 'NotificationHub.ps1')
. (Join-Path $PSScriptRoot 'ApiHost.ErrorHandling.ps1')
. (Join-Path $PSScriptRoot 'RequestDeadline.ps1')
. (Join-Path $PSScriptRoot 'GitHubRateLimit.ps1')
. (Join-Path $PSScriptRoot 'OperationHeartbeat.ps1')
. (Join-Path $PSScriptRoot 'PerformanceBudget.ps1')

$script:StatusCacheMemory = @{}
$script:StatusCacheDefaultTtlSeconds = 120
$script:StatusCacheSchemaVersion = 4

$script:RoadmapCacheMemory = @{}
$script:RoadmapCacheDefaultTtlSeconds = 300

$script:DocAuditCacheMemory = @{}
$script:DocAuditCacheDefaultTtlSeconds = 300

$script:RoadmapAuditCacheMemory = @{}
$script:RoadmapAuditCacheDefaultTtlSeconds = 300

$script:PortfolioAssessmentCacheMemory = @{}
$script:PortfolioAssessmentCacheDefaultTtlSeconds = 180
$script:ClientIoTimeoutMs = 15000
$script:RequestTimeoutSeconds = Get-EffectiveRequestTimeoutSeconds `
    -ConfiguredSeconds $RequestTimeoutSeconds `
    -EnvironmentValue ([System.Environment]::GetEnvironmentVariable('REPO_MGMT_REQUEST_TIMEOUT_SECONDS'))
# Cold full-portfolio scans legitimately outrun the ordinary deadline, so the
# scan routes get their own (still bounded) tier instead of an exemption.
$script:ScanRequestTimeoutSeconds = Get-EffectiveScanRequestTimeoutSeconds `
    -ConfiguredSeconds $ScanRequestTimeoutSeconds `
    -EnvironmentValue ([System.Environment]::GetEnvironmentVariable('REPO_MGMT_SCAN_REQUEST_TIMEOUT_SECONDS')) `
    -BaseSeconds $script:RequestTimeoutSeconds
$script:RequestDeadlineController = $null

$script:RoadmapRepairHistoryRoot   = Join-Path $WorkspaceRoot 'output\roadmap-repair-history'
$script:RepoEvaluationHistoryRoot  = Join-Path $WorkspaceRoot 'output\repo-evaluations'

# Release 1.3 — production static frontend bundle path
$script:FrontendDistPath = Join-Path $WorkspaceRoot 'frontend\dist'

# Structured operations log (JSONL) — dashboard /api/log/tail reads this
$script:OpsLogPath       = $null
$script:OpsLogWriteCount = 0
$script:OpsLogMaxLines   = 5000    # default; overridden from retention.maxOpsLogLines

# Release 2.7 Phase D — last app.db maintenance result, surfaced by
# GET /api/maintenance/database so an operator can see whether the scheduled
# prune is actually running rather than only that it is configured.
$script:LastDbMaintenance = $null

# Auto-scan shared state — thread-safe; written by background runspace, read by main loop
$script:AutoScanState = [hashtable]::Synchronized(@{
    Enabled             = $false
    IntervalMinutes     = 0
    NextScanAt          = [datetime]::MaxValue
    LastScanAt          = $null
    PendingInvalidation = $false
})

try {
    $opsLogDir = Join-Path $WorkspaceRoot 'backend\modules\output\logs'
    if (-not (Test-Path -LiteralPath $opsLogDir)) {
        $null = New-Item -ItemType Directory -Path $opsLogDir -Force
    }
    $script:OpsLogPath = Join-Path $opsLogDir 'operations.jsonl'
} catch { }

function Write-HostLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    if ($LogPath) {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
    # Also write structured JSONL for the dashboard log tail endpoint
    if ($script:OpsLogPath) {
        try {
            $lvl = if ($Message -match '^ERROR|FAIL|\[ERR\]')   { 'ERROR' }
                   elseif ($Message -match '^WARN|\[WARN\]')     { 'WARN'  }
                   elseif ($Message -match '^\[TRACE\]')         { 'TRACE' }
                   else                                           { 'INFO'  }
            $entry = '{"ts":"{0}","level":"{1}","msg":{2}}' -f `
                (Get-Date).ToUniversalTime().ToString('o'), $lvl,
                ($Message | ConvertTo-Json -Compress)
            Add-Content -LiteralPath $script:OpsLogPath -Value $entry -Encoding UTF8

            $dbLog = Write-AppDbOpsLogEntry -Level $lvl -Source 'api-host' -Message $Message
            if (-not $dbLog.success -and $dbLog.reason -ne 'app-db-not-initialized') {
                Write-Verbose ("Write-HostLog: app-db ops log mirror skipped: {0}" -f $dbLog.reason)
            }

            $script:OpsLogWriteCount++
            if ($script:OpsLogWriteCount % 250 -eq 0) {
                Invoke-TrimOpsLog -MaxLines $script:OpsLogMaxLines
            }
        } catch { }
    }
}

# Trim operations.jsonl to at most $MaxLines lines, keeping the most recent entries.
function Invoke-TrimOpsLog {
    param([int]$MaxLines = 5000)
    if (-not $script:OpsLogPath) { return }
    if (-not (Test-Path -LiteralPath $script:OpsLogPath)) { return }
    try {
        $allLines = [System.IO.File]::ReadAllLines($script:OpsLogPath)
        if ($allLines.Count -le $MaxLines) { return }
        $kept = $allLines[($allLines.Count - $MaxLines)..($allLines.Count - 1)]
        [System.IO.File]::WriteAllLines($script:OpsLogPath, $kept, [System.Text.Encoding]::UTF8)
    } catch { }

    try {
        $dbTrim = Invoke-AppDbOpsLogTrim -MaxRows $MaxLines
        if (-not $dbTrim.success -and $dbTrim.reason -ne 'app-db-not-initialized') {
            Write-Verbose ("Invoke-TrimOpsLog: app-db trim skipped: {0}" -f $dbTrim.reason)
        }
    } catch { }
}

function Parse-Bool {
    param([object]$Value, [bool]$Default = $false)
    if ($null -eq $Value) { return $Default }
    $text = [string]$Value
    return $text -match '^(1|true|yes|on)$'
}

function Get-ListeningProcessIds {
    param(
        [Parameter(Mandatory = $true)]
        [int]$LocalPort
    )

    $processIds = @()

    $getNetTcpConnection = Get-Command -Name 'Get-NetTCPConnection' -ErrorAction SilentlyContinue
    if ($getNetTcpConnection) {
        try {
            $connections = @(Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction Stop)
            if ($connections.Count -gt 0) {
                return @($connections | Select-Object -ExpandProperty OwningProcess -Unique)
            }
        } catch { }
    }

    $ssCommand = Get-Command -Name 'ss' -ErrorAction SilentlyContinue
    if ($ssCommand) {
        foreach ($line in @(ss -ltnpH "sport = :$LocalPort" 2>$null)) {
            foreach ($match in [regex]::Matches($line, 'pid=(\d+)')) {
                $processIds += [int]$match.Groups[1].Value
            }
        }

        if ($processIds.Count -gt 0) {
            return @($processIds | Sort-Object -Unique)
        }
    }

    $netstatCommand = Get-Command -Name 'netstat' -ErrorAction SilentlyContinue
    if (-not $netstatCommand) {
        return @()
    }

    foreach ($line in @(netstat -ano -p tcp 2>$null)) {
        $trimmed = $line.Trim()
        if ($trimmed -notmatch '^TCP\s+') { continue }

        $parts = $trimmed -split '\s+'
        if ($parts.Count -lt 5) { continue }
        if ($parts[3] -ne 'LISTENING') { continue }

        $localAddress = $parts[1]
        $separatorIndex = $localAddress.LastIndexOf(':')
        if ($separatorIndex -lt 0) { continue }

        $portText = $localAddress.Substring($separatorIndex + 1)
        if ($portText -ne [string]$LocalPort) { continue }

        if ($parts[4] -match '^\d+$') {
            $processIds += [int]$parts[4]
        }
    }

    return @($processIds | Sort-Object -Unique)
}

function Stop-PortListeners {
    param(
        [Parameter(Mandatory = $true)]
        [int]$LocalPort
    )

    $listenerPids = @(Get-ListeningProcessIds -LocalPort $LocalPort | Where-Object { $_ -gt 0 -and $_ -ne $PID } | Sort-Object -Unique)
    if ($listenerPids.Count -eq 0) {
        return
    }

    foreach ($listenerPid in $listenerPids) {
        $processLabel = "PID $listenerPid"
        try {
            $process = Get-Process -Id $listenerPid -ErrorAction Stop
            $processLabel = "$($process.ProcessName) (PID $listenerPid)"
        } catch { }

        Write-HostLog "Port $LocalPort is already in use by $processLabel. Terminating it before startup."

        try {
            Stop-Process -Id $listenerPid -Force -ErrorAction Stop
        } catch {
            throw "Port $LocalPort is already in use by $processLabel and it could not be terminated. $($_.Exception.Message)"
        }

        $released = $false
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            Start-Sleep -Milliseconds 250
            $remaining = @(Get-ListeningProcessIds -LocalPort $LocalPort | Where-Object { $_ -eq $listenerPid })
            if ($remaining.Count -eq 0) {
                $released = $true
                break
            }
        }

        if (-not $released) {
            throw "Terminated $processLabel, but port $LocalPort is still reported as in use."
        }

        Write-HostLog "Released port $LocalPort from $processLabel."
    }
}

function Get-ValueOrDefault {
    param(
        [Parameter()]
        [object]$Value,
        [Parameter()]
        [object]$Default = $null
    )

    if ($null -ne $Value) {
        return $Value
    }

    return $Default
}

function Get-ObjectPropertyValue {
    param(
        [Parameter()]
        [object]$InputObject,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName,
        [Parameter()]
        [object]$Default = $null
    )

    if ($null -eq $InputObject) {
        return $Default
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($PropertyName)) {
            return Get-ValueOrDefault $InputObject[$PropertyName] $Default
        }

        return $Default
    }

    if ($null -ne $InputObject.PSObject -and ($InputObject.PSObject.Properties.Name -contains $PropertyName)) {
        return Get-ValueOrDefault $InputObject.$PropertyName $Default
    }

    return $Default
}

function Get-OperationsRepoId {
    param(
        [Parameter()]
        [object]$Repo
    )

    # Identity must stay stable across scans so operator-authored state
    # (curation) keyed by repoId survives new commits and metadata churn.
    # The scan fingerprint hashes volatile signals (head SHA, dirty counts,
    # doc mtimes), so it is only the last resort before a random id.
    $localPath = [string](Get-ObjectPropertyValue -InputObject $Repo -PropertyName 'localPath' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($localPath)) {
        return ('path:{0}' -f $localPath.ToLowerInvariant())
    }

    $githubFullName = [string](Get-ObjectPropertyValue -InputObject $Repo -PropertyName 'githubFullName' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($githubFullName)) {
        return ('gh:{0}' -f $githubFullName.ToLowerInvariant())
    }

    $repoName = [string](Get-ObjectPropertyValue -InputObject $Repo -PropertyName 'repoName' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($repoName)) {
        return ('repo:{0}' -f $repoName.ToLowerInvariant())
    }

    $scanFingerprint = [string](Get-ObjectPropertyValue -InputObject $Repo -PropertyName 'scanFingerprint' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($scanFingerprint)) {
        return $scanFingerprint
    }

    return [guid]::NewGuid().Guid
}

function Get-OperationsReposPayload {
    param(
        [Parameter()]
        [hashtable]$Settings = $null
    )

    if ($null -eq $Settings) {
        $Settings = Get-HostSettings
    }

    $indexPayload = Get-PortfolioIndexPayload -WorkspaceRoot $WorkspaceRoot
    $entries = @()
    $generatedAt = ''
    $summary = $null
    $count = 0
    $cacheSource = ''

    if ($null -ne $indexPayload -and ($indexPayload.PSObject.Properties.Name -contains 'repos')) {
        $entries = @(
            @($indexPayload.repos) | ForEach-Object {
                $repo = $_
                $repoId = [string](Get-ObjectPropertyValue -InputObject $repo -PropertyName 'repoId' -Default '')
                if ([string]::IsNullOrWhiteSpace($repoId)) {
                    $repoId = Get-OperationsRepoId -Repo $repo
                    $repo | Add-Member -NotePropertyName repoId -NotePropertyValue $repoId -Force
                }
                $repo
            }
        )
        $generatedAt = [string](Get-ObjectPropertyValue -InputObject $indexPayload -PropertyName 'generatedAt' -Default '')
        $summary = Get-ObjectPropertyValue -InputObject $indexPayload -PropertyName 'summary' -Default $null
        $count = [int](Get-ObjectPropertyValue -InputObject $indexPayload -PropertyName 'repoCount' -Default @($entries).Count)
        $cacheSource = 'portfolio-index'
    }
    else {
        $ttlSeconds = Get-PortfolioAssessmentCacheTtlSeconds -Settings $Settings
        $assessmentCache = if ($ttlSeconds -gt 0) {
            Get-PortfolioAssessmentFromCache -TtlSeconds $ttlSeconds
        }
        else {
            $null
        }

        if ($null -ne $assessmentCache -and $assessmentCache.hit) {
            $fallbackPayload = New-PortfolioIndexPayload `
                -Assessments $assessmentCache.entries `
                -Summary $assessmentCache.summary `
                -SignalSources $assessmentCache.signalSources `
                -GeneratedAt $assessmentCache.generatedAt
            $entries = @(
                @($fallbackPayload.repos) | ForEach-Object {
                    $repo = $_
                    $repoId = [string](Get-ObjectPropertyValue -InputObject $repo -PropertyName 'repoId' -Default '')
                    if ([string]::IsNullOrWhiteSpace($repoId)) {
                        $repoId = Get-OperationsRepoId -Repo $repo
                        $repo | Add-Member -NotePropertyName repoId -NotePropertyValue $repoId -Force
                    }
                    $repo
                }
            )
            $generatedAt = [string](Get-ObjectPropertyValue -InputObject $fallbackPayload -PropertyName 'generatedAt' -Default '')
            $summary = Get-ObjectPropertyValue -InputObject $fallbackPayload -PropertyName 'summary' -Default $null
            $count = [int](Get-ObjectPropertyValue -InputObject $fallbackPayload -PropertyName 'repoCount' -Default @($entries).Count)
            $cacheSource = 'assessment-cache'
        }
    }

    if ([string]::IsNullOrWhiteSpace($cacheSource)) {
        return [pscustomobject]@{
            available = $false
            error = 'Operations workspace is not ready yet. Run /api/portfolio/assessment first to build the indexed portfolio.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($generatedAt)) {
        $generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    }

    $curationMap = Get-PortfolioCurationMap -WorkspaceRoot $WorkspaceRoot
    $entries = Apply-PortfolioCurationToEntries -Entries @($entries) -CurationMap $curationMap

    return [pscustomobject]@{
        available = $true
        entries = @($entries)
        generatedAt = $generatedAt
        summary = $summary
        count = $count
        cacheSource = $cacheSource
    }
}

function Add-PortfolioCurationToAssessments {
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Assessments = @()
    )

    $curationMap = Get-PortfolioCurationMap -WorkspaceRoot $WorkspaceRoot
    foreach ($assessment in @($Assessments)) {
        if ($null -eq $assessment) { continue }

        $repoId = [string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'repoId' -Default '')
        if ([string]::IsNullOrWhiteSpace($repoId)) {
            # Assessments carry htmlUrl rather than githubFullName; derive the
            # owner/repo pair from it so GitHub-only entries key identically to
            # index rows (gh:owner/repo) instead of falling to repo:name.
            $githubFullName = ''
            $htmlUrl = [string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'htmlUrl' -Default '')
            if ($htmlUrl -match '(?i)github\.com/([^/]+)/([^/?#]+)') {
                $githubFullName = ('{0}/{1}' -f $Matches[1], ($Matches[2] -replace '\.git$', ''))
            }
            $repoId = Get-PortfolioRepoId `
                -LocalPath ([string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'localPath' -Default '')) `
                -GitHubFullName $githubFullName `
                -RepoName ([string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'repoName' -Default ''))
            $assessment | Add-Member -NotePropertyName repoId -NotePropertyValue $repoId -Force
        }

        $curation = if ($curationMap.ContainsKey($repoId)) { $curationMap[$repoId] } else { $null }
        $state = if ($null -ne $curation) { [string]$curation.curationState } else { 'none' }
        if (-not (Test-ValidCurationState -CurationState $state)) { $state = 'none' }
        $assessment | Add-Member -NotePropertyName curationState -NotePropertyValue $state -Force
        $assessment | Add-Member -NotePropertyName curationUpdatedAt -NotePropertyValue $(if ($null -ne $curation) { [string]$curation.updatedAt } else { $null }) -Force
    }

    return ,@($Assessments)
}

function Update-PortfolioIndexRepoCuration {
    param(
        [Parameter(Mandatory = $true)][string]$RepoId,
        [Parameter(Mandatory = $true)][string]$CurationState,
        [Parameter(Mandatory = $true)][string]$UpdatedAt
    )

    $payload = Get-PortfolioIndexPayload -WorkspaceRoot $WorkspaceRoot
    if ($null -eq $payload -or -not ($payload.PSObject.Properties.Name -contains 'repos')) {
        return $false
    }

    $updated = $false
    foreach ($repo in @($payload.repos)) {
        if ($null -eq $repo) { continue }
        $candidateRepoId = [string](Get-OperationsRepoId -Repo $repo)
        if ($candidateRepoId -ne $RepoId) { continue }

        $repo | Add-Member -NotePropertyName curationState -NotePropertyValue $CurationState -Force
        $repo | Add-Member -NotePropertyName curationUpdatedAt -NotePropertyValue $UpdatedAt -Force
        $updated = $true
        break
    }

    if (-not $updated) { return $false }

    try {
        $indexPath = Join-Path (Join-Path $WorkspaceRoot 'output\index') 'repos.index.json'
        $json = $payload | ConvertTo-Json -Depth 12
        Set-Content -LiteralPath $indexPath -Value $json -Encoding UTF8
        return $true
    } catch {
        Write-HostLog ("WARN operations.curation index mirror failed: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Get-PortfolioTrendSeedPayload {
    param(
        [Parameter()]
        [hashtable]$Settings = $null
    )

    if ($null -eq $Settings) {
        $Settings = Get-HostSettings
    }

    $indexPayload = Get-PortfolioIndexPayload -WorkspaceRoot $WorkspaceRoot
    if ($null -ne $indexPayload -and ($indexPayload.PSObject.Properties.Name -contains 'repos')) {
        $generatedAt = [string](Get-ObjectPropertyValue -InputObject $indexPayload -PropertyName 'generatedAt' -Default '')
        if ([string]::IsNullOrWhiteSpace($generatedAt)) {
            $generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        }

        return [pscustomobject]@{
            available   = $true
            entries     = @(Convert-PortfolioIndexReposToAssessments -IndexRepos @($indexPayload.repos))
            summary     = Get-ObjectPropertyValue -InputObject $indexPayload -PropertyName 'summary' -Default $null
            generatedAt = $generatedAt
            seedSource  = 'portfolio-index'
        }
    }

    $ttlSeconds = Get-PortfolioAssessmentCacheTtlSeconds -Settings $Settings
    $assessmentCache = if ($ttlSeconds -gt 0) {
        Get-PortfolioAssessmentFromCache -TtlSeconds $ttlSeconds
    } else {
        $null
    }

    if ($null -ne $assessmentCache -and $assessmentCache.hit) {
        return [pscustomobject]@{
            available   = $true
            entries     = @($assessmentCache.entries)
            summary     = $assessmentCache.summary
            generatedAt = [string]$assessmentCache.generatedAt
            seedSource  = 'assessment-cache'
        }
    }

    return [pscustomobject]@{
        available = $false
        error = 'Portfolio trend analytics are not ready yet. Run /api/portfolio/assessment first so the dashboard has a warm assessment or persisted index snapshot.'
    }
}

function Resolve-OperationsRepoRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoId
    )

    $settings = Get-HostSettings
    $opsPayload = Get-OperationsReposPayload -Settings $settings
    if (-not $opsPayload.available) {
        return [pscustomobject]@{ found = $false; statusCode = 409; error = $opsPayload.error; record = $null }
    }

    $matchedRecords = @($opsPayload.entries | Where-Object {
        $candidateRepoId = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoId' -Default '')
        $candidateRepoName = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')
        $candidateLocalPath = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'localPath' -Default '')
        $candidateGithubFullName = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'githubFullName' -Default '')
        $candidateRepoId -eq $RepoId -or
        $candidateRepoName -eq $RepoId -or
        $candidateLocalPath -eq $RepoId -or
        $candidateGithubFullName -eq $RepoId
    } | Select-Object -First 1)

    if ($matchedRecords.Count -eq 0 -or $null -eq $matchedRecords[0]) {
        return [pscustomobject]@{ found = $false; statusCode = 404; error = "No operations repo record found for repoId '$RepoId'."; record = $null }
    }

    return [pscustomobject]@{ found = $true; statusCode = 200; error = $null; record = $matchedRecords[0] }
}

# Release 2.0 Phase 3: build a fresh merge-readiness evaluation for one
# operations repo record — latest agent run, live PR mergeability and
# Actions state from GitHub when the run has a PR, local dirty count, and
# unresolved assessment blockers — and persist it as the repo's snapshot.
function Invoke-MergeReadinessForRepo {
    param(
        [Parameter(Mandatory = $true)]
        [object]$RepoRecord,
        [Parameter(Mandatory = $true)]
        [string]$RepoId,
        [Parameter()]
        [string]$CorrelationId = ''
    )

    $repoName = [string](Get-ObjectPropertyValue -InputObject $RepoRecord -PropertyName 'repoName' -Default '')
    $latestRun = $null
    $runs = @(Get-AgentRuns -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -Limit 1)
    if ($runs.Count -gt 0) { $latestRun = $runs[0] }

    $prDetail = $null
    $freshActions = $null
    if ($null -ne $latestRun) {
        $githubRepo = [string](Get-ObjectPropertyValue -InputObject $latestRun -PropertyName 'githubRepo' -Default '')
        $prNumber = Get-ObjectPropertyValue -InputObject $latestRun -PropertyName 'prNumber' -Default $null
        $runBranch = [string](Get-ObjectPropertyValue -InputObject $latestRun -PropertyName 'branch' -Default '')
        $repoParts = $githubRepo -split '/'
        if ($repoParts.Count -eq 2 -and $null -ne $prNumber) {
            $settings = Get-HostSettings
            $token = Get-ConfiguredGitHubToken -Settings $settings
            $headers = Get-GitHubApiHeaders -Token $token
            try {
                $prUri = "https://api.github.com/repos/$($repoParts[0])/$($repoParts[1])/pulls/$([int]$prNumber)"
                $prDetail = Invoke-RestMethod -Uri $prUri -Headers $headers -Method Get
            } catch {
                Write-HostLog ("[WARN ] merge-readiness correlationId={0} repoId={1} PR detail lookup failed: {2}" -f $CorrelationId, $RepoId, $_.Exception.Message)
                return [pscustomobject]@{ success = $false; statusCode = 502; error = "GitHub PR lookup failed for ${githubRepo}: $($_.Exception.Message)"; evaluation = $null }
            }

            if (-not [string]::IsNullOrWhiteSpace($runBranch)) {
                $workflowRun = Get-LatestGitHubWorkflowRunViaApi -Owner $repoParts[0] -Repo $repoParts[1] -Headers $headers -Branch $runBranch
                if ($null -ne $workflowRun) {
                    $freshActions = [pscustomobject]@{
                        status       = [string]$workflowRun.status
                        conclusion   = [string]$workflowRun.conclusion
                        workflowName = [string]$workflowRun.name
                        runUrl       = [string]$workflowRun.runUrl
                        observedAt   = (Get-Date).ToUniversalTime().ToString('o')
                    }
                }
            }
        }
    }

    $dirtyCount = [int](Get-ObjectPropertyValue -InputObject $RepoRecord -PropertyName 'localDirtyCount' -Default 0)
    if ($dirtyCount -le 0) {
        $dirtyCount = [int](Get-ObjectPropertyValue -InputObject $RepoRecord -PropertyName 'localModifiedCount' -Default 0) +
            [int](Get-ObjectPropertyValue -InputObject $RepoRecord -PropertyName 'localUntrackedCount' -Default 0)
    }
    $auditBlockers = @(Get-ObjectPropertyValue -InputObject $RepoRecord -PropertyName 'blockingReasons' -Default @() | ForEach-Object { [string]$_ })

    $evaluation = Get-MergeReadinessEvaluation -RepoId $RepoId -RepoName $repoName `
        -AgentRun $latestRun -PrDetail $prDetail -ActionsState $freshActions `
        -LocalDirtyCount $dirtyCount -AuditBlockers $auditBlockers
    $null = Save-MergeReadinessSnapshot -WorkspaceRoot $WorkspaceRoot -Evaluation $evaluation

    $dbSnapshot = Write-AppDbMergeReadinessSnapshot -Evaluation $evaluation
    if (-not $dbSnapshot.success -and $dbSnapshot.reason -ne 'app-db-not-initialized') {
        Write-HostLog ("[WARN ] merge-readiness correlationId={0} repoId={1} sqlite snapshot skipped: {2}" -f $CorrelationId, $RepoId, $dbSnapshot.reason)
    }

    return [pscustomobject]@{ success = $true; statusCode = 200; error = $null; evaluation = $evaluation }
}

function Resolve-WriteBackPullRequestDetail {
    <#
    .SYNOPSIS
        Release 3.1 — read the work item's pull request live from GitHub.
    .DESCRIPTION
        Write-back needs a merge commit, and no stored artifact in this repo
        records one: the merge-readiness snapshot knows `prState` but not the
        commit, so a snapshot alone can only ever yield `merge-unverified`.
        The PR url carries both halves of the slug and the number, so it is the
        join key rather than the agent-run record, which the packaging path may
        not have at all.

        Returns $null on any failure — a missing PR detail must produce a
        refusal from the gate, never an optimistic pass.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PrUrl,
        [Parameter()][string]$CorrelationId = ''
    )

    if ([string]::IsNullOrWhiteSpace($PrUrl)) { return $null }
    $m = [regex]::Match($PrUrl, '^https?://github\.com/([^/]+)/([^/]+)/pull/(\d+)')
    if (-not $m.Success) {
        Write-HostLog ("[WARN ] roadmap.write-back correlationId={0} unrecognized PR url '{1}'" -f $CorrelationId, $PrUrl)
        return $null
    }

    $token = Get-ConfiguredGitHubToken -Settings (Get-HostSettings)
    try {
        $uri = "https://api.github.com/repos/$($m.Groups[1].Value)/$($m.Groups[2].Value)/pulls/$($m.Groups[3].Value)"
        return (Invoke-RestMethod -Uri $uri -Headers (Get-GitHubApiHeaders -Token $token) -Method Get)
    } catch {
        Write-HostLog ("[WARN ] roadmap.write-back correlationId={0} PR lookup failed for {1}: {2}" -f $CorrelationId, $PrUrl, $_.Exception.Message)
        return $null
    }
}

function Resolve-WriteBackContext {
    <#
    .SYNOPSIS
        Release 3.1 — everything both write-back routes need, gathered once.
    .DESCRIPTION
        Preview and apply must agree on the item, the roadmap file and the
        evidence, and apply must re-derive all of it rather than trust what the
        preview returned. Sharing this resolver is what makes "apply re-runs
        the gate" true rather than a comment.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter()][AllowEmptyString()][string]$ItemTextOverride = '',
        [Parameter()][AllowEmptyString()][string]$RoadmapPathOverride = '',
        [Parameter()][string]$CorrelationId = ''
    )

    $trace = Get-WorkItemTrace -WorkspaceRoot $WorkspaceRoot -Id $Id
    if ($null -eq $trace) {
        return [pscustomobject]@{
            ok = $false; statusCode = 404; category = 'work-item-not-found'
            error = "No work item matches id '$Id'. Accepted ids: packetId, packaging runId, dispatch runId, or agent-run id."
        }
    }

    $repoName = [string](Get-ValueOrDefault $trace.identity.repoName '')
    $itemText = if (-not [string]::IsNullOrWhiteSpace($ItemTextOverride)) { $ItemTextOverride } else { [string](Get-ValueOrDefault $trace.identity.itemText '') }

    # The roadmap index only covers the configured localRoots, so an explicit
    # path has to win — the same reason submit-pr accepts one.
    $roadmapPath = if (-not [string]::IsNullOrWhiteSpace($RoadmapPathOverride)) { $RoadmapPathOverride } else { [string](Get-ValueOrDefault $trace.identity.roadmapPath '') }
    if ([string]::IsNullOrWhiteSpace($roadmapPath) -and -not [string]::IsNullOrWhiteSpace($repoName)) {
        $cache = Get-RoadmapFromCache -TtlSeconds (Get-RoadmapCacheTtlSeconds -Settings (Get-HostSettings))
        if ($cache.hit -and $cache.entries) {
            $entry = @($cache.entries) | Where-Object { [string](if ($_ -is [System.Collections.IDictionary]) { $_['repoName'] } else { $_.repoName }) -eq $repoName } | Select-Object -First 1
            if ($null -ne $entry) {
                $roadmapPath = [string](if ($entry -is [System.Collections.IDictionary]) { Get-ValueOrDefault $entry['roadmapPath'] '' } else { Get-ValueOrDefault $entry.roadmapPath '' })
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($roadmapPath) -or -not (Test-Path -LiteralPath $roadmapPath -PathType Leaf)) {
        return [pscustomobject]@{
            ok = $false; statusCode = 409; category = 'roadmap-not-found'
            error = "No roadmap file could be resolved for '$repoName'. Run a roadmap scan, or pass roadmapPath explicitly."
            trace = $trace
        }
    }

    # Re-read the PR live; the snapshot cannot carry a merge commit.
    $prUrl = [string](Get-ValueOrDefault $trace.identity.prUrl '')
    $prDetail = Resolve-WriteBackPullRequestDetail -PrUrl $prUrl -CorrelationId $CorrelationId

    $repoId = [string](Get-ValueOrDefault $trace.identity.repoId '')
    $snapshot = if (-not [string]::IsNullOrWhiteSpace($repoId)) { Get-MergeReadinessSnapshot -WorkspaceRoot $WorkspaceRoot -RepoId $repoId } else { $null }

    $agentRunId = [string](Get-ValueOrDefault $trace.identity.agentRunId '')
    $agentRun = if (-not [string]::IsNullOrWhiteSpace($agentRunId)) { Get-AgentRunDetail -WorkspaceRoot $WorkspaceRoot -RunId $agentRunId } else { $null }

    $dispatchRunId = [string](Get-ValueOrDefault $trace.identity.dispatchRunId '')
    $runSummary = $null
    if (-not [string]::IsNullOrWhiteSpace($dispatchRunId)) {
        $summaryPath = Join-Path $WorkspaceRoot ("output\roadmap-task-history\runs\{0}.summary.json" -f $dispatchRunId)
        if (Test-Path -LiteralPath $summaryPath -PathType Leaf) {
            try { $runSummary = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8) } catch { $runSummary = $null }
        }
    }

    $evidence = Get-RoadmapWriteBackEvidence -PrDetail $prDetail -MergeReadiness $snapshot -AgentRun $agentRun -RunSummary $runSummary
    $gate = Test-RoadmapWriteBackEvidence -Evidence $evidence -ItemText $itemText

    return [pscustomobject]@{
        ok            = $true
        statusCode    = 200
        trace         = $trace
        repoName      = $repoName
        itemText      = $itemText
        roadmapPath   = $roadmapPath
        dispatchRunId = $dispatchRunId
        packetId      = [string](Get-ValueOrDefault $trace.identity.packetId '')
        evidence      = $evidence
        gate          = $gate
    }
}

function Send-HttpJson {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,
        [Parameter(Mandatory = $true)]
        [object]$Payload,
        [Parameter()]
        [string]$StatusText = 'OK',
        [Parameter()]
        [string]$CorrelationId,
        [Parameter()]
        [string[]]$ExtraHeaders = @()
    )

    $json = $Payload | ConvertTo-Json -Depth 12
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    try { $Stream.WriteTimeout = $script:ClientIoTimeoutMs } catch { }

    $headerLines = [System.Collections.Generic.List[string]]::new()
    $headerLines.Add("HTTP/1.1 $StatusCode $StatusText")
    $headerLines.Add('Content-Type: application/json; charset=utf-8')
    $headerLines.Add("Content-Length: $($bodyBytes.Length)")
    $headerLines.Add('Connection: close')
    $headerLines.Add("Access-Control-Allow-Origin: {0}" -f $(if ($script:CorsAllowOrigin) { $script:CorsAllowOrigin } else { '*' }))
    $headerLines.Add('Access-Control-Allow-Methods: GET, POST, OPTIONS')
    $headerLines.Add('Access-Control-Allow-Headers: Content-Type, Authorization, X-Api-Key')
    $headerLines.Add('Access-Control-Allow-Credentials: true')
    foreach ($h in $ExtraHeaders) { if (-not [string]::IsNullOrWhiteSpace($h)) { $headerLines.Add($h) } }
    if ($CorrelationId) { $headerLines.Add("X-Correlation-Id: $CorrelationId") }
    $headerLines.Add('')
    $headerLines.Add('')
    $headers = $headerLines -join "`r`n"

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
    $Stream.Flush()
}

function Send-HttpContent {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,
        [Parameter(Mandatory = $true)]
        [byte[]]$BodyBytes,
        [Parameter()]
        [string]$ContentType = 'application/octet-stream',
        [Parameter()]
        [string]$StatusText = 'OK',
        [Parameter()]
        [string]$CorrelationId
    )

    $headers = @(
        "HTTP/1.1 $StatusCode $StatusText",
        "Content-Type: $ContentType",
        "Content-Length: $($BodyBytes.Length)",
        'Connection: close',
        ("Access-Control-Allow-Origin: {0}" -f $(if ($script:CorsAllowOrigin) { $script:CorsAllowOrigin } else { '*' })),
        'Access-Control-Allow-Methods: GET, POST, OPTIONS',
        'Access-Control-Allow-Headers: Content-Type, Authorization, X-Api-Key',
        $(if ($CorrelationId) { "X-Correlation-Id: $CorrelationId" } else { '' }),
        '',
        ''
    ) -join "`r`n"

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($BodyBytes, 0, $BodyBytes.Length)
    $Stream.Flush()
}

<#
.SYNOPSIS
    Serve a file from the built frontend dist/ directory (Release 1.3).
.DESCRIPTION
    Reads the file at $FilePath, detects MIME type, sets Cache-Control, optionally
    compresses with gzip when the client accepts it and the file is larger than 1 KB.
#>
function Send-StaticFile {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter()]
        [hashtable]$RequestHeaders = @{},

        [Parameter()]
        [string]$CorrelationId = ''
    )

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    $contentType = switch ($ext) {
        '.html'  { 'text/html; charset=utf-8' }
        '.js'    { 'application/javascript; charset=utf-8' }
        '.mjs'   { 'application/javascript; charset=utf-8' }
        '.css'   { 'text/css; charset=utf-8' }
        '.json'  { 'application/json; charset=utf-8' }
        '.svg'   { 'image/svg+xml' }
        '.png'   { 'image/png' }
        '.jpg'   { 'image/jpeg' }
        '.jpeg'  { 'image/jpeg' }
        '.gif'   { 'image/gif' }
        '.ico'   { 'image/x-icon' }
        '.woff'  { 'font/woff' }
        '.woff2' { 'font/woff2' }
        '.ttf'   { 'font/ttf' }
        '.map'   { 'application/json' }
        '.txt'   { 'text/plain; charset=utf-8' }
        '.xml'   { 'application/xml' }
        '.webmanifest' { 'application/manifest+json; charset=utf-8' }
        default  { 'application/octet-stream' }
    }

    # Cache-Control: Vite emits assets with 8-char base64url hashes in the
    # filename (e.g. index-BxA1c2D3.js). The base64url alphabet includes '-',
    # so the hash itself may contain dashes (e.g. index-BbNsaX-S.js) — the
    # character class must allow them or those assets fall back to no-cache.
    # Hashed assets are immutable — cache for 1 year. index.html and anything
    # else: no-cache. Require the file to live in an assets/ directory so
    # dash-heavy unhashed names (e.g. fonts copied from public/) are not
    # mistaken for hashed output.
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $inAssetsDir = (Split-Path -Path $FilePath -Parent) -match '[\\/]assets$'
    $isHashedAsset = $inAssetsDir -and $baseName -match '-[A-Za-z0-9_-]{8,}$' -and $ext -ne '.html'
    $cacheControl = if ($isHashedAsset) { 'public, max-age=31536000, immutable' } else { 'no-cache, no-store, must-revalidate' }

    $bodyBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $useGzip = $false

    if ($bodyBytes.Length -gt 1024) {
        $acceptEncoding = if ($RequestHeaders.ContainsKey('accept-encoding')) { $RequestHeaders['accept-encoding'] } else { '' }
        if ($acceptEncoding -like '*gzip*') {
            try {
                $ms = New-Object System.IO.MemoryStream
                $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress, $true)
                $gz.Write($bodyBytes, 0, $bodyBytes.Length)
                $gz.Close()
                $bodyBytes = $ms.ToArray()
                $useGzip = $true
            } catch {
                # Compression failed — serve uncompressed
                $bodyBytes = [System.IO.File]::ReadAllBytes($FilePath)
                $useGzip = $false
            }
        }
    }

    $headerLines = [System.Collections.Generic.List[string]]::new()
    $headerLines.Add('HTTP/1.1 200 OK')
    $headerLines.Add("Content-Type: $contentType")
    $headerLines.Add("Content-Length: $($bodyBytes.Length)")
    $headerLines.Add("Cache-Control: $cacheControl")
    $headerLines.Add('Connection: close')
    $headerLines.Add('Access-Control-Allow-Origin: *')
    $headerLines.Add('Access-Control-Allow-Methods: GET, POST, OPTIONS')
    $headerLines.Add('Access-Control-Allow-Headers: Content-Type, Authorization')
    if ($useGzip) {
        $headerLines.Add('Content-Encoding: gzip')
        $headerLines.Add('Vary: Accept-Encoding')
    }
    if ($CorrelationId) { $headerLines.Add("X-Correlation-Id: $CorrelationId") }
    $headerLines.Add('')
    $headerLines.Add('')

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headerLines -join "`r`n")
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
    $Stream.Flush()
}

function Send-ErrorJson {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        [Parameter(Mandatory = $true)]
        [string]$CorrelationId,
        [Parameter()]
        [string]$Operation = 'api.request'
    )

    Add-MetricCounter -Name 'api_requests_total'
    Add-MetricCounter -Name 'operation_failures_total'
    Send-HttpJson -Stream $Stream -StatusCode $StatusCode -StatusText 'Error' -CorrelationId $CorrelationId -Payload @{
        operation = $Operation
        correlationId = $CorrelationId
        success = $false
        timestamp = (Get-Date).ToString('o')
        error = @{
            category = Get-ErrorCategory -Message $ErrorMessage
            message = $ErrorMessage
        }
    }
}

function Read-HttpRequest {
    param(
        [System.Net.Sockets.TcpClient]$Client,
        # Release 2.2 TLS: when the accept loop has already wrapped the raw
        # NetworkStream in an SslStream, it is passed here so the request is
        # read (and the response written) over the encrypted stream.
        [System.IO.Stream]$Stream
    )

    $stream = if ($null -ne $Stream) { $Stream } else { $Client.GetStream() }
    try {
        $stream.ReadTimeout = $script:ClientIoTimeoutMs
        $stream.WriteTimeout = $script:ClientIoTimeoutMs
    } catch { }
    # Latin-1 (ISO-8859-1), not ASCII: it is the only single-byte encoding with a
    # lossless 1:1 byte<->char mapping for all 256 values, so the reader stays
    # byte-exact while Content-Length (a BYTE count) still matches the char count
    # ReadBlock expects. A UTF-8 reader would decode multi-byte sequences into
    # fewer chars than Content-Length, and ReadBlock would then block waiting for
    # bytes that never arrive. The body is re-decoded as UTF-8 below.
    #
    # ASCII silently replaced every non-ASCII byte with '?', so any JSON body
    # containing an em-dash, arrow, or accented character was corrupted before a
    # route ever saw it — one em-dash (3 UTF-8 bytes) arrived as '???'. Found
    # 2026-08-09 when the Phase A live submit-PR opened a PR that mangled every
    # '—' in ROADMAP.md.
    $requestReaderEncoding = [System.Text.Encoding]::GetEncoding(28591)
    $reader = New-Object System.IO.StreamReader($stream, $requestReaderEncoding, $false, 4096, $true)

    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) {
        return $null
    }

    $parts = $requestLine.Split(' ')
    if ($parts.Count -lt 2) {
        return $null
    }

    $method = $parts[0].ToUpperInvariant()
    $target = $parts[1]

    $headers = @{}
    while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq '') { break }
        $idx = $line.IndexOf(':')
        if ($idx -gt 0) {
            $key = $line.Substring(0, $idx).Trim().ToLowerInvariant()
            $value = $line.Substring($idx + 1).Trim()
            $headers[$key] = $value
        }
    }

    $body = ''
    $contentLength = 0
    if ($headers.ContainsKey('content-length')) {
        [void][int]::TryParse($headers['content-length'], [ref]$contentLength)
    }

    # Cap body reads to 10 MB to prevent memory exhaustion from malicious requests
    $script:MaxRequestBodyBytes = 10 * 1024 * 1024
    if ($contentLength -gt $script:MaxRequestBodyBytes) {
        return $null
    }

    if ($contentLength -gt 0) {
        $buffer = New-Object char[] $contentLength
        $read = $reader.ReadBlock($buffer, 0, $contentLength)
        $body = -join $buffer[0..($read - 1)]
        # Recover the original bytes from the byte-exact Latin-1 chars, then
        # decode them as UTF-8 — what an application/json body actually is.
        $body = [System.Text.Encoding]::UTF8.GetString($requestReaderEncoding.GetBytes($body))
    }

    $uriObj = [System.Uri]("http://localhost$target")

    return [pscustomobject]@{
        Method = $method
        Target = $target
        Path = $uriObj.AbsolutePath.TrimEnd('/')
        Query = $uriObj.Query.TrimStart('?')
        Headers = $headers
        Body = $body
        Stream = $stream
    }
}

function Test-ShutdownRequested {
    if ([string]::IsNullOrWhiteSpace($ShutdownSignalPath)) {
        return $false
    }

    return (Test-Path -LiteralPath $ShutdownSignalPath)
}

function Get-NextTcpClient {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.Sockets.TcpListener]$Listener,
        [Parameter()]
        [int]$PollMilliseconds = 100
    )

    if ([string]::IsNullOrWhiteSpace($ShutdownSignalPath)) {
        return $Listener.AcceptTcpClient()
    }

    while ($true) {
        if (Test-ShutdownRequested) {
            return $null
        }

        if ($Listener.Pending()) {
            return $Listener.AcceptTcpClient()
        }

        Start-Sleep -Milliseconds $PollMilliseconds
    }
}

function Parse-QueryString {
    param([string]$Query)
    $result = @{}
    if ([string]::IsNullOrWhiteSpace($Query)) { return $result }
    foreach ($pair in $Query -split '&') {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $kv = $pair -split '=', 2
        $k = [System.Uri]::UnescapeDataString($kv[0])
        $v = if ($kv.Count -gt 1) { [System.Uri]::UnescapeDataString($kv[1]) } else { '' }
        $result[$k] = $v
    }
    return $result
}

function Parse-JsonBody {
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return @{} }
    return ConvertFrom-JsonCompat -Json $Body
}

function ConvertTo-HashtableRecursive {
    param([Parameter(Mandatory = $true)][AllowNull()][object]$InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-HashtableRecursive -InputObject $InputObject[$key]
        }
        return $hash
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += ConvertTo-HashtableRecursive -InputObject $item
        }
        return ,$list
    }

    if ($InputObject -is [pscustomobject]) {
        $hash = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $hash[$prop.Name] = ConvertTo-HashtableRecursive -InputObject $prop.Value
        }
        return $hash
    }

    return $InputObject
}

function ConvertFrom-JsonCompat {
    param([Parameter(Mandatory = $true)][string]$Json)

    $obj = ConvertFrom-Json -InputObject $Json
    return ConvertTo-HashtableRecursive -InputObject $obj
}

function Get-ReportsRootPath {
    $reportsRoot = Join-Path $WorkspaceRoot 'reports'
    if (-not (Test-Path -LiteralPath $reportsRoot)) {
        $null = New-Item -ItemType Directory -Path $reportsRoot -Force
    }
    return $reportsRoot
}

function Get-ConfiguredLocalRootsOrWorkspace {
    param([hashtable]$Settings)

    # Use separate declaration + assignment to prevent PowerShell from unwrapping
    # a single-element array when the if/else block is used as an expression on the RHS.
    [string[]]$configuredRoots = @()
    if ($Settings.ContainsKey('inventory') -and $Settings.inventory.ContainsKey('localRoots') -and $Settings.inventory.localRoots) {
        $configuredRoots = @($Settings.inventory.localRoots | ForEach-Object { [string]$_ })
    }

    $validRoots = @($configuredRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) })
    if ($validRoots.Count -gt 0) {
        return $validRoots
    }

    return @($WorkspaceRoot)
}

function ConvertTo-HtmlEncodedText {
    param([object]$Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function New-RepoStatusCsvContent {
    param([object[]]$Repos)

    $rows = @('Repository,Branch,Status,LastCommitDate,LastCommitAuthor,OpenPrCount,CommitsLastWeek,CommitsLastMonth,UncommittedChanges,Archived,Stale,Owner,Visibility,Language,LocalPath,HtmlUrl')
    foreach ($repo in @($Repos)) {
        $values = @(
            [string](Get-ObjectPropertyValue $repo 'name' ''),
            [string](Get-ObjectPropertyValue $repo 'branch' ''),
            [string](Get-ObjectPropertyValue $repo 'status' ''),
            [string](Get-ObjectPropertyValue $repo 'lastCommitDate' ''),
            [string](Get-ObjectPropertyValue $repo 'lastCommitAuthor' ''),
            [string](Get-ObjectPropertyValue $repo 'openPrCount' 0),
            [string](Get-ObjectPropertyValue $repo 'commitsLastWeek' 0),
            [string](Get-ObjectPropertyValue $repo 'commitsLastMonth' 0),
            [string](Get-ObjectPropertyValue $repo 'uncommittedChanges' 0),
            [string]([bool](Get-ObjectPropertyValue $repo 'isArchived' $false)),
            [string]([bool](Get-ObjectPropertyValue $repo 'isStale' $false)),
            [string](Get-ObjectPropertyValue $repo 'owner' ''),
            [string](Get-ObjectPropertyValue $repo 'visibility' ''),
            [string](Get-ObjectPropertyValue $repo 'language' ''),
            [string](Get-ValueOrDefault (Get-ObjectPropertyValue $repo 'localPath' (Get-ObjectPropertyValue $repo 'path' '')) ''),
            [string](Get-ObjectPropertyValue $repo 'htmlUrl' '')
        ) | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' }

        $rows += ($values -join ',')
    }

    return ($rows -join "`r`n")
}

function New-RepoStatusHtmlContent {
    param(
        [object[]]$Repos,
        [string]$SourceLabel,
        [datetime]$GeneratedAt
    )

    $repoList = @($Repos)
    $repoCount = $repoList.Count
    $dirtyCount = @($repoList | Where-Object { [int](Get-ValueOrDefault $_.uncommittedChanges 0) -gt 0 -or [string](Get-ValueOrDefault $_.status '') -eq 'dirty' }).Count
    $archivedCount = @($repoList | Where-Object { [bool](Get-ValueOrDefault $_.isArchived $false) }).Count
    $staleCount = @($repoList | Where-Object { [bool](Get-ValueOrDefault $_.isStale $false) }).Count
    $openPrTotal = ($repoList | Measure-Object -Property openPrCount -Sum).Sum
    $weeklyCommitTotal = ($repoList | Measure-Object -Property commitsLastWeek -Sum).Sum
    $monthlyCommitTotal = ($repoList | Measure-Object -Property commitsLastMonth -Sum).Sum
    $generatedDisplay = $GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss')
    $sourceDisplay = if ([string]::IsNullOrWhiteSpace($SourceLabel)) { 'Repository dashboard export' } else { $SourceLabel }

    $rowMarkup = foreach ($repo in $repoList) {
        $name = ConvertTo-HtmlEncodedText (Get-ValueOrDefault $repo.name 'unknown')
        $branch = ConvertTo-HtmlEncodedText (Get-ValueOrDefault $repo.branch '')
        $statusRaw = [string](Get-ValueOrDefault $repo.status 'unknown')
        $status = ConvertTo-HtmlEncodedText $statusRaw
        $statusClass = switch ($statusRaw.ToLowerInvariant()) {
            'dirty' { 'warn' }
            'ahead' { 'accent' }
            'behind' { 'warn' }
            'diverged' { 'danger' }
            default { 'ok' }
        }
        $lastCommitDate = ConvertTo-HtmlEncodedText (Get-ObjectPropertyValue $repo 'lastCommitDate' '')
        $lastCommitAuthor = ConvertTo-HtmlEncodedText (Get-ObjectPropertyValue $repo 'lastCommitAuthor' '')
        $owner = ConvertTo-HtmlEncodedText (Get-ObjectPropertyValue $repo 'owner' '')
        $visibility = ConvertTo-HtmlEncodedText (Get-ObjectPropertyValue $repo 'visibility' '')
        $language = ConvertTo-HtmlEncodedText (Get-ObjectPropertyValue $repo 'language' '')
        $topics = @(Get-ObjectPropertyValue $repo 'topics' @())
        $topicMarkup = if ($topics.Count -gt 0) {
            ($topics | Select-Object -First 4 | ForEach-Object { "<span class=""chip"">$(ConvertTo-HtmlEncodedText $_)</span>" }) -join ''
        }
        else {
            '<span class="muted">No topics</span>'
        }
        $pathValue = [string](Get-ValueOrDefault (Get-ObjectPropertyValue $repo 'localPath' (Get-ObjectPropertyValue $repo 'path' '')) '')
        $pathMarkup = if (-not [string]::IsNullOrWhiteSpace($pathValue)) {
            "<div class=""meta-line""><span class=""meta-label"">Path</span><code>$(ConvertTo-HtmlEncodedText $pathValue)</code></div>"
        }
        else {
            ''
        }
        $htmlUrlValue = [string](Get-ObjectPropertyValue $repo 'htmlUrl' '')
        $htmlLinkMarkup = if (-not [string]::IsNullOrWhiteSpace($htmlUrlValue)) {
            "<div class=""meta-line""><span class=""meta-label"">Remote</span><a href=""$(ConvertTo-HtmlEncodedText $htmlUrlValue)"" target=""_blank"" rel=""noreferrer"">$(ConvertTo-HtmlEncodedText $htmlUrlValue)</a></div>"
        }
        else {
            '<div class="meta-line"><span class="meta-label">Remote</span><span class="muted">n/a</span></div>'
        }

@"
          <tr>
            <td>
              <div class="repo-name">$name</div>
              <div class="repo-meta">
                <span>$owner</span>
                <span>$visibility</span>
                <span>$language</span>
              </div>
              <div class="chip-row">$topicMarkup</div>
            </td>
            <td><code>$branch</code></td>
            <td><span class="badge $statusClass">$status</span></td>
            <td>
              <div>$lastCommitDate</div>
              <div class="muted">$lastCommitAuthor</div>
            </td>
            <td class="numeric">$([int](Get-ValueOrDefault $repo.openPrCount 0))</td>
            <td class="numeric">$([int](Get-ValueOrDefault $repo.commitsLastWeek 0))</td>
            <td class="numeric">$([int](Get-ValueOrDefault $repo.commitsLastMonth 0))</td>
            <td class="numeric">$([int](Get-ValueOrDefault $repo.uncommittedChanges 0))</td>
            <td>
              $pathMarkup
              $htmlLinkMarkup
            </td>
          </tr>
"@
    }

    if (@($rowMarkup).Count -eq 0) {
        $rowMarkup = @'
          <tr>
            <td colspan="9" class="empty-state">No repositories were included in this export.</td>
          </tr>
'@
    }

@"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Repository Report - $generatedDisplay</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #08111f;
      --panel: rgba(10, 24, 45, 0.82);
      --panel-strong: #0d1e36;
      --line: rgba(142, 169, 197, 0.22);
      --text: #e7eef7;
      --muted: #97a8bc;
      --accent: #34d399;
      --accent-strong: #10b981;
      --warn: #f59e0b;
      --danger: #f97316;
      --shadow: 0 24px 60px rgba(0, 0, 0, 0.35);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif;
      background:
        radial-gradient(circle at top left, rgba(52, 211, 153, 0.18), transparent 28%),
        radial-gradient(circle at top right, rgba(59, 130, 246, 0.18), transparent 32%),
        linear-gradient(180deg, #09101d 0%, #08111f 52%, #050a12 100%);
      color: var(--text);
      min-height: 100vh;
    }
    .shell {
      width: min(1400px, calc(100% - 32px));
      margin: 32px auto;
      padding: 24px;
      border: 1px solid var(--line);
      border-radius: 28px;
      background: var(--panel);
      backdrop-filter: blur(18px);
      box-shadow: var(--shadow);
    }
    .hero {
      display: grid;
      gap: 20px;
      grid-template-columns: 1.5fr 1fr;
      align-items: end;
      margin-bottom: 28px;
    }
    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 12px;
      border-radius: 999px;
      background: rgba(52, 211, 153, 0.12);
      color: #b6f4df;
      font-size: 12px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    h1 {
      margin: 14px 0 10px;
      font-size: clamp(32px, 4vw, 54px);
      line-height: 1;
    }
    .lede {
      margin: 0;
      color: var(--muted);
      max-width: 70ch;
      line-height: 1.6;
    }
    .meta-card {
      padding: 20px;
      border-radius: 22px;
      background: linear-gradient(180deg, rgba(13, 30, 54, 0.94), rgba(8, 17, 31, 0.94));
      border: 1px solid var(--line);
    }
    .meta-card strong {
      display: block;
      margin-bottom: 8px;
      font-size: 14px;
      color: #bcd0e8;
      letter-spacing: 0.06em;
      text-transform: uppercase;
    }
    .meta-card span {
      display: block;
      color: var(--text);
      line-height: 1.6;
      word-break: break-word;
    }
    .stats {
      display: grid;
      gap: 14px;
      grid-template-columns: repeat(6, minmax(0, 1fr));
      margin-bottom: 24px;
    }
    .stat {
      padding: 18px;
      border-radius: 20px;
      border: 1px solid var(--line);
      background: rgba(255, 255, 255, 0.03);
    }
    .stat .label {
      display: block;
      margin-bottom: 12px;
      color: var(--muted);
      font-size: 12px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    .stat .value {
      display: block;
      font-size: clamp(24px, 3vw, 34px);
      font-weight: 700;
    }
    .table-shell {
      overflow: hidden;
      border-radius: 24px;
      border: 1px solid var(--line);
      background: rgba(4, 10, 20, 0.55);
    }
    table {
      width: 100%;
      border-collapse: collapse;
    }
    thead th {
      text-align: left;
      font-size: 12px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: #a9bdd3;
      background: rgba(13, 30, 54, 0.94);
      padding: 16px 18px;
      border-bottom: 1px solid var(--line);
      position: sticky;
      top: 0;
    }
    tbody td {
      padding: 16px 18px;
      border-bottom: 1px solid rgba(142, 169, 197, 0.12);
      vertical-align: top;
    }
    tbody tr:hover {
      background: rgba(255, 255, 255, 0.03);
    }
    .repo-name {
      font-size: 16px;
      font-weight: 700;
      margin-bottom: 6px;
    }
    .repo-meta, .chip-row, .meta-line {
      display: flex;
      flex-wrap: wrap;
      gap: 8px 10px;
      align-items: center;
    }
    .repo-meta {
      color: var(--muted);
      font-size: 13px;
      margin-bottom: 8px;
    }
    .chip {
      display: inline-flex;
      align-items: center;
      padding: 4px 10px;
      border-radius: 999px;
      background: rgba(148, 163, 184, 0.12);
      color: #d5dfeb;
      font-size: 12px;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 86px;
      padding: 7px 12px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }
    .badge.ok { background: rgba(16, 185, 129, 0.14); color: #b6f4df; }
    .badge.warn { background: rgba(245, 158, 11, 0.16); color: #f9d48e; }
    .badge.accent { background: rgba(59, 130, 246, 0.16); color: #b9d5ff; }
    .badge.danger { background: rgba(249, 115, 22, 0.16); color: #ffca9c; }
    .muted, .meta-label {
      color: var(--muted);
    }
    .meta-label {
      min-width: 52px;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }
    .numeric {
      text-align: right;
      font-variant-numeric: tabular-nums;
    }
    a { color: #9fd0ff; }
    code {
      font-family: "Cascadia Code", Consolas, monospace;
      font-size: 12px;
      background: rgba(148, 163, 184, 0.1);
      padding: 2px 6px;
      border-radius: 8px;
      word-break: break-all;
    }
    .empty-state {
      text-align: center;
      color: var(--muted);
      padding: 40px 18px;
    }
    @media (max-width: 1100px) {
      .hero, .stats { grid-template-columns: 1fr 1fr; }
    }
    @media (max-width: 820px) {
      .shell { width: min(100% - 20px, 1400px); padding: 18px; margin: 14px auto; }
      .hero, .stats { grid-template-columns: 1fr; }
      .table-shell { overflow-x: auto; }
      table { min-width: 980px; }
    }
  </style>
</head>
<body>
  <main class="shell">
    <section class="hero">
      <div>
        <span class="eyebrow">Repo Management Report</span>
        <h1>Repository Status Snapshot</h1>
        <p class="lede">A saved dashboard export with repository health, activity, and discovery metadata. This file was generated from the current application view and written into the repo-local reports folder for later review.</p>
      </div>
      <aside class="meta-card">
        <strong>Export Context</strong>
        <span>Source: $(ConvertTo-HtmlEncodedText $sourceDisplay)</span>
        <span>Generated: $(ConvertTo-HtmlEncodedText $generatedDisplay)</span>
        <span>Repository Count: $repoCount</span>
      </aside>
    </section>

    <section class="stats">
      <article class="stat"><span class="label">Repositories</span><span class="value">$repoCount</span></article>
      <article class="stat"><span class="label">Dirty</span><span class="value">$dirtyCount</span></article>
      <article class="stat"><span class="label">Archived</span><span class="value">$archivedCount</span></article>
      <article class="stat"><span class="label">Stale</span><span class="value">$staleCount</span></article>
      <article class="stat"><span class="label">Open PRs</span><span class="value">$([int](Get-ValueOrDefault $openPrTotal 0))</span></article>
      <article class="stat"><span class="label">Commits 7d / 30d</span><span class="value">$([int](Get-ValueOrDefault $weeklyCommitTotal 0)) / $([int](Get-ValueOrDefault $monthlyCommitTotal 0))</span></article>
    </section>

    <section class="table-shell">
      <table>
        <thead>
          <tr>
            <th>Repository</th>
            <th>Branch</th>
            <th>Status</th>
            <th>Last Commit</th>
            <th>Open PRs</th>
            <th>Commits 7d</th>
            <th>Commits 30d</th>
            <th>Changes</th>
            <th>Links</th>
          </tr>
        </thead>
        <tbody>
$(($rowMarkup -join "`n"))
        </tbody>
      </table>
    </section>
  </main>
</body>
</html>
"@
}

function Export-RepoStatusReports {
    param(
        [object[]]$Repos,
        [string]$SourceLabel
    )

    $reportsRoot = Get-ReportsRootPath
    $generatedAt = Get-Date
    $timestamp = $generatedAt.ToString('yyyyMMdd_HHmmssfff')
    $htmlFileName = "repo-status-report_$timestamp.html"
    $csvFileName = "repo-status-report_$timestamp.csv"
    $htmlPath = Join-Path $reportsRoot $htmlFileName
    $csvPath = Join-Path $reportsRoot $csvFileName

    $htmlContent = New-RepoStatusHtmlContent -Repos $Repos -SourceLabel $SourceLabel -GeneratedAt $generatedAt
    $csvContent = New-RepoStatusCsvContent -Repos $Repos

    Set-Content -LiteralPath $htmlPath -Value $htmlContent -Encoding UTF8
    Set-Content -LiteralPath $csvPath -Value $csvContent -Encoding UTF8

    return [pscustomobject]@{
        generatedAt = $generatedAt.ToString('o')
        repoCount = @($Repos).Count
        sourceLabel = $SourceLabel
        reportFileName = $htmlFileName
        reportPath = $htmlPath
        reportUrl = "/api/reports/$([System.Uri]::EscapeDataString($htmlFileName))"
        csvFileName = $csvFileName
        csvPath = $csvPath
    }
}

function Invoke-PowerShellScriptFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter()]
        [string[]]$Arguments = @(),
        [Parameter()]
        [switch]$AllowFailure
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Script not found: $ScriptPath"
    }

    function ConvertTo-PlainScriptOutput {
        param([string]$Text)

        if ([string]::IsNullOrWhiteSpace($Text)) {
            return $Text
        }

        $withoutAnsi = [regex]::Replace($Text, '\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])', '')
        $trimmed = $withoutAnsi.Trim()
        $lines = @($trimmed -split "`r?`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($lines.Count -gt 1 -and $lines[0] -match '^[A-Za-z]+(?:\.[A-Za-z]+)*:') {
            $messageLines = @(
                $lines |
                    Where-Object { $_ -match '^\|\s+' } |
                    ForEach-Object { ($_ -replace '^\|\s+', '').Trim() } |
                    Where-Object { $_ -notmatch '^\d+\s+\|' } |
                    Where-Object { $_ -notmatch '^~+$' } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
            if ($messageLines.Count -gt 0) {
                return (($messageLines -join ' ') -replace '\s{2,}', ' ').Trim()
            }
        }

        return $trimmed
    }

    $rawOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $outputText = ConvertTo-PlainScriptOutput -Text (($rawOutput | ForEach-Object { $_.ToString() }) -join "`n")

    if (($exitCode -ne 0) -and (-not $AllowFailure.IsPresent)) {
        if ([string]::IsNullOrWhiteSpace($outputText)) {
            throw "Script failed with exit code ${exitCode}: $ScriptPath"
        }
        throw $outputText
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $outputText
        Lines = @($rawOutput)
    }
}

function Get-JsonObjectFromText {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw 'No output received from script.'
    }

    $start = $Text.IndexOf('{')
    $end = $Text.LastIndexOf('}')
    if ($start -lt 0 -or $end -lt 0 -or $end -le $start) {
        throw 'Script output did not contain a JSON object.'
    }

    $json = $Text.Substring($start, $end - $start + 1)
    return ConvertFrom-JsonCompat -Json $json
}

function Get-HostSettings {
    $configPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return @{
            inventory = @{ localRoots = @($WorkspaceRoot); maxDepth = 3; includeNonGitFolders = $false }
            reconcile = @{ ownerType = 'Auto'; gitHubOwner = '' }
            retention = @{ days = 30 }
            secrets = @{ gitHubTokenEnvVar = 'GITHUB_TOKEN' }
        }
    }

    return ConvertFrom-JsonCompat -Json (Get-Content -LiteralPath $configPath -Raw)
}

function Remove-StoredSecretsFromSettings {
    <#
    .SYNOPSIS
        Strip literal secrets left in settings.json by an older build.
    .DESCRIPTION
        settings.json is git-tracked, so a literal secret stored in it is one
        commit from leaking. The host reads only environment variable *names*
        now, so any surviving value is dead weight and pure risk. Removes
        secrets.githubToken and readme.copilotApiKey at startup and tells the
        operator to revoke them. The secrets themselves are never logged.
    .OUTPUTS
        [string[]] The dotted paths of the keys that held a value.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $configPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
    if (-not (Test-Path -LiteralPath $configPath)) { return @() }

    # container key -> secret key, for every literal-secret slot older builds wrote.
    $legacySecretKeys = @(
        @{ Container = 'secrets'; Key = 'githubToken';    EnvVarSetting = 'secrets.gitHubTokenEnvVar' },
        @{ Container = 'readme';  Key = 'copilotApiKey';  EnvVarSetting = 'readme.copilotApiKeyEnvVar' }
    )

    try {
        $settings = ConvertFrom-JsonCompat -Json (Get-Content -LiteralPath $configPath -Raw)
        if (-not ($settings -is [System.Collections.IDictionary])) { return @() }

        $removed = [System.Collections.Generic.List[string]]::new()
        $changed = $false
        foreach ($slot in $legacySecretKeys) {
            if (-not $settings.ContainsKey($slot.Container)) { continue }
            $container = $settings[$slot.Container]
            if (-not ($container -is [System.Collections.IDictionary]) -or -not $container.ContainsKey($slot.Key)) { continue }
            if (-not $PSCmdlet.ShouldProcess($configPath, ("Remove {0}.{1}" -f $slot.Container, $slot.Key))) { continue }

            if (-not [string]::IsNullOrWhiteSpace([string]$container[$slot.Key])) {
                $removed.Add(('{0}.{1} (use {2})' -f $slot.Container, $slot.Key, $slot.EnvVarSetting))
            }
            $container.Remove($slot.Key)
            $changed = $true
        }

        if (-not $changed) { return @() }

        if (-not $settings.ContainsKey('secrets')) { $settings.secrets = @{} }
        if (-not $settings.secrets.ContainsKey('gitHubTokenEnvVar')) {
            $settings.secrets.gitHubTokenEnvVar = 'GITHUB_TOKEN'
        }
        ($settings | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $configPath -Encoding UTF8

        if ($removed.Count -gt 0) {
            Write-HostLog ("WARN secrets: removed stored secret(s) from settings.json - {0}. Storing secrets is no longer supported; set the named environment variable instead, and REVOKE the removed value - it may exist in git history." -f ($removed -join '; '))
        }
        return $removed.ToArray()
    }
    catch {
        Write-HostLog ("WARN secrets: could not strip stored secrets - {0}" -f $_.Exception.Message)
        return @()
    }
}

# ── Release 2.2 — API authentication + network hardening ─────────────────────
# Backward-compatible by default: with no `auth` block (or requireApiKey=false)
# the gate is a no-op and every existing loopback flow keeps working. Auth only
# engages when an operator opts in, which is also what the non-loopback bind
# guard requires before exposing the host off 127.0.0.1.

function Test-IsLoopbackAddress {
    param([string]$Address)
    if ([string]::IsNullOrWhiteSpace($Address)) { return $true }
    $a = $Address.Trim().ToLowerInvariant()
    if ($a -eq 'localhost' -or $a -eq '::1' -or $a -eq '0:0:0:0:0:0:0:1') { return $true }
    try {
        $ip = [System.Net.IPAddress]::Parse($a)
        return [System.Net.IPAddress]::IsLoopback($ip)
    } catch {
        return $false
    }
}

function Get-AuthApiKeyEnvVarName {
    param([hashtable]$Settings)
    $envVarName = 'REPO_MGMT_API_KEY'
    if ($null -ne $Settings -and $Settings.ContainsKey('auth') -and $Settings.auth -is [System.Collections.IDictionary] -and
        $Settings.auth.ContainsKey('apiKeyEnvVar') -and $Settings.auth.apiKeyEnvVar) {
        $envVarName = [string]$Settings.auth.apiKeyEnvVar
    }
    return $envVarName
}

function Get-ConfiguredApiKey {
    param([hashtable]$Settings)
    # Env var wins over settings.json so the key never has to live in a
    # committed file. Returns '' when nothing is configured.
    $envVal = [System.Environment]::GetEnvironmentVariable((Get-AuthApiKeyEnvVarName -Settings $Settings))
    if (-not [string]::IsNullOrWhiteSpace($envVal)) { return $envVal.Trim() }
    if ($null -ne $Settings -and $Settings.ContainsKey('auth') -and $Settings.auth -is [System.Collections.IDictionary] -and
        $Settings.auth.ContainsKey('apiKey') -and $Settings.auth.apiKey) {
        return ([string]$Settings.auth.apiKey).Trim()
    }
    return ''
}

function Test-ApiAuthRequired {
    param([hashtable]$Settings)
    # Env override lets an operator (or the auth smoke) enforce auth without
    # editing the committed settings.json.
    $envToggle = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_REQUIRE_API_KEY')
    if (-not [string]::IsNullOrWhiteSpace($envToggle) -and $envToggle.Trim() -match '^(?i)(1|true|yes|on)$') {
        return $true
    }
    if ($null -eq $Settings -or -not $Settings.ContainsKey('auth') -or -not ($Settings.auth -is [System.Collections.IDictionary])) {
        return $false
    }
    if ($Settings.auth.ContainsKey('requireApiKey')) { return [bool]$Settings.auth.requireApiKey }
    return $false
}

function New-ApiKey {
    # 32 random bytes -> 64 hex chars. RandomNumberGenerator.Create() is
    # available on both Windows PowerShell 5.1 and PowerShell 7.
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

function Get-RequestApiKey {
    param([object]$Request)
    if ($Request.Headers.ContainsKey('x-api-key') -and $Request.Headers['x-api-key']) {
        return ([string]$Request.Headers['x-api-key']).Trim()
    }
    if ($Request.Headers.ContainsKey('authorization') -and $Request.Headers['authorization']) {
        $auth = [string]$Request.Headers['authorization']
        if ($auth -match '^(?i)bearer\s+(.+)$') { return $Matches[1].Trim() }
    }
    return ''
}

function Test-RequestApiKeyValid {
    param([object]$Request, [string]$ExpectedKey)
    if ([string]::IsNullOrWhiteSpace($ExpectedKey)) { return $true }
    $provided = Get-RequestApiKey -Request $Request
    if ([string]::IsNullOrEmpty($provided)) { return $false }
    # Length-checked ordinal compare — adequate for a loopback/LAN tool.
    if ($provided.Length -ne $ExpectedKey.Length) { return $false }
    return [System.String]::Equals($provided, $ExpectedKey, [System.StringComparison]::Ordinal)
}

# Release 2.3 Phase 3 — shields.io-style SVG badge generator (self-contained,
# no external calls). Returns a flat two-cell badge as an SVG string.
function New-SvgBadge {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Color = '#4c1'
    )
    $esc = {
        param($s)
        ([string]$s).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
    }
    $labelText = & $esc $Label
    $msgText = & $esc $Message
    # ~6.5px/char + padding; good enough for a flat badge.
    $labelWidth = [int]([math]::Max(30, ($labelText.Length * 6.5) + 10))
    $msgWidth = [int]([math]::Max(30, ($msgText.Length * 6.5) + 10))
    $total = $labelWidth + $msgWidth
    $labelMid = [int]($labelWidth / 2)
    $msgMid = [int]($labelWidth + ($msgWidth / 2))
    return @"
<svg xmlns="http://www.w3.org/2000/svg" width="$total" height="20" role="img" aria-label="${labelText}: ${msgText}">
  <linearGradient id="s" x2="0" y2="100%"><stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient>
  <rect width="$total" height="20" rx="3" fill="#fff"/>
  <g>
    <rect width="$labelWidth" height="20" rx="3" fill="#555"/>
    <rect x="$labelWidth" width="$msgWidth" height="20" rx="3" fill="$Color"/>
    <rect width="$total" height="20" rx="3" fill="url(#s)"/>
  </g>
  <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" font-size="11">
    <text x="$labelMid" y="14">$labelText</text>
    <text x="$msgMid" y="14">$msgText</text>
  </g>
</svg>
"@
}

# Release 2.3 Phase 3 — portfolio health digest payload (totalRepos, byLevel,
# improvedThisWeek, topCandidates). Derived from the operations/index entries;
# delivered to a webhook by the digest route, or returned as a dry-run preview.
function Get-DigestPayload {
    param([array]$Entries, [int]$ImprovedThisWeek = 0)
    $entries = @($Entries)
    $byLevel = @{}
    foreach ($e in $entries) {
        $lvl = [string](Get-ObjectPropertyValue -InputObject $e -PropertyName 'dispatchReadiness' -Default 'unknown')
        if ([string]::IsNullOrWhiteSpace($lvl)) { $lvl = 'unknown' }
        if ($byLevel.ContainsKey($lvl)) { $byLevel[$lvl] = [int]$byLevel[$lvl] + 1 } else { $byLevel[$lvl] = 1 }
    }
    $topCandidates = @($entries |
        Where-Object { ([string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'dispatchReadiness' -Default '')) -eq 'ready' } |
        ForEach-Object { [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '') } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 5)
    return @{
        totalRepos       = @($entries).Count
        byLevel          = $byLevel
        improvedThisWeek = [int]$ImprovedThisWeek
        topCandidates    = @($topCandidates)
        generatedAt      = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-StatusCacheTtlSeconds {
    param([hashtable]$Settings)

    $ttl = $script:StatusCacheDefaultTtlSeconds
    if (
        $null -ne $Settings -and
        $Settings.ContainsKey('inventory') -and
        $Settings.inventory -is [System.Collections.IDictionary] -and
        $Settings.inventory.ContainsKey('statusCacheTtlSeconds') -and
        $Settings.inventory.statusCacheTtlSeconds
    ) {
        $candidate = [int]$Settings.inventory.statusCacheTtlSeconds
        if ($candidate -gt 0) {
            $ttl = $candidate
        }
    }

    return $ttl
}

function Get-StatusCacheFilePath {
    $cacheDir = Join-Path $WorkspaceRoot 'backend\modules\output\cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        $null = New-Item -ItemType Directory -Path $cacheDir -Force
    }
    return Join-Path $cacheDir 'status-cache.json'
}

# ── Cross-process cache coherence ────────────────────────────────────────────
# Every cache below has two layers: a per-process memory entry and a file. That
# was safe while the host was the only writer. It is not safe now: the
# background refresh worker is a SEPARATE PROCESS whose only channel back to
# the host is the file it writes.
#
# A memory entry is therefore a view of one file version, not an independent
# copy, and it must lose to a newer file. Without that the host serves the
# snapshot it happened to take first, forever - and the stale-while-revalidate
# path makes it worse rather than better, because -IgnoreTtl means age never
# retires the entry either. The portal would stop freezing and start lying.

function Get-CacheFileStamp {
    <#
    .SYNOPSIS
        Last-write time of a cache file, or $null when there is no file.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        return [System.IO.File]::GetLastWriteTimeUtc($Path)
    }
    catch {
        # Unreadable stamp = cannot prove the memory entry is current, so treat
        # it as superseded. A slow disk read beats serving stale data blind.
        return $null
    }
}

function Test-MemoryCacheEntryCurrent {
    <#
    .SYNOPSIS
        Whether an in-memory cache entry still describes the file on disk.
    .DESCRIPTION
        Identity, not age: the entry records the file version it was built from,
        so a write by any process invalidates it exactly once. Comparing
        timestamps for "newer" instead would need a tolerance for the host's own
        write, and a tolerance is a window in which the bug comes back.

        No file means nothing can have superseded the entry - a memory-only
        entry (the cache directory is unwritable, say) stays usable.
    #>
    param(
        [Parameter(Mandatory = $true)][hashtable]$Entry,
        [Parameter(Mandatory = $true)][string]$CacheFilePath
    )

    $fileStamp = Get-CacheFileStamp -Path $CacheFilePath
    if ($null -eq $fileStamp) { return $true }
    if (-not $Entry.ContainsKey('FileWriteTimeUtc') -or $null -eq $Entry.FileWriteTimeUtc) { return $false }
    return ([datetime]$Entry.FileWriteTimeUtc) -eq $fileStamp
}

# Cross-cutting — stale-cache diagnostics: age + TTL + staleness for one cache
# file, so the dashboard/operator can see which cached view is fresh vs stale.
function Get-CacheDiagnosticEntry {
    param([string]$Path, [int]$TtlSeconds)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return @{ present = $false; ageSeconds = $null; ttlSeconds = [int]$TtlSeconds; stale = $true }
    }
    $ageSeconds = [math]::Round((((Get-Date).ToUniversalTime()) - ([System.IO.File]::GetLastWriteTimeUtc($Path))).TotalSeconds, 1)
    return @{
        present    = $true
        ageSeconds = $ageSeconds
        ttlSeconds = [int]$TtlSeconds
        stale      = ([int]$TtlSeconds -gt 0 -and $ageSeconds -gt [int]$TtlSeconds)
    }
}

function Get-StatusCacheKey {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$LocalRoots,
        [Parameter(Mandatory = $true)]
        [int]$MaxDepth,
        [Parameter(Mandatory = $true)]
        [bool]$IncludeNonGitFolders
    )

    $normalizedRoots = @(
        $LocalRoots |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
            Sort-Object
    )

    return '{0}|depth:{1}|nonGit:{2}' -f ($normalizedRoots -join ';'), $MaxDepth, $IncludeNonGitFolders
}

function Get-StatusCacheMeta {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Hit,
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [int]$TtlSeconds,
        [Parameter()]
        [double]$AgeSeconds = 0,
        [Parameter(Mandatory = $true)]
        [bool]$BypassRequested,
        [Parameter()]
        [string]$CachedAt = ''
    )

    return @{
        hit = $Hit
        source = $Source
        ageSeconds = [math]::Round([double]$AgeSeconds, 3)
        ttlSeconds = $TtlSeconds
        bypassRequested = $BypassRequested
        cachedAt = $CachedAt
    }
}

function Add-StatusCacheMeta {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result,
        [Parameter(Mandatory = $true)]
        [hashtable]$CacheMeta
    )

    if ($Result -is [System.Collections.IDictionary]) {
        if (-not $Result.ContainsKey('meta') -or $null -eq $Result.meta) {
            $Result.meta = @{}
        }
        if (-not ($Result.meta -is [System.Collections.IDictionary])) {
            $Result.meta = @{ raw = $Result.meta }
        }
        $Result.meta.statusCache = $CacheMeta
        return $Result
    }

    if (-not ($Result.PSObject.Properties.Name -contains 'meta') -or $null -eq $Result.meta) {
        $Result | Add-Member -NotePropertyName meta -NotePropertyValue @{} -Force
    }
    elseif (-not ($Result.meta -is [System.Collections.IDictionary])) {
        $Result.meta = @{ raw = $Result.meta }
    }

    $Result.meta.statusCache = $CacheMeta
    return $Result
}

function Test-StatusResponseHasActivityMetrics {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Response
    )

    $repoItems = @()
    if ($Response -is [System.Collections.IDictionary]) {
        if ($Response.ContainsKey('data') -and $Response.data -is [System.Collections.IDictionary] -and $Response.data.ContainsKey('repos')) {
            $repoItems = @($Response.data.repos)
        }
    }
    elseif ($Response.PSObject.Properties.Name -contains 'data' -and $null -ne $Response.data) {
        $data = $Response.data
        if ($data -is [System.Collections.IDictionary]) {
            if ($data.ContainsKey('repos')) {
                $repoItems = @($data.repos)
            }
        }
        elseif ($data.PSObject.Properties.Name -contains 'repos') {
            $repoItems = @($data.repos)
        }
    }

    if (@($repoItems).Count -eq 0) {
        return $true
    }

    foreach ($repo in @($repoItems)) {
        if ($repo -is [System.Collections.IDictionary]) {
            if (
                (-not $repo.ContainsKey('lastCommitAuthor')) -or
                (-not $repo.ContainsKey('commitsLastWeek')) -or
                (-not $repo.ContainsKey('commitsLastMonth'))
            ) {
                return $false
            }
            continue
        }

        $props = @($repo.PSObject.Properties.Name)
        if (
            ($props -notcontains 'lastCommitAuthor') -or
            ($props -notcontains 'commitsLastWeek') -or
            ($props -notcontains 'commitsLastMonth')
        ) {
            return $false
        }
    }

    return $true
}

function Get-StatusFromCache {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [int]$TtlSeconds,
        # When set, returns cached data regardless of TTL (stale-while-revalidate support)
        [Parameter()]
        [switch]$IgnoreTtl
    )

    $nowUtc = (Get-Date).ToUniversalTime()
    $cacheFile = Get-StatusCacheFilePath

    if ($script:StatusCacheMemory.ContainsKey($Key)) {
        $memoryEntry = $script:StatusCacheMemory[$Key]
        if (-not (Test-MemoryCacheEntryCurrent -Entry $memoryEntry -CacheFilePath $cacheFile)) {
            # The background worker finished a scan. Drop the entry and read its
            # file below; keeping it would pin the host to the first snapshot it
            # ever took, since -IgnoreTtl never expires one.
            $script:StatusCacheMemory.Remove($Key)
            Write-HostLog ("[TRACE] status.cache memory entry superseded by background refresh key='{0}'" -f $Key)
        }
        else {
            $ageSeconds = (($nowUtc) - [datetime]$memoryEntry.CreatedAtUtc).TotalSeconds
            if ($IgnoreTtl.IsPresent -or $ageSeconds -le $TtlSeconds) {
                if (-not (Test-StatusResponseHasActivityMetrics -Response $memoryEntry.Response)) {
                    $script:StatusCacheMemory.Remove($Key)
                    Write-HostLog ("Status cache miss: memory entry missing activity metrics for key '{0}'" -f $Key)
                    return [pscustomobject]@{ hit = $false }
                }
                return [pscustomobject]@{
                    hit = $true
                    source = 'memory'
                    ageSeconds = $ageSeconds
                    cachedAt = ([datetime]$memoryEntry.CreatedAtUtc).ToString('o')
                    response = $memoryEntry.Response
                }
            }
        }
    }

    if (-not (Test-Path -LiteralPath $cacheFile)) {
        return [pscustomobject]@{ hit = $false }
    }

    try {
        $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]@{ hit = $false }
        }
        $diskEntry = ConvertFrom-JsonCompat -Json $raw
        if ($null -eq $diskEntry -or -not $diskEntry.ContainsKey('key') -or -not $diskEntry.ContainsKey('createdAtUtc') -or -not $diskEntry.ContainsKey('response')) {
            return [pscustomobject]@{ hit = $false }
        }
        $schemaVersion = if ($diskEntry.ContainsKey('schemaVersion') -and $null -ne $diskEntry.schemaVersion) {
            [int]$diskEntry.schemaVersion
        } else {
            0
        }
        if ($schemaVersion -ne 0 -and $schemaVersion -ne $script:StatusCacheSchemaVersion) {
            return [pscustomobject]@{ hit = $false }
        }
        if ([string]$diskEntry.key -ne $Key) {
            return [pscustomobject]@{ hit = $false }
        }
        if (-not (Test-StatusResponseHasActivityMetrics -Response $diskEntry.response)) {
            Write-HostLog ("Status cache miss: disk entry missing activity metrics for key '{0}'" -f $Key)
            return [pscustomobject]@{ hit = $false }
        }

        $createdAtUtc = [datetime]$diskEntry.createdAtUtc
        $ageSeconds = (($nowUtc) - $createdAtUtc).TotalSeconds
        if ((-not $IgnoreTtl.IsPresent) -and ($ageSeconds -gt $TtlSeconds)) {
            return [pscustomobject]@{ hit = $false }
        }

        $script:StatusCacheMemory[$Key] = @{
            CreatedAtUtc = $createdAtUtc
            Response = $diskEntry.response
            FileWriteTimeUtc = (Get-CacheFileStamp -Path $cacheFile)
        }

        return [pscustomobject]@{
            hit = $true
            source = 'disk'
            ageSeconds = $ageSeconds
            cachedAt = $createdAtUtc.ToString('o')
            response = $diskEntry.response
        }
    }
    catch {
        return [pscustomobject]@{ hit = $false }
    }
}

function Save-StatusCache {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [object]$Response
    )

    $nowUtc = (Get-Date).ToUniversalTime()
    $entry = @{
        schemaVersion = $script:StatusCacheSchemaVersion
        key = $Key
        createdAtUtc = $nowUtc.ToString('o')
        response = $Response
    }

    # Written first, stamped after: the memory entry has to name the file
    # version it matches, and that version does not exist until the write does.
    $cacheFile = Get-StatusCacheFilePath
    try {
        ($entry | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $cacheFile -Encoding UTF8
    }
    catch {
        Write-HostLog ("Status cache write skipped: {0}" -f $_.Exception.Message)
    }

    $script:StatusCacheMemory[$Key] = @{
        CreatedAtUtc = $nowUtc
        Response = $Response
        FileWriteTimeUtc = (Get-CacheFileStamp -Path $cacheFile)
    }
}

function Clear-StatusCache {
    $script:StatusCacheMemory = @{}
    try {
        $cacheFile = Get-StatusCacheFilePath
        if (Test-Path -LiteralPath $cacheFile) {
            Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-HostLog ("Status cache clear skipped: {0}" -f $_.Exception.Message)
    }
}

# ── Background status refresh ────────────────────────────────────────────────
# No HTTP request may run a portfolio scan. Measured 2026-08-11: the sweep costs
# 196.7s, the status cache TTL is 120s, and the miss path scanned inline on the
# single request thread - so the portal spent about two thirds of its life
# unable to answer anything, permanently, because the refresh took longer than
# the interval that triggered it. A miss now serves what is on disk and kicks
# this worker instead.

function Get-StatusRefreshLockPath {
    $cacheDir = Split-Path -Parent (Get-StatusCacheFilePath)
    return Join-Path $cacheDir 'status-refresh.lock'
}

function Get-StatusRefreshState {
    <#
    .SYNOPSIS
        Whether a background refresh is in flight, and since when.
    .DESCRIPTION
        Liveness is decided by the recorded process, not by the lock file's
        existence: a worker killed mid-scan (or a host restarted under it)
        would otherwise leave a lock that suppresses every future refresh and
        freezes the cache forever. A lock naming a process that is gone is a
        stale lock, and stale locks are ignored.
    #>
    $lockPath = Get-StatusRefreshLockPath
    if (-not (Test-Path -LiteralPath $lockPath)) {
        return @{ running = $false; startedAt = $null; processId = $null; stale = $false }
    }

    $lockPid = 0
    $startedAt = $null
    try {
        $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
        $lockPid = [int]$lock.processId
        $startedAt = [datetime]$lock.startedAt
    }
    catch {
        # An unreadable lock is a stale lock. Treating it as "running" would
        # wedge the cache permanently on one corrupt write.
        return @{ running = $false; startedAt = $null; processId = $null; stale = $true }
    }

    $alive = $false
    if ($lockPid -gt 0) {
        $alive = $null -ne (Get-Process -Id $lockPid -ErrorAction Ignore)
    }

    return @{
        running   = $alive
        startedAt = $startedAt
        processId = $lockPid
        stale     = (-not $alive)
    }
}

function Start-BackgroundStatusRefresh {
    <#
    .SYNOPSIS
        Kicks the out-of-process cache refresh. Returns $true if it started one.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Launches a read-only scan whose only write is the host''s own cache file. It is triggered by an HTTP GET on a cache miss, where no operator is present to answer a -WhatIf prompt.')]
    param(
        [Parameter(Mandatory = $true)][string[]]$LocalRoots,
        [Parameter()][int]$MaxDepth = 2,
        [Parameter()][switch]$IncludeNonGitFolders
    )

    $state = Get-StatusRefreshState
    if ($state.running) {
        return $false
    }

    $lockPath = Get-StatusRefreshLockPath
    $worker = Join-Path $WorkspaceRoot 'scripts\Invoke-StatusCacheRefresh.ps1'
    if (-not (Test-Path -LiteralPath $worker)) {
        Write-HostLog ("[ERROR] status.refresh cannot start - worker missing at {0}" -f $worker)
        return $false
    }

    try {
        # This host is running under some PowerShell; reuse the same executable
        # rather than assuming pwsh is on PATH, which it is not for a service
        # running as LocalSystem.
        $psExe = (Get-Process -Id $PID).Path

        $arguments = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $worker,
            '-WorkspaceRoot', $WorkspaceRoot,
            '-LocalRoots', ($LocalRoots -join ','),
            '-MaxDepth', $MaxDepth,
            '-LockPath', $lockPath
        )
        if ($IncludeNonGitFolders) { $arguments += '-IncludeNonGitFolders' }
        if (-not [string]::IsNullOrWhiteSpace($LogPath)) { $arguments += @('-LogPath', $LogPath) }

        $process = Start-Process -FilePath $psExe -ArgumentList $arguments -WindowStyle Hidden -PassThru

        # Written AFTER the process exists so the lock always names a real pid.
        $lockBody = @{
            processId = $process.Id
            startedAt = (Get-Date).ToUniversalTime().ToString('o')
            roots     = @($LocalRoots)
        } | ConvertTo-Json -Compress
        Set-Content -LiteralPath $lockPath -Value $lockBody -Encoding UTF8

        Write-HostLog ("[TRACE] status.refresh started pid={0} roots={1}" -f $process.Id, ($LocalRoots -join ','))
        return $true
    }
    catch {
        Write-HostLog ("[ERROR] status.refresh failed to start: {0}" -f $_.Exception.Message)
        try {
            if (Test-Path -LiteralPath $lockPath) { Remove-Item -LiteralPath $lockPath -Force }
        }
        catch {
            # A lock left behind by a launch that never produced a process would
            # block refreshes until something clears it by hand.
            Write-HostLog ("[WARN] status.refresh could not clear lock {0}: {1}" -f $lockPath, $_.Exception.Message)
        }
        return $false
    }
}

# Valid POSIX/Windows environment variable name. Enforced on write so a bad
# name is rejected at the dialog instead of silently resolving to nothing.
$script:EnvVarNamePattern = '^[A-Za-z_][A-Za-z0-9_]*$'

# A service process cannot see User-scoped environment variables. Detecting this
# lets the token diagnostics name the actual cause instead of "not set".
$script:RunningAsService = (-not [Environment]::UserInteractive) -or
    ([Environment]::UserName -eq 'SYSTEM')

function Get-GitHubTokenEnvVarName {
    <#
    .SYNOPSIS
        Name of the environment variable that holds the GitHub token.
    .DESCRIPTION
        The host never stores a token. Settings carry only the *name* of the
        variable to read; 'GITHUB_TOKEN' is the default when unset.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )

    if ($Settings.ContainsKey('secrets') -and
        $Settings.secrets -is [System.Collections.IDictionary] -and
        $Settings.secrets.ContainsKey('gitHubTokenEnvVar') -and
        $Settings.secrets.gitHubTokenEnvVar) {
        return [string]$Settings.secrets.gitHubTokenEnvVar
    }

    return 'GITHUB_TOKEN'
}

function Get-GitHubTokenResolution {
    <#
    .SYNOPSIS
        Resolve the GitHub token plus the diagnostics needed to explain a miss.
    .DESCRIPTION
        Resolution order is the named environment variable first, then the
        'gh' CLI credential as a last resort. Returns the token together with
        the variable name, the source, and — on Windows — which environment
        scope supplied the value, so the UI can tell an operator that a
        User-scoped variable is invisible to a LocalSystem service.

        Never emits the token into logs or responses; callers that surface
        this to a client must project only the non-secret fields.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )

    $envVarName = Get-GitHubTokenEnvVarName -Settings $Settings

    $envToken = [Environment]::GetEnvironmentVariable($envVarName)
    if (-not [string]::IsNullOrWhiteSpace($envToken)) {
        # Report the scope this process actually inherited it from. A value
        # present in Process but absent from User/Machine came from the
        # launching shell and will not survive a service restart.
        $scope = 'Process'
        foreach ($candidate in 'Machine', 'User') {
            try {
                $scoped = [Environment]::GetEnvironmentVariable($envVarName, $candidate)
                if ($scoped -eq $envToken) { $scope = $candidate; break }
            }
            catch { }
        }

        return [pscustomobject]@{
            EnvVarName = $envVarName
            Token      = $envToken
            Source     = 'env'
            Scope      = $scope
        }
    }

    $ghCommand = Get-Command -Name 'gh' -ErrorAction SilentlyContinue
    if ($ghCommand) {
        try {
            $ghTokenOutput = & $ghCommand.Source auth token 2>$null
            if ($LASTEXITCODE -eq 0) {
                $ghToken = ($ghTokenOutput | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($ghToken)) {
                    return [pscustomobject]@{
                        EnvVarName = $envVarName
                        Token      = $ghToken
                        Source     = 'gh-cli'
                        Scope      = ''
                    }
                }
            }
        }
        catch { }
    }

    return [pscustomobject]@{
        EnvVarName = $envVarName
        Token      = ''
        Source     = 'none'
        Scope      = ''
    }
}

function Get-ConfiguredGitHubToken {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )

    return (Get-GitHubTokenResolution -Settings $Settings).Token
}

function Get-GitHubTokenMissHint {
    <#
    .SYNOPSIS
        Operator-facing explanation for a token name that did not resolve.
    .DESCRIPTION
        Shared by the auth-status route and by the callers that fail on a
        missing token, so every surface names the same cause. A service
        process cannot read a User-scoped variable, which is the miss
        operators hit most often.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvVarName
    )

    if ($script:RunningAsService) {
        return "Environment variable '$EnvVarName' is not visible to this host, which runs as a service. Service processes cannot read User-scoped variables - set it at Machine scope and restart the service."
    }

    return "Environment variable '$EnvVarName' is not set in the host's process. Set it and restart the host; a variable set after launch is not picked up."
}

function Get-GitHubApiHeaders {
    param(
        [Parameter()]
        [string]$Token
    )

    $headers = @{
        'User-Agent' = 'GitHubRepoManagement'
        Accept = 'application/vnd.github+json'
    }

    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers.Authorization = "Bearer $Token"
    }

    return $headers
}

function Get-GitHubOwnerTypeViaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    try {
        $uri = "https://api.github.com/users/$Owner"
        $response = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get
        if ($response -and $response.type) {
            $typeValue = [string]$response.type
            if ($typeValue -eq 'Organization') { return 'Organization' }
            return 'User'
        }
    }
    catch {
        if (Test-GitHubErrorIsOwnerAbsent -ErrorRecord $_) {
            Set-GitHubOwnerKnownAbsent -Owner $Owner
        }
        else {
            Write-HostLog ("[TRACE] github.ownerType lookup failed owner={0} error={1}" -f $Owner, $_.Exception.Message)
        }
    }

    return 'User'
}

function Get-GitHubCommitCountViaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Repo,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [int]$SinceDays
    )

    $since = (Get-Date).ToUniversalTime().AddDays(-1 * [math]::Abs($SinceDays)).ToString('o')
    $uri = "https://api.github.com/repos/$Owner/$Repo/commits?per_page=1&since=$([System.Uri]::EscapeDataString($since))"

    try {
        $response = Invoke-WebRequest -Uri $uri -Headers $Headers -Method Get
        $null = Update-GitHubRateLimitSnapshot -Headers $response.Headers
        $bodyText = [string]$response.Content
        $bodyItems = @()
        if (-not [string]::IsNullOrWhiteSpace($bodyText)) {
            try { $bodyItems = @(ConvertFrom-Json -InputObject $bodyText) } catch { $bodyItems = @() }
        }

        if ($bodyItems.Count -eq 0) {
            return 0
        }

        $linkHeader = [string]$response.Headers['Link']
        if (-not [string]::IsNullOrWhiteSpace($linkHeader)) {
            if ($linkHeader -match 'page=(\d+)>;\s*rel="last"') {
                return [int]$matches[1]
            }
            if ($linkHeader -match 'rel="next"') {
                return 2
            }
        }

        return 1
    }
    catch {
        Write-HostLog ("[TRACE] github.commitCount failed owner={0} repo={1} sinceDays={2} error={3}" -f $Owner, $Repo, $SinceDays, $_.Exception.Message)
        return 0
    }
}

function Get-LatestGitHubWorkflowRunViaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Repo,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter()]
        [string]$Branch = ''
    )

    $uri = "https://api.github.com/repos/$Owner/$Repo/actions/runs?per_page=1"
    if (-not [string]::IsNullOrWhiteSpace($Branch)) {
        $uri += "&branch=$([System.Uri]::EscapeDataString($Branch))"
    }

    try {
        # Invoke-WebRequest so the rate-limit headers survive: this is the LAST
        # GitHub call an insights sweep makes (once per repo, after the commit
        # counts), so its headers carry the most current remaining figure.
        $rawResponse = Invoke-WebRequest -Uri $uri -Headers $Headers -Method Get -UseBasicParsing
        $null = Update-GitHubRateLimitSnapshot -Headers $rawResponse.Headers
        $responseBody = [string]$rawResponse.Content
        if ([string]::IsNullOrWhiteSpace($responseBody)) { return $null }
        $response = ConvertFrom-Json -InputObject $responseBody
        $runs = @(Get-ObjectPropertyValue -InputObject $response -PropertyName 'workflow_runs' -Default @())
        if ($runs.Count -eq 0) {
            return $null
        }

        $run = $runs[0]
        $runTimestamp = [string](Get-ObjectPropertyValue -InputObject $run -PropertyName 'run_started_at' -Default '')
        if ([string]::IsNullOrWhiteSpace($runTimestamp)) {
            $runTimestamp = [string](Get-ObjectPropertyValue -InputObject $run -PropertyName 'updated_at' -Default '')
        }
        if ([string]::IsNullOrWhiteSpace($runTimestamp)) {
            $runTimestamp = [string](Get-ObjectPropertyValue -InputObject $run -PropertyName 'created_at' -Default '')
        }

        return [pscustomobject]@{
            status     = [string](Get-ObjectPropertyValue -InputObject $run -PropertyName 'status' -Default '')
            conclusion = [string](Get-ObjectPropertyValue -InputObject $run -PropertyName 'conclusion' -Default '')
            name       = [string](Get-ObjectPropertyValue -InputObject $run -PropertyName 'name' -Default '')
            runUrl     = [string](Get-ObjectPropertyValue -InputObject $run -PropertyName 'html_url' -Default '')
            timestamp  = if ([string]::IsNullOrWhiteSpace($runTimestamp)) { $null } else { $runTimestamp }
        }
    }
    catch {
        Write-HostLog ("[TRACE] github.workflowRun failed owner={0} repo={1} error={2}" -f $Owner, $Repo, $_.Exception.Message)
        return $null
    }
}

function Get-GitHubRepoIdentityFromOriginUrl {
    param(
        [Parameter()]
        [string]$OriginUrl
    )

    if ([string]::IsNullOrWhiteSpace($OriginUrl)) {
        return $null
    }

    $patterns = @(
        '^(?:https://|git@)github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$',
        '^ssh://git@github\.com/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$'
    )

    foreach ($pattern in $patterns) {
        if ($OriginUrl -match $pattern) {
            return [pscustomobject]@{
                owner = [string]$matches.owner
                repo = [string]$matches.repo
            }
        }
    }

    return $null
}

function Get-GitHubPagesDefaultUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Repo
    )

    if ($Repo.Equals("$Owner.github.io", [System.StringComparison]::OrdinalIgnoreCase)) {
        return "https://$Owner.github.io/"
    }

    return "https://$Owner.github.io/$Repo/"
}

function Get-GitHubPagesSiteUrlViaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Repo,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter()]
        [string]$FallbackUrl = ''
    )

    $uri = "https://api.github.com/repos/$Owner/$Repo/pages"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get
        $htmlUrl = Get-ObjectPropertyValue -InputObject $response -PropertyName 'html_url' -Default ''
        if (-not [string]::IsNullOrWhiteSpace([string]$htmlUrl)) {
            return [string]$htmlUrl
        }
    }
    catch {
        Write-HostLog ("[TRACE] github.pages lookup failed owner={0} repo={1} error={2}" -f $Owner, $Repo, $_.Exception.Message)
    }

    return $FallbackUrl
}

function ConvertTo-GitHubRepoMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [object]$RepoItem,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter()]
        [string]$FallbackOwner = ''
    )

    $repoName = [string](Get-ObjectPropertyValue -InputObject $RepoItem -PropertyName 'name' -Default '')
    if ([string]::IsNullOrWhiteSpace($repoName)) {
        return $null
    }

    $repoOwner = $FallbackOwner
    $ownerObject = Get-ObjectPropertyValue -InputObject $RepoItem -PropertyName 'owner' -Default $null
    $ownerLogin = Get-ObjectPropertyValue -InputObject $ownerObject -PropertyName 'login' -Default ''
    if (-not [string]::IsNullOrWhiteSpace([string]$ownerLogin)) {
        $repoOwner = [string]$ownerLogin
    }

    $hasPages = [bool](Get-ObjectPropertyValue -InputObject $RepoItem -PropertyName 'has_pages' -Default $false)
    $homepage = [string](Get-ObjectPropertyValue -InputObject $RepoItem -PropertyName 'homepage' -Default '')
    $pagesUrl = ''
    if ($hasPages) {
        $fallbackPagesUrl = if (-not [string]::IsNullOrWhiteSpace($homepage)) {
            $homepage
        }
        elseif (-not [string]::IsNullOrWhiteSpace($repoOwner)) {
            Get-GitHubPagesDefaultUrl -Owner $repoOwner -Repo $repoName
        }
        else {
            ''
        }

        if (-not [string]::IsNullOrWhiteSpace($repoOwner)) {
            $pagesUrl = Get-GitHubPagesSiteUrlViaApi -Owner $repoOwner -Repo $repoName -Headers $Headers -FallbackUrl $fallbackPagesUrl
        }
        else {
            $pagesUrl = $fallbackPagesUrl
        }
    }

    return [pscustomobject]@{
        name = $repoName
        htmlUrl = Get-ObjectPropertyValue -InputObject $RepoItem -PropertyName 'html_url' -Default $null
        owner = $repoOwner
        visibility = if ([bool](Get-ObjectPropertyValue -InputObject $RepoItem -PropertyName 'private' -Default $false)) { 'private' } else { 'public' }
        language = Get-ObjectPropertyValue -InputObject $RepoItem -PropertyName 'language' -Default $null
        topics = @((Get-ObjectPropertyValue -InputObject $RepoItem -PropertyName 'topics' -Default @()))
        hasPages = $hasPages
        pagesUrl = if ([string]::IsNullOrWhiteSpace($pagesUrl)) { $null } else { $pagesUrl }
        createdAt = Get-ObjectPropertyValue -InputObject $RepoItem -PropertyName 'created_at' -Default $null
        updatedAt = Get-ObjectPropertyValue -InputObject $RepoItem -PropertyName 'updated_at' -Default $null
        # pushed_at, carried separately from updated_at because they answer
        # different questions: updated_at moves when a description or star count
        # changes, so a repo nobody has pushed to in a year looks freshly
        # updated. Only pushed_at tracks actual commits reaching the remote,
        # which is what staleness is measured against.
        pushedAt = Get-ObjectPropertyValue -InputObject $RepoItem -PropertyName 'pushed_at' -Default $null
        latestWorkflowRunStatus = $null
        latestWorkflowRunConclusion = $null
        latestWorkflowRunName = $null
        latestWorkflowRunTimestamp = $null
    }
}

function Get-GitHubRepoMetadataMapViaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter()]
        [string]$Token,
        [Parameter()]
        [int]$MaxPages = 10
    )

    $repoMap = @{}
    $repoLimit = [Math]::Max(100, $MaxPages * 100)

    # Single choke point for owner-scoped metadata: one check here spares the
    # three sequential 404s (owner type, repo list, open PRs) that a dead owner
    # otherwise costs on every sweep.
    if (Test-GitHubOwnerKnownAbsent -Owner $Owner) {
        return $repoMap
    }

    try {
        $apiResult = Get-GitHubReposViaApi -Owner $Owner -Token $Token -RepoLimit $repoLimit -IncludePrivate:$true -IncludeForks:$false -IncludeArchived:$true -FetchCommitMetrics:$false
        foreach ($repo in @($apiResult.repos)) {
            if ($null -eq $repo) { continue }

            $repoName = [string](Get-ObjectPropertyValue -InputObject $repo -PropertyName 'name' -Default '')
            if ([string]::IsNullOrWhiteSpace($repoName)) { continue }

            $repoMap[$repoName.ToLowerInvariant()] = [pscustomobject]@{
                name = $repoName
                htmlUrl = Get-ObjectPropertyValue -InputObject $repo -PropertyName 'htmlUrl' -Default $null
                owner = Get-ObjectPropertyValue -InputObject $repo -PropertyName 'owner' -Default $Owner
                visibility = Get-ObjectPropertyValue -InputObject $repo -PropertyName 'visibility' -Default $null
                language = Get-ObjectPropertyValue -InputObject $repo -PropertyName 'language' -Default $null
                topics = @((Get-ObjectPropertyValue -InputObject $repo -PropertyName 'topics' -Default @()))
                hasPages = [bool](Get-ObjectPropertyValue -InputObject $repo -PropertyName 'hasPages' -Default $false)
                pagesUrl = Get-ObjectPropertyValue -InputObject $repo -PropertyName 'pagesUrl' -Default $null
                createdAt = Get-ObjectPropertyValue -InputObject $repo -PropertyName 'createdAt' -Default $null
                updatedAt = Get-ObjectPropertyValue -InputObject $repo -PropertyName 'updatedAt' -Default $null
                latestWorkflowRunStatus = Get-ObjectPropertyValue -InputObject $repo -PropertyName 'latestWorkflowRunStatus' -Default $null
                latestWorkflowRunConclusion = Get-ObjectPropertyValue -InputObject $repo -PropertyName 'latestWorkflowRunConclusion' -Default $null
                latestWorkflowRunName = Get-ObjectPropertyValue -InputObject $repo -PropertyName 'latestWorkflowRunName' -Default $null
                latestWorkflowRunTimestamp = Get-ObjectPropertyValue -InputObject $repo -PropertyName 'latestWorkflowRunTimestamp' -Default $null
            }
        }
    }
    catch {
        Write-HostLog ("[TRACE] github.repoMetadata fetch failed owner={0} error={1}" -f $Owner, $_.Exception.Message)
    }

    return $repoMap
}

function Add-GitHubMetadataToStatusResult {
    param(
        [Parameter(Mandatory = $true)]
        [object]$StatusResult,
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )

    if ($null -eq $StatusResult -or -not $StatusResult.success -or $null -eq $StatusResult.data) {
        return $StatusResult
    }

    $repos = @($StatusResult.data.repos)
    if ($repos.Count -eq 0) {
        return $StatusResult
    }

    $reposByOwner = @{}
    foreach ($repo in $repos) {
        $identity = Get-GitHubRepoIdentityFromOriginUrl -OriginUrl ([string](Get-ObjectPropertyValue -InputObject $repo -PropertyName 'originUrl' -Default ''))
        if ($null -eq $identity -or [string]::IsNullOrWhiteSpace($identity.owner) -or [string]::IsNullOrWhiteSpace($identity.repo)) {
            continue
        }

        $ownerKey = $identity.owner.ToLowerInvariant()
        if (-not $reposByOwner.ContainsKey($ownerKey)) {
            $reposByOwner[$ownerKey] = [pscustomobject]@{
                owner = $identity.owner
                repos = New-Object System.Collections.ArrayList
            }
        }

        $null = $reposByOwner[$ownerKey].repos.Add([pscustomobject]@{
            repo = $repo
            repoName = $identity.repo
        })
    }

    if ($reposByOwner.Count -eq 0) {
        return $StatusResult
    }

    $token = Get-ConfiguredGitHubToken -Settings $Settings
    $ownerProgressCount = 0
    foreach ($ownerEntry in $reposByOwner.Values) {
        # Owner-level tick bounds the silent window even when an owner resolves to
        # zero repos and the per-repo tick inside the fetch never runs — the shape
        # a dead owner (404) produces.
        $ownerProgressCount++
        $null = Update-ActivePortalOperationProgress -Stage 'github-metadata' -Completed $ownerProgressCount

        $metadataMap = Get-GitHubRepoMetadataMapViaApi -Owner $ownerEntry.owner -Token $token
        if ($metadataMap.Count -eq 0) {
            continue
        }

        foreach ($entry in @($ownerEntry.repos)) {
            $repoKey = $entry.repoName.ToLowerInvariant()
            if (-not $metadataMap.ContainsKey($repoKey)) {
                continue
            }

            $metadata = $metadataMap[$repoKey]
            foreach ($propertyName in @('htmlUrl', 'owner', 'visibility', 'language', 'topics', 'hasPages', 'pagesUrl', 'createdAt', 'updatedAt', 'pushedAt', 'latestWorkflowRunStatus', 'latestWorkflowRunConclusion', 'latestWorkflowRunName', 'latestWorkflowRunTimestamp')) {
                $propertyValue = Get-ObjectPropertyValue -InputObject $metadata -PropertyName $propertyName -Default $null
                $entry.repo | Add-Member -NotePropertyName $propertyName -NotePropertyValue $propertyValue -Force
            }

            # Release 3.1 — the comparison this join always had the parts for and
            # never made. The local side already carries lastCommitDate from
            # `git log -1 --format=%cI`; pushedAt arrived one line above. Both
            # facts are on this object, so the classification costs nothing —
            # no extra request, no fetch, no clone read.
            $staleness = Resolve-RepoStaleness `
                -LocalCommitDate (Get-ObjectPropertyValue -InputObject $entry.repo -PropertyName 'lastCommitDate' -Default $null) `
                -RemotePushedAt  (Get-ObjectPropertyValue -InputObject $metadata   -PropertyName 'pushedAt'       -Default $null)

            $entry.repo | Add-Member -NotePropertyName 'staleness' -NotePropertyValue $staleness -Force
            $entry.repo | Add-Member -NotePropertyName 'isStale'   -NotePropertyValue ([bool]$staleness.isStale) -Force
            # localAhead / remoteAhead stay untouched. Two timestamps cannot
            # produce a commit count, and writing a plausible-looking zero is
            # exactly the "unmeasured rendered as measured" failure this release
            # is fixing elsewhere. The exact tier needs `git ls-remote`.
        }
    }

    return $StatusResult
}

function Get-GitHubReposViaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Token,
        [Parameter()]
        [bool]$IncludePrivate = $true,
        [Parameter()]
        [bool]$IncludeForks = $false,
        [Parameter()]
        [bool]$IncludeArchived = $true,
        [Parameter()]
        [bool]$FetchCommitMetrics = $true,
        [Parameter()]
        [int]$RepoLimit = 50
    )

    $headers = Get-GitHubApiHeaders -Token $Token
    Clear-GitHubRateLimitSnapshot

    $openPrCounts = @{}
    try {
        $openPrCounts = Get-GitHubOpenPrCountsViaApi -Owner $Owner -Token $Token
    }
    catch {
        Write-HostLog ("[TRACE] github.openpr api aggregation failed owner={0} error={1}" -f $Owner, $_.Exception.Message)
    }

    $ownerType = Get-GitHubOwnerTypeViaApi -Owner $Owner -Headers $headers
    $repoType = if ($IncludePrivate) { 'all' } else { 'public' }

    $uris = @()
    if ($ownerType -eq 'Organization') {
        $uris += "https://api.github.com/orgs/$Owner/repos?per_page=100&sort=updated&type=$repoType"
    }
    else {
        $uris += "https://api.github.com/users/$Owner/repos?per_page=100&sort=updated&type=$repoType"
        if ($IncludePrivate) {
            $uris += "https://api.github.com/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member"
        }
    }

    $repoMap = @{}
    foreach ($uri in $uris) {
        try {
            # Invoke-WebRequest, not Invoke-RestMethod: the rate-limit headers
            # are only reachable on the response object, and Invoke-RestMethod
            # discards them on Windows PowerShell.
            $reposResponse = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get -UseBasicParsing
            $null = Update-GitHubRateLimitSnapshot -Headers $reposResponse.Headers
            $reposBody = [string]$reposResponse.Content
            $reposRaw = @()
            if (-not [string]::IsNullOrWhiteSpace($reposBody)) {
                $reposRaw = @((ConvertFrom-Json -InputObject $reposBody) | ForEach-Object { $_ })
            }
            foreach ($repoItem in $reposRaw) {
                if ($null -eq $repoItem -or -not $repoItem.name) { continue }

                $repoOwner = if ($repoItem.owner -and $repoItem.owner.login) { [string]$repoItem.owner.login } else { '' }
                if (-not [string]::IsNullOrWhiteSpace($repoOwner) -and $repoOwner.ToLowerInvariant() -ne $Owner.ToLowerInvariant()) { continue }

                if ((-not $IncludeForks) -and [bool]$repoItem.fork) { continue }
                if ((-not $IncludeArchived) -and [bool]$repoItem.archived) { continue }

                $key = [string]$repoItem.name
                if (-not $repoMap.ContainsKey($key)) {
                    $repoMap[$key] = $repoItem
                }
            }
        }
        catch {
            # The /user/repos URI is token-scoped, not owner-scoped: a 404 there
            # says nothing about whether $Owner exists, so it must not mark one
            # absent.
            if ((Test-GitHubErrorIsOwnerAbsent -ErrorRecord $_) -and ($uri -notmatch '://api\.github\.com/user/repos')) {
                Set-GitHubOwnerKnownAbsent -Owner $Owner
            }
            else {
                Write-HostLog ("[TRACE] github.repos fetch failed owner={0} uri={1} error={2}" -f $Owner, $uri, $_.Exception.Message)
            }
            continue
        }
    }

    $allRepos = @($repoMap.Values | Sort-Object -Property updated_at -Descending)
    # Each iteration below makes sequential network calls (workflow run, and the
    # Pages lookup inside ConvertTo-GitHubRepoMetadata). Across ~75 repos that is
    # minutes of wall clock. Publishing per repo is what keeps the watchdog's
    # progress contract true here: without it the whole phase reads as frozen and
    # a working scan is restarted. Ambient, so it is a no-op outside a request.
    $repoProgressCount = 0
    $repos = @($allRepos | Select-Object -First $RepoLimit | ForEach-Object {
        $repoProgressCount++
        $null = Update-ActivePortalOperationProgress -Stage 'github-metadata' -Completed $repoProgressCount

        $repoOpenPrCount = 0
        if ($openPrCounts.ContainsKey($_.name)) {
            $repoOpenPrCount = [int]$openPrCounts[$_.name]
        }

        $commitCountWeek = 0
        $commitCountMonth = 0
        if ($FetchCommitMetrics) {
            $commitCountWeek = Get-GitHubCommitCountViaApi -Owner $Owner -Repo ([string]$_.name) -Headers $headers -SinceDays 7
            $commitCountMonth = Get-GitHubCommitCountViaApi -Owner $Owner -Repo ([string]$_.name) -Headers $headers -SinceDays 30
        }

        $workflowRun = Get-LatestGitHubWorkflowRunViaApi -Owner $Owner -Repo ([string]$_.name) -Headers $headers

        $lastCommitAuthor = ''
        if ($_.owner -and $_.owner.login) {
            $lastCommitAuthor = [string]$_.owner.login
        }

        $metadata = ConvertTo-GitHubRepoMetadata -RepoItem $_ -Headers $headers -FallbackOwner $Owner

        [pscustomobject]@{
            name = $_.name
            branch = if ($_.default_branch) { $_.default_branch } else { 'main' }
            status = 'clean'
            lastCommitDate = if ($_.pushed_at) { $_.pushed_at } else { $_.updated_at }
            lastCommitMessage = if ($_.description) { [string]$_.description } else { '' }
            lastCommitAuthor = $lastCommitAuthor
            commitsLastWeek = $commitCountWeek
            commitsLastMonth = $commitCountMonth
            uncommittedChanges = 0
            isArchived = [bool]$_.archived
            # A GitHub-only listing has no local clone to compare against, so
            # drift is genuinely unknown rather than absent. Resolved through the
            # same function as the joined path so both report unknown identically
            # instead of one of them asserting "not stale" for free.
            staleness = (Resolve-RepoStaleness -LocalCommitDate $null -RemotePushedAt (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'pushed_at' -Default $null))
            isStale = [bool](Resolve-RepoStaleness -LocalCommitDate $null -RemotePushedAt (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'pushed_at' -Default $null)).isStale
            localAhead = 0
            remoteAhead = 0
            openPrCount = $repoOpenPrCount
            htmlUrl = $metadata.htmlUrl
            owner = $metadata.owner
            visibility = $metadata.visibility
            language = $metadata.language
            topics = $metadata.topics
            hasPages = $metadata.hasPages
            pagesUrl = $metadata.pagesUrl
            createdAt = if ($_.created_at) { [string]$_.created_at } else { $null }
            updatedAt = if ($_.updated_at) { [string]$_.updated_at } else { $null }
            latestWorkflowRunStatus = if ($null -ne $workflowRun) { $workflowRun.status } else { $null }
            latestWorkflowRunConclusion = if ($null -ne $workflowRun) { $workflowRun.conclusion } else { $null }
            latestWorkflowRunName = if ($null -ne $workflowRun) { $workflowRun.name } else { $null }
            latestWorkflowRunTimestamp = if ($null -ne $workflowRun) { $workflowRun.timestamp } else { $null }
        }
    })

    return [pscustomobject]@{
        source = 'github'
        username = $Owner
        totalRepos = @($allRepos).Count
        fetchedRepos = @($repos).Count
        repos = $repos
        # Observed, not assumed: whatever the last GitHub response reported.
        # Still $null when no call returned parseable headers — a blank readout
        # is honest, a fabricated 0/0 is not.
        rateLimit = Get-GitHubRateLimitSnapshot
    }
}

function Get-GitHubOpenPrCountsViaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    $headers = @{
        Authorization = "Bearer $Token"
        'User-Agent' = 'GitHubRepoManagement'
        Accept = 'application/vnd.github+json'
    }

    $counts = @{}
    $page = 1
    $maxPages = 10
    while ($page -le $maxPages) {
        $query = [System.Uri]::EscapeDataString("user:$Owner is:pr is:open")
        $uri = "https://api.github.com/search/issues?q=$query&per_page=100&page=$page"
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        $items = @($response.items)
        if ($items.Count -eq 0) {
            break
        }

        foreach ($item in $items) {
            if ($null -eq $item.repository_url) { continue }
            $segments = ([string]$item.repository_url).TrimEnd('/') -split '/'
            if ($segments.Length -lt 1) { continue }
            $repoName = $segments[$segments.Length - 1]
            if (-not $counts.ContainsKey($repoName)) {
                $counts[$repoName] = 0
            }
            $counts[$repoName] = [int]$counts[$repoName] + 1
        }

        if ($items.Count -lt 100) {
            break
        }

        $page++
    }

    return $counts
}

function Get-GitHubOpenPrCountsViaGh {
    param([Parameter(Mandatory = $true)][string]$Owner)

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        return @{}
    }

    $counts = @{}
    $page = 1
    $maxPages = 10
    while ($page -le $maxPages) {
        $query = "user:$Owner is:pr is:open"
        $json = (& gh api "search/issues" --field q="$query" --field per_page='100' --field page="$page" 2>$null) | Out-String
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
            break
        }

        $response = ConvertFrom-Json $json
        $items = @($response.items)
        if ($items.Count -eq 0) {
            break
        }

        foreach ($item in $items) {
            $repoUrl = [string]$item.repository_url
            if ([string]::IsNullOrWhiteSpace($repoUrl)) { continue }
            $segments = $repoUrl.TrimEnd('/') -split '/'
            if ($segments.Length -lt 1) { continue }
            $repoName = $segments[$segments.Length - 1]
            if (-not $counts.ContainsKey($repoName)) {
                $counts[$repoName] = 0
            }
            $counts[$repoName] = [int]$counts[$repoName] + 1
        }

        if ($items.Count -lt 100) {
            break
        }
        $page++
    }

    return $counts
}

function Invoke-GitOperation {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('pull', 'sync')]
        [string]$OperationType,
        [Parameter()]
        [string[]]$RepoNames,
        [Parameter()]
        [string[]]$RepoPaths
    )

    $status = Get-StatusAdapterResult -LocalRoots @($WorkspaceRoot) -MaxDepth 4 -IncludeNonGitFolders:$false -LogPath $LogPath -OnProgress (Get-ActivePortalOperationTick -Stage 'workspace-scan')
    if (-not $status.success) {
        throw "Unable to enumerate repositories for ${OperationType}: $($status.error)"
    }

    $repos = @($status.data.repos)
    if ($RepoPaths -and $RepoPaths.Count -gt 0) {
        $pathSet = @{}
        foreach ($p in $RepoPaths) {
            if (-not [string]::IsNullOrWhiteSpace([string]$p)) {
                $pathSet[[string]$p] = $true
            }
        }
        $repos = @($repos | Where-Object { $pathSet.ContainsKey([string]$_.path) })
    }
    elseif ($RepoNames -and $RepoNames.Count -gt 0) {
        $nameSet = @{}
        foreach ($n in $RepoNames) { $nameSet[$n] = $true }
        $repos = @($repos | Where-Object { $nameSet.ContainsKey($_.name) })
    }

    $results = @()
    foreach ($repo in $repos) {
        $repoPath = [string]$repo.path
        $name = [string]$repo.name
        try {
            if ($OperationType -eq 'pull') {
                $output = (& git -C $repoPath pull --ff-only 2>&1) | Out-String
            }
            else {
                $output = (& git -C $repoPath fetch --all --prune 2>&1) | Out-String
            }
            $results += [pscustomobject]@{
                name = $name
                path = $repoPath
                success = $true
                output = $output.Trim()
            }
        }
        catch {
            $results += [pscustomobject]@{
                name = $name
                path = $repoPath
                success = $false
                error = $_.Exception.Message
            }
        }
    }

    return [pscustomobject]@{
        operation = $OperationType
        total = @($results).Count
        succeeded = @($results | Where-Object { $_.success }).Count
        failed = @($results | Where-Object { -not $_.success }).Count
        results = $results
    }
}

function Get-RoadmapCacheFilePath {
    $cacheDir = Join-Path $WorkspaceRoot 'backend\modules\output\cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        $null = New-Item -ItemType Directory -Path $cacheDir -Force
    }
    return Join-Path $cacheDir 'roadmap-index-cache.json'
}

function Get-RoadmapCacheTtlSeconds {
    param([hashtable]$Settings)
    $ttl = $script:RoadmapCacheDefaultTtlSeconds
    if (
        $null -ne $Settings -and
        $Settings.ContainsKey('roadmap') -and
        $Settings.roadmap -is [System.Collections.IDictionary] -and
        $Settings.roadmap.ContainsKey('scanCacheTtlSeconds') -and
        $Settings.roadmap.scanCacheTtlSeconds
    ) {
        $candidate = [int]$Settings.roadmap.scanCacheTtlSeconds
        if ($candidate -ge 0) { $ttl = $candidate }
    }
    return $ttl
}

function Get-RoadmapFromCache {
    param([int]$TtlSeconds)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'roadmap-global'
    $cacheFile = Get-RoadmapCacheFilePath

    if ($script:RoadmapCacheMemory.ContainsKey($key)) {
        $entry = $script:RoadmapCacheMemory[$key]
        # The assessment route reads this cache with -TtlSeconds ([int]::MaxValue),
        # so age can never retire the entry. Only the file version can.
        if (-not (Test-MemoryCacheEntryCurrent -Entry $entry -CacheFilePath $cacheFile)) {
            $script:RoadmapCacheMemory.Remove($key)
        }
        else {
            $age = (($nowUtc) - [datetime]$entry.CreatedAtUtc).TotalSeconds
            if ($age -le $TtlSeconds) {
                return [pscustomobject]@{ hit = $true; source = 'memory'; ageSeconds = $age; cachedAt = ([datetime]$entry.CreatedAtUtc).ToString('o'); entries = $entry.Entries; scannedAt = $entry.ScannedAt }
            }
        }
    }

    if (-not (Test-Path -LiteralPath $cacheFile)) { return [pscustomobject]@{ hit = $false } }

    try {
        $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{ hit = $false } }
        $disk = ConvertFrom-JsonCompat -Json $raw
        if ($null -eq $disk -or -not $disk.ContainsKey('createdAtUtc')) { return [pscustomobject]@{ hit = $false } }
        $created = [datetime]$disk.createdAtUtc
        $age = (($nowUtc) - $created).TotalSeconds
        if ($age -gt $TtlSeconds) { return [pscustomobject]@{ hit = $false } }
        $script:RoadmapCacheMemory[$key] = @{ CreatedAtUtc = $created; Entries = $disk.entries; ScannedAt = [string]$disk.scannedAt; FileWriteTimeUtc = (Get-CacheFileStamp -Path $cacheFile) }
        return [pscustomobject]@{ hit = $true; source = 'disk'; ageSeconds = $age; cachedAt = $created.ToString('o'); entries = $disk.entries; scannedAt = [string]$disk.scannedAt }
    }
    catch { return [pscustomobject]@{ hit = $false } }
}

function Save-RoadmapCache {
    param([array]$Entries, [string]$ScannedAt)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'roadmap-global'
    $cacheFile = Get-RoadmapCacheFilePath
    try {
        (@{ createdAtUtc = $nowUtc.ToString('o'); scannedAt = $ScannedAt; entries = $Entries } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $cacheFile -Encoding UTF8
    }
    catch { Write-HostLog ("Roadmap cache write skipped: {0}" -f $_.Exception.Message) }
    $script:RoadmapCacheMemory[$key] = @{ CreatedAtUtc = $nowUtc; Entries = $Entries; ScannedAt = $ScannedAt; FileWriteTimeUtc = (Get-CacheFileStamp -Path $cacheFile) }
}

function Clear-RoadmapCache {
    $script:RoadmapCacheMemory = @{}
    try {
        $cacheFile = Get-RoadmapCacheFilePath
        if (Test-Path -LiteralPath $cacheFile) { Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue }
    }
    catch { Write-HostLog ("Roadmap cache clear skipped: {0}" -f $_.Exception.Message) }
}

function Get-RoadmapStandard {
    <#
    .SYNOPSIS
        Load and return the roadmap audit rules and maturity thresholds from
        standards/roadmap/roadmap-audit-rules.json.
    .OUTPUTS
        [pscustomobject] with rules, maturityThresholds, version, ruleCount, loadedAt — or $null on failure.
    #>
    $standardPath = Join-Path $WorkspaceRoot 'standards\roadmap\roadmap-audit-rules.json'
    if (-not (Test-Path -LiteralPath $standardPath)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $standardPath -Raw -Encoding UTF8 -ErrorAction Stop
        $parsed = ConvertFrom-Json -InputObject $raw
        return [pscustomobject]@{
            version           = [string]$parsed.version
            description       = [string]$parsed.description
            rules             = @($parsed.rules)
            maturityThresholds = $parsed.maturityThresholds
            ruleCount         = @($parsed.rules).Count
            maturityLevels    = @($parsed.maturityThresholds.PSObject.Properties.Name)
            loadedAt          = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
    catch {
        return $null
    }
}

function Get-RoadmapAuditCacheFilePath {
    $cacheDir = Join-Path $WorkspaceRoot 'backend\modules\output\cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        $null = New-Item -ItemType Directory -Path $cacheDir -Force
    }
    return Join-Path $cacheDir 'roadmap-audit-cache.json'
}

function Get-RoadmapAuditCacheTtlSeconds {
    param([hashtable]$Settings)
    $ttl = $script:RoadmapAuditCacheDefaultTtlSeconds
    if (
        $null -ne $Settings -and
        $Settings.ContainsKey('roadmap') -and
        $Settings.roadmap -is [System.Collections.IDictionary] -and
        $Settings.roadmap.ContainsKey('auditCacheTtlSeconds') -and
        $Settings.roadmap.auditCacheTtlSeconds
    ) {
        $candidate = [int]$Settings.roadmap.auditCacheTtlSeconds
        if ($candidate -ge 0) { $ttl = $candidate }
    }
    return $ttl
}

function Get-RoadmapAuditFromCache {
    param([int]$TtlSeconds)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'roadmap-audit-global'
    $cacheFile = Get-RoadmapAuditCacheFilePath

    if ($script:RoadmapAuditCacheMemory.ContainsKey($key)) {
        $entry = $script:RoadmapAuditCacheMemory[$key]
        if (-not (Test-MemoryCacheEntryCurrent -Entry $entry -CacheFilePath $cacheFile)) {
            $script:RoadmapAuditCacheMemory.Remove($key)
        }
        else {
            $age = (($nowUtc) - [datetime]$entry.CreatedAtUtc).TotalSeconds
            if ($age -le $TtlSeconds) {
                return [pscustomobject]@{ hit = $true; source = 'memory'; ageSeconds = $age; cachedAt = ([datetime]$entry.CreatedAtUtc).ToString('o'); entries = $entry.Entries; auditedAt = $entry.AuditedAt }
            }
        }
    }

    if (-not (Test-Path -LiteralPath $cacheFile)) { return [pscustomobject]@{ hit = $false } }

    try {
        $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{ hit = $false } }
        $disk = ConvertFrom-JsonCompat -Json $raw
        if ($null -eq $disk -or -not $disk.ContainsKey('createdAtUtc')) { return [pscustomobject]@{ hit = $false } }
        $created = [datetime]$disk.createdAtUtc
        $age = (($nowUtc) - $created).TotalSeconds
        if ($age -gt $TtlSeconds) { return [pscustomobject]@{ hit = $false } }
        $script:RoadmapAuditCacheMemory[$key] = @{ CreatedAtUtc = $created; Entries = $disk.entries; AuditedAt = [string]$disk.auditedAt; FileWriteTimeUtc = (Get-CacheFileStamp -Path $cacheFile) }
        return [pscustomobject]@{ hit = $true; source = 'disk'; ageSeconds = $age; cachedAt = $created.ToString('o'); entries = $disk.entries; auditedAt = [string]$disk.auditedAt }
    }
    catch { return [pscustomobject]@{ hit = $false } }
}

function Save-RoadmapAuditCache {
    param([array]$Entries, [string]$AuditedAt)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'roadmap-audit-global'
    $cacheFile = Get-RoadmapAuditCacheFilePath
    try {
        (@{ createdAtUtc = $nowUtc.ToString('o'); auditedAt = $AuditedAt; entries = $Entries } | ConvertTo-Json -Depth 15) | Set-Content -LiteralPath $cacheFile -Encoding UTF8
    }
    catch { Write-HostLog ("Roadmap audit cache write skipped: {0}" -f $_.Exception.Message) }
    $script:RoadmapAuditCacheMemory[$key] = @{ CreatedAtUtc = $nowUtc; Entries = $Entries; AuditedAt = $AuditedAt; FileWriteTimeUtc = (Get-CacheFileStamp -Path $cacheFile) }
}

function Clear-RoadmapAuditCache {
    $script:RoadmapAuditCacheMemory = @{}
    try {
        $cacheFile = Get-RoadmapAuditCacheFilePath
        if (Test-Path -LiteralPath $cacheFile) { Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue }
    }
    catch { Write-HostLog ("Roadmap audit cache clear skipped: {0}" -f $_.Exception.Message) }
}

function Invoke-RoadmapAuditScan {
    <#
    .SYNOPSIS
        Scan all roadmap entries, normalize each contract, and apply the audit
        rule pack. Returns an array of RoadmapAuditEntry objects.
    #>
    param(
        [string[]]$LocalRoots,
        [int]$MaxDepth = 3
    )

    Write-HostLog '[TRACE] roadmap.audit.scan normalize-start'
    $auditRules = Get-RoadmapStandard
    if ($null -eq $auditRules) {
        Write-HostLog '[WARN] roadmap.audit.scan audit-rules-missing — scoring skipped'
    }

    $roadmapEntries = Invoke-RoadmapScan -LocalRoots $LocalRoots -MaxDepth $MaxDepth
    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($entry in $roadmapEntries) {
        $repoName = [string]$entry.repoName
        $repoPath = [string]$entry.repoPath
        $roadmapPath = [string]$entry.roadmapPath

        try {
            # Read raw content
            $rawContent = ''
            if (-not [string]::IsNullOrWhiteSpace($roadmapPath) -and (Test-Path -LiteralPath $roadmapPath)) {
                $rawContent = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8 -ErrorAction Stop
            }

            # Parse
            Write-HostLog ("[TRACE] roadmap.audit.scan parse repoName={0}" -f $repoName)
            $parsed = Invoke-ParseRoadmapContent -Content $rawContent -SourcePath $roadmapPath

            # Normalize
            Write-HostLog ("[TRACE] roadmap.audit.scan normalize repoName={0} state={1}" -f $repoName, $parsed.roadmapState)
            $contract = Invoke-NormalizeRoadmapContract -ParsedResult $parsed -RawContent $rawContent -RepoName $repoName -RepoPath $repoPath -RoadmapPath $roadmapPath -AuditRules $auditRules

            # Audit / score
            if ($null -ne $auditRules) {
                Write-HostLog ("[TRACE] roadmap.audit.scan score repoName={0}" -f $repoName)
                $contract = Invoke-AuditRoadmapContract -Contract $contract -AuditRules $auditRules
            }

            $results.Add($contract)
        }
        catch {
            Write-HostLog ("[WARN] roadmap.audit.scan audit-rule-failure repoName={0} error={1}" -f $repoName, $_.Exception.Message)
            $results.Add([pscustomobject]@{
                schemaVersion         = '1.0'
                repoName              = $repoName
                repoPath              = $repoPath
                roadmapPath           = $roadmapPath
                roadmapState          = 'parse-error'
                maturityLevel         = 'L0-Absent'
                maturityScore         = 0
                pendingCount          = 0
                completedCount        = 0
                totalCount            = 0
                nextPendingItem       = $null
                sections              = @()
                hasProductIntent      = $false
                hasReleaseSections    = $false
                hasAcceptanceCriteria = $false
                hasOutOfScope         = $false
                releaseCount          = 0
                vagueItemCount        = 0
                parseError            = $_.Exception.Message
                auditFindings         = @()
                parsedAt              = (Get-Date).ToUniversalTime().ToString('o')
            })
        }
    }

    Write-HostLog ("[TRACE] roadmap.audit.scan done auditedCount={0}" -f $results.Count)
    return @($results)
}

# ---------------------------------------------------------------------------
# Roadmap Repair helpers (Release 0.9)
# ---------------------------------------------------------------------------

function Get-RoadmapRepairHistoryPath {
    if (-not (Test-Path -LiteralPath $script:RoadmapRepairHistoryRoot)) {
        $null = New-Item -ItemType Directory -Path $script:RoadmapRepairHistoryRoot -Force -ErrorAction SilentlyContinue
    }
    return $script:RoadmapRepairHistoryRoot
}

function Save-RoadmapRepairHistoryEntry {
    <#
    .SYNOPSIS
        Persist a repair history record to disk.
    #>
    param(
        [string]$PreviewId,
        [string]$RepoName,
        [string]$RoadmapPath,
        [string]$PreviewState,
        [string]$OriginalMaturityLevel,
        [string]$Event,        # 'preview', 'apply', or 'submit-pr'
        [string]$AppliedAt     = '',
        # Release 2.7 Phase A — a live submit-PR records the PR it opened here,
        # in the same append-only stream as preview/apply, so a repair's whole
        # life is one ordered history rather than three separate ones.
        [string]$PrUrl         = '',
        [string]$PrNumber      = '',
        [string]$Branch        = '',
        [string]$RepoSlug      = ''
    )
    try {
        $historyRoot = Get-RoadmapRepairHistoryPath
        $historyFile = Join-Path $historyRoot 'repair-history.jsonl'
        $record = [ordered]@{
            previewId            = $PreviewId
            repoName             = $RepoName
            roadmapPath          = $RoadmapPath
            previewState         = $PreviewState
            originalMaturityLevel = $OriginalMaturityLevel
            event                = $Event
            timestamp            = (Get-Date).ToUniversalTime().ToString('o')
        }
        if (-not [string]::IsNullOrWhiteSpace($AppliedAt)) {
            $record['appliedAt'] = $AppliedAt
        }
        foreach ($pair in @(@{k='prUrl';v=$PrUrl}, @{k='prNumber';v=$PrNumber}, @{k='branch';v=$Branch}, @{k='repoSlug';v=$RepoSlug})) {
            if (-not [string]::IsNullOrWhiteSpace([string]$pair.v)) { $record[$pair.k] = [string]$pair.v }
        }
        $line = ConvertTo-Json -InputObject $record -Compress -Depth 5
        Add-Content -LiteralPath $historyFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        Write-HostLog ("Roadmap repair history write skipped: {0}" -f $_.Exception.Message)
    }
}

function Get-RoadmapRepairHistory {
    <#
    .SYNOPSIS
        Read the last N repair history entries from disk.
    #>
    param([int]$Limit = 25)
    $historyRoot = Get-RoadmapRepairHistoryPath
    $historyFile = Join-Path $historyRoot 'repair-history.jsonl'
    $items = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $historyFile)) { return @() }
    try {
        $lines = Get-Content -LiteralPath $historyFile -Encoding UTF8 -ErrorAction Stop | Select-Object -Last $Limit
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json
                $items.Add($obj)
            } catch { }
        }
    } catch { }
    return @($items)
}

function Build-RoadmapRepairPreview {
    <#
    .SYNOPSIS
        Build a full repair preview for a named repository.
        Reads the roadmap, runs audit, plans repair, generates proposed content.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter()]
        [string]$RoadmapPath = ''
    )

    # Resolve roadmap path
    $settings  = Get-HostSettings
    $roadmapTtl = Get-RoadmapCacheTtlSeconds -Settings $settings
    $roadmapCacheResult = Get-RoadmapFromCache -TtlSeconds $roadmapTtl
    $roadmapEntry = $null
    if ($roadmapCacheResult.hit -and $roadmapCacheResult.entries) {
        $roadmapEntry = @($roadmapCacheResult.entries) | Where-Object { [string]$_.repoName -eq $RepoName } | Select-Object -First 1
    }

    $effectiveRoadmapPath = $RoadmapPath
    if ([string]::IsNullOrWhiteSpace($effectiveRoadmapPath) -and $null -ne $roadmapEntry) {
        $rp = if ($roadmapEntry -is [System.Collections.IDictionary]) { $roadmapEntry['roadmapPath'] } else { $roadmapEntry.roadmapPath }
        if (-not [string]::IsNullOrWhiteSpace([string]$rp)) { $effectiveRoadmapPath = [string]$rp }
    }

    $rawContent = ''
    $parsedResult = $null
    if (-not [string]::IsNullOrWhiteSpace($effectiveRoadmapPath) -and (Test-Path -LiteralPath $effectiveRoadmapPath)) {
        Write-HostLog ("[TRACE] roadmap.repair.preview read repoName={0} path={1}" -f $RepoName, $effectiveRoadmapPath)
        $rawContent = Get-Content -LiteralPath $effectiveRoadmapPath -Raw -Encoding UTF8 -ErrorAction Stop
        $parsedResult = Invoke-ParseRoadmapContent -Content $rawContent -SourcePath $effectiveRoadmapPath
    }

    # Normalize and audit
    $repoPath = ''
    if ($null -ne $roadmapEntry) {
        $repoPath = if ($roadmapEntry -is [System.Collections.IDictionary]) { [string](Get-ValueOrDefault $roadmapEntry['repoPath'] '') } else { [string](Get-ValueOrDefault $roadmapEntry.repoPath '') }
    }
    $auditRules = Get-RoadmapStandard
    $contract = Invoke-NormalizeRoadmapContract `
        -ParsedResult $parsedResult `
        -RawContent $rawContent `
        -RepoName $RepoName `
        -RepoPath $repoPath `
        -RoadmapPath $effectiveRoadmapPath `
        -AuditRules $auditRules

    if ($null -ne $auditRules) {
        $contract = Invoke-AuditRoadmapContract -Contract $contract -AuditRules $auditRules
    }

    Write-HostLog ("[TRACE] roadmap.repair.preview plan repoName={0} maturityLevel={1}" -f $RepoName, $contract.maturityLevel)

    # Plan the repair
    $repairPlan = Invoke-PlanRoadmapRepair -Contract $contract

    # Generate preview
    $preview = Invoke-GenerateRepairPreview `
        -Contract    $contract `
        -RepairPlan  $repairPlan `
        -RawContent  $rawContent `
        -RepoName    $RepoName

    # Attach extra context
    $preview | Add-Member -NotePropertyName 'repoName'             -NotePropertyValue $RepoName               -Force
    $preview | Add-Member -NotePropertyName 'roadmapPath'          -NotePropertyValue $effectiveRoadmapPath   -Force
    $preview | Add-Member -NotePropertyName 'originalMaturityLevel' -NotePropertyValue $contract.maturityLevel -Force
    $preview | Add-Member -NotePropertyName 'originalMaturityScore' -NotePropertyValue $contract.maturityScore -Force
    $preview | Add-Member -NotePropertyName 'auditFindings'         -NotePropertyValue @(Get-ValueOrDefault $contract.auditFindings @()) -Force

    # Persist preview event to history
    Save-RoadmapRepairHistoryEntry `
        -PreviewId            $preview.previewId `
        -RepoName             $RepoName `
        -RoadmapPath          $effectiveRoadmapPath `
        -PreviewState         $preview.previewState `
        -OriginalMaturityLevel $contract.maturityLevel `
        -Event                'preview'

    return $preview
}

function Apply-RoadmapRepair {
    <#
    .SYNOPSIS
        Apply a previously generated repair preview to the roadmap file.
        Requires explicit operator approval via the previewId.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $true)]
        [string]$PreviewId,

        [Parameter(Mandatory = $true)]
        [string]$ProposedContent,

        [Parameter()]
        [string]$RoadmapPath = '',

        [Parameter()]
        [string]$OriginalMaturityLevel = ''
    )

    if ([string]::IsNullOrWhiteSpace($ProposedContent)) {
        throw 'proposedContent is required to apply a repair.'
    }

    # Resolve roadmap path
    $settings  = Get-HostSettings
    $roadmapTtl = Get-RoadmapCacheTtlSeconds -Settings $settings
    $roadmapCacheResult = Get-RoadmapFromCache -TtlSeconds $roadmapTtl
    $roadmapEntry = $null
    if ($roadmapCacheResult.hit -and $roadmapCacheResult.entries) {
        $roadmapEntry = @($roadmapCacheResult.entries) | Where-Object { [string]$_.repoName -eq $RepoName } | Select-Object -First 1
    }

    $effectiveRoadmapPath = $RoadmapPath
    if ([string]::IsNullOrWhiteSpace($effectiveRoadmapPath) -and $null -ne $roadmapEntry) {
        $rp = if ($roadmapEntry -is [System.Collections.IDictionary]) { $roadmapEntry['roadmapPath'] } else { $roadmapEntry.roadmapPath }
        if (-not [string]::IsNullOrWhiteSpace([string]$rp)) { $effectiveRoadmapPath = [string]$rp }
    }

    if ([string]::IsNullOrWhiteSpace($effectiveRoadmapPath)) {
        throw "Cannot apply repair: roadmap path could not be resolved for repo '$RepoName'. Run a roadmap scan first."
    }

    # Backup original before write
    $backupDir = Join-Path $script:RoadmapRepairHistoryRoot 'backups'
    $null = New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction SilentlyContinue
    $backupFile = Join-Path $backupDir ("$RepoName-$PreviewId-original.md")
    if (Test-Path -LiteralPath $effectiveRoadmapPath) {
        Copy-Item -LiteralPath $effectiveRoadmapPath -Destination $backupFile -Force -ErrorAction SilentlyContinue
    }

    # Write proposed content to roadmap file
    Write-HostLog ("[TRACE] roadmap.repair.apply write repoName={0} path={1} previewId={2}" -f $RepoName, $effectiveRoadmapPath, $PreviewId)
    Set-Content -LiteralPath $effectiveRoadmapPath -Value $ProposedContent -Encoding UTF8

    # Invalidate roadmap and audit caches so next fetch reflects the new file
    Clear-RoadmapCache
    Clear-RoadmapAuditCache

    $appliedAt = (Get-Date).ToUniversalTime().ToString('o')

    # Persist apply event to history
    Save-RoadmapRepairHistoryEntry `
        -PreviewId            $PreviewId `
        -RepoName             $RepoName `
        -RoadmapPath          $effectiveRoadmapPath `
        -PreviewState         'applied' `
        -OriginalMaturityLevel $OriginalMaturityLevel `
        -Event                'apply' `
        -AppliedAt            $appliedAt

    Write-HostLog ("[TRACE] roadmap.repair.apply done repoName={0} appliedAt={1}" -f $RepoName, $appliedAt)

    return [pscustomobject]@{
        repoName      = $RepoName
        roadmapPath   = $effectiveRoadmapPath
        previewId     = $PreviewId
        appliedAt     = $appliedAt
        backupPath    = $backupFile
    }
}

function Get-DocAuditCacheFilePath {
    $cacheDir = Join-Path $WorkspaceRoot 'backend\modules\output\cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        $null = New-Item -ItemType Directory -Path $cacheDir -Force
    }
    return Join-Path $cacheDir 'docs-audit-cache.json'
}

function Get-DocAuditCacheTtlSeconds {
    param([hashtable]$Settings)
    $ttl = $script:DocAuditCacheDefaultTtlSeconds
    if (
        $null -ne $Settings -and
        $Settings.ContainsKey('docAudit') -and
        $Settings.docAudit -is [System.Collections.IDictionary] -and
        $Settings.docAudit.ContainsKey('scanCacheTtlSeconds') -and
        $Settings.docAudit.scanCacheTtlSeconds
    ) {
        $candidate = [int]$Settings.docAudit.scanCacheTtlSeconds
        if ($candidate -ge 0) { $ttl = $candidate }
    }
    return $ttl
}

function Get-DocAuditFromCache {
    param([int]$TtlSeconds)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'docaudit-global'
    $cacheFile = Get-DocAuditCacheFilePath

    if ($script:DocAuditCacheMemory.ContainsKey($key)) {
        $entry = $script:DocAuditCacheMemory[$key]
        if (-not (Test-MemoryCacheEntryCurrent -Entry $entry -CacheFilePath $cacheFile)) {
            $script:DocAuditCacheMemory.Remove($key)
        }
        else {
            $age = (($nowUtc) - [datetime]$entry.CreatedAtUtc).TotalSeconds
            if ($age -le $TtlSeconds) {
                return [pscustomobject]@{ hit = $true; source = 'memory'; ageSeconds = $age; cachedAt = ([datetime]$entry.CreatedAtUtc).ToString('o'); entries = $entry.Entries; auditedAt = $entry.AuditedAt }
            }
        }
    }

    if (-not (Test-Path -LiteralPath $cacheFile)) { return [pscustomobject]@{ hit = $false } }

    try {
        $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{ hit = $false } }
        $disk = ConvertFrom-JsonCompat -Json $raw
        if ($null -eq $disk -or -not $disk.ContainsKey('createdAtUtc')) { return [pscustomobject]@{ hit = $false } }
        $created = [datetime]$disk.createdAtUtc
        $age = (($nowUtc) - $created).TotalSeconds
        if ($age -gt $TtlSeconds) { return [pscustomobject]@{ hit = $false } }
        $script:DocAuditCacheMemory[$key] = @{ CreatedAtUtc = $created; Entries = $disk.entries; AuditedAt = [string]$disk.auditedAt; FileWriteTimeUtc = (Get-CacheFileStamp -Path $cacheFile) }
        return [pscustomobject]@{ hit = $true; source = 'disk'; ageSeconds = $age; cachedAt = $created.ToString('o'); entries = $disk.entries; auditedAt = [string]$disk.auditedAt }
    }
    catch { return [pscustomobject]@{ hit = $false } }
}

function Save-DocAuditCache {
    param([array]$Entries, [string]$AuditedAt)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'docaudit-global'
    $cacheFile = Get-DocAuditCacheFilePath
    try {
        (@{ createdAtUtc = $nowUtc.ToString('o'); auditedAt = $AuditedAt; entries = $Entries } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $cacheFile -Encoding UTF8
    }
    catch { Write-HostLog ("DocAudit cache write skipped: {0}" -f $_.Exception.Message) }
    $script:DocAuditCacheMemory[$key] = @{ CreatedAtUtc = $nowUtc; Entries = $Entries; AuditedAt = $AuditedAt; FileWriteTimeUtc = (Get-CacheFileStamp -Path $cacheFile) }
}

function Get-PortfolioAssessmentCacheTtlSeconds {
    param([hashtable]$Settings)
    $ttl = $script:PortfolioAssessmentCacheDefaultTtlSeconds
    if (
        $null -ne $Settings -and
        $Settings.ContainsKey('portfolio') -and
        $Settings.portfolio -is [System.Collections.IDictionary] -and
        $Settings.portfolio.ContainsKey('assessmentCacheTtlSeconds') -and
        $Settings.portfolio.assessmentCacheTtlSeconds
    ) {
        $candidate = [int]$Settings.portfolio.assessmentCacheTtlSeconds
        if ($candidate -gt 0) { $ttl = $candidate }
    }
    return $ttl
}

function Get-PortfolioAssessmentFromCache {
    param([int]$TtlSeconds)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'portfolio-assessment-global'
    if ($script:PortfolioAssessmentCacheMemory.ContainsKey($key)) {
        $entry = $script:PortfolioAssessmentCacheMemory[$key]
        $age = ($nowUtc - [datetime]$entry.CreatedAtUtc).TotalSeconds
        if ($age -le $TtlSeconds) {
            return [pscustomobject]@{
                hit          = $true
                source       = 'memory'
                ageSeconds   = $age
                generatedAt  = $entry.GeneratedAt
                entries      = $entry.Entries
                summary      = $entry.Summary
                signalSources = $entry.SignalSources
            }
        }
    }
    return [pscustomobject]@{ hit = $false }
}

function Save-PortfolioAssessmentCache {
    param(
        [array]$Entries,
        [object]$Summary,
        [object]$SignalSources,
        [string]$GeneratedAt
    )
    $nowUtc = (Get-Date).ToUniversalTime()
    $script:PortfolioAssessmentCacheMemory['portfolio-assessment-global'] = @{
        CreatedAtUtc  = $nowUtc
        GeneratedAt   = $GeneratedAt
        Entries       = $Entries
        Summary       = $Summary
        SignalSources = $SignalSources
    }
}

function Clear-PortfolioAssessmentCache {
    $script:PortfolioAssessmentCacheMemory = @{}
}

function Clear-DocAuditCache {
    $script:DocAuditCacheMemory = @{}
    try {
        $cacheFile = Get-DocAuditCacheFilePath
        if (Test-Path -LiteralPath $cacheFile) { Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue }
    }
    catch { Write-HostLog ("DocAudit cache clear skipped: {0}" -f $_.Exception.Message) }
}

function Invoke-DocAuditScan {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$LocalRoots,
        [Parameter()]
        [int]$MaxDepth = 3
    )

    $standardsPath = Join-Path $WorkspaceRoot 'backend\config\doc-standards.json'
    $standards = Get-DocStandards -StandardsPath $standardsPath

    # Reuse the roadmap cache to enrich audit with roadmap state (avoid double scan)
    $settings = Get-HostSettings
    $ttlSeconds = Get-RoadmapCacheTtlSeconds -Settings $settings
    $roadmapCached = Get-RoadmapFromCache -TtlSeconds $ttlSeconds
    $roadmapEntries = if ($roadmapCached.hit) { @($roadmapCached.entries) } else {
        @(Invoke-RoadmapScan -LocalRoots $LocalRoots -MaxDepth $MaxDepth)
    }

    $results = Invoke-AuditRepoScan `
        -LocalRoots $LocalRoots `
        -MaxDepth $MaxDepth `
        -RoadmapEntries $roadmapEntries `
        -Standards $standards

    foreach ($r in @($results)) {
        $readinessLabel = [string]$r.dispatchReadiness
        Write-HostLog ("[TRACE] docaudit.scan repoName={0} readiness={1} critical={2} warning={3}" -f $r.repoName, $readinessLabel, $r.criticalCount, $r.warningCount)
    }

    return @($results)
}

function Invoke-RoadmapScan {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$LocalRoots,
        [Parameter()]
        [int]$MaxDepth = 3
    )

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($root in $LocalRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        try {
            # ROADMAP files sit one level below the repo directory, exactly like
            # the .git folder the doc-audit scanner uses for repo discovery at
            # Depth ($MaxDepth + 1). The file search must go one level deeper
            # than the repo depth or repos at the deepest discovered level are
            # doc-audited with their roadmap invisible (dispatchReadiness
            # then falsely reports missing-roadmap).
            $files = Get-ChildItem -Path $root -Recurse -Depth ($MaxDepth + 1) -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -imatch '^ROADMAP(\..+)?$' }
            foreach ($file in $files) {
                $repoName = $file.Directory.Name
                $repoPath = $file.DirectoryName
                $dir = $file.Directory
                while ($null -ne $dir) {
                    if (Test-Path (Join-Path $dir.FullName '.git')) {
                        $repoName = $dir.Name
                        $repoPath = $dir.FullName
                        break
                    }
                    $dir = $dir.Parent
                }
                # Parse the roadmap content to classify state and extract next pending item
                $parseResult = $null
                try {
                    $rawContent = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
                    $parseResult = Invoke-ParseRoadmapContent -Content $rawContent -SourcePath $file.FullName
                    Write-HostLog ("[TRACE] roadmap.parse repoName={0} state={1} pendingCount={2} completedCount={3}" -f $repoName, $parseResult.roadmapState, $parseResult.pendingCount, $parseResult.completedCount)
                    if ($parseResult.roadmapState -eq 'parse-error') {
                        Write-HostLog ("[WARN] roadmap.parse repoName={0} parseError={1}" -f $repoName, $parseResult.parseError)
                    }
                } catch {
                    Write-HostLog ("[WARN] roadmap.parse repoName={0} error={1}" -f $repoName, $_.Exception.Message)
                    $parseResult = [pscustomobject]@{
                        roadmapState    = 'parse-error'
                        pendingCount    = 0
                        completedCount  = 0
                        totalCount      = 0
                        nextPendingItem = $null
                        parseError      = $_.Exception.Message
                    }
                }

                $nextItem = $null
                if ($null -ne $parseResult -and $null -ne $parseResult.nextPendingItem) {
                    $nextItem = @{
                        text    = [string]$parseResult.nextPendingItem.text
                        section = [string]$parseResult.nextPendingItem.section
                    }
                }

                $activeRelease = if ($null -ne $parseResult) {
                    Get-ObjectPropertyValue -InputObject $parseResult -PropertyName 'activeRelease' -Default $null
                } else {
                    $null
                }
                $activePhasePlan = if ($null -ne $parseResult) {
                    Get-ObjectPropertyValue -InputObject $parseResult -PropertyName 'activePhasePlan' -Default $null
                } else {
                    $null
                }
                $budgetGuardrail = if ($null -ne $parseResult) {
                    Get-ObjectPropertyValue -InputObject $parseResult -PropertyName 'budgetGuardrail' -Default $null
                } else {
                    $null
                }

                $entries.Add([pscustomobject]@{
                    repoName        = $repoName
                    repoPath        = $repoPath
                    roadmapPath     = $file.FullName
                    lastModified    = $file.LastWriteTime.ToString('o')
                    sizeBytes       = [long]$file.Length
                    roadmapState    = if ($null -ne $parseResult) { [string]$parseResult.roadmapState } else { 'parse-error' }
                    pendingCount    = if ($null -ne $parseResult) { [int]$parseResult.pendingCount    } else { 0 }
                    completedCount  = if ($null -ne $parseResult) { [int]$parseResult.completedCount  } else { 0 }
                    nextPendingItem = $nextItem
                    activeRelease   = $activeRelease
                    activePhasePlan = $activePhasePlan
                    budgetGuardrail = $budgetGuardrail
                    estimatedSessionWorkUnits = if ($null -ne $activePhasePlan) {
                        Get-ObjectPropertyValue -InputObject $activePhasePlan -PropertyName 'workUnitsEstimated' -Default $null
                    } else {
                        $null
                    }
                })
            }
        }
        catch { Write-HostLog ("[TRACE] roadmap.scan root_error root={0} error={1}" -f $root, $_.Exception.Message) }
    }
    return @($entries)
}

function Get-RoadmapTaskHistory {
    param(
        [Parameter()]
        [int]$Limit = 25
    )

    $historyRoot = Join-Path $WorkspaceRoot 'output\roadmap-task-history'
    $runsPath = Join-Path $historyRoot 'runs'

    if (-not (Test-Path -LiteralPath $runsPath)) {
        return @()
    }

    $files = Get-ChildItem -Path $runsPath -Filter '*.summary.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First ([math]::Max($Limit, 1))

    $items = @()
    foreach ($file in $files) {
        try {
            $raw = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $summary = ConvertFrom-JsonCompat -Json $raw
            $items += [pscustomobject]@{
                runId = [string]$summary.runId
                status = [string]$summary.status
                repository = [string]$summary.repository
                selectedTask = if ($summary.ContainsKey('selectedTask')) { [string]$summary.selectedTask } else { '' }
                roadmapPath = if ($summary.ContainsKey('roadmapPath')) { [string]$summary.roadmapPath } else { '' }
                startedAt = if ($summary.ContainsKey('startedAt')) { [string]$summary.startedAt } else { '' }
                completedAt = if ($summary.ContainsKey('completedAt')) { [string]$summary.completedAt } else { '' }
                error = if ($summary.ContainsKey('error')) { [string]$summary.error } else { '' }
                summaryPath = $file.FullName
            }
        }
        catch {
            continue
        }
    }

    return @($items)
}

function Get-CopilotTaskDisplayText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    return ([regex]::Replace($Text, '\s*\[[a-zA-Z0-9_-]+\]', '')).Trim()
}

function Get-CopilotTaskComparisonKey {
    param([string]$Text)

    $displayText = Get-CopilotTaskDisplayText -Text $Text
    if ([string]::IsNullOrWhiteSpace($displayText)) {
        return ''
    }

    return (($displayText -replace '\s+', ' ').Trim().ToLowerInvariant())
}

function Get-CopilotTaskReadmeContext {
    param([string]$RepoPath)

    if ([string]::IsNullOrWhiteSpace($RepoPath) -or -not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
        return @{
            readmePath               = $null
            summary                  = ''
            headings                 = @()
            hasSetupGuidance         = $false
            hasUsageGuidance         = $false
            hasArchitectureGuidance  = $false
        }
    }

    $analysis = _GetReadmeAnalysis -LocalPath $RepoPath
    $content = [string](Get-ObjectPropertyValue -InputObject $analysis -PropertyName 'content' -Default '')
    $headings = @(
        [regex]::Matches($content, '(?im)^#{1,6}\s+(.+?)\s*$') |
            ForEach-Object { $_.Groups[1].Value.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -First 8
    )

    $paragraphs = [System.Collections.Generic.List[string]]::new()
    $buffer = [System.Collections.Generic.List[string]]::new()
    foreach ($rawLine in ($content -split '\r?\n')) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($buffer.Count -gt 0) {
                $paragraphs.Add(($buffer -join ' ').Trim())
                $buffer.Clear()
            }
            continue
        }

        if ($line -match '^#{1,6}\s+' -or
            $line -match '^\s*[-*]\s+' -or
            $line -match '^\s*```' -or
            $line -match '^\s*>\s*') {
            continue
        }

        $buffer.Add($line)
    }
    if ($buffer.Count -gt 0) {
        $paragraphs.Add(($buffer -join ' ').Trim())
    }

    $summary = (@($paragraphs | Select-Object -First 2) -join ' ').Trim()
    if ($summary.Length -gt 420) {
        $summary = $summary.Substring(0, 417).TrimEnd() + '...'
    }

    return @{
        readmePath              = Get-ObjectPropertyValue -InputObject $analysis -PropertyName 'readmePath' -Default $null
        summary                 = $summary
        headings                = @($headings)
        hasSetupGuidance        = [bool](Get-ObjectPropertyValue -InputObject $analysis -PropertyName 'hasSetupSection' -Default $false)
        hasUsageGuidance        = [bool](Get-ObjectPropertyValue -InputObject $analysis -PropertyName 'hasUsageSection' -Default $false)
        hasArchitectureGuidance = [bool](Get-ObjectPropertyValue -InputObject $analysis -PropertyName 'hasArchitectureSection' -Default $false)
    }
}

function Get-CopilotTaskReleaseContext {
    param(
        [string]$RoadmapContent,
        [string]$SelectedTask
    )

    $empty = @{
        releaseName         = $null
        releaseVersion      = $null
        releaseTitle        = $null
        releaseGoal         = ''
        pendingMilestones   = @()
        completedMilestones = @()
        acceptanceCriteria  = @()
        outOfScope          = @()
    }

    if ([string]::IsNullOrWhiteSpace($RoadmapContent)) {
        return $empty
    }

    $selectedRelease = Get-RoadmapSelectedReleaseContext -RoadmapContent $RoadmapContent -SelectedTask $SelectedTask
    if ($null -eq $selectedRelease -or [string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'releaseName' -Default ''))) {
        return $empty
    }

    return @{
        releaseName               = [string](Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'releaseName' -Default $null)
        releaseVersion            = [string](Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'releaseVersion' -Default $null)
        releaseTitle              = [string](Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'releaseTitle' -Default $null)
        releaseGoal               = [string](Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'releaseGoal' -Default '')
        pendingMilestones         = @(Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'pendingMilestones' -Default @())
        completedMilestones       = @(Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'completedMilestones' -Default @())
        acceptanceCriteria        = @(Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'acceptanceCriteria' -Default @())
        outOfScope                = @(Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'outOfScope' -Default @())
        phasePlan                 = @(Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'phasePlan' -Default @())
        activePhasePlan           = Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'activePhasePlan' -Default $null
        budgetGuardrail           = Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'budgetGuardrail' -Default $null
        estimatedSessionWorkUnits = Get-ObjectPropertyValue -InputObject $selectedRelease -PropertyName 'estimatedSessionWorkUnits' -Default $null
    }
}

function Get-CopilotTaskConstraints {
    param(
        [object]$ReleaseContext,
        [object]$AssessmentEntry,
        [array]$DocFindings = @()
    )

    $constraints = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($item in @(Get-ObjectPropertyValue -InputObject $ReleaseContext -PropertyName 'outOfScope' -Default @())) {
        $text = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $constraints.Add(@{ source = 'roadmap-out-of-scope'; text = $text })
        }
    }

    foreach ($reason in @(Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'blockingReasons' -Default @())) {
        $text = [string]$reason
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $constraints.Add(@{ source = 'portfolio-blocker'; text = $text })
        }
    }

    $criticalDocFindings = @($DocFindings | Where-Object {
        [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'severity' -Default '') -eq 'critical'
    })
    foreach ($finding in $criticalDocFindings) {
        $message = [string](Get-ObjectPropertyValue -InputObject $finding -PropertyName 'message' -Default '')
        $action = [string](Get-ObjectPropertyValue -InputObject $finding -PropertyName 'recommendedAction' -Default '')
        $parts = @($message, $action) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($parts.Count -gt 0) {
            $constraints.Add(@{ source = 'docs-critical'; text = ($parts -join ' -> ') })
        }
    }

    return @($constraints)
}

function Find-PortfolioAssessmentEntry {
    param(
        [string]$RepoName,
        [object]$Settings
    )

    $portfolioTtl = Get-PortfolioAssessmentCacheTtlSeconds -Settings $Settings
    $portfolioCache = Get-PortfolioAssessmentFromCache -TtlSeconds $portfolioTtl
    if (-not $portfolioCache.hit -or $null -eq $portfolioCache.entries) {
        return $null
    }

    return @($portfolioCache.entries) | Where-Object {
        [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '') -eq $RepoName
    } | Select-Object -First 1
}

function Get-OperationsPromptRefinementRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $true)]
        [string]$RunId
    )

    if ([string]::IsNullOrWhiteSpace($RepoName) -or [string]::IsNullOrWhiteSpace($RunId)) {
        return $null
    }

    $safeRepoName = $RepoName -replace '[\\/:*?"<>|]', '_'
    $refineRoot = Join-Path $WorkspaceRoot 'output\roadmap-task-history\prompt-refinements'
    $refineFile = Join-Path $refineRoot "$safeRepoName.refinements.jsonl"
    if (-not (Test-Path -LiteralPath $refineFile -PathType Leaf)) {
        return $null
    }

    try {
        return @(
            Get-Content -LiteralPath $refineFile -Encoding UTF8 -ErrorAction Stop |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object {
                    try { ConvertFrom-JsonCompat -Json $_ } catch { $null }
                } |
                Where-Object {
                    $null -ne $_ -and [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'runId' -Default '') -eq $RunId
                } |
                Select-Object -First 1
        )[0]
    } catch {
        Write-HostLog ("WARN operations.prompt.refine could not read refinement record for repoName={0} runId={1}: {2}" -f $RepoName, $RunId, $_.Exception.Message)
        return $null
    }
}

function Resolve-RoadmapPathForRepo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter()]
        [string]$LocalPath = '',

        [Parameter()]
        [object]$RoadmapEntry = $null
    )

    $candidateFromEntry = [string](Get-ObjectPropertyValue -InputObject $RoadmapEntry -PropertyName 'roadmapPath' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($candidateFromEntry) -and (Test-Path -LiteralPath $candidateFromEntry -PathType Leaf)) {
        return $candidateFromEntry
    }

    if (-not [string]::IsNullOrWhiteSpace($LocalPath) -and (Test-Path -LiteralPath $LocalPath -PathType Container)) {
        foreach ($candidateName in @('ROADMAP.md', 'Roadmap.md', 'docs\planning\roadmap.md', 'docs\ROADMAP.md', 'roadmap.md')) {
            $candidatePath = Join-Path $LocalPath $candidateName
            if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
                return $candidatePath
            }
        }
    }

    return ''
}

function Get-DispatchPlanningContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter()]
        [string]$RoadmapPath = '',

        [Parameter()]
        [string]$PromptRefinementRunId = '',

        [Parameter()]
        [object]$AssessmentEntry = $null
    )

    $defaultEstimatedUnits = [double](Get-AgentBudgetLedgerConfig -WorkspaceRoot $WorkspaceRoot -Settings (Get-HostSettings)).unitWeights.agentRun
    $planning = @{
        roadmapPath             = if (-not [string]::IsNullOrWhiteSpace($RoadmapPath)) { $RoadmapPath } else { '' }
        selectedTaskText        = ''
        selectedTaskSection     = ''
        releaseName             = $null
        releaseVersion          = $null
        releaseTitle            = $null
        plannedPhaseName        = $null
        workUnitsEstimated      = $defaultEstimatedUnits
        workUnitsEstimateSource = 'budget-default-agent-run'
        budgetGuardrail         = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($PromptRefinementRunId)) {
        $refineRecord = Get-OperationsPromptRefinementRecord -RepoName $RepoName -RunId $PromptRefinementRunId
        if ($null -ne $refineRecord) {
            $planning.selectedTaskText = [string](Get-ObjectPropertyValue -InputObject $refineRecord -PropertyName 'selectedItemText' -Default '')
            $planning.selectedTaskSection = [string](Get-ObjectPropertyValue -InputObject $refineRecord -PropertyName 'selectedItemSection' -Default '')
        }
    }

    if ([string]::IsNullOrWhiteSpace($planning.selectedTaskText) -and $null -ne $AssessmentEntry) {
        $topValueItem = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'topValueItem' -Default $null
        $planning.selectedTaskText = [string](Get-ObjectPropertyValue -InputObject $topValueItem -PropertyName 'text' -Default (Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'nextPendingItemText' -Default ''))
        $planning.selectedTaskSection = [string](Get-ObjectPropertyValue -InputObject $topValueItem -PropertyName 'section' -Default '')
    }

    if (-not [string]::IsNullOrWhiteSpace($planning.roadmapPath) -and (Test-Path -LiteralPath $planning.roadmapPath -PathType Leaf)) {
        try {
            $roadmapContent = Get-Content -LiteralPath $planning.roadmapPath -Raw -Encoding UTF8 -ErrorAction Stop
            $releaseContext = Get-CopilotTaskReleaseContext -RoadmapContent $roadmapContent -SelectedTask $planning.selectedTaskText

            $planning.releaseName = Get-ObjectPropertyValue -InputObject $releaseContext -PropertyName 'releaseName' -Default $null
            $planning.releaseVersion = Get-ObjectPropertyValue -InputObject $releaseContext -PropertyName 'releaseVersion' -Default $null
            $planning.releaseTitle = Get-ObjectPropertyValue -InputObject $releaseContext -PropertyName 'releaseTitle' -Default $null
            $planning.budgetGuardrail = Get-ObjectPropertyValue -InputObject $releaseContext -PropertyName 'budgetGuardrail' -Default $null

            $activePhasePlan = Get-ObjectPropertyValue -InputObject $releaseContext -PropertyName 'activePhasePlan' -Default $null
            if ($null -ne $activePhasePlan) {
                $planning.plannedPhaseName = [string](Get-ObjectPropertyValue -InputObject $activePhasePlan -PropertyName 'phaseName' -Default '')
                $phaseEstimate = Get-ObjectPropertyValue -InputObject $activePhasePlan -PropertyName 'workUnitsEstimated' -Default $null
                if ($null -ne $phaseEstimate) {
                    $planning.workUnitsEstimated = [double]$phaseEstimate
                    $planning.workUnitsEstimateSource = 'roadmap-phase-plan'
                }
            }
        } catch {
            Write-HostLog ("WARN roadmap.dispatch planning-context could not parse roadmap for repoName={0}: {1}" -f $RepoName, $_.Exception.Message)
        }
    }

    if ($planning.workUnitsEstimateSource -eq 'budget-default-agent-run' -and $null -ne $AssessmentEntry) {
        $assessmentEstimate = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'estimatedSessionWorkUnits' -Default $null
        if ($null -ne $assessmentEstimate) {
            $planning.workUnitsEstimated = [double]$assessmentEstimate
            $planning.workUnitsEstimateSource = 'assessment-cache'
        }

        if ($null -eq $planning.budgetGuardrail) {
            $planning.budgetGuardrail = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'budgetGuardrail' -Default $null
        }

        if ([string]::IsNullOrWhiteSpace([string]$planning.plannedPhaseName)) {
            $assessmentPhase = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'activePhasePlan' -Default $null
            $planning.plannedPhaseName = [string](Get-ObjectPropertyValue -InputObject $assessmentPhase -PropertyName 'phaseName' -Default '')
        }

        if ($null -eq $planning.releaseName) {
            $assessmentRelease = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'activeRelease' -Default $null
            $planning.releaseName = Get-ObjectPropertyValue -InputObject $assessmentRelease -PropertyName 'releaseName' -Default $null
            $planning.releaseVersion = Get-ObjectPropertyValue -InputObject $assessmentRelease -PropertyName 'releaseVersion' -Default $null
            $planning.releaseTitle = Get-ObjectPropertyValue -InputObject $assessmentRelease -PropertyName 'releaseTitle' -Default $null
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$planning.plannedPhaseName)) {
        $planning.plannedPhaseName = $null
    }

    return $planning
}

function Get-QuotaPendingWorkSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings,

        [Parameter()]
        [string]$ExcludeRepoName = ''
    )

    $portfolioTtl = Get-PortfolioAssessmentCacheTtlSeconds -Settings $Settings
    $portfolioCache = Get-PortfolioAssessmentFromCache -TtlSeconds $portfolioTtl
    if (-not $portfolioCache.hit -or $null -eq $portfolioCache.entries) {
        return @()
    }

    return @(
        @($portfolioCache.entries) |
            Where-Object {
                [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'dispatchReadiness' -Default '') -eq 'ready' -and
                [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '') -ne $ExcludeRepoName
            } |
            Select-Object -First 10 |
            ForEach-Object {
                [ordered]@{
                    repoName             = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')
                    nextPendingItemText  = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'nextPendingItemText' -Default '')
                    lifecycleState       = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'lifecycleState' -Default '')
                    recommendedAction    = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'recommendedAction' -Default '')
                    estimatedSessionWorkUnits = Get-ObjectPropertyValue -InputObject $_ -PropertyName 'estimatedSessionWorkUnits' -Default $null
                }
            }
    )
}

function Normalize-TaskSelectionMatchValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    $normalized = [string]$Value
    try {
        $normalized = $normalized.Normalize([Text.NormalizationForm]::FormKC)
    } catch {
        # Fall back to the original value when Unicode normalization is unavailable.
    }

    $normalized = $normalized `
        -replace '[\u2010\u2011\u2012\u2013\u2014\u2015\u2212]', '-' `
        -replace '\s+', ' '

    return $normalized.Trim().ToLowerInvariant()
}

function Build-CopilotTaskPacket {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter()]
        [string]$RoadmapPath = '',

        [Parameter()]
        [object]$AuditEntry = $null,

        [Parameter()]
        [object]$AssessmentEntry = $null,

        # When provided, overrides value-ranking and roadmap-order selection so the
        # packet is built around this specific roadmap item text/section.
        [Parameter()]
        [string]$ForcedItemText = '',

        [Parameter()]
        [string]$ForcedItemSection = ''
    )

    # Step 1: Resolve roadmap path from cache or parameter
    $settings  = Get-HostSettings
    $roadmapTtl = Get-RoadmapCacheTtlSeconds -Settings $settings
    $roadmapCache = Get-RoadmapFromCache -TtlSeconds $roadmapTtl
    $roadmapEntry = $null
    if ($roadmapCache.hit -and $roadmapCache.entries) {
        $roadmapEntry = @($roadmapCache.entries) | Where-Object { [string]$_.repoName -eq $RepoName } | Select-Object -First 1
    }

    if ($null -eq $roadmapEntry) {
        $roadmapAuditTtl = Get-RoadmapAuditCacheTtlSeconds -Settings $settings
        $roadmapAuditCache = Get-RoadmapAuditFromCache -TtlSeconds $roadmapAuditTtl
        if ($roadmapAuditCache.hit -and $roadmapAuditCache.entries) {
            $roadmapEntry = @($roadmapAuditCache.entries) | Where-Object {
                $n = if ($_ -is [System.Collections.IDictionary]) { [string]$_['repoName'] } else { [string]$_.repoName }
                $n -eq $RepoName
            } | Select-Object -First 1
        }
    }

    $effectiveRoadmapPath = $RoadmapPath
    if ([string]::IsNullOrWhiteSpace($effectiveRoadmapPath) -and $null -ne $roadmapEntry) {
        $rp = if ($roadmapEntry -is [System.Collections.IDictionary]) { $roadmapEntry['roadmapPath'] } else { $roadmapEntry.roadmapPath }
        if (-not [string]::IsNullOrWhiteSpace([string]$rp)) { $effectiveRoadmapPath = [string]$rp }
    }

    if ([string]::IsNullOrWhiteSpace($effectiveRoadmapPath) -and $null -ne $AuditEntry) {
        $auditRepoPath = if ($AuditEntry -is [System.Collections.IDictionary]) { [string](Get-ValueOrDefault $AuditEntry['repoPath'] '') } else { [string](Get-ValueOrDefault $AuditEntry.repoPath '') }
        if (-not [string]::IsNullOrWhiteSpace($auditRepoPath) -and (Test-Path -LiteralPath $auditRepoPath -PathType Container)) {
            foreach ($candidateName in @('ROADMAP.md', 'Roadmap.md', 'docs\planning\roadmap.md', 'docs\ROADMAP.md', 'roadmap.md')) {
                $candidatePath = Join-Path $auditRepoPath $candidateName
                if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
                    $effectiveRoadmapPath = $candidatePath
                    break
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($effectiveRoadmapPath) -or -not (Test-Path -LiteralPath $effectiveRoadmapPath)) {
        throw "Roadmap file not found for repo '$RepoName'. Ensure a roadmap scan has been run (GET /api/roadmap/index or POST /api/roadmap/scan), or provide roadmapPath from the Work Queue entry."
    }

    # Step 2: Parse roadmap with full section context
    $rawContent = Get-Content -LiteralPath $effectiveRoadmapPath -Raw -Encoding UTF8
    $parseResult = Invoke-ParseRoadmapContent -Content $rawContent -SourcePath $effectiveRoadmapPath

    if ($parseResult.roadmapState -ne 'pending') {
        throw "Repository '$RepoName' has no pending roadmap items (state: $($parseResult.roadmapState))."
    }

    # Step 3: Extract selected item + neighboring context (preserving document order)
    $selected = $parseResult.nextPendingItem
    $allPendingInOrder = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($sec in @($parseResult.sections)) {
        $secName = [string]$sec.name
        foreach ($item in @($sec.pendingItems)) {
            $allPendingInOrder.Add([pscustomobject]@{
                text    = [string]$item
                section = $secName
                tags    = @()
            })
        }
    }

    $selectionSource = 'roadmap-order'

    # Operator-forced item takes precedence over value ranking.
    if (-not [string]::IsNullOrWhiteSpace($ForcedItemText)) {
        $normalizedForcedText = Normalize-TaskSelectionMatchValue -Value $ForcedItemText
        $normalizedForcedSection = Normalize-TaskSelectionMatchValue -Value $ForcedItemSection
        $forcedMatch = @($allPendingInOrder | Where-Object {
            (Normalize-TaskSelectionMatchValue -Value ([string]$_.text)) -eq $normalizedForcedText -and (
                [string]::IsNullOrWhiteSpace($normalizedForcedSection) -or (Normalize-TaskSelectionMatchValue -Value ([string]$_.section)) -eq $normalizedForcedSection
            )
        } | Select-Object -First 1)
        if ($forcedMatch.Count -gt 0 -and $null -ne $forcedMatch[0]) {
            $selected = [pscustomobject]@{
                text    = [string]$forcedMatch[0].text
                section = [string]$forcedMatch[0].section
                tags    = @($forcedMatch[0].tags)
            }
            $selectionSource = 'operator-selected'
        }
        # If the forced text is not found in pending items, fall through to value-ranking below.
    }

    $topValueItem = if ($null -ne $AssessmentEntry) {
        Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'topValueItem' -Default $null
    } else {
        $null
    }
    if ($selectionSource -eq 'roadmap-order' -and $null -ne $topValueItem) {
        $preferredText = [string](Get-ObjectPropertyValue -InputObject $topValueItem -PropertyName 'text' -Default '')
        $preferredSection = [string](Get-ObjectPropertyValue -InputObject $topValueItem -PropertyName 'section' -Default '')
        $normalizedPreferredText = Normalize-TaskSelectionMatchValue -Value $preferredText
        $normalizedPreferredSection = Normalize-TaskSelectionMatchValue -Value $preferredSection
        $preferredMatch = @($allPendingInOrder | Where-Object {
            (Normalize-TaskSelectionMatchValue -Value ([string]$_.text)) -eq $normalizedPreferredText -and (
                [string]::IsNullOrWhiteSpace($normalizedPreferredSection) -or (Normalize-TaskSelectionMatchValue -Value ([string]$_.section)) -eq $normalizedPreferredSection
            )
        } | Select-Object -First 1)
        if ($preferredMatch.Count -gt 0 -and $null -ne $preferredMatch[0]) {
            $selected = [pscustomobject]@{
                text    = [string]$preferredMatch[0].text
                section = [string]$preferredMatch[0].section
                tags    = @($preferredMatch[0].tags)
            }
            $selectionSource = 'value-ranked'
        }
    }

    $selectedIdx = -1
    for ($i = 0; $i -lt $allPendingInOrder.Count; $i++) {
        if ($allPendingInOrder[$i].text -eq [string]$selected.text -and $allPendingInOrder[$i].section -eq [string]$selected.section) {
            $selectedIdx = $i
            break
        }
    }

    $previousItem = $null
    $followUpCandidates = @()
    if ($selectedIdx -ge 0) {
        if ($selectedIdx -gt 0) {
            $previousItem = [string]$allPendingInOrder[$selectedIdx - 1].text
        }
        $followUpCandidates = @($allPendingInOrder | Select-Object -Skip ($selectedIdx + 1) -First 3 | ForEach-Object {
            @{ text = [string]$_.text; section = [string]$_.section }
        })
    }

    # Step 4: Extract doc findings from audit entry
    $docFindings = @()
    $repoPath = ''
    $dispatchReadiness = 'ready'
    if ($null -ne $AuditEntry) {
        $docFindings = if ($AuditEntry -is [System.Collections.IDictionary]) {
            if ($AuditEntry.ContainsKey('docFindings') -and $null -ne $AuditEntry['docFindings']) { @($AuditEntry['docFindings']) } else { @() }
        } else {
            if ($null -ne $AuditEntry.PSObject -and ($AuditEntry.PSObject.Properties.Name -contains 'docFindings')) { @($AuditEntry.docFindings) } else { @() }
        }
        $repoPath = if ($AuditEntry -is [System.Collections.IDictionary]) { [string](Get-ValueOrDefault $AuditEntry['repoPath'] '') } else { [string](Get-ValueOrDefault $AuditEntry.repoPath '') }
        $dispatchReadiness = if ($AuditEntry -is [System.Collections.IDictionary]) { [string](Get-ValueOrDefault $AuditEntry['dispatchReadiness'] 'ready') } else { [string](Get-ValueOrDefault $AuditEntry.dispatchReadiness 'ready') }
    } elseif ($null -ne $roadmapEntry) {
        $repoPath = if ($roadmapEntry -is [System.Collections.IDictionary]) { [string](Get-ValueOrDefault $roadmapEntry['repoPath'] '') } else { [string](Get-ValueOrDefault $roadmapEntry.repoPath '') }
    }

    if ([string]::IsNullOrWhiteSpace($repoPath) -and $null -ne $AssessmentEntry) {
        $repoPath = [string](Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'localPath' -Default '')
    }
    if (($dispatchReadiness -eq 'ready' -or [string]::IsNullOrWhiteSpace($dispatchReadiness)) -and $null -ne $AssessmentEntry) {
        $dispatchReadiness = [string](Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'dispatchReadiness' -Default $dispatchReadiness)
    }

    $readmeContext = Get-CopilotTaskReadmeContext -RepoPath $repoPath
    $releaseContext = Get-CopilotTaskReleaseContext -RoadmapContent $rawContent -SelectedTask ([string]$selected.text)
    $constraints = @(Get-CopilotTaskConstraints -ReleaseContext $releaseContext -AssessmentEntry $AssessmentEntry -DocFindings @($docFindings))

    # Step 5: Build acceptance criteria
    $acceptanceCriteria = @(
        @(Get-ObjectPropertyValue -InputObject $releaseContext -PropertyName 'acceptanceCriteria' -Default @()) |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
    $acceptanceCriteria += @(
        "The selected roadmap item is implemented end-to-end with production-safe changes.",
        "All affected tests pass and no new test failures are introduced.",
        "Documentation updated to reflect the change (README, CHANGELOG, relevant docs).",
        "Roadmap checkbox for the completed item is marked `- [x]` in $([System.IO.Path]::GetFileName($effectiveRoadmapPath)).",
        "No placeholder stubs or TODO comments left in modified code."
    )
    $criticalFindings = @($docFindings | Where-Object {
        $sev = if ($_ -is [System.Collections.IDictionary]) { [string]$_['severity'] } else { [string]$_.severity }
        $sev -eq 'critical'
    })
    if ($criticalFindings.Count -gt 0) {
        $acceptanceCriteria += "Resolve the $($criticalFindings.Count) critical documentation finding(s) listed in this packet."
    }
    $acceptanceCriteria = @($acceptanceCriteria | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)

    # Step 6: Guardrails
    $guardrails = @(
        @{ rule = "Do not introduce placeholder stub-outs or empty TODO blocks." },
        @{ rule = "Update affected documentation when any workflow or API behavior changes." },
        @{ rule = "Preserve existing launcher, logging, and API host behavior unless the selected roadmap item explicitly changes them." },
        @{ rule = "Keep all changes tightly scoped to the selected roadmap item." },
        @{ rule = "Do not silently mark roadmap items complete without fully implementing them." },
        @{ rule = "Run the relevant tests/quality gates before finalizing." }
    )

    # Step 6b: Recent execution history for this repo — surface what has already run and outcomes
    $executionHistorySection = ''
    try {
        $ledger     = Read-ExecutionLedger -WorkspaceRoot $WorkspaceRoot
        $repoHistory = @($ledger.history | Where-Object { $_.repoName -eq $RepoName } | Select-Object -Last 5)
        if ($repoHistory.Count -gt 0) {
            $histLines = @($repoHistory | ForEach-Object {
                $ts    = if ($_.timestamp) { ([datetime]$_.timestamp).ToString('yyyy-MM-dd') } else { 'unknown' }
                $task  = if ([string]::IsNullOrWhiteSpace($_.taskText)) { '(unknown task)' } else { $_.taskText }
                $out   = if ([string]::IsNullOrWhiteSpace($_.outcome)) { $_.event } else { $_.outcome }
                "  [$ts] $($_.event): $task — $out"
            })
            $executionHistorySection = "`n`nExecution history for this repo (most recent first):`n" + ($histLines -join "`n")
        }
    } catch { }

    # Step 6c: Roadmap audit quality context — maturity level and high-severity findings
    $auditQualitySection = ''
    try {
        if ($script:RoadmapAuditCacheMemory.ContainsKey($RepoName)) {
            $cachedAudit  = $script:RoadmapAuditCacheMemory[$RepoName]
            $auditScore   = if ($cachedAudit -is [System.Collections.IDictionary]) { $cachedAudit['score'] } else { $cachedAudit.score }
            $auditLevel   = if ($cachedAudit -is [System.Collections.IDictionary]) { $cachedAudit['maturityLevel'] } else { $cachedAudit.maturityLevel }
            if ($null -ne $auditScore -or $null -ne $auditLevel) {
                $auditQualitySection = "`n`nRoadmap quality: $auditLevel (score $auditScore/100)"
                $auditFindings = if ($cachedAudit -is [System.Collections.IDictionary]) {
                    if ($cachedAudit.ContainsKey('findings') -and $null -ne $cachedAudit['findings']) { @($cachedAudit['findings']) } else { @() }
                } else {
                    if ($null -ne $cachedAudit.PSObject -and ($cachedAudit.PSObject.Properties.Name -contains 'findings')) { @($cachedAudit.findings) } else { @() }
                }
                $critAudit = @($auditFindings | Where-Object {
                    $sev = if ($_ -is [System.Collections.IDictionary]) { [string]$_['severity'] } else { [string]$_.severity }
                    $sev -in @('critical', 'high')
                } | Select-Object -First 3)
                if ($critAudit.Count -gt 0) {
                    $auditLines = @($critAudit | ForEach-Object {
                        $code = if ($_ -is [System.Collections.IDictionary]) { [string]$_['ruleCode'] } else { [string]$_.ruleCode }
                        $msg  = if ($_ -is [System.Collections.IDictionary]) { [string]$_['message'] } else { [string]$_.message }
                        "  [$code] $msg"
                    })
                    $auditQualitySection += " — high/critical audit findings:`n" + ($auditLines -join "`n")
                }
            }
        }
    } catch { }

    # Step 6d: Cross-cutting tag context from parsed roadmap
    $tagSection = ''
    if ($parseResult.PSObject.Properties['allTags'] -and $parseResult.allTags.Count -gt 0) {
        $tagSection = "`n`nCross-cutting concern tags across pending items: " + ($parseResult.allTags -join ', ')
        if ($null -ne $selected -and $selected.PSObject.Properties['tags'] -and @($selected.tags).Count -gt 0) {
            $tagSection += "`nThis task is tagged: " + (@($selected.tags) -join ', ')
        }
    }

    # Step 7: Assemble prompt from all context
    $neighboringLines = ''
    if (-not [string]::IsNullOrWhiteSpace($previousItem)) {
        $neighboringLines += "`n  Previous item: $previousItem"
    }
    if ($followUpCandidates.Count -gt 0) {
        $followUpLines = @($followUpCandidates | ForEach-Object { "  - $($_['text']) (section: $($_['section']))" })
        $neighboringLines += "`n  Follow-up candidates after this item:`n" + ($followUpLines -join "`n")
    }

    $releaseSummarySection = ''
    $releaseName = [string](Get-ObjectPropertyValue -InputObject $releaseContext -PropertyName 'releaseName' -Default '')
    $releaseGoal = [string](Get-ObjectPropertyValue -InputObject $releaseContext -PropertyName 'releaseGoal' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($releaseName)) {
        $releaseSummarySection = "`nRelease context: $releaseName"
        if (-not [string]::IsNullOrWhiteSpace($releaseGoal)) {
            $releaseSummarySection += "`nRelease goal: $releaseGoal"
        }
        $releaseOutOfScope = @(
            Get-ObjectPropertyValue -InputObject $releaseContext -PropertyName 'outOfScope' -Default @()
        )
        if ($releaseOutOfScope.Count -gt 0) {
            $releaseSummarySection += "`nDo not drift into out-of-scope work:`n" + (@($releaseOutOfScope | ForEach-Object { "  - $_" }) -join "`n")
        }
    }

    $readmeSummarySection = ''
    $readmeSummary = [string](Get-ObjectPropertyValue -InputObject $readmeContext -PropertyName 'summary' -Default '')
    $readmeHeadings = @(
        Get-ObjectPropertyValue -InputObject $readmeContext -PropertyName 'headings' -Default @()
    )
    if (-not [string]::IsNullOrWhiteSpace($readmeSummary)) {
        $readmeSummarySection = "`n`nREADME summary:`n  $readmeSummary"
        if ($readmeHeadings.Count -gt 0) {
            $readmeSummarySection += "`nKey README headings: " + (@($readmeHeadings | Select-Object -First 6) -join ', ')
        }
    }

    # Doc findings block for prompt
    $docFindingsSummary = ''
    if ($docFindings.Count -gt 0) {
        $lines = @($docFindings | ForEach-Object {
            $sev  = if ($_ -is [System.Collections.IDictionary]) { [string]$_['severity'] } else { [string]$_.severity }
            $file = if ($_ -is [System.Collections.IDictionary]) { [string]$_['file'] } else { [string]$_.file }
            $msg  = if ($_ -is [System.Collections.IDictionary]) { [string]$_['message'] } else { [string]$_.message }
            $rec  = if ($_ -is [System.Collections.IDictionary]) { [string]$_['recommendedAction'] } else { [string]$_.recommendedAction }
            "  [$($sev.ToUpper())] $file`: $msg → $rec"
        })
        $docFindingsSummary = "`n`nDocumentation findings for this repository:`n" + ($lines -join "`n")
    }

    $portfolioSummarySection = ''
    if ($null -ne $AssessmentEntry) {
        $lifecycleState = [string](Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'lifecycleState' -Default '')
        $recommendedAction = [string](Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'recommendedAction' -Default '')
        $maturityLevel = [string](Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'maturityLevel' -Default '')
        $maturityScore = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'maturityScore' -Default $null
        $readmeScore = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'readmeScore' -Default $null
        $roadmapScore = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'roadmapScore' -Default $null
        $documentationHealthScore = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'documentationHealthScore' -Default $null

        $portfolioSummarySection = "`n`nPortfolio assessment context:"
        if (-not [string]::IsNullOrWhiteSpace($lifecycleState)) {
            $portfolioSummarySection += "`n  Lifecycle state: $lifecycleState"
        }
        if (-not [string]::IsNullOrWhiteSpace($recommendedAction)) {
            $portfolioSummarySection += "`n  Recommended action: $recommendedAction"
        }
        if (-not [string]::IsNullOrWhiteSpace($maturityLevel)) {
            $portfolioSummarySection += "`n  Maturity: $maturityLevel"
            if ($null -ne $maturityScore) {
                $portfolioSummarySection += " (score $maturityScore/100)"
            }
        }
        if ($null -ne $readmeScore -or $null -ne $roadmapScore -or $null -ne $documentationHealthScore) {
            $portfolioSummarySection += "`n  Scores: README=$readmeScore, ROADMAP=$roadmapScore, Docs health=$documentationHealthScore"
        }
    }

    $selectedValueItem = $null
    if ($null -ne $AssessmentEntry) {
        $pendingItems = @(Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'pendingItems' -Default @())
        $selectedValueItem = @($pendingItems | Where-Object {
            [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'text' -Default '') -eq [string]$selected.text -and
            [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'section' -Default '') -eq [string]$selected.section
        } | Select-Object -First 1)
        if ($selectedValueItem.Count -gt 0) {
            $selectedValueItem = $selectedValueItem[0]
        } else {
            $selectedValueItem = $null
        }
    }

    $valueSummarySection = ''
    if ($null -ne $selectedValueItem -or $null -ne $topValueItem) {
        $effectiveValueItem = if ($null -ne $selectedValueItem) { $selectedValueItem } else { $topValueItem }
        $valueScore = Get-ObjectPropertyValue -InputObject $effectiveValueItem -PropertyName 'valueScore' -Default $null
        $valueTier = [string](Get-ObjectPropertyValue -InputObject $effectiveValueItem -PropertyName 'valueTier' -Default '')
        $valueRationale = @(
            Get-ObjectPropertyValue -InputObject $effectiveValueItem -PropertyName 'valueRationale' -Default @()
        )
        $valueSummarySection = "`n`nValue rationale:"
        $valueSummarySection += "`n  Selected by: $selectionSource"
        if ($null -ne $valueScore) {
            $valueSummarySection += "`n  Score: $valueScore"
        }
        if (-not [string]::IsNullOrWhiteSpace($valueTier)) {
            $valueSummarySection += "`n  Tier: $valueTier"
        }
        if ($valueRationale.Count -gt 0) {
            $valueSummarySection += "`n  Why this item matters:`n" + (@($valueRationale | ForEach-Object { "  - $_" }) -join "`n")
        }
    }

    $budgetSummarySection = ''
    $releaseActivePhase = Get-ObjectPropertyValue -InputObject $releaseContext -PropertyName 'activePhasePlan' -Default $null
    $releaseBudgetGuardrail = Get-ObjectPropertyValue -InputObject $releaseContext -PropertyName 'budgetGuardrail' -Default $null
    $plannedPhaseName = [string](Get-ObjectPropertyValue -InputObject $releaseActivePhase -PropertyName 'phaseName' -Default '')
    $estimatedSessionWorkUnits = Get-ObjectPropertyValue -InputObject $releaseActivePhase -PropertyName 'workUnitsEstimated' -Default (Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'estimatedSessionWorkUnits' -Default $null)
    if ($null -ne $estimatedSessionWorkUnits -or $null -ne $releaseBudgetGuardrail) {
        $budgetSummarySection = "`n`nBudget / quota planning context:"
        if (-not [string]::IsNullOrWhiteSpace($plannedPhaseName)) {
            $budgetSummarySection += "`n  Active phase: $plannedPhaseName"
        }
        if ($null -ne $estimatedSessionWorkUnits) {
            $budgetSummarySection += "`n  Estimated session work units: $estimatedSessionWorkUnits"
        }
        $releaseEstimatedUnits = Get-ObjectPropertyValue -InputObject $releaseBudgetGuardrail -PropertyName 'estimatedReleaseWorkUnits' -Default $null
        $releaseMaxPerPhase = Get-ObjectPropertyValue -InputObject $releaseBudgetGuardrail -PropertyName 'maxUnitsPerPhase' -Default $null
        if ($null -ne $releaseEstimatedUnits -or $null -ne $releaseMaxPerPhase) {
            $budgetSummarySection += "`n  Release guardrail:"
            if ($null -ne $releaseEstimatedUnits) {
                $budgetSummarySection += " estimated release units=$releaseEstimatedUnits"
            }
            if ($null -ne $releaseMaxPerPhase) {
                $budgetSummarySection += ", max per phase=$releaseMaxPerPhase"
            }
        }
    }

    $constraintSummarySection = ''
    if ($constraints.Count -gt 0) {
        $constraintSummarySection = "`n`nExplicit constraints:"
        $constraintSummarySection += "`n" + (@($constraints | ForEach-Object {
            $source = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'source' -Default 'context')
            $text = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'text' -Default '')
            "  - [$source] $text"
        }) -join "`n")
    }

    $guardrailLines = @($guardrails | ForEach-Object { "- $($_['rule'])" })
    $criteriLines   = @($acceptanceCriteria | ForEach-Object { "- $_" })

    $generatedPrompt = @"
Continue roadmap execution for repository: $RepoName

Roadmap file: $effectiveRoadmapPath
Selected section: $([string]$selected.section)
Selected task: $([string]$selected.text)$neighboringLines

Dispatch readiness: $dispatchReadiness$releaseSummarySection$budgetSummarySection$portfolioSummarySection$valueSummarySection$readmeSummarySection$auditQualitySection$tagSection$docFindingsSummary$constraintSummarySection$executionHistorySection

Acceptance criteria:
$($criteriLines -join "`n")

Guardrails (must be respected):
$($guardrailLines -join "`n")

Execution requirements:
1. Verify the most recently completed roadmap entries are truly complete across code, tests, and docs.
2. Implement the selected task end-to-end with production-safe changes.
3. Update documentation (README, CHANGELOG, etc.) for completed work.
4. Mark the completed roadmap checkbox as ``- [x]`` in the roadmap file.
5. Run the repo's relevant tests/quality gates before finalizing.
"@

    # Step 8: Stable run ID and history paths
    $runId = "{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $historyRoot = Join-Path $WorkspaceRoot 'output\roadmap-task-history'
    $runsPath    = Join-Path $historyRoot 'runs'
    $null = New-Item -ItemType Directory -Path $runsPath -Force -ErrorAction SilentlyContinue

    return @{
        packetVersion      = '1.1'
        runId              = $runId
        createdAt          = (Get-Date).ToUniversalTime().ToString('o')
        repoContext        = @{
            repoName                     = $RepoName
            repoPath                     = $repoPath
            roadmapPath                  = $effectiveRoadmapPath
            dispatchReadiness            = $dispatchReadiness
            lifecycleState               = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'lifecycleState' -Default $null
            recommendedAction            = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'recommendedAction' -Default $null
            blockingReasons              = @(Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'blockingReasons' -Default @())
            maturityLevel                = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'maturityLevel' -Default $null
            maturityScore                = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'maturityScore' -Default $null
            sourceCoverage               = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'sourceCoverage' -Default $null
            dispatchReadinessExplanation = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'dispatchReadinessExplanation' -Default $null
            readmeScore                  = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'readmeScore' -Default $null
            roadmapScore                 = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'roadmapScore' -Default $null
            documentationHealthScore     = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'documentationHealthScore' -Default $null
            pendingItemCount             = Get-ObjectPropertyValue -InputObject $AssessmentEntry -PropertyName 'pendingItemCount' -Default $null
            estimatedSessionWorkUnits    = $estimatedSessionWorkUnits
            plannedPhaseName             = if (-not [string]::IsNullOrWhiteSpace($plannedPhaseName)) { $plannedPhaseName } else { $null }
        }
        readmeContext       = $readmeContext
        roadmapContext      = $releaseContext
        selectedRoadmapItem = @{
            text            = [string]$selected.text
            section         = [string]$selected.section
            tags            = @($selected.tags)
            previousItem    = $previousItem
            nextItem        = if ($followUpCandidates.Count -gt 0) { [string]$followUpCandidates[0]['text'] } else { $null }
            selectionSource = $selectionSource
        }
        followUpCandidates = @($followUpCandidates)
        docFindings        = @($docFindings)
        valueContext       = @{
            selectedBy            = $selectionSource
            selectedIsTopValueItem = [bool]($null -ne $topValueItem -and [string](Get-ObjectPropertyValue -InputObject $topValueItem -PropertyName 'text' -Default '') -eq [string]$selected.text -and [string](Get-ObjectPropertyValue -InputObject $topValueItem -PropertyName 'section' -Default '') -eq [string]$selected.section)
            topValueItemText      = if ($null -ne $topValueItem) { [string](Get-ObjectPropertyValue -InputObject $topValueItem -PropertyName 'text' -Default '') } else { $null }
            valueScore            = if ($null -ne $selectedValueItem) { Get-ObjectPropertyValue -InputObject $selectedValueItem -PropertyName 'valueScore' -Default $null } else { Get-ObjectPropertyValue -InputObject $topValueItem -PropertyName 'valueScore' -Default $null }
            valueTier             = if ($null -ne $selectedValueItem) { Get-ObjectPropertyValue -InputObject $selectedValueItem -PropertyName 'valueTier' -Default $null } else { Get-ObjectPropertyValue -InputObject $topValueItem -PropertyName 'valueTier' -Default $null }
            rationale             = if ($null -ne $selectedValueItem) { @(Get-ObjectPropertyValue -InputObject $selectedValueItem -PropertyName 'valueRationale' -Default @()) } else { @(Get-ObjectPropertyValue -InputObject $topValueItem -PropertyName 'valueRationale' -Default @()) }
        }
        constraints        = @($constraints)
        acceptanceCriteria = @($acceptanceCriteria)
        guardrails         = @($guardrails)
        generatedPrompt    = $generatedPrompt
        historyPath        = (Join-Path $historyRoot 'history.jsonl')
        runEventsPath      = (Join-Path $runsPath ("{0}.events.jsonl" -f $runId))
        runSummaryPath     = (Join-Path $runsPath ("{0}.summary.json" -f $runId))
    }
}

function Convert-ToTrimmedStringArray {
    param(
        [Parameter()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return @()
    }

    $items = @()
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @($Value)
    }
    else {
        $items = @($Value)
    }

    return @(
        $items |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
}

function Invoke-OperationsPromptRefine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter()]
        [string]$RoadmapPath = '',

        [Parameter()]
        [string]$SelectedTaskText = '',

        [Parameter()]
        [string]$SelectedTaskSection = '',

        [Parameter()]
        [object]$AdditionalConstraints = @(),

        [Parameter()]
        [object]$EmphasisAreas = @(),

        [Parameter()]
        [string]$OperatorInstructions = '',

        [Parameter()]
        [object]$AuditEntry = $null,

        [Parameter()]
        [object]$AssessmentEntry = $null
    )

    $selectedTaskText = [string](Get-ValueOrDefault $SelectedTaskText '')
    $selectedTaskText = $selectedTaskText.Trim()
    $selectedTaskSection = [string](Get-ValueOrDefault $SelectedTaskSection '')
    $selectedTaskSection = $selectedTaskSection.Trim()
    $operatorInstructions = [string](Get-ValueOrDefault $OperatorInstructions '')
    $operatorInstructions = $operatorInstructions.Trim()
    $additionalConstraints = @(Convert-ToTrimmedStringArray -Value $AdditionalConstraints)
    $emphasisAreas = @(Convert-ToTrimmedStringArray -Value $EmphasisAreas)

    $packet = Build-CopilotTaskPacket `
        -RepoName $RepoName `
        -RoadmapPath $RoadmapPath `
        -AuditEntry $AuditEntry `
        -AssessmentEntry $AssessmentEntry `
        -ForcedItemText $selectedTaskText `
        -ForcedItemSection $selectedTaskSection
    $warnings = [System.Collections.Generic.List[hashtable]]::new()

    $effectiveSelectedTaskText = [string](Get-ObjectPropertyValue -InputObject $packet.selectedRoadmapItem -PropertyName 'text' -Default '')
    $effectiveSelectedTaskSection = [string](Get-ObjectPropertyValue -InputObject $packet.selectedRoadmapItem -PropertyName 'section' -Default '')
    $selectionSource = [string](Get-ObjectPropertyValue -InputObject $packet.selectedRoadmapItem -PropertyName 'selectionSource' -Default '')

    if (-not [string]::IsNullOrWhiteSpace($selectedTaskText) -and $selectionSource -ne 'operator-selected') {
        $warnings.Add(@{
            severity = 'warning'
            code = 'selected-task-not-found'
            message = if (-not [string]::IsNullOrWhiteSpace($selectedTaskSection)) {
                "Selected task '$selectedTaskText' in section '$selectedTaskSection' was not found among pending roadmap items. Using default packet selection."
            }
            else {
                "Selected task '$selectedTaskText' was not found among pending roadmap items. Using default packet selection."
            }
        })
    }

    $dispatchReadiness = [string](Get-ObjectPropertyValue -InputObject $packet.repoContext -PropertyName 'dispatchReadiness' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($dispatchReadiness) -and $dispatchReadiness -ne 'ready') {
        $warnings.Add(@{
            severity = 'warning'
            code = 'dispatch-not-ready'
            message = "Repo dispatchReadiness is '$dispatchReadiness'. Review blockers before dispatch."
        })
    }

    $criticalFindings = @(
        @($packet.docFindings) | Where-Object {
            [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'severity' -Default '') -eq 'critical'
        }
    )
    if ($criticalFindings.Count -gt 0) {
        $warnings.Add(@{
            severity = 'critical'
            code = 'critical-doc-findings'
            message = "Packet includes $($criticalFindings.Count) critical documentation finding(s)."
        })
    }

    $refinementLines = [System.Collections.Generic.List[string]]::new()
    $refinementLines.Add('Operator refinement directives:')
    $refinementLines.Add("- Selected task focus: $effectiveSelectedTaskText")
    if (-not [string]::IsNullOrWhiteSpace($effectiveSelectedTaskSection)) {
        $refinementLines.Add("- Selected task section: $effectiveSelectedTaskSection")
    }

    if (@($emphasisAreas).Count -gt 0) {
        $refinementLines.Add('- Emphasis areas:')
        foreach ($area in @($emphasisAreas)) {
            $refinementLines.Add("  - $area")
        }
    }

    if (@($additionalConstraints).Count -gt 0) {
        $refinementLines.Add('- Additional constraints:')
        foreach ($constraint in @($additionalConstraints)) {
            $refinementLines.Add("  - $constraint")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($operatorInstructions)) {
        $refinementLines.Add('- Operator instructions:')
        $refinementLines.Add("  $operatorInstructions")
    }

    if ($warnings.Count -gt 0) {
        $refinementLines.Add('- Warnings to preserve in final prompt:')
        foreach ($warning in @($warnings)) {
            $refinementLines.Add("  - [$([string]$warning.severity)] $([string]$warning.message)")
        }
    }

    $refinedPrompt = ($packet.generatedPrompt.TrimEnd() + "`n`n" + ($refinementLines -join "`n")).TrimEnd()

    return @{
        packet = $packet
        refinedPrompt = $refinedPrompt
        warnings = @($warnings)
        applied = @{
            selectedTaskText = $effectiveSelectedTaskText
            selectedTaskSection = $effectiveSelectedTaskSection
            additionalConstraints = @($additionalConstraints)
            emphasisAreas = @($emphasisAreas)
            operatorInstructions = if (-not [string]::IsNullOrWhiteSpace($operatorInstructions)) { $operatorInstructions } else { $null }
        }
    }
}

function Write-OperationsPromptRefinementHistory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $true)]
        [object]$Result
    )

    $runId = "{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $createdAt = (Get-Date).ToUniversalTime().ToString('o')
    $safeRepoName = $RepoName -replace '[\\/:*?"<>|]', '_'
    $refineRoot = Join-Path $WorkspaceRoot 'output\roadmap-task-history\prompt-refinements'
    $null = New-Item -ItemType Directory -Path $refineRoot -Force -ErrorAction SilentlyContinue
    $refineFile = Join-Path $refineRoot "$safeRepoName.refinements.jsonl"

    $record = @{
        runId = $runId
        createdAt = $createdAt
        repoName = $RepoName
        selectedItemText = [string](Get-ObjectPropertyValue -InputObject $Result.packet.selectedRoadmapItem -PropertyName 'text' -Default '')
        selectedItemSection = [string](Get-ObjectPropertyValue -InputObject $Result.packet.selectedRoadmapItem -PropertyName 'section' -Default '')
        selectionSource = [string](Get-ObjectPropertyValue -InputObject $Result.packet.selectedRoadmapItem -PropertyName 'selectionSource' -Default 'roadmap-order')
        operatorInstructions = Get-ObjectPropertyValue -InputObject $Result.applied -PropertyName 'operatorInstructions' -Default $null
        additionalConstraints = @(Get-ObjectPropertyValue -InputObject $Result.applied -PropertyName 'additionalConstraints' -Default @())
        emphasisAreas = @(Get-ObjectPropertyValue -InputObject $Result.applied -PropertyName 'emphasisAreas' -Default @())
        warningCount = @($Result.warnings).Count
    }

    try {
        $refineJson = ConvertTo-Json -InputObject $record -Compress -Depth 5
        Add-Content -LiteralPath $refineFile -Value $refineJson -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-HostLog ("WARN operations.prompt.refine could not write refinement history for repoName={0}: {1}" -f $RepoName, $_.Exception.Message)
    }

    return $record
}

function Write-OperationsPromptDispatchRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $true)]
        [string]$PromptRefinementRunId,

        [Parameter(Mandatory = $true)]
        [string]$DispatchRunId,

        [Parameter()]
        [string]$GitHubRepo = '',

        [Parameter()]
        [string]$Status = 'started',

        [Parameter()]
        [string]$StartedAt = '',

        [Parameter()]
        [string]$LocalPath = '',

        [Parameter()]
        [string]$BaseBranch = ''
    )

    if ([string]::IsNullOrWhiteSpace($PromptRefinementRunId) -or [string]::IsNullOrWhiteSpace($DispatchRunId)) {
        return $null
    }

    $safeRepoName = $RepoName -replace '[\\/:*?"<>|]', '_'
    $refineRoot = Join-Path $WorkspaceRoot 'output\roadmap-task-history\prompt-refinements'
    $null = New-Item -ItemType Directory -Path $refineRoot -Force -ErrorAction SilentlyContinue
    $dispatchFile = Join-Path $refineRoot "$safeRepoName.dispatches.jsonl"
    $recordedAt = (Get-Date).ToUniversalTime().ToString('o')
    if ([string]::IsNullOrWhiteSpace($StartedAt)) {
        $StartedAt = $recordedAt
    }

    $record = @{
        promptRefinementRunId = $PromptRefinementRunId
        dispatchRunId         = $DispatchRunId
        repoName              = $RepoName
        githubRepo            = $GitHubRepo
        status                = $Status
        startedAt             = $StartedAt
        recordedAt            = $recordedAt
        localPath             = if (-not [string]::IsNullOrWhiteSpace($LocalPath)) { $LocalPath } else { $null }
        baseBranch            = if (-not [string]::IsNullOrWhiteSpace($BaseBranch)) { $BaseBranch } else { $null }
    }

    try {
        $dispatchJson = ConvertTo-Json -InputObject $record -Compress -Depth 5
        Add-Content -LiteralPath $dispatchFile -Value $dispatchJson -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-HostLog ("WARN operations.prompt.dispatch could not write dispatch history for repoName={0} promptRunId={1}: {2}" -f $RepoName, $PromptRefinementRunId, $_.Exception.Message)
    }

    return $record
}

function Get-OperationsPromptDispatchRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName
    )

    $safeRepoName = $RepoName -replace '[\\/:*?"<>|]', '_'
    $refineRoot = Join-Path $WorkspaceRoot 'output\roadmap-task-history\prompt-refinements'
    $dispatchFile = Join-Path $refineRoot "$safeRepoName.dispatches.jsonl"
    if (-not (Test-Path -LiteralPath $dispatchFile -PathType Leaf)) {
        return @()
    }

    try {
        return @(
            Get-Content -LiteralPath $dispatchFile -Encoding UTF8 -ErrorAction Stop |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object {
                    try { ConvertFrom-JsonCompat -Json $_ } catch { $null }
                } |
                Where-Object { $null -ne $_ } |
                Sort-Object {
                    [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'startedAt' -Default '')
                } -Descending
        )
    }
    catch {
        Write-HostLog ("WARN operations.prompt.dispatch could not read dispatch history for repoName={0}: {1}" -f $RepoName, $_.Exception.Message)
        return @()
    }
}

function Get-OperationsPromptRefinementHistory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter()]
        [int]$Limit = 20
    )

    $safeRepoName = $RepoName -replace '[\\/:*?"<>|]', '_'
    $refineRoot = Join-Path $WorkspaceRoot 'output\roadmap-task-history\prompt-refinements'
    $refineFile = Join-Path $refineRoot "$safeRepoName.refinements.jsonl"
    if (-not (Test-Path -LiteralPath $refineFile -PathType Leaf)) {
        return @()
    }

    try {
        $lines = @(Get-Content -LiteralPath $refineFile -Encoding UTF8 -ErrorAction Stop | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $dispatchRecords = @(Get-OperationsPromptDispatchRecords -RepoName $RepoName)
        $dispatchRecordsByPromptRunId = @{}
        foreach ($dispatchRecord in $dispatchRecords) {
            $promptRunId = [string](Get-ObjectPropertyValue -InputObject $dispatchRecord -PropertyName 'promptRefinementRunId' -Default '')
            if ([string]::IsNullOrWhiteSpace($promptRunId)) {
                continue
            }

            if (-not $dispatchRecordsByPromptRunId.ContainsKey($promptRunId)) {
                $dispatchRecordsByPromptRunId[$promptRunId] = @()
            }

            $dispatchRecordsByPromptRunId[$promptRunId] = @($dispatchRecordsByPromptRunId[$promptRunId]) + @($dispatchRecord)
        }

        return @($lines |
            Select-Object -Last ([Math]::Min($Limit, $lines.Count)) |
            ForEach-Object {
                try { ConvertFrom-JsonCompat -Json $_ } catch { $null }
            } |
            Where-Object { $null -ne $_ } |
            ForEach-Object {
                $historyItem = $_
                $historyRunId = [string](Get-ObjectPropertyValue -InputObject $historyItem -PropertyName 'runId' -Default '')
                $linkedDispatchRecords = if (-not [string]::IsNullOrWhiteSpace($historyRunId) -and $dispatchRecordsByPromptRunId.ContainsKey($historyRunId)) {
                    @($dispatchRecordsByPromptRunId[$historyRunId] | Sort-Object {
                        [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'startedAt' -Default '')
                    } -Descending)
                }
                else {
                    @()
                }

                [pscustomobject]@{
                    runId                 = $historyRunId
                    createdAt             = [string](Get-ObjectPropertyValue -InputObject $historyItem -PropertyName 'createdAt' -Default '')
                    repoName              = [string](Get-ObjectPropertyValue -InputObject $historyItem -PropertyName 'repoName' -Default $RepoName)
                    selectedItemText      = [string](Get-ObjectPropertyValue -InputObject $historyItem -PropertyName 'selectedItemText' -Default '')
                    selectedItemSection   = [string](Get-ObjectPropertyValue -InputObject $historyItem -PropertyName 'selectedItemSection' -Default '')
                    selectionSource       = [string](Get-ObjectPropertyValue -InputObject $historyItem -PropertyName 'selectionSource' -Default 'roadmap-order')
                    operatorInstructions  = Get-ObjectPropertyValue -InputObject $historyItem -PropertyName 'operatorInstructions' -Default $null
                    additionalConstraints = @(Get-ObjectPropertyValue -InputObject $historyItem -PropertyName 'additionalConstraints' -Default @())
                    emphasisAreas         = @(Get-ObjectPropertyValue -InputObject $historyItem -PropertyName 'emphasisAreas' -Default @())
                    warningCount          = [int](Get-ObjectPropertyValue -InputObject $historyItem -PropertyName 'warningCount' -Default 0)
                    dispatchCount         = @($linkedDispatchRecords).Count
                    latestDispatchAt      = if (@($linkedDispatchRecords).Count -gt 0) {
                        [string](Get-ObjectPropertyValue -InputObject $linkedDispatchRecords[0] -PropertyName 'startedAt' -Default '')
                    }
                    else {
                        $null
                    }
                    dispatchRecords       = @($linkedDispatchRecords)
                }
            } |
            Sort-Object { [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'createdAt' -Default '') } -Descending)
    }
    catch {
        Write-HostLog ("WARN operations.prompt.history could not read history for repoName={0}: {1}" -f $RepoName, $_.Exception.Message)
        return @()
    }
}

# Release 2.2 — resolve API auth once at startup, generate + persist a key on
# first run when auth is required but none is set, then guard non-loopback binds.
$script:AuthSettings = Get-HostSettings
$script:AuthRequired = Test-ApiAuthRequired -Settings $script:AuthSettings
$script:EffectiveApiKey = Get-ConfiguredApiKey -Settings $script:AuthSettings
if ($script:AuthRequired -and [string]::IsNullOrWhiteSpace($script:EffectiveApiKey)) {
    $generatedKey = New-ApiKey
    try {
        $cfgPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
        $cfg = if (Test-Path -LiteralPath $cfgPath) { ConvertFrom-JsonCompat -Json (Get-Content -LiteralPath $cfgPath -Raw) } else { @{} }
        if (-not $cfg.ContainsKey('auth') -or -not ($cfg.auth -is [System.Collections.IDictionary])) { $cfg.auth = @{ requireApiKey = $true } }
        $cfg.auth.apiKey = $generatedKey
        ($cfg | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $cfgPath -Encoding UTF8
        Write-HostLog "Auth: generated a first-run API key and wrote it to settings.json (auth.apiKey)."
    } catch {
        Write-HostLog ("WARN auth: could not persist generated API key: {0}" -f $_.Exception.Message)
    }
    $script:EffectiveApiKey = $generatedKey
}
$script:AuthEnforced = $script:AuthRequired -and -not [string]::IsNullOrWhiteSpace($script:EffectiveApiKey)
# Release 2.7 — human login layer. Whether the API gate is ON stays governed by
# the Release 2.2 switch (auth.requireApiKey / REPO_MGMT_REQUIRE_API_KEY) so the
# open-by-default config the smokes rely on is unchanged. A configured operator
# password does NOT by itself enable the gate; it adds a session-cookie credential
# that, when the gate is on, authorizes a browser in place of the API key. So a
# request is authorized by a valid API key (automation) OR a valid session cookie
# (a logged-in human).
$script:HumanLoginConfigured = $false
try { $script:HumanLoginConfigured = [bool](Test-PortalPasswordConfigured -WorkspaceRoot $WorkspaceRoot) } catch { $script:HumanLoginConfigured = $false }
$script:GateEnabled = $script:AuthEnforced
# Explicit single-operator opt-out (roadmap: "single-operator interim bind is
# acceptable"): binding a non-loopback address without auth is refused unless
# the operator acknowledges the risk via REPO_MGMT_ALLOW_INSECURE_BIND or
# network.allowInsecureBind, in which case it is allowed with a loud warning.
$allowInsecureBind = $false
$insecureEnv = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_ALLOW_INSECURE_BIND')
if (-not [string]::IsNullOrWhiteSpace($insecureEnv) -and $insecureEnv.Trim() -match '^(?i)(1|true|yes|on)$') { $allowInsecureBind = $true }
if ($script:AuthSettings.ContainsKey('network') -and $script:AuthSettings.network -is [System.Collections.IDictionary] -and
    $script:AuthSettings.network.ContainsKey('allowInsecureBind') -and [bool]$script:AuthSettings.network.allowInsecureBind) { $allowInsecureBind = $true }
if (-not (Test-IsLoopbackAddress -Address $BindAddress) -and -not $script:GateEnabled) {
    if ($allowInsecureBind) {
        Write-HostLog ("WARNING: binding non-loopback '{0}' WITHOUT API auth (allowInsecureBind acknowledged). The API is exposed unauthenticated on this network — set auth.requireApiKey for shared use." -f $BindAddress)
    }
    else {
        $bindRefusal = ("Refusing to bind non-loopback address '{0}' without API auth. Set auth.requireApiKey=true (and an apiKey or apiKeyEnvVar) in settings.json, acknowledge the risk with network.allowInsecureBind=true, or bind 127.0.0.1." -f $BindAddress)
        Write-HostLog $bindRefusal
        throw $bindRefusal
    }
}

# Release 2.2 — scoped CORS + request rate limiting (opt-in via settings.network
# or env overrides; both default off so loopback dev is unchanged).
$script:CorsAllowOrigin = '*'
$script:RateLimitEnabled = $false
$script:RateLimitMaxRequests = 0
$script:RateLimitWindowSeconds = 10
$script:RateLimitHits = @{}
# Release 2.4 — in-memory agent claim registry (repoName(lower) -> claim info).
$script:AgentClaims = @{}
try {
    if ($script:AuthSettings.ContainsKey('network') -and $script:AuthSettings.network -is [System.Collections.IDictionary]) {
        $net = $script:AuthSettings.network
        if ($net.ContainsKey('allowedOrigins') -and @($net.allowedOrigins).Count -gt 0) {
            $script:CorsAllowOrigin = [string]@($net.allowedOrigins)[0]
        }
        if ($net.ContainsKey('rateLimit') -and $net.rateLimit -is [System.Collections.IDictionary] -and $net.rateLimit.ContainsKey('maxRequests') -and [int]$net.rateLimit.maxRequests -gt 0) {
            $script:RateLimitEnabled = $true
            $script:RateLimitMaxRequests = [int]$net.rateLimit.maxRequests
            if ($net.rateLimit.ContainsKey('windowSeconds') -and [int]$net.rateLimit.windowSeconds -gt 0) { $script:RateLimitWindowSeconds = [int]$net.rateLimit.windowSeconds }
        }
    }
} catch { Write-HostLog ("WARN network config parse failed: {0}" -f $_.Exception.Message) }
$corsEnv = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_CORS_ORIGIN')
if (-not [string]::IsNullOrWhiteSpace($corsEnv)) { $script:CorsAllowOrigin = $corsEnv.Trim() }
$rlMaxEnv = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_RATE_LIMIT_MAX')
if (-not [string]::IsNullOrWhiteSpace($rlMaxEnv)) {
    $parsedMax = 0
    if ([int]::TryParse($rlMaxEnv.Trim(), [ref]$parsedMax) -and $parsedMax -gt 0) {
        $script:RateLimitEnabled = $true; $script:RateLimitMaxRequests = $parsedMax
    }
}
$rlWinEnv = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_RATE_LIMIT_WINDOW')
if (-not [string]::IsNullOrWhiteSpace($rlWinEnv)) {
    $parsedWin = 0
    if ([int]::TryParse($rlWinEnv.Trim(), [ref]$parsedWin) -and $parsedWin -gt 0) { $script:RateLimitWindowSeconds = $parsedWin }
}
Write-HostLog ("Network: corsOrigin='{0}' rateLimitEnabled={1} max={2}/{3}s" -f $script:CorsAllowOrigin, $script:RateLimitEnabled, $script:RateLimitMaxRequests, $script:RateLimitWindowSeconds)

# Release 2.2 — optional TLS. Loads a PFX (settings.network.tls or env) so the
# accept loop wraps each connection in an SslStream. Off by default; when no
# certificate is configured the request path is unchanged (plain NetworkStream).
$script:TlsCertificate = $null
try {
    $pfxPath = ''
    $pfxPassword = ''
    if ($script:AuthSettings.ContainsKey('network') -and $script:AuthSettings.network -is [System.Collections.IDictionary] -and
        $script:AuthSettings.network.ContainsKey('tls') -and $script:AuthSettings.network.tls -is [System.Collections.IDictionary]) {
        $tlsCfg = $script:AuthSettings.network.tls
        if ($tlsCfg.ContainsKey('pfxPath')) { $pfxPath = [string]$tlsCfg.pfxPath }
        if ($tlsCfg.ContainsKey('pfxPassword')) { $pfxPassword = [string]$tlsCfg.pfxPassword }
    }
    $envPfx = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_TLS_PFX')
    if (-not [string]::IsNullOrWhiteSpace($envPfx)) { $pfxPath = $envPfx }
    $envPfxPw = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_TLS_PFX_PASSWORD')
    if ($null -ne $envPfxPw) { $pfxPassword = $envPfxPw }
    if (-not [string]::IsNullOrWhiteSpace($pfxPath) -and (Test-Path -LiteralPath $pfxPath)) {
        $script:TlsCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pfxPath, $pfxPassword)
        Write-HostLog ("TLS: enabled with certificate '{0}' (subject={1})" -f $pfxPath, $script:TlsCertificate.Subject)
    }
} catch { Write-HostLog ("WARN TLS: certificate load failed - {0}" -f $_.Exception.Message); $script:TlsCertificate = $null }

# Everything above is definition and configuration; everything below binds the
# port and takes ownership of it. A caller that only wants the functions must
# return HERE - one line further and Stop-PortListeners would terminate the
# running service, which is precisely what a background worker must never do.
if ($LoadDefinitionsOnly) {
    return
}

$listenerAddress = [System.Net.IPAddress]::Parse($BindAddress)
Stop-PortListeners -LocalPort $Port
$listener = [System.Net.Sockets.TcpListener]::new($listenerAddress, $Port)
$listener.Start()
Write-HostLog ("Repo Management API host started on http://{0}:{1}" -f $BindAddress, $Port)
Write-HostLog ("Auth: {0}" -f $(if ($script:AuthEnforced) { 'API key required on /api routes' } else { 'open (loopback; no API key required)' }))
Write-HostLog ("Ops log: {0}" -f (Get-ValueOrDefault $script:OpsLogPath '(none)'))
$requestTimeoutLogPath = Join-Path $WorkspaceRoot 'output\logs\request-timeouts.jsonl'
$script:RequestDeadlineController = Start-RequestDeadlineWatchdog `
    -TimeoutSeconds $script:RequestTimeoutSeconds `
    -IncidentLogPath $requestTimeoutLogPath
Write-HostLog ("Request deadline: {0}s default / {1}s scan routes (incident log: {2})" -f $script:RequestTimeoutSeconds, $script:ScanRequestTimeoutSeconds, $requestTimeoutLogPath)

# A fresh process has no operation in flight. Without this, a host killed
# mid-scan leaves an active marker behind and its successor inherits a claim to
# be busy that it is not (portal restart-loop incident, 2026-08-10).
Clear-PortalOperationState -WorkspaceRoot $WorkspaceRoot
Write-HostLog ("Operation heartbeat: {0} (progress written at least every {1}s while a long operation is active)" -f (Get-PortalOperationStatePath -WorkspaceRoot $WorkspaceRoot), $script:PortalHeartbeatIntervalSeconds)

# GitHub auth is env-var-name indirection only: settings carry the variable
# NAME, never a token. Report what the name resolves to in THIS process, since
# a LocalSystem service cannot see a User-scoped variable.
$null = Remove-StoredSecretsFromSettings
try {
    $tokenResolution = Get-GitHubTokenResolution -Settings (Get-HostSettings)
    switch ($tokenResolution.Source) {
        'env' {
            Write-HostLog ("GitHub auth: token from env var '{0}' ({1} scope)" -f $tokenResolution.EnvVarName, $tokenResolution.Scope)
        }
        'gh-cli' {
            Write-HostLog ("GitHub auth: env var '{0}' is empty; falling back to the 'gh' CLI credential" -f $tokenResolution.EnvVarName)
        }
        default {
            Write-HostLog ("WARN GitHub auth: env var '{0}' is not set in this process and no 'gh' credential is available - GitHub calls will run unauthenticated (60 req/hr, no private repos). Set it in a scope this host can read{1}." -f $tokenResolution.EnvVarName, $(if ($script:RunningAsService) { ' (a service cannot read User-scoped variables; use Machine scope)' } else { '' }))
        }
    }
}
catch { Write-HostLog ("WARN GitHub auth: token resolution probe failed - {0}" -f $_.Exception.Message) }

# Release 2.1 Phase 1 — SQLite persistence boundary bootstrap (non-fatal).
# JSON stores remain authoritative during rollout; a missing SQLite provider
# only disables the additive mirror writes.
try {
    $persistenceInit = Initialize-AppDatabase -WorkspaceRoot $WorkspaceRoot
    if ($persistenceInit.success) {
        Write-HostLog ("Persistence: app database ready at {0} (provider={1}, sqlite={2})" -f $persistenceInit.databasePath, $persistenceInit.providerDetail, $persistenceInit.sqliteVersion)
        $importResult = Import-AppDbOpsLogFromJsonl -JsonlPath $script:OpsLogPath
        if ($importResult.success) {
            Write-HostLog ("Persistence: imported {0} ops-log rows from JSONL seed" -f $importResult.imported)
        } else {
            Write-HostLog ("WARN persistence: ops-log import skipped - {0}" -f $importResult.reason)
        }
    } else {
        Write-HostLog ("WARN persistence: app database unavailable - {0}" -f $persistenceInit.error)
    }
} catch {
    Write-HostLog ("WARN persistence: bootstrap failed - {0}" -f $_.Exception.Message)
}

# Apply startup settings: ops log cap and auto-scan interval
try {
    $startupSettings = Get-HostSettings
    # --- ops log max lines ---
    if ($startupSettings.ContainsKey('retention') -and
        $null -ne $startupSettings.retention -and
        $startupSettings.retention -is [hashtable] -and
        $startupSettings.retention.ContainsKey('maxOpsLogLines')) {
        $cfgMax = [int]$startupSettings.retention.maxOpsLogLines
        if ($cfgMax -gt 0) { $script:OpsLogMaxLines = $cfgMax }
    }
    Invoke-TrimOpsLog -MaxLines $script:OpsLogMaxLines

    # --- auto-scan ---
    if ($startupSettings.ContainsKey('scanning') -and
        $null -ne $startupSettings.scanning -and
        $startupSettings.scanning -is [hashtable] -and
        $startupSettings.scanning.ContainsKey('autoScanIntervalMinutes')) {
        $cfgInterval = [int]$startupSettings.scanning.autoScanIntervalMinutes
        if ($cfgInterval -gt 0) {
            $script:AutoScanState.Enabled         = $true
            $script:AutoScanState.IntervalMinutes = $cfgInterval
            $script:AutoScanState.NextScanAt      = (Get-Date).AddMinutes($cfgInterval)
            Write-HostLog ("Auto-scan enabled: every {0} minute(s). Next at {1}." -f $cfgInterval, $script:AutoScanState.NextScanAt.ToString('HH:mm:ss'))

            # Background runspace — fires every 30 s, sets PendingInvalidation when interval elapses
            $autoRunspace = [runspacefactory]::CreateRunspace()
            $autoRunspace.Open()
            $autoRunspace.SessionStateProxy.SetVariable('AutoScanState', $script:AutoScanState)
            $autoPs = [powershell]::Create()
            $autoPs.Runspace = $autoRunspace
            $null = $autoPs.AddScript({
                while ($true) {
                    Start-Sleep -Seconds 30
                    if ($AutoScanState.Enabled -and (Get-Date) -ge $AutoScanState.NextScanAt) {
                        $AutoScanState.PendingInvalidation = $true
                        $AutoScanState.LastScanAt          = Get-Date
                        $AutoScanState.NextScanAt          = (Get-Date).AddMinutes($AutoScanState.IntervalMinutes)
                    }
                }
            })
            $null = $autoPs.BeginInvoke()
        }
    }
} catch {
    Write-HostLog ("WARN startup settings init failed: {0}" -f $_.Exception.Message)
}

try {
    while ($true) {
        # Drain any pending auto-scan cache invalidation from the background runspace
        if ($script:AutoScanState.PendingInvalidation) {
            $script:AutoScanState.PendingInvalidation = $false
            Clear-StatusCache
            Clear-RoadmapCache
            Clear-RoadmapAuditCache
            Clear-DocAuditCache
            Write-HostLog ("Auto-scan: all caches invalidated at {0}." -f (Get-Date).ToString('HH:mm:ss'))
        }

        $client = Get-NextTcpClient -Listener $listener
        if ($null -eq $client) {
            break
        }
        try {
            # Release 2.2 TLS: wrap the raw stream in an SslStream when a cert is
            # configured; otherwise the plain NetworkStream is used unchanged.
            $activeStream = $null
            if ($null -ne $script:TlsCertificate) {
                try {
                    $sslStream = [System.Net.Security.SslStream]::new($client.GetStream(), $false)
                    $sslStream.AuthenticateAsServer($script:TlsCertificate, $false, [System.Security.Authentication.SslProtocols]::None, $false)
                    $activeStream = $sslStream
                } catch {
                    Write-HostLog ("WARN TLS handshake failed: {0}" -f $_.Exception.Message)
                    try { $client.Close() } catch { }
                    continue
                }
            }
            $req = if ($null -ne $activeStream) { Read-HttpRequest -Client $client -Stream $activeStream } else { Read-HttpRequest -Client $client }
            if ($null -eq $req) {
                $client.Close()
                continue
            }

            $path = if ([string]::IsNullOrWhiteSpace($req.Path)) { '/' } else { [string]$req.Path }
            # Normalize API paths so //api/... and /api/.../ resolve to the
            # same route contract instead of falling through to SPA fallback.
            $path = '/' + (($path -replace '\\', '/') -replace '^/+', '' -replace '/+', '/')
            if ($path.Length -gt 1 -and $path.EndsWith('/')) {
                $path = $path.TrimEnd('/')
            }
            $correlationId = if ($req.Headers.ContainsKey('x-correlation-id') -and $req.Headers['x-correlation-id']) { $req.Headers['x-correlation-id'] } else { [guid]::NewGuid().ToString('n') }
            $requestStart = Get-Date
            Set-RequestDeadline -Controller $script:RequestDeadlineController `
                -TimeoutSeconds (Get-RequestDeadlineSecondsForPath -Path $path `
                    -DefaultSeconds $script:RequestTimeoutSeconds `
                    -ScanSeconds $script:ScanRequestTimeoutSeconds) `
                -CorrelationId $correlationId `
                -Method $req.Method `
                -Path $path

            # The heartbeat lifecycle mirrors the deadline lifecycle and is keyed
            # off the SAME route classifier, so every route that gets the extended
            # scan budget is automatically visible to the watchdog as "working".
            # Per-route instrumentation was the original defect: the first fix
            # instrumented /api/status only, while /api/portfolio/assessment and
            # the rest of Get-LongRunningScanRoutePattern stayed bare and kept
            # being restarted mid-scan (ROADMAP Lane 0.9).
            if (Test-LongRunningScanRoute -Path $path) {
                $null = Start-PortalOperation -WorkspaceRoot $WorkspaceRoot `
                    -Operation ("{0} {1}" -f $req.Method, $path) `
                    -CorrelationId $correlationId -Stage 'started'
            }

            if ($req.Method -eq 'OPTIONS') {
                Add-MetricCounter -Name 'api_requests_total'
                Send-HttpJson -Stream $req.Stream -StatusCode 204 -StatusText 'No Content' -Payload @{} -CorrelationId $correlationId
                $client.Close()
                continue
            }

            # Release 2.2/2.7 — request auth gate. Health checks, the auth status
            # + login/logout routes, the setup wizard, and the static SPA shell
            # stay open so an unconfigured/logged-out browser can reach the login
            # screen; everything else under /api/ requires a valid API key
            # (automation) OR a valid session cookie (a logged-in human).
            if ($script:GateEnabled) {
                $authExempt = ($path -eq '/health/live') -or ($path -eq '/health/ready') -or
                    ($path -eq '/api/auth/status') -or ($path -eq '/api/auth/login') -or ($path -eq '/api/auth/logout') -or
                    ($path -eq '/setup') -or ($path -like '/setup/*') -or
                    (-not ($path -like '/api/*'))
                if (-not $authExempt) {
                    $apiKeyOk = $script:AuthEnforced -and (Test-RequestApiKeyValid -Request $req -ExpectedKey $script:EffectiveApiKey)
                    $sessionOk = $script:HumanLoginConfigured -and (Test-RequestSessionValid -Request $req -WorkspaceRoot $WorkspaceRoot)
                    if (-not $apiKeyOk -and -not $sessionOk) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 401 -StatusText 'Unauthorized' -CorrelationId $correlationId -Payload @{
                            success  = $false
                            error    = 'Unauthorized: log in at /api/auth/login, or send an API key as `Authorization: Bearer <key>` or `X-Api-Key: <key>`.'
                            category = 'auth'
                        }
                        $client.Close()
                        continue
                    }
                }
            }

            # Release 2.2 — fixed-window per-IP rate limit on /api routes (opt-in).
            if ($script:RateLimitEnabled -and ($path -like '/api/*')) {
                $clientIp = try { [string]$client.Client.RemoteEndPoint.Address } catch { 'unknown' }
                $nowTs = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                $windowStart = $nowTs - $script:RateLimitWindowSeconds
                # Explicit typed list + ToArray(): PowerShell's `@() += x` idiom
                # collapses to a scalar when stored back into a hashtable, so the
                # window never accumulated. See memory: List ::new() + ToArray().
                $kept = [System.Collections.Generic.List[long]]::new()
                if ($script:RateLimitHits.ContainsKey($clientIp)) {
                    foreach ($ts in @($script:RateLimitHits[$clientIp])) {
                        if ([long]$ts -ge $windowStart) { $kept.Add([long]$ts) }
                    }
                }
                $kept.Add($nowTs)
                $script:RateLimitHits[$clientIp] = $kept.ToArray()
                if ($kept.Count -gt $script:RateLimitMaxRequests) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 429 -StatusText 'Too Many Requests' -CorrelationId $correlationId -Payload @{
                        success  = $false
                        error    = ("Rate limit exceeded: more than {0} requests per {1}s." -f $script:RateLimitMaxRequests, $script:RateLimitWindowSeconds)
                        category = 'rate-limit'
                    }
                    $client.Close()
                    continue
                }
            }

            if ($req.Method -eq 'GET' -and $path -like '/api/artifacts/*') {
                $repoName = [System.Uri]::UnescapeDataString($path.Substring('/api/artifacts/'.Length))
                $outputRoot = Join-Path $WorkspaceRoot 'backend\modules\output'
                $files = @()
                if (Test-Path -LiteralPath $outputRoot) {
                    $files = Get-ChildItem -Path $outputRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                        $_.Name -like "*$repoName*" -or $_.FullName -like "*$repoName*"
                    } | Sort-Object LastWriteTime -Descending | Select-Object -First 200 | ForEach-Object {
                        [pscustomobject]@{
                            name = $_.Name
                            path = $_.FullName
                            sizeBytes = $_.Length
                            lastWriteTime = $_.LastWriteTime.ToString('o')
                        }
                    }
                }

                Add-MetricCounter -Name 'api_requests_total'
                Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                    success = $true
                    repoName = $repoName
                    artifacts = $files
                }
                $client.Close()
                continue
            }

            if ($req.Method -eq 'GET' -and $path -like '/api/reports/*') {
                $reportName = [System.IO.Path]::GetFileName([System.Uri]::UnescapeDataString($path.Substring('/api/reports/'.Length)))
                $reportsRoot = Get-ReportsRootPath
                $reportPath = Join-Path $reportsRoot $reportName

                if ([string]::IsNullOrWhiteSpace($reportName) -or -not (Test-Path -LiteralPath $reportPath)) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-ErrorJson -Stream $req.Stream -StatusCode 404 -ErrorMessage 'Report file not found.' -CorrelationId $correlationId -Operation 'reports.open'
                    $client.Close()
                    continue
                }

                $contentType = switch ([System.IO.Path]::GetExtension($reportPath).ToLowerInvariant()) {
                    '.html' { 'text/html; charset=utf-8' }
                    '.csv' { 'text/csv; charset=utf-8' }
                    default { 'application/octet-stream' }
                }

                Add-MetricCounter -Name 'api_requests_total'
                Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                Send-HttpContent -Stream $req.Stream -StatusCode 200 -ContentType $contentType -CorrelationId $correlationId -BodyBytes ([System.IO.File]::ReadAllBytes($reportPath))
                $client.Close()
                continue
            }

            if ($path -like '/api/merge-readiness/*') {
                $mrIsEvaluate = $req.Method -eq 'POST' -and $path -like '/api/merge-readiness/*/evaluate'
                $mrIsMerge = $req.Method -eq 'POST' -and $path -like '/api/merge-readiness/*/merge'
                $mrIsGet = $req.Method -eq 'GET' -and -not $mrIsEvaluate -and -not $mrIsMerge

                if ($mrIsEvaluate -or $mrIsMerge -or $mrIsGet) {
                    $mrRepoId = if ($mrIsEvaluate) {
                        [System.Uri]::UnescapeDataString($path.Substring('/api/merge-readiness/'.Length, $path.Length - '/api/merge-readiness/'.Length - '/evaluate'.Length))
                    } elseif ($mrIsMerge) {
                        [System.Uri]::UnescapeDataString($path.Substring('/api/merge-readiness/'.Length, $path.Length - '/api/merge-readiness/'.Length - '/merge'.Length))
                    } else {
                        [System.Uri]::UnescapeDataString($path.Substring('/api/merge-readiness/'.Length))
                    }

                    if ([string]::IsNullOrWhiteSpace($mrRepoId)) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = 'repoId is required in /api/merge-readiness/{repoId}.'
                        }
                        $client.Close()
                        continue
                    }

                    if ($mrIsGet) {
                        Write-HostLog ("[TRACE] merge-readiness.get correlationId={0} repoId={1}" -f $correlationId, $mrRepoId)
                        $snapshot = Get-MergeReadinessSnapshot -WorkspaceRoot $WorkspaceRoot -RepoId $mrRepoId
                        Add-MetricCounter -Name 'api_requests_total'
                        if ($null -eq $snapshot) {
                            Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                                success = $false
                                error = "No merge-readiness evaluation exists for repoId '$mrRepoId'. Run POST /api/merge-readiness/{repoId}/evaluate first."
                            }
                        } else {
                            Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                            Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                success = $true
                                data    = $snapshot
                            }
                        }
                        $client.Close()
                        continue
                    }

                    # evaluate and merge both need the resolved repo record and a
                    # fresh evaluation.
                    Write-HostLog ("[TRACE] merge-readiness.{0} correlationId={1} repoId={2} start" -f $(if ($mrIsMerge) { 'merge' } else { 'evaluate' }), $correlationId, $mrRepoId)
                    $mrResolved = Resolve-OperationsRepoRecord -RepoId $mrRepoId
                    if (-not $mrResolved.found) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode $mrResolved.statusCode -StatusText $(if ($mrResolved.statusCode -eq 404) { 'Not Found' } else { 'Conflict' }) -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = $mrResolved.error
                        }
                        $client.Close()
                        continue
                    }

                    $mrOutcome = Invoke-MergeReadinessForRepo -RepoRecord $mrResolved.record -RepoId $mrRepoId -CorrelationId $correlationId
                    if (-not $mrOutcome.success) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode $mrOutcome.statusCode -StatusText 'Bad Gateway' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = $mrOutcome.error
                        }
                        $client.Close()
                        continue
                    }

                    if ($mrIsEvaluate) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] merge-readiness.evaluate correlationId={0} repoId={1} ready={2} blockers={3}" -f $correlationId, $mrRepoId, $mrOutcome.evaluation.ready, @($mrOutcome.evaluation.blockers).Count)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $mrOutcome.evaluation
                        }
                        $client.Close()
                        continue
                    }

                    # Operator merge action — server-side gate: refuse unless the
                    # fresh evaluation is ready (guardrail: merge stays an explicit
                    # operator action and is never offered while blockers exist).
                    if (-not $mrOutcome.evaluation.ready) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Write-HostLog ("[TRACE] merge-readiness.merge correlationId={0} repoId={1} refused blockers={2}" -f $correlationId, $mrRepoId, @($mrOutcome.evaluation.blockers).Count)
                        Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = 'Merge refused: the repo is not merge-ready. Resolve the blockers and evaluate again.'
                            data = $mrOutcome.evaluation
                        }
                        $client.Close()
                        continue
                    }

                    $mergeRunId = [string]$mrOutcome.evaluation.runId
                    $mergeRun = $null
                    if (-not [string]::IsNullOrWhiteSpace($mergeRunId)) {
                        $mergeRunDetail = Get-AgentRunDetail -WorkspaceRoot $WorkspaceRoot -RunId $mergeRunId
                        if ($null -ne $mergeRunDetail) { $mergeRun = $mergeRunDetail.run }
                    }
                    $mergeGithubRepo = [string](Get-ObjectPropertyValue -InputObject $mergeRun -PropertyName 'githubRepo' -Default '')
                    $mergeRepoParts = $mergeGithubRepo -split '/'
                    $mergePrNumber = Get-ObjectPropertyValue -InputObject $mergeRun -PropertyName 'prNumber' -Default $null
                    if ($mergeRepoParts.Count -ne 2 -or $null -eq $mergePrNumber) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = 'Merge refused: the agent run has no usable GitHub repo/PR identity.'
                        }
                        $client.Close()
                        continue
                    }

                    $mergeSettings = Get-HostSettings
                    $mergeToken = Get-ConfiguredGitHubToken -Settings $mergeSettings
                    $mergeHeaders = Get-GitHubApiHeaders -Token $mergeToken
                    $mergeResponse = $null
                    try {
                        $mergeUri = "https://api.github.com/repos/$($mergeRepoParts[0])/$($mergeRepoParts[1])/pulls/$([int]$mergePrNumber)/merge"
                        $mergeBody = @{ merge_method = 'merge' } | ConvertTo-Json -Compress
                        $mergeResponse = Invoke-RestMethod -Uri $mergeUri -Headers $mergeHeaders -Method Put -Body $mergeBody -ContentType 'application/json'
                    } catch {
                        Write-HostLog ("[WARN ] merge-readiness.merge correlationId={0} repoId={1} GitHub merge failed: {2}" -f $correlationId, $mrRepoId, $_.Exception.Message)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 502 -StatusText 'Bad Gateway' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = "GitHub merge failed for ${mergeGithubRepo} PR #${mergePrNumber}: $($_.Exception.Message)"
                        }
                        $client.Close()
                        continue
                    }

                    # Record the merged outcome on the agent run (non-fatal) and
                    # refresh the stored snapshot to reflect the merged PR.
                    try {
                        $null = Update-AgentRunRecord -WorkspaceRoot $WorkspaceRoot -RunId $mergeRunId -Patch @{
                            status  = 'completed'
                            outcome = 'merged'
                            prState = 'merged'
                        } -Actor 'operator' -Summary "PR #$mergePrNumber merged via operator merge action."
                    } catch {
                        Write-HostLog ("[WARN ] merge-readiness.merge correlationId={0} ledger update failed: {1}" -f $correlationId, $_.Exception.Message)
                    }
                    $postMerge = Invoke-MergeReadinessForRepo -RepoRecord $mrResolved.record -RepoId $mrRepoId -CorrelationId $correlationId

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] merge-readiness.merge correlationId={0} repoId={1} merged sha={2}" -f $correlationId, $mrRepoId, [string](Get-ObjectPropertyValue -InputObject $mergeResponse -PropertyName 'sha' -Default ''))
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            merged     = $true
                            sha        = [string](Get-ObjectPropertyValue -InputObject $mergeResponse -PropertyName 'sha' -Default '')
                            message    = [string](Get-ObjectPropertyValue -InputObject $mergeResponse -PropertyName 'message' -Default '')
                            runId      = $mergeRunId
                            evaluation = $(if ($postMerge.success) { $postMerge.evaluation } else { $mrOutcome.evaluation })
                        }
                    }
                    $client.Close()
                    continue
                }
            }

            if ($req.Method -eq 'POST' -and $path -like '/api/agent-runs/*/refresh') {
                $refreshRunId = [System.Uri]::UnescapeDataString($path.Substring('/api/agent-runs/'.Length, $path.Length - '/api/agent-runs/'.Length - '/refresh'.Length))
                if ([string]::IsNullOrWhiteSpace($refreshRunId)) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                        success = $false
                        error = 'runId is required in /api/agent-runs/{runId}/refresh.'
                    }
                    $client.Close()
                    continue
                }

                Write-HostLog ("[TRACE] agent-runs.refresh correlationId={0} runId={1} start" -f $correlationId, $refreshRunId)
                $refreshDetail = Get-AgentRunDetail -WorkspaceRoot $WorkspaceRoot -RunId $refreshRunId
                if ($null -eq $refreshDetail) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                        success = $false
                        error = "No agent run found for runId '$refreshRunId'."
                    }
                    $client.Close()
                    continue
                }

                $refreshGithubRepo = [string](Get-ObjectPropertyValue -InputObject $refreshDetail.run -PropertyName 'githubRepo' -Default '')
                $refreshRepoParts = $refreshGithubRepo -split '/'
                if ([string]::IsNullOrWhiteSpace($refreshGithubRepo) -or $refreshRepoParts.Count -ne 2) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                        success = $false
                        error = "Agent run '$refreshRunId' has no usable GitHub owner/repo identity; cannot refresh branch, PR, or Actions state."
                    }
                    $client.Close()
                    continue
                }

                $refreshOwner = $refreshRepoParts[0]
                $refreshRepoName = $refreshRepoParts[1]
                $refreshSettings = Get-HostSettings
                $refreshToken = Get-ConfiguredGitHubToken -Settings $refreshSettings
                $refreshHeaders = Get-GitHubApiHeaders -Token $refreshToken

                $refreshPulls = $null
                try {
                    $pullsUri = "https://api.github.com/repos/$refreshOwner/$refreshRepoName/pulls?state=all&sort=created&direction=desc&per_page=30"
                    $refreshPulls = @(Invoke-RestMethod -Uri $pullsUri -Headers $refreshHeaders -Method Get)
                } catch {
                    Write-HostLog ("[WARN ] agent-runs.refresh correlationId={0} runId={1} GitHub PR lookup failed: {2}" -f $correlationId, $refreshRunId, $_.Exception.Message)
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 502 -StatusText 'Bad Gateway' -CorrelationId $correlationId -Payload @{
                        success = $false
                        error = "GitHub pull-request lookup failed for ${refreshGithubRepo}: $($_.Exception.Message)"
                    }
                    $client.Close()
                    continue
                }

                # Resolve the branch first so the Actions lookup targets the
                # agent's head branch rather than the default branch.
                $refreshCandidate = Select-AgentRunPullRequestCandidate -Run $refreshDetail.run -PullRequests $refreshPulls
                $refreshBranch = [string](Get-ObjectPropertyValue -InputObject $refreshDetail.run -PropertyName 'branch' -Default '')
                if ($null -ne $refreshCandidate.pullRequest) {
                    $candidateHead = Get-ObjectPropertyValue -InputObject $refreshCandidate.pullRequest -PropertyName 'head' -Default $null
                    $candidateRef = [string](Get-ObjectPropertyValue -InputObject $candidateHead -PropertyName 'ref' -Default '')
                    if (-not [string]::IsNullOrWhiteSpace($candidateRef)) { $refreshBranch = $candidateRef }
                }

                $refreshActionsRun = $null
                if (-not [string]::IsNullOrWhiteSpace($refreshBranch)) {
                    $refreshActionsRun = Get-LatestGitHubWorkflowRunViaApi -Owner $refreshOwner -Repo $refreshRepoName -Headers $refreshHeaders -Branch $refreshBranch
                }

                $refreshResult = Invoke-AgentRunRefresh -WorkspaceRoot $WorkspaceRoot -RunId $refreshRunId -PullRequests $refreshPulls -ActionsRun $refreshActionsRun

                Add-MetricCounter -Name 'api_requests_total'
                Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                Write-HostLog ("[TRACE] agent-runs.refresh correlationId={0} done runId={1} prFound={2} validation={3}" -f $correlationId, $refreshRunId, $refreshResult.pullRequestFound, $(if ($null -ne $refreshResult.validationEvent) { $refreshResult.validationEvent } else { 'none' }))
                Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                    success = $true
                    data    = $refreshResult
                }
                $client.Close()
                continue
            }

            if ($req.Method -eq 'GET' -and $path -like '/api/agent-runs/*' -and $path -ne '/api/agent-runs' -and
                $path -ne '/api/agent-runs/metrics-history' -and $path -ne '/api/agent-runs/quota-burn-history') {
                $agentRunIdParam = [System.Uri]::UnescapeDataString($path.Substring('/api/agent-runs/'.Length))
                if ([string]::IsNullOrWhiteSpace($agentRunIdParam)) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                        success = $false
                        error = 'runId is required in /api/agent-runs/{runId}.'
                    }
                    $client.Close()
                    continue
                }

                Write-HostLog ("[TRACE] agent-runs.detail correlationId={0} runId={1} start" -f $correlationId, $agentRunIdParam)
                $runDetail = Get-AgentRunDetail -WorkspaceRoot $WorkspaceRoot -RunId $agentRunIdParam
                if ($null -eq $runDetail) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                        success = $false
                        error = "No agent run found for runId '$agentRunIdParam'."
                    }
                    $client.Close()
                    continue
                }

                Add-MetricCounter -Name 'api_requests_total'
                Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                Write-HostLog ("[TRACE] agent-runs.detail correlationId={0} done runId={1} events={2}" -f $correlationId, $agentRunIdParam, @($runDetail.events).Count)
                Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                    success = $true
                    data    = $runDetail
                }
                $client.Close()
                continue
            }

            # ── Release 3.1 — one work item's whole life, from one id ──────
            # Accepts any identifier the chain mints (packetId, packaging runId,
            # dispatch runId, agent-run id): an operator holding one of them
            # should not have to know which ledger minted it.
            if ($req.Method -eq 'GET' -and $path -like '/api/trace/*' -and $path -ne '/api/trace/') {
                $traceIdParam = [System.Uri]::UnescapeDataString($path.Substring('/api/trace/'.Length))
                if ([string]::IsNullOrWhiteSpace($traceIdParam)) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                        success = $false
                        error = 'id is required in /api/trace/{id}.'
                    }
                    $client.Close()
                    continue
                }

                Write-HostLog ("[TRACE] trace.get correlationId={0} id={1} start" -f $correlationId, $traceIdParam)
                try {
                    $workItemTrace = Get-WorkItemTrace -WorkspaceRoot $WorkspaceRoot -Id $traceIdParam
                } catch {
                    $workItemTrace = $null
                    Write-HostLog ("[TRACE] trace.get correlationId={0} id={1} error={2}" -f $correlationId, $traceIdParam, $_.Exception.Message)
                }
                Add-MetricCounter -Name 'api_requests_total'
                if ($null -eq $workItemTrace) {
                    Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                        success = $false
                        error = "No work item matches id '$traceIdParam'. Accepted ids: packetId, packaging runId, dispatch runId, or agent-run id."
                    }
                    $client.Close()
                    continue
                }

                Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                Write-HostLog ("[TRACE] trace.get correlationId={0} id={1} done status={2} stage={3} gaps={4}" -f `
                        $correlationId, $traceIdParam, $workItemTrace.status, $workItemTrace.currentStage, (@($workItemTrace.gaps) -join ','))
                Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                    success = $true
                    data    = $workItemTrace
                }
                $client.Close()
                continue
            }

            # ── Release 2.3 Phase 3 — SVG maturity/health badges ───────────
            if ($req.Method -eq 'GET' -and $path -like '/api/badges/*' -and $path.EndsWith('.svg')) {
                $badgeName = [System.Uri]::UnescapeDataString($path.Substring('/api/badges/'.Length))
                $badgeName = $badgeName.Substring(0, $badgeName.Length - 4)  # strip .svg
                $settings = Get-HostSettings
                $opsPayload = Get-OperationsReposPayload -Settings $settings
                $entries = if ($opsPayload.available) { @($opsPayload.entries) } else { @() }
                $svg = ''
                if ($badgeName -ieq 'portfolio') {
                    $total = @($entries).Count
                    $ready = @($entries | Where-Object { ([string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'dispatchReadiness' -Default '')) -eq 'ready' }).Count
                    $color = if ($total -gt 0 -and $ready -gt 0) { '#4c1' } else { '#9f9f9f' }
                    $svg = New-SvgBadge -Label 'portfolio' -Message ("{0} repos / {1} ready" -f $total, $ready) -Color $color
                }
                else {
                    $match = @($entries | Where-Object { ([string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')).ToLowerInvariant() -eq $badgeName.ToLowerInvariant() } | Select-Object -First 1)
                    if ($match.Count -gt 0 -and $null -ne $match[0]) {
                        $dr = [string](Get-ObjectPropertyValue -InputObject $match[0] -PropertyName 'dispatchReadiness' -Default 'unknown')
                        $color = switch ($dr) { 'ready' { '#4c1' } 'blocked' { '#e05d44' } default { '#dfb317' } }
                        $svg = New-SvgBadge -Label 'readiness' -Message $dr -Color $color
                    }
                    else {
                        $svg = New-SvgBadge -Label 'readiness' -Message 'unknown' -Color '#9f9f9f'
                    }
                }
                Add-MetricCounter -Name 'api_requests_total'
                Send-HttpContent -Stream $req.Stream -StatusCode 200 -BodyBytes ([System.Text.Encoding]::UTF8.GetBytes($svg)) -ContentType 'image/svg+xml; charset=utf-8' -CorrelationId $correlationId
                $client.Close(); continue
            }

            # ── Release 2.4 — Agent Integration Protocol (/api/v1/agent/*) ──
            if ($path -like '/api/v1/agent/*') {
                $agentSub = $path.Substring('/api/v1/agent/'.Length)
                if ($req.Method -eq 'GET' -and $agentSub -eq 'queue') {
                    $settings = Get-HostSettings
                    $opsPayload = Get-OperationsReposPayload -Settings $settings
                    $queueRepos = @()
                    if ($opsPayload.available) {
                        $queueRepos = @($opsPayload.entries | ForEach-Object {
                            $rn = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')
                            $dr = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'dispatchReadiness' -Default 'unknown')
                            [pscustomobject]@{ repoName = $rn; readyForWork = ($dr -eq 'ready'); claimed = $script:AgentClaims.ContainsKey($rn.ToLowerInvariant()) }
                        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_.repoName) })
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{ success = $true; data = @{ repos = $queueRepos; generatedAt = (Get-Date).ToUniversalTime().ToString('o') } }
                    $client.Close(); continue
                }
                if ($req.Method -eq 'GET' -and $agentSub -like 'readiness/*') {
                    $repoName = [System.Uri]::UnescapeDataString($agentSub.Substring('readiness/'.Length))
                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ success = $false; error = 'repoName is required'; category = 'validation' }
                        $client.Close(); continue
                    }
                    $settings = Get-HostSettings
                    $opsPayload = Get-OperationsReposPayload -Settings $settings
                    $found = $false; $lifecycleState = 'unknown'; $dispatchReadiness = 'unknown'; $roadmapState = 'unknown'; $blockingReasons = @()
                    if ($opsPayload.available) {
                        $match = @($opsPayload.entries | Where-Object { ([string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')).ToLowerInvariant() -eq $repoName.ToLowerInvariant() } | Select-Object -First 1)
                        if ($match.Count -gt 0 -and $null -ne $match[0]) {
                            $found = $true
                            $dispatchReadiness = [string](Get-ObjectPropertyValue -InputObject $match[0] -PropertyName 'dispatchReadiness' -Default 'unknown')
                            $lifecycleState = [string](Get-ObjectPropertyValue -InputObject $match[0] -PropertyName 'lifecycleState' -Default 'unknown')
                            $roadmapState = [string](Get-ObjectPropertyValue -InputObject $match[0] -PropertyName 'roadmapState' -Default 'unknown')
                            $blockingReasons = @(Get-ObjectPropertyValue -InputObject $match[0] -PropertyName 'blockingReasons' -Default @())
                        }
                    }
                    $claimKey = $repoName.ToLowerInvariant()
                    $claimInfo = if ($script:AgentClaims.ContainsKey($claimKey)) { $script:AgentClaims[$claimKey] } else { $null }
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            schemaVersion     = 'v1'
                            repoName          = $repoName
                            found             = [bool]$found
                            lifecycleState    = $lifecycleState
                            dispatchReadiness = $dispatchReadiness
                            roadmapState      = $roadmapState
                            readyForWork      = ($dispatchReadiness -eq 'ready')
                            blockingReasons   = @($blockingReasons)
                            claim             = @{
                                claimed   = ($null -ne $claimInfo)
                                claimedBy = if ($claimInfo) { $claimInfo.claimedBy } else { $null }
                                claimId   = if ($claimInfo) { $claimInfo.claimId } else { $null }
                                claimedAt = if ($claimInfo) { $claimInfo.claimedAt } else { $null }
                            }
                            generatedAt       = (Get-Date).ToUniversalTime().ToString('o')
                        }
                    }
                    $client.Close(); continue
                }
                if ($req.Method -eq 'POST' -and $agentSub -like 'claim/*') {
                    $repoName = [System.Uri]::UnescapeDataString($agentSub.Substring('claim/'.Length))
                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ success = $false; error = 'repoName is required'; category = 'validation' }
                        $client.Close(); continue
                    }
                    $body = Parse-JsonBody -Body $req.Body
                    $agentId = if ($null -ne $body -and $body.ContainsKey('agentId') -and $body.agentId) { [string]$body.agentId } else { 'unknown-agent' }
                    $claimKey = $repoName.ToLowerInvariant()
                    if ($script:AgentClaims.ContainsKey($claimKey)) {
                        $existing = $script:AgentClaims[$claimKey]
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = ("Repository '{0}' is already claimed by '{1}'." -f $repoName, $existing.claimedBy)
                            category = 'conflict'
                            data = @{ claim = @{ claimed = $true; claimedBy = $existing.claimedBy; claimId = $existing.claimId; claimedAt = $existing.claimedAt } }
                        }
                        $client.Close(); continue
                    }
                    $claimId = [guid]::NewGuid().ToString('n')
                    $claimedAt = (Get-Date).ToUniversalTime().ToString('o')
                    $script:AgentClaims[$claimKey] = @{ claimedBy = $agentId; claimId = $claimId; claimedAt = $claimedAt; repoName = $repoName }
                    Write-HostLog ("[TRACE] agent.claim repoName={0} agentId={1} claimId={2}" -f $repoName, $agentId, $claimId)
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{ success = $true; data = @{ repoName = $repoName; claim = @{ claimed = $true; claimedBy = $agentId; claimId = $claimId; claimedAt = $claimedAt } } }
                    $client.Close(); continue
                }
                if ($req.Method -eq 'POST' -and $agentSub -like 'complete/*') {
                    $repoName = [System.Uri]::UnescapeDataString($agentSub.Substring('complete/'.Length))
                    $claimKey = $repoName.ToLowerInvariant()
                    if (-not $script:AgentClaims.ContainsKey($claimKey)) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{ success = $false; error = ("No active claim for '{0}'." -f $repoName); category = 'not-found' }
                        $client.Close(); continue
                    }
                    $script:AgentClaims.Remove($claimKey)
                    Write-HostLog ("[TRACE] agent.complete repoName={0}" -f $repoName)
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{ success = $true; data = @{ repoName = $repoName; claim = @{ claimed = $false; claimedBy = $null; claimId = $null; claimedAt = $null } } }
                    $client.Close(); continue
                }
                Add-MetricCounter -Name 'api_requests_total'
                Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{ success = $false; error = ("Unknown agent route: {0} /api/v1/agent/{1}" -f $req.Method, $agentSub); category = 'not-found' }
                $client.Close(); continue
            }

            if ($req.Method -eq 'POST' -and $path -like '/api/operations/repos/*/curation') {
                $prefix = '/api/operations/repos/'
                $suffix = '/curation'
                if (-not $path.EndsWith($suffix)) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ success = $false; error = 'Invalid curation route path.' }
                    $client.Close()
                    continue
                }

                $encodedRepoId = $path.Substring($prefix.Length, $path.Length - $prefix.Length - $suffix.Length)
                $repoId = [System.Uri]::UnescapeDataString($encodedRepoId)
                if ([string]::IsNullOrWhiteSpace($repoId)) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ success = $false; error = 'repoId is required in /api/operations/repos/{repoId}/curation.' }
                    $client.Close()
                    continue
                }

                $body = Parse-JsonBody -Body $req.Body
                $curationState = if ($body.ContainsKey('curationState') -and $body.curationState) { [string]$body.curationState } else { '' }
                $reason = if ($body.ContainsKey('reason') -and $body.reason) { [string]$body.reason } else { '' }
                if ([string]::IsNullOrWhiteSpace($curationState)) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ success = $false; error = 'curationState is required.' }
                    $client.Close()
                    continue
                }

                $settings = Get-HostSettings
                $opsPayload = Get-OperationsReposPayload -Settings $settings
                if (-not $opsPayload.available) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{ success = $false; error = $opsPayload.error }
                    $client.Close()
                    continue
                }

                $repoEntry = @($opsPayload.entries | Where-Object {
                    $candidateRepoId = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoId' -Default '')
                    $candidateRepoName = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')
                    $candidateLocalPath = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'localPath' -Default '')
                    $candidateGithubFullName = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'githubFullName' -Default '')
                    $candidateRepoId -eq $repoId -or
                    $candidateRepoName -eq $repoId -or
                    $candidateLocalPath -eq $repoId -or
                    $candidateGithubFullName -eq $repoId
                } | Select-Object -First 1)

                if ($repoEntry.Count -eq 0 -or $null -eq $repoEntry[0]) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{ success = $false; error = "No operations repo record found for repoId '$repoId'." }
                    $client.Close()
                    continue
                }

                $effectiveRepoId = [string](Get-ObjectPropertyValue -InputObject $repoEntry[0] -PropertyName 'repoId' -Default $repoId)
                $writeResult = Set-PortfolioRepoCurationState -WorkspaceRoot $WorkspaceRoot -RepoId $effectiveRepoId -CurationState $curationState -Reason $reason
                if (-not $writeResult.success) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ success = $false; error = [string]$writeResult.error }
                    $client.Close()
                    continue
                }

                $updatedAt = [string](Get-ObjectPropertyValue -InputObject $writeResult.data -PropertyName 'updatedAt' -Default ((Get-Date).ToUniversalTime().ToString('o')))
                $null = Update-PortfolioIndexRepoCuration -RepoId $effectiveRepoId -CurationState ([string]$writeResult.data.curationState) -UpdatedAt $updatedAt

                Add-MetricCounter -Name 'api_requests_total'
                Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{ success = $true; data = $writeResult.data }
                $client.Close()
                continue
            }

            if ($req.Method -eq 'GET' -and $path -like '/api/operations/repos/*' -and $path -ne '/api/operations/repos') {
                $repoId = [System.Uri]::UnescapeDataString($path.Substring('/api/operations/repos/'.Length))
                if ([string]::IsNullOrWhiteSpace($repoId)) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                        success = $false
                        error = 'repoId is required in /api/operations/repos/{repoId}.'
                    }
                    $client.Close()
                    continue
                }

                Write-HostLog ("[TRACE] operations.repoDetail correlationId={0} repoId={1} start" -f $correlationId, $repoId)
                $settings = Get-HostSettings
                $opsPayload = Get-OperationsReposPayload -Settings $settings
                if (-not $opsPayload.available) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                        success = $false
                        error = $opsPayload.error
                    }
                    $client.Close()
                    continue
                }

                $repoEntry = @($opsPayload.entries | Where-Object {
                    $candidateRepoId = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoId' -Default '')
                    $candidateRepoName = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')
                    $candidateLocalPath = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'localPath' -Default '')
                    $candidateGithubFullName = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'githubFullName' -Default '')
                    $candidateRepoId -eq $repoId -or
                    $candidateRepoName -eq $repoId -or
                    $candidateLocalPath -eq $repoId -or
                    $candidateGithubFullName -eq $repoId
                } | Select-Object -First 1)

                if ($repoEntry.Count -eq 0 -or $null -eq $repoEntry[0]) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                        success = $false
                        error = "No operations repo record found for repoId '$repoId'."
                    }
                    $client.Close()
                    continue
                }

                $repoRecord = $repoEntry[0]
                $repoName = [string](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'repoName' -Default '')

                $docAuditTtl = Get-DocAuditCacheTtlSeconds -Settings $settings
                $docAuditCache = Get-DocAuditFromCache -TtlSeconds $docAuditTtl
                $docAuditEntry = $null
                if ($docAuditCache.hit -and $docAuditCache.entries) {
                    $docAuditEntry = @($docAuditCache.entries | Where-Object {
                        [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '') -eq $repoName
                    } | Select-Object -First 1)
                    if ($docAuditEntry.Count -gt 0) {
                        $docAuditEntry = $docAuditEntry[0]
                    }
                    else {
                        $docAuditEntry = $null
                    }
                }

                $roadmapAuditTtl = Get-RoadmapAuditCacheTtlSeconds -Settings $settings
                $roadmapAuditCache = Get-RoadmapAuditFromCache -TtlSeconds $roadmapAuditTtl
                $roadmapAuditEntry = $null
                if ($roadmapAuditCache.hit -and $roadmapAuditCache.entries) {
                    $roadmapAuditEntry = @($roadmapAuditCache.entries | Where-Object {
                        [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '') -eq $repoName
                    } | Select-Object -First 1)
                    if ($roadmapAuditEntry.Count -gt 0) {
                        $roadmapAuditEntry = $roadmapAuditEntry[0]
                    }
                    else {
                        $roadmapAuditEntry = $null
                    }
                }

                $docFindings = @()
                if ($null -ne $docAuditEntry) {
                    $docFindings = @(Get-ObjectPropertyValue -InputObject $docAuditEntry -PropertyName 'docFindings' -Default @())
                }

                $roadmapFindings = @()
                if ($null -ne $roadmapAuditEntry) {
                    $roadmapFindings = @(Get-ObjectPropertyValue -InputObject $roadmapAuditEntry -PropertyName 'auditFindings' -Default @())
                }

                Add-MetricCounter -Name 'api_requests_total'
                Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                Write-HostLog ("[TRACE] operations.repoDetail correlationId={0} repoId={1} done docFindings={2} roadmapFindings={3} durationMs={4}" -f $correlationId, $repoId, @($docFindings).Count, @($roadmapFindings).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                    success = $true
                    data = @{
                        repoId = [string](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'repoId' -Default $repoId)
                        repo = $repoRecord
                        documentationContext = @{
                            hasReadme = [bool](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'hasReadme' -Default $false)
                            readmeLastWriteUtc = [string](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'readmeLastWriteUtc' -Default '')
                            hasRoadmap = [bool](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'hasRoadmap' -Default $false)
                            roadmapPath = [string](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'roadmapPath' -Default '')
                            roadmapLastWriteUtc = [string](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'roadmapLastWriteUtc' -Default '')
                            docFindingCount = [int](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'docFindingCount' -Default @($docFindings).Count)
                            structureFindings = @(Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'structureFindings' -Default @())
                        }
                        docAudit = @{
                            auditedAt = [string](Get-ObjectPropertyValue -InputObject $docAuditCache -PropertyName 'auditedAt' -Default '')
                            dispatchReadiness = [string](Get-ObjectPropertyValue -InputObject $docAuditEntry -PropertyName 'dispatchReadiness' -Default (Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'dispatchReadiness' -Default 'missing-roadmap'))
                            criticalCount = [int](Get-ObjectPropertyValue -InputObject $docAuditEntry -PropertyName 'criticalCount' -Default 0)
                            warningCount = [int](Get-ObjectPropertyValue -InputObject $docAuditEntry -PropertyName 'warningCount' -Default 0)
                            infoCount = [int](Get-ObjectPropertyValue -InputObject $docAuditEntry -PropertyName 'infoCount' -Default 0)
                            findings = @($docFindings)
                        }
                        roadmapAudit = @{
                            auditedAt = [string](Get-ObjectPropertyValue -InputObject $roadmapAuditCache -PropertyName 'auditedAt' -Default '')
                            roadmapState = [string](Get-ObjectPropertyValue -InputObject $roadmapAuditEntry -PropertyName 'roadmapState' -Default (Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'roadmapState' -Default 'missing'))
                            maturityLevel = [string](Get-ObjectPropertyValue -InputObject $roadmapAuditEntry -PropertyName 'maturityLevel' -Default (Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'maturityLevel' -Default 'L0-Absent'))
                            maturityScore = [double](Get-ObjectPropertyValue -InputObject $roadmapAuditEntry -PropertyName 'maturityScore' -Default (Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'maturityScore' -Default 0))
                            pendingCount = [int](Get-ObjectPropertyValue -InputObject $roadmapAuditEntry -PropertyName 'pendingCount' -Default (Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'pendingItemCount' -Default 0))
                            nextPendingItem = (Get-ObjectPropertyValue -InputObject $roadmapAuditEntry -PropertyName 'nextPendingItem' -Default $null)
                            auditFindings = @($roadmapFindings)
                        }
                        dispatchContext = @{
                            dispatchReadiness = [string](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'dispatchReadiness' -Default 'missing-roadmap')
                            dispatchReadinessExplanation = [string](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'dispatchReadinessExplanation' -Default '')
                            recommendedAction = [string](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'recommendedAction' -Default '')
                            blockingReasons = @(Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'blockingReasons' -Default @())
                            pendingItemCount = [int](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'pendingItemCount' -Default 0)
                            nextPendingItemText = [string](Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'nextPendingItemText' -Default '')
                            topValueItem = (Get-ObjectPropertyValue -InputObject $repoRecord -PropertyName 'topValueItem' -Default $null)
                        }
                    }
                }
                $client.Close()
                continue
            }

            # Release 2.3 Phase 5E: POST /api/portfolio/assessment/refresh-all is the
            # explicit operator-driven full reassessment. It shares the assessment
            # handler; the flag forces refresh semantics so every repo emits a
            # forced-refresh scan decision instead of the differential reuse path.
            $forcedRefreshAll = ($req.Method -eq 'POST' -and $path -eq '/api/portfolio/assessment/refresh-all')
            $routeKey = if ($forcedRefreshAll) { 'GET /api/portfolio/assessment' } else { "$($req.Method) $path" }
            switch ($routeKey) {
                'GET /health/live' {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{ status = 'ok'; service = 'repo-management-api'; time = (Get-Date).ToString('o') }
                }
                'GET /health/ready' {
                    $checks = @{
                        adaptersPath = Test-Path -LiteralPath $adapterRoot
                        adapters = Test-Path -LiteralPath (Join-Path $adapterRoot 'Adapters.ps1')
                    }
                    $healthy = -not ($checks.Values -contains $false)
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{ status = if ($healthy) { 'ready' } else { 'degraded' }; checks = $checks }
                }
                'GET /health/dependencies' {
                    $depChecks = [ordered]@{
                        git = [bool](Get-Command git -ErrorAction SilentlyContinue)
                        gh = [bool](Get-Command gh -ErrorAction SilentlyContinue)
                        adapterRootExists = Test-Path -LiteralPath $adapterRoot
                        workspaceRootExists = Test-Path -LiteralPath $WorkspaceRoot
                        outputWritable = $false
                    }

                    try {
                        $testOutputRoot = Join-Path $WorkspaceRoot 'backend\modules\output'
                        $null = New-Item -ItemType Directory -Path $testOutputRoot -Force -ErrorAction Stop
                        $probe = Join-Path $testOutputRoot '.health-probe'
                        Set-Content -LiteralPath $probe -Value 'ok' -Encoding UTF8
                        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
                        $depChecks.outputWritable = $true
                    }
                    catch {
                        $depChecks.outputWritable = $false
                    }

                    $healthy = -not ($depChecks.Values -contains $false)
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        status = if ($healthy) { 'healthy' } else { 'degraded' }
                        dependencies = $depChecks
                    }
                }
                'GET /metrics' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $snapshot = Get-MetricsSnapshot
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload $snapshot
                }
                'GET /api/persistence/status' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $persistenceCapability = Get-SqliteCapability
                    $persistenceState = Get-AppDatabaseState
                    $persistenceTables = @()
                    $agentRunEventCount = $null
                    if ($persistenceState.enabled) {
                        try {
                            $tableRows = Invoke-AppDbQuery -DatabasePath $persistenceState.databasePath -Sql "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
                            $persistenceTables = @($tableRows | ForEach-Object { [string]$_.name })
                            $countRows = Invoke-AppDbQuery -DatabasePath $persistenceState.databasePath -Sql 'SELECT COUNT(*) AS n FROM agent_run_events'
                            $agentRunEventCount = [long]$countRows[0].n
                        } catch {
                            Write-HostLog ("WARN persistence.status table inspection failed: {0}" -f $_.Exception.Message)
                        }
                    }
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success            = $true
                        capability         = $persistenceCapability
                        database           = $persistenceState
                        tables             = $persistenceTables
                        agentRunEventCount = $agentRunEventCount
                    }
                }
                # ── Release 2.7 Phase D — scheduled app.db maintenance ──────────
                # GET reports what a run WOULD remove (never mutates); POST runs
                # the prune + VACUUM. Invoke-DailyEvidence.ps1 calls the same
                # module function, so the scheduled path and the operator path
                # cannot drift apart.
                'GET /api/maintenance/database' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $maintDays = Get-AppDbMaintenanceRetentionDays -Settings (Get-HostSettings)
                    $maintReport = Invoke-AppDbMaintenance -MaxSnapshotDays $maintDays -ReportOnly
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            configuredRetentionDays = $maintDays
                            lastRun                 = $script:LastDbMaintenance
                            preview                 = $maintReport
                        }
                    }
                }
                'POST /api/maintenance/database' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $maintBody = Parse-JsonBody -Body $req.Body
                    $maintDays = Get-AppDbMaintenanceRetentionDays -Settings (Get-HostSettings)
                    if ($null -ne $maintBody -and $maintBody.ContainsKey('maxSnapshotDays') -and [int]$maintBody.maxSnapshotDays -gt 0) {
                        $maintDays = [int]$maintBody.maxSnapshotDays
                    }
                    $skipVacuum = ($null -ne $maintBody -and $maintBody.ContainsKey('skipVacuum') -and [bool]$maintBody.skipVacuum)
                    $maintResult = Invoke-AppDbMaintenance -MaxSnapshotDays $maintDays -SkipVacuum:$skipVacuum -Confirm:$false
                    $script:LastDbMaintenance = $maintResult
                    Write-HostLog ("maintenance.database removed={0} vacuumed={1} reclaimedBytes={2} durationMs={3} correlationId={4}" -f `
                            $maintResult.totalRowsRemoved, $maintResult.vacuumed, $maintResult.reclaimedBytes, $maintResult.durationMs, $correlationId)
                    $maintStatus = if ($maintResult.success) { 200 } else { 500 }
                    Send-HttpJson -Stream $req.Stream -StatusCode $maintStatus -CorrelationId $correlationId -Payload @{
                        success = [bool]$maintResult.success
                        data    = $maintResult
                    }
                }
                # ── Release 2.2/2.7 — auth status, login, logout ────────────────
                'GET /api/auth/status' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $apiKeyAuthed = if ($script:AuthEnforced) { [bool](Test-RequestApiKeyValid -Request $req -ExpectedKey $script:EffectiveApiKey) } else { $false }
                    $sessionAuthed = if ($script:HumanLoginConfigured) { [bool](Test-RequestSessionValid -Request $req -WorkspaceRoot $WorkspaceRoot) } else { $false }
                    $authedNow = if ($script:GateEnabled) { ($apiKeyAuthed -or $sessionAuthed) } else { $true }
                    $authMethod = if ($sessionAuthed) { 'session' } elseif ($apiKeyAuthed) { 'apiKey' } else { $null }
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            authRequired    = [bool]$script:AuthRequired
                            authEnforced    = [bool]$script:AuthEnforced
                            gateEnabled     = [bool]$script:GateEnabled
                            loginConfigured = [bool]$script:HumanLoginConfigured
                            authenticated   = [bool]$authedNow
                            method          = $authMethod
                            keyEnvVar       = (Get-AuthApiKeyEnvVarName -Settings $script:AuthSettings)
                            bindAddress     = $BindAddress
                            isLoopbackBind  = [bool](Test-IsLoopbackAddress -Address $BindAddress)
                        }
                    }
                }
                'POST /api/auth/login' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $loginBody = Parse-JsonBody -Body $req.Body
                    $loginPassword = if ($loginBody -and $loginBody.ContainsKey('password')) { [string]$loginBody.password } else { '' }
                    if (-not $script:HumanLoginConfigured) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                            success = $false; category = 'auth'
                            error   = 'No portal password is configured. Set one with scripts\Set-PortalLogin.ps1, then restart the host.'
                        }
                    }
                    elseif ([string]::IsNullOrEmpty($loginPassword) -or -not (Test-PortalPassword -WorkspaceRoot $WorkspaceRoot -Password $loginPassword)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 401 -StatusText 'Unauthorized' -CorrelationId $correlationId -Payload @{
                            success = $false; category = 'auth'; error = 'Invalid password.'
                        }
                    }
                    else {
                        $ttlHours = 12
                        $token = New-SessionToken -WorkspaceRoot $WorkspaceRoot -TtlHours $ttlHours
                        $cookieSecure = ($null -ne $script:TlsCertificate)
                        $cookieHeader = New-SessionCookieHeader -Token $token -TtlHours $ttlHours -Secure $cookieSecure
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -ExtraHeaders @($cookieHeader) -Payload @{
                            success = $true; data = @{ authenticated = $true; method = 'session'; ttlHours = $ttlHours }
                        }
                    }
                }
                'POST /api/auth/logout' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $cookieSecure = ($null -ne $script:TlsCertificate)
                    $clearHeader = New-SessionClearCookieHeader -Secure $cookieSecure
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -ExtraHeaders @($clearHeader) -Payload @{
                        success = $true; data = @{ authenticated = $false }
                    }
                }
                'GET /api/auth/github/status' {
                    # Release 2.2 — reports the effective GitHub auth mode and
                    # PAT-precedence. PAT/env token wins over a configured GitHub
                    # App. Live App-token minting/refresh needs a registered app
                    # (operator step); this route surfaces which mode is active.
                    # Doubles as the env-var resolve probe for the Settings dialog:
                    # it answers "does the name I configured actually resolve in
                    # the host's own process?", which is the failure a browser
                    # cannot detect on the operator's behalf. Pass ?validate=1 to
                    # additionally spend one GitHub call confirming the token is
                    # live and reporting its expiry.
                    Add-MetricCounter -Name 'api_requests_total'
                    $q = Parse-QueryString -Query $req.Query
                    $validateLive = ($q.ContainsKey('validate') -and $q['validate'] -in @('1', 'true', 'yes'))
                    $s = Get-HostSettings
                    $resolution = Get-GitHubTokenResolution -Settings $s
                    $tokenEnvVar = $resolution.EnvVarName
                    $patPresent = ($resolution.Source -eq 'env')
                    $ghCliPresent = [bool](Get-Command gh -ErrorAction SilentlyContinue)
                    $githubAppConfigured = $false
                    if ($s.ContainsKey('githubApp') -and $s.githubApp -is [System.Collections.IDictionary]) {
                        $ga = $s.githubApp
                        $githubAppConfigured = ($ga.ContainsKey('appId') -and $ga.appId) -and ($ga.ContainsKey('installationId') -and $ga.installationId)
                    }
                    $mode = if ($patPresent) { 'pat' } elseif ($resolution.Source -eq 'gh-cli') { 'gh-cli' } elseif ($githubAppConfigured) { 'github-app' } else { 'none' }
                    $appReadiness = $null
                    try { $appReadiness = Get-GitHubAppReadiness -GitHubApp $(if ($s.ContainsKey('githubApp')) { $s.githubApp } else { $null }) } catch { $appReadiness = $null }

                    # Name the actual cause of a miss instead of a bare "not set".
                    $hint = ''
                    if ($resolution.Source -eq 'none') {
                        $hint = Get-GitHubTokenMissHint -EnvVarName $tokenEnvVar
                    }
                    elseif ($resolution.Source -eq 'env' -and $resolution.Scope -eq 'Process' -and $script:RunningAsService) {
                        $hint = "Resolved from the process environment only. It will not survive a service restart unless it is set at Machine scope."
                    }

                    $liveCheck = $null
                    if ($validateLive) {
                        if ([string]::IsNullOrWhiteSpace($resolution.Token)) {
                            $liveCheck = @{ checked = $true; valid = $false; error = 'No token to validate.' }
                        }
                        else {
                            try {
                                $probeHeaders = Get-GitHubApiHeaders -Token $resolution.Token
                                $probeResponse = Invoke-WebRequest -Uri 'https://api.github.com/user' -Headers $probeHeaders -Method Get -UseBasicParsing -ErrorAction Stop
                                $probeLogin = (ConvertFrom-JsonCompat -Json $probeResponse.Content).login
                                $probeExpiry = ''
                                try { $probeExpiry = [string]($probeResponse.Headers['github-authentication-token-expiration'] | Select-Object -First 1) } catch { }
                                $liveCheck = @{
                                    checked   = $true
                                    valid     = $true
                                    login     = [string]$probeLogin
                                    expiresAt = $probeExpiry
                                }
                            }
                            catch {
                                $liveCheck = @{ checked = $true; valid = $false; error = ("GitHub rejected the token: {0}" -f $_.Exception.Message) }
                            }
                        }
                    }

                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            mode                = $mode
                            patPresent          = [bool]$patPresent
                            ghCliPresent        = [bool]$ghCliPresent
                            githubAppConfigured = [bool]$githubAppConfigured
                            githubAppReadiness  = $appReadiness
                            tokenEnvVar         = $tokenEnvVar
                            tokenSource         = $resolution.Source
                            tokenEnvScope       = $resolution.Scope
                            runningAsService    = [bool]$script:RunningAsService
                            hint                = $hint
                            liveCheck           = $liveCheck
                            precedence          = @('env-var', 'gh-cli', 'github-app')
                        }
                    }
                }
                'GET /api/digest/preview' {
                    # Release 2.3 Phase 3 — build the digest payload without delivery.
                    Add-MetricCounter -Name 'api_requests_total'
                    $settings = Get-HostSettings
                    $opsPayload = Get-OperationsReposPayload -Settings $settings
                    $entries = if ($opsPayload.available) { @($opsPayload.entries) } else { @() }
                    $digest = Get-DigestPayload -Entries $entries
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{ success = $true; data = @{ delivered = $false; payload = $digest } }
                }
                'POST /api/digest/send' {
                    # Release 2.3 Phase 3 — build + deliver the digest to a webhook.
                    # No webhook configured/provided -> dry-run (delivered=false),
                    # returning the payload so callers can preview it.
                    Add-MetricCounter -Name 'api_requests_total'
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $opsPayload = Get-OperationsReposPayload -Settings $settings
                    $entries = if ($opsPayload.available) { @($opsPayload.entries) } else { @() }
                    $digest = Get-DigestPayload -Entries $entries
                    $webhookUrl = ''
                    if ($null -ne $body -and $body.ContainsKey('webhookUrl') -and $body.webhookUrl) { $webhookUrl = [string]$body.webhookUrl }
                    elseif ($settings.ContainsKey('digest') -and $settings.digest -is [System.Collections.IDictionary] -and $settings.digest.ContainsKey('webhookUrl') -and $settings.digest.webhookUrl) { $webhookUrl = [string]$settings.digest.webhookUrl }
                    $delivered = $false
                    $deliveryError = $null
                    if (-not [string]::IsNullOrWhiteSpace($webhookUrl)) {
                        try {
                            $null = Invoke-WebRequest -Uri $webhookUrl -Method Post -ContentType 'application/json' -Body ($digest | ConvertTo-Json -Depth 8) -TimeoutSec 15 -SkipHttpErrorCheck
                            $delivered = $true
                        } catch { $deliveryError = $_.Exception.Message }
                    }
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{ delivered = [bool]$delivered; webhookConfigured = (-not [string]::IsNullOrWhiteSpace($webhookUrl)); deliveryError = $deliveryError; payload = $digest }
                    }
                }
                'POST /api/automation/run' {
                    # Release 2.7 Phase B — scheduled documentation refinement.
                    # Preview-first: select favorite/portfolio-candidate repos with
                    # weak README/ROADMAP, generate doc-improve PREVIEWS (never apply),
                    # record append-only history, and optionally deliver a digest.
                    # Nothing is mutated. An external cron/webhook hits this endpoint.
                    Add-MetricCounter -Name 'api_requests_total'
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $opsPayload = Get-OperationsReposPayload -Settings $settings
                    if (-not [bool](Get-ObjectPropertyValue -InputObject $opsPayload -PropertyName 'available' -Default $false)) {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 409 -ErrorMessage 'Portfolio not ready. Run /api/portfolio/assessment first, then retry.' -CorrelationId $correlationId -Operation 'automation.run'
                    }
                    else {
                        $entries = @(Get-ObjectPropertyValue -InputObject $opsPayload -PropertyName 'entries' -Default @())
                        $curationMap = @{}
                        try { $curationMap = Get-PortfolioCurationMap -WorkspaceRoot $WorkspaceRoot } catch { $curationMap = @{} }
                        $targets = @(Select-AutomationDocTargets -Entries $entries -CurationMap $curationMap)
                        $run = Invoke-ScheduledDocRefinement -WorkspaceRoot $WorkspaceRoot -Targets $targets -Settings $settings -Provider 'heuristic' -TriggeredBy 'api'
                        $null = Write-AutomationRunRecord -WorkspaceRoot $WorkspaceRoot -Run $run
                        $digest = New-AutomationDigestPayload -Run $run

                        # Optional webhook delivery (same pattern as /api/digest/send).
                        # No webhook -> dry-run (delivered=false). Nothing is applied either way.
                        $webhookUrl = ''
                        if ($null -ne $body -and $body.ContainsKey('webhookUrl') -and $body.webhookUrl) { $webhookUrl = [string]$body.webhookUrl }
                        elseif ($settings.ContainsKey('automation') -and $settings.automation -is [System.Collections.IDictionary] -and $settings.automation.ContainsKey('webhookUrl') -and $settings.automation.webhookUrl) { $webhookUrl = [string]$settings.automation.webhookUrl }
                        $delivered = $false
                        $deliveryError = $null
                        if (-not [string]::IsNullOrWhiteSpace($webhookUrl)) {
                            try {
                                $null = Invoke-WebRequest -Uri $webhookUrl -Method Post -ContentType 'application/json' -Body ($digest | ConvertTo-Json -Depth 8) -TimeoutSec 15 -SkipHttpErrorCheck
                                $delivered = $true
                            } catch { $deliveryError = $_.Exception.Message }
                        }

                        # Release 2.7 Phase D — failure alerting. A run that errored
                        # previously returned HTTP 200 with the errors buried in the
                        # payload, so a scheduled run degrading over time was
                        # invisible unless someone read the history by hand. Fire the
                        # same execution.failed event the portal watchdog uses.
                        $runOutcome = Get-AutomationRunOutcome -Run $run
                        $alertFired = $false
                        $alertError = $null
                        if ($runOutcome -ne 'ok') {
                            try {
                                $null = Send-NotificationEvent -WorkspaceRoot $WorkspaceRoot -EventName 'execution.failed' -EventPayload @{
                                    source        = 'automation-scheduler'
                                    runId         = [string]$run.runId
                                    kind          = [string]$run.kind
                                    outcome       = $runOutcome
                                    targetCount   = [int]$run.targetCount
                                    proposalCount = [int]$run.proposalCount
                                    errorCount    = @($run.errors).Count
                                    errors        = @($run.errors)
                                }
                                $alertFired = $true
                            } catch { $alertError = $_.Exception.Message }
                            Write-HostLog ("WARN automation.run outcome={0} errors={1} runId={2} alertFired={3}" -f `
                                    $runOutcome, @($run.errors).Count, $run.runId, $alertFired)
                        }

                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                run               = $run
                                digest            = $digest
                                delivered         = [bool]$delivered
                                webhookConfigured = (-not [string]::IsNullOrWhiteSpace($webhookUrl))
                                deliveryError     = $deliveryError
                                outcome           = $runOutcome
                                alertFired        = [bool]$alertFired
                                alertError        = $alertError
                            }
                        }
                    }
                }
                'GET /api/automation/history' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $q = Parse-QueryString -Query $req.Query
                    $limit = if ($q.ContainsKey('limit') -and $q.limit) { [int]$q.limit } else { 50 }
                    $kindFilter = if ($q.ContainsKey('kind') -and $q.kind) { [string]$q.kind } else { '' }
                    # Every scheduled run, both kinds. They are stored in separate
                    # files on purpose (Phase D's overdue alert reads the
                    # doc-refinement file alone, so a live packaging cron cannot
                    # mask a dead doc cron), and merged here so the history route
                    # still answers "every scheduled run" as its contract says.
                    $docRuns = @(Get-AutomationRunHistory -WorkspaceRoot $WorkspaceRoot -Limit 0)
                    $pkgRuns = @(Get-PackagingRunHistory -WorkspaceRoot $WorkspaceRoot -Limit 0)
                    $history = @(@($docRuns) + @($pkgRuns))
                    if (-not [string]::IsNullOrWhiteSpace($kindFilter)) {
                        $history = @($history | Where-Object { [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'kind' -Default 'doc-refinement') -eq $kindFilter })
                    }
                    $history = @($history | Sort-Object -Property @{ Expression = { [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'finishedAt' -Default '') }; Descending = $true })
                    if ($limit -gt 0 -and @($history).Count -gt $limit) { $history = @($history[0..($limit - 1)]) }
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            count             = @($history).Count
                            kind              = $kindFilter
                            docRefinementRuns = @($docRuns).Count
                            packagingRuns     = @($pkgRuns).Count
                            runs              = $history
                        }
                    }
                }
                # ── Release 3.0 — operator-runner presence ──────────────────────
                # The portal enqueues work it cannot execute. Without this route
                # the UI cannot tell "queued and about to run" from "queued into
                # an empty room", and the operator only finds out when nothing
                # ever leaves `queued`.
                'GET /api/roadmap/runner' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $runnerState = Get-RunnerPresence -WorkspaceRoot $WorkspaceRoot
                    $runnerBacklog = Get-QueuedTaskBacklog -WorkspaceRoot $WorkspaceRoot
                    $runnerPayload = [ordered]@{}
                    foreach ($property in $runnerState.PSObject.Properties) { $runnerPayload[$property.Name] = $property.Value }
                    foreach ($property in $runnerBacklog.PSObject.Properties) { $runnerPayload[$property.Name] = $property.Value }
                    # Backlog without presence understates the problem: "no
                    # runner" matters far more with 12 tasks already waiting.
                    $runnerPayload['strandedCount'] = if ($runnerState.present) { 0 } else { [int]$runnerBacklog.queuedTotal }
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = $runnerPayload
                    }
                }
                # ── Release 2.7 Phase D — automation health ─────────────────────
                # Interval firing is delegated to an external cron, so a scheduler
                # that stops changes nothing visible in the product: the config
                # still reads "enabled" and history just stops growing. This route
                # turns that silence into an alert.
                'GET /api/automation/status' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $healthSettings = Get-HostSettings
                    $autoHealth = Get-AutomationHealth -WorkspaceRoot $WorkspaceRoot -Settings $healthSettings
                    # Phase C's packaging cron has its own history file and its
                    # own health reader — Get-AutomationHealth deliberately reads
                    # only the doc-refinement file, so a packaging cron that
                    # stopped was invisible here. Two readers, never a merged
                    # file: each scheduler is judged by its own evidence.
                    $packagingHealth = Get-PackagingHealth -WorkspaceRoot $WorkspaceRoot -Settings $healthSettings

                    # The doc-refinement fields stay at the top level so the
                    # existing badge keeps working unchanged; packaging is added
                    # beside them rather than replacing the shape.
                    $healthPayload = [ordered]@{}
                    foreach ($property in $autoHealth.PSObject.Properties) { $healthPayload[$property.Name] = $property.Value }
                    $healthPayload['kind'] = 'doc-refinement'
                    $healthPayload['packaging'] = $packagingHealth
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = $healthPayload
                    }
                }
                # ── Release 2.7 Phase C — scheduled roadmap-item packaging ──────
                # For each curated repo with a contract-ready (L3+) roadmap: rank
                # its pending items, price the top one through the quota guard,
                # build a task packet + repair-PR plan, and QUEUE IT FOR APPROVAL.
                # This route never dispatches and never merges — dispatch needs
                # the explicit approval action below.
                'POST /api/automation/package-run' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $opsPayload = Get-OperationsReposPayload -Settings $settings
                    if (-not [bool](Get-ObjectPropertyValue -InputObject $opsPayload -PropertyName 'available' -Default $false)) {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 409 -ErrorMessage 'Portfolio not ready. Run /api/portfolio/assessment first, then retry.' -CorrelationId $correlationId -Operation 'automation.package-run'
                    }
                    else {
                        $entries = @(Get-ObjectPropertyValue -InputObject $opsPayload -PropertyName 'entries' -Default @())
                        $curationMap = @{}
                        try { $curationMap = Get-PortfolioCurationMap -WorkspaceRoot $WorkspaceRoot } catch { $curationMap = @{} }

                        $packagingConfig = $null
                        if ($settings.ContainsKey('automation') -and $settings.automation -is [System.Collections.IDictionary] -and $settings.automation.ContainsKey('packaging')) {
                            $packagingConfig = $settings.automation.packaging
                        }
                        $defaultWorkUnits = 3.0
                        if ($null -ne $packagingConfig -and $packagingConfig -is [System.Collections.IDictionary] -and $packagingConfig.ContainsKey('defaultWorkUnitsPerItem')) {
                            $parsedUnits = 0.0
                            if ([double]::TryParse([string]$packagingConfig.defaultWorkUnitsPerItem, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedUnits) -and $parsedUnits -gt 0) {
                                $defaultWorkUnits = [double]$parsedUnits
                            }
                        }

                        $packagingRun = Invoke-ScheduledRoadmapPackaging `
                            -WorkspaceRoot $WorkspaceRoot `
                            -Entries $entries `
                            -CurationMap $curationMap `
                            -Settings $settings `
                            -DefaultWorkUnits $defaultWorkUnits `
                            -TriggeredBy 'api'
                        $null = Write-PackagingRunRecord -WorkspaceRoot $WorkspaceRoot -Run $packagingRun
                        $packagingDigest = New-PackagingDigestPayload -Run $packagingRun

                        # Notify per run (same delivery path as Phase B's digest).
                        # No webhook configured -> dry-run; nothing is dispatched either way.
                        $pkgWebhookUrl = ''
                        if ($null -ne $body -and $body.ContainsKey('webhookUrl') -and $body.webhookUrl) { $pkgWebhookUrl = [string]$body.webhookUrl }
                        elseif ($settings.ContainsKey('automation') -and $settings.automation -is [System.Collections.IDictionary] -and $settings.automation.ContainsKey('webhookUrl') -and $settings.automation.webhookUrl) { $pkgWebhookUrl = [string]$settings.automation.webhookUrl }
                        $pkgDelivered = $false
                        $pkgDeliveryError = $null
                        if (-not [string]::IsNullOrWhiteSpace($pkgWebhookUrl)) {
                            try {
                                $null = Invoke-WebRequest -Uri $pkgWebhookUrl -Method Post -ContentType 'application/json' -Body ($packagingDigest | ConvertTo-Json -Depth 10) -TimeoutSec 15 -SkipHttpErrorCheck
                                $pkgDelivered = $true
                            } catch { $pkgDeliveryError = $_.Exception.Message }
                        }

                        # Failure alerting, same contract as Phase B: a run that
                        # errored must not return a quiet 200 with the errors
                        # buried in the payload.
                        $pkgOutcome = Get-AutomationRunOutcome -Run $packagingRun
                        $pkgAlertFired = $false
                        $pkgAlertError = $null
                        if ($pkgOutcome -ne 'ok') {
                            try {
                                $null = Send-NotificationEvent -WorkspaceRoot $WorkspaceRoot -EventName 'execution.failed' -EventPayload @{
                                    source        = 'automation-packaging'
                                    runId         = [string]$packagingRun.runId
                                    kind          = [string]$packagingRun.kind
                                    outcome       = $pkgOutcome
                                    packagedCount = [int]$packagingRun.packagedCount
                                    skippedCount  = [int]$packagingRun.skippedCount
                                    errorCount    = @($packagingRun.errors).Count
                                    errors        = @($packagingRun.errors)
                                }
                                $pkgAlertFired = $true
                            } catch { $pkgAlertError = $_.Exception.Message }
                            Write-HostLog ("WARN automation.package-run outcome={0} errors={1} runId={2} alertFired={3}" -f `
                                    $pkgOutcome, @($packagingRun.errors).Count, $packagingRun.runId, $pkgAlertFired)
                        }

                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                run               = $packagingRun
                                digest            = $packagingDigest
                                delivered         = [bool]$pkgDelivered
                                webhookConfigured = (-not [string]::IsNullOrWhiteSpace($pkgWebhookUrl))
                                deliveryError     = $pkgDeliveryError
                                outcome           = $pkgOutcome
                                alertFired        = [bool]$pkgAlertFired
                                alertError        = $pkgAlertError
                                note              = 'Packaged for approval only. Nothing was dispatched, applied, or merged.'
                            }
                        }
                    }
                }
                'GET /api/automation/packages' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $q = Parse-QueryString -Query $req.Query
                    $pkgStatus = if ($q.ContainsKey('status') -and $q.status) { [string]$q.status } else { '' }
                    $pkgLimit = if ($q.ContainsKey('limit') -and $q.limit) { [int]$q.limit } else { 100 }
                    $pkgItems = @(Get-PackagedItemQueue -WorkspaceRoot $WorkspaceRoot -Status $pkgStatus -Limit $pkgLimit)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            count            = @($pkgItems).Count
                            status           = $pkgStatus
                            pendingCount     = @(@($pkgItems) | Where-Object { [string]$_.status -eq 'pending-approval' }).Count
                            items            = $pkgItems
                        }
                    }
                }
                'POST /api/automation/packages/approve' {
                    # The approval gate. A packet becomes runnable here and
                    # nowhere else — and only from pending-approval, only if the
                    # quota guard still allows it at approval time.
                    Add-MetricCounter -Name 'api_requests_total'
                    $body = Parse-JsonBody -Body $req.Body
                    $approvePacketId = if ($null -ne $body -and $body.ContainsKey('packetId') -and $body.packetId) { [string]$body.packetId } else { '' }
                    $approveActor = if ($null -ne $body -and $body.ContainsKey('actor') -and $body.actor) { [string]$body.actor } else { 'operator' }
                    $approveDispatch = $true
                    if ($null -ne $body -and $body.ContainsKey('dispatch')) { $approveDispatch = [bool]$body.dispatch }

                    if ([string]::IsNullOrWhiteSpace($approvePacketId)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ success = $false; error = 'packetId is required'; category = 'validation' }
                    }
                    else {
                        $approveItem = Get-PackagedItem -WorkspaceRoot $WorkspaceRoot -PacketId $approvePacketId
                        $approveFrom = if ($null -ne $approveItem) { [string]$approveItem.status } else { '' }
                        $approveTransition = Test-PackagedItemTransition -From $approveFrom -To 'approved'
                        if (-not $approveTransition.allowed) {
                            $approveStatusCode = if ($approveTransition.reason -eq 'packet-not-found') { 404 } else { 409 }
                            $approveStatusText = if ($approveStatusCode -eq 404) { 'Not Found' } else { 'Conflict' }
                            Send-HttpJson -Stream $req.Stream -StatusCode $approveStatusCode -StatusText $approveStatusText -CorrelationId $correlationId -Payload @{
                                success  = $false
                                error    = [string]$approveTransition.message
                                category = [string]$approveTransition.reason
                                data     = @{ packetId = $approvePacketId; status = $approveFrom }
                            }
                        }
                        else {
                            $approvePacket = $approveItem.packet
                            $approveSettings = Get-HostSettings
                            $approveQuota = Test-PackagingQuota `
                                -WorkspaceRoot $WorkspaceRoot `
                                -RepoName ([string](Get-ObjectPropertyValue -InputObject $approvePacket -PropertyName 'repoName' -Default $approveItem.repoName)) `
                                -EstimatedWorkUnits ([double](Get-ObjectPropertyValue -InputObject $approvePacket -PropertyName 'estimatedWorkUnits' -Default 3.0)) `
                                -Settings $approveSettings

                            if (-not $approveQuota.allowed) {
                                # Budget may have been consumed since packaging.
                                # Record the refused attempt (status unchanged) so
                                # the audit trail shows it, and refuse with 409.
                                $null = Write-PackagedItemRecord -WorkspaceRoot $WorkspaceRoot -Record ([pscustomobject]@{
                                    schemaVersion = '1'
                                    packetId      = $approvePacketId
                                    runId         = [string]$approveItem.runId
                                    repoName      = [string]$approveItem.repoName
                                    status        = 'pending-approval'
                                    recordedAt    = (Get-Date).ToUniversalTime().ToString('o')
                                    actor         = $approveActor
                                    note          = ("quota-refused: {0} — {1}" -f $approveQuota.blockedCode, $approveQuota.message)
                                })
                                Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                                    success  = $false
                                    error    = [string]$approveQuota.message
                                    category = ("quota-refused:{0}" -f $approveQuota.blockedCode)
                                    data     = @{ packetId = $approvePacketId; status = 'pending-approval'; dispatched = $false }
                                }
                            }
                            else {
                                # Release 3.1 — the runner precondition is evaluated BEFORE the
                                # approval is recorded, for the same reason the dispatch route
                                # evaluates it before the queue write: a refusal must leave no
                                # trace. Recording `approved` first and refusing after would
                                # strand the packet outright — `approved` may only transition to
                                # `dispatched` or `dispatch-failed`, so a packet approved into an
                                # empty room could never be approved again. This mirrors the
                                # quota refusal above: audit note, status unchanged, 409.
                                $approveAcknowledgeNoRunner = $false
                                if ($body.ContainsKey('acknowledgeNoRunner')) { $approveAcknowledgeNoRunner = [bool]$body.acknowledgeNoRunner }
                                $approvePresence = Get-RunnerPresence -WorkspaceRoot $WorkspaceRoot
                                if ($approveDispatch -and -not $approvePresence.present -and -not $approveAcknowledgeNoRunner) {
                                    $approveBacklog = Get-QueuedTaskBacklog -WorkspaceRoot $WorkspaceRoot
                                    $null = Write-PackagedItemRecord -WorkspaceRoot $WorkspaceRoot -Record ([pscustomobject]@{
                                        schemaVersion = '1'
                                        packetId      = $approvePacketId
                                        runId         = [string]$approveItem.runId
                                        repoName      = [string]$approveItem.repoName
                                        status        = 'pending-approval'
                                        recordedAt    = (Get-Date).ToUniversalTime().ToString('o')
                                        actor         = $approveActor
                                        note          = ("runner-absent: approval refused so the packet is not stranded — {0}" -f [string]$approvePresence.message)
                                    })
                                    Write-HostLog ("WARN automation.packages.approve correlationId={0} packetId={1} refused - runner {2}, stranded={3} (nothing written, packet stays pending-approval)" -f `
                                            $correlationId, $approvePacketId, $approvePresence.state, [int]$approveBacklog.queuedTotal)
                                    Add-MetricCounter -Name 'api_requests_total'
                                    Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                                        success  = $false
                                        error    = ("No operator runner can claim this packet, so approving it would strand it. {0} Start one with: pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1" -f [string]$approvePresence.message)
                                        category = 'runner-absent'
                                        data     = @{
                                            packetId      = $approvePacketId
                                            status        = 'pending-approval'
                                            dispatched    = $false
                                            runnerCommand = 'pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1'
                                            runner        = $approvePresence
                                            strandedCount = [int]$approveBacklog.queuedTotal
                                            overrideField = 'acknowledgeNoRunner'
                                            queuedNothing = $true
                                        }
                                    }
                                    break
                                }

                                $null = Write-PackagedItemRecord -WorkspaceRoot $WorkspaceRoot -Record ([pscustomobject]@{
                                    schemaVersion = '1'
                                    packetId      = $approvePacketId
                                    runId         = [string]$approveItem.runId
                                    repoName      = [string]$approveItem.repoName
                                    status        = 'approved'
                                    recordedAt    = (Get-Date).ToUniversalTime().ToString('o')
                                    actor         = $approveActor
                                    note          = 'Approved by an explicit operator action.'
                                })

                                $approveDispatchResult = $null
                                $approveDispatchError = $null
                                if ($approveDispatch) {
                                    try {
                                        # The writer gates too — that is the structural guarantee for
                                        # any future caller. Reaching a refusal here would mean the
                                        # runner died between the check above and this line, which the
                                        # catch below records as a dispatch failure, correctly.
                                        $approveDispatchResult = Submit-PackagedItemToRunner -WorkspaceRoot $WorkspaceRoot -Packet $approvePacket -Actor $approveActor -AcknowledgeNoRunner:$approveAcknowledgeNoRunner
                                        if ($approveDispatchResult.refused) {
                                            throw ("Runner became unavailable between the precondition check and the queue write: {0}" -f [string]$approveDispatchResult.message)
                                        }
                                        $null = Write-PackagedItemRecord -WorkspaceRoot $WorkspaceRoot -Record ([pscustomobject]@{
                                            schemaVersion = '1'
                                            packetId      = $approvePacketId
                                            runId         = [string]$approveItem.runId
                                            repoName      = [string]$approveItem.repoName
                                            status        = 'dispatched'
                                            recordedAt    = (Get-Date).ToUniversalTime().ToString('o')
                                            actor         = $approveActor
                                            dispatchRunId = [string]$approveDispatchResult.runId
                                            note          = ("Enqueued for the operator runner as run {0} on branch {1}." -f $approveDispatchResult.runId, $approveDispatchResult.branch)
                                        })
                                    } catch {
                                        $approveDispatchError = $_.Exception.Message
                                        $null = Write-PackagedItemRecord -WorkspaceRoot $WorkspaceRoot -Record ([pscustomobject]@{
                                            schemaVersion = '1'
                                            packetId      = $approvePacketId
                                            runId         = [string]$approveItem.runId
                                            repoName      = [string]$approveItem.repoName
                                            status        = 'dispatch-failed'
                                            recordedAt    = (Get-Date).ToUniversalTime().ToString('o')
                                            actor         = $approveActor
                                            note          = ("Dispatch failed: {0}" -f $approveDispatchError)
                                        })
                                    }
                                }

                                if ($approveDispatch -and $null -eq $approveDispatchResult) {
                                    Send-HttpJson -Stream $req.Stream -StatusCode 500 -StatusText 'Internal Server Error' -CorrelationId $correlationId -Payload @{
                                        success  = $false
                                        error    = ("Packet {0} was approved but could not be enqueued: {1}" -f $approvePacketId, $approveDispatchError)
                                        category = 'dispatch-failed'
                                        data     = @{ packetId = $approvePacketId; status = 'dispatch-failed'; dispatched = $false }
                                    }
                                }
                                else {
                                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                        success = $true
                                        data = @{
                                            packetId       = $approvePacketId
                                            status         = if ($approveDispatch) { 'dispatched' } else { 'approved' }
                                            dispatched     = [bool]$approveDispatch
                                            dispatchTarget = 'operator-runner'
                                            dispatchRunId  = if ($null -ne $approveDispatchResult) { [string]$approveDispatchResult.runId } else { $null }
                                            branch         = if ($null -ne $approveDispatchResult) { [string]$approveDispatchResult.branch } else { $null }
                                            note           = 'Queued for the operator runner (Invoke-RoadmapTaskRunner.ps1). Nothing was merged; the PR opens for review.'
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                'POST /api/automation/packages/reject' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $body = Parse-JsonBody -Body $req.Body
                    $rejectPacketId = if ($null -ne $body -and $body.ContainsKey('packetId') -and $body.packetId) { [string]$body.packetId } else { '' }
                    $rejectActor = if ($null -ne $body -and $body.ContainsKey('actor') -and $body.actor) { [string]$body.actor } else { 'operator' }
                    $rejectReason = if ($null -ne $body -and $body.ContainsKey('reason') -and $body.reason) { [string]$body.reason } else { 'Rejected by the operator.' }

                    if ([string]::IsNullOrWhiteSpace($rejectPacketId)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ success = $false; error = 'packetId is required'; category = 'validation' }
                    }
                    else {
                        $rejectItem = Get-PackagedItem -WorkspaceRoot $WorkspaceRoot -PacketId $rejectPacketId
                        $rejectFrom = if ($null -ne $rejectItem) { [string]$rejectItem.status } else { '' }
                        $rejectTransition = Test-PackagedItemTransition -From $rejectFrom -To 'rejected'
                        if (-not $rejectTransition.allowed) {
                            $rejectStatusCode = if ($rejectTransition.reason -eq 'packet-not-found') { 404 } else { 409 }
                            $rejectStatusText = if ($rejectStatusCode -eq 404) { 'Not Found' } else { 'Conflict' }
                            Send-HttpJson -Stream $req.Stream -StatusCode $rejectStatusCode -StatusText $rejectStatusText -CorrelationId $correlationId -Payload @{
                                success  = $false
                                error    = [string]$rejectTransition.message
                                category = [string]$rejectTransition.reason
                                data     = @{ packetId = $rejectPacketId; status = $rejectFrom }
                            }
                        }
                        else {
                            $null = Write-PackagedItemRecord -WorkspaceRoot $WorkspaceRoot -Record ([pscustomobject]@{
                                schemaVersion = '1'
                                packetId      = $rejectPacketId
                                runId         = [string]$rejectItem.runId
                                repoName      = [string]$rejectItem.repoName
                                status        = 'rejected'
                                recordedAt    = (Get-Date).ToUniversalTime().ToString('o')
                                actor         = $rejectActor
                                note          = $rejectReason
                            })
                            Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                success = $true
                                data = @{ packetId = $rejectPacketId; status = 'rejected'; dispatched = $false }
                            }
                        }
                    }
                }
                'GET /setup/status' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $s = Get-HostSettings
                    $roots = @()
                    if ($s.ContainsKey('inventory') -and $s.inventory -is [System.Collections.IDictionary] -and $s.inventory.ContainsKey('localRoots')) {
                        $roots = @($s.inventory.localRoots | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
                    }
                    $configExists = Test-Path -LiteralPath (Join-Path $WorkspaceRoot 'backend\config\settings.json')
                    $firstScanComplete = Test-Path -LiteralPath (Join-Path $WorkspaceRoot 'output\index\repos.index.json')
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            needsSetup        = -not ($configExists -and (@($roots).Count -gt 0))
                            settingsExists    = [bool]$configExists
                            hasLocalRoots     = (@($roots).Count -gt 0)
                            localRootCount    = @($roots).Count
                            firstScanComplete = [bool]$firstScanComplete
                            authRequired      = [bool]$script:AuthRequired
                        }
                    }
                }
                'GET /setup/prerequisites' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $s = Get-HostSettings
                    $prereqResolution = Get-GitHubTokenResolution -Settings $s
                    $tokenEnvVar = $prereqResolution.EnvVarName
                    $tokenPresent = ($prereqResolution.Source -ne 'none')
                    $outputWritable = $false
                    try {
                        $probeDir = Join-Path $WorkspaceRoot 'output'
                        $null = New-Item -ItemType Directory -Path $probeDir -Force -ErrorAction Stop
                        $probe = Join-Path $probeDir '.setup-probe'
                        Set-Content -LiteralPath $probe -Value 'ok' -Encoding UTF8
                        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
                        $outputWritable = $true
                    } catch { $outputWritable = $false }
                    $checks = @(
                        @{ id = 'powershell';  label = 'PowerShell 5.1+';                 required = $true;  ok = ($PSVersionTable.PSVersion.Major -ge 5); detail = $PSVersionTable.PSVersion.ToString() },
                        @{ id = 'git';         label = 'Git available';                   required = $true;  ok = [bool](Get-Command git -ErrorAction SilentlyContinue); detail = '' },
                        @{ id = 'outputWritable'; label = 'output/ directory writable';    required = $true;  ok = $outputWritable; detail = '' },
                        @{ id = 'gh';          label = 'GitHub CLI (optional)';           required = $false; ok = [bool](Get-Command gh -ErrorAction SilentlyContinue); detail = '' },
                        @{ id = 'githubToken'; label = 'GitHub token/CLI configured';     required = $false; ok = [bool]$tokenPresent; detail = $(if ($tokenPresent) { "env var '$tokenEnvVar' (source: $($prereqResolution.Source))" } else { "env var '$tokenEnvVar' is not set" }) }
                    )
                    $requiredOk = (@($checks | Where-Object { $_.required -and -not $_.ok }).Count -eq 0)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{ prerequisitesMet = [bool]$requiredOk; checks = $checks }
                    }
                }
                'POST /setup/config' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $body = Parse-JsonBody -Body $req.Body
                    $newRoots = @()
                    if ($null -ne $body -and $body.ContainsKey('localRoots') -and $body.localRoots) {
                        $newRoots = @($body.localRoots | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    }
                    if (@($newRoots).Count -eq 0) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ success = $false; error = 'setup requires at least one non-empty localRoots entry'; category = 'validation' }
                    }
                    else {
                        $missingRoots = @($newRoots | Where-Object { -not (Test-Path -LiteralPath $_) })
                        if (@($missingRoots).Count -gt 0) {
                            Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ success = $false; error = ("localRoots not found on disk: {0}" -f ($missingRoots -join ', ')); category = 'validation' }
                        }
                        else {
                            $cfgPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
                            $cfg = if (Test-Path -LiteralPath $cfgPath) { ConvertFrom-JsonCompat -Json (Get-Content -LiteralPath $cfgPath -Raw) } else { @{} }
                            if (-not $cfg.ContainsKey('inventory') -or -not ($cfg.inventory -is [System.Collections.IDictionary])) { $cfg.inventory = @{} }
                            $cfg.inventory.localRoots = $newRoots
                            if ($body.ContainsKey('maxDepth') -and $body.maxDepth) { $cfg.inventory.maxDepth = [int]$body.maxDepth }
                            elseif (-not $cfg.inventory.ContainsKey('maxDepth')) { $cfg.inventory.maxDepth = 3 }
                            if (-not $cfg.inventory.ContainsKey('includeNonGitFolders')) { $cfg.inventory.includeNonGitFolders = $false }
                            if ($body.ContainsKey('gitHubOwner')) {
                                if (-not $cfg.ContainsKey('reconcile') -or -not ($cfg.reconcile -is [System.Collections.IDictionary])) { $cfg.reconcile = @{ ownerType = 'Auto' } }
                                $cfg.reconcile.gitHubOwner = [string]$body.gitHubOwner
                            }
                            $generatedApiKey = $null
                            if ($body.ContainsKey('requireApiKey') -and [bool]$body.requireApiKey) {
                                if (-not $cfg.ContainsKey('auth') -or -not ($cfg.auth -is [System.Collections.IDictionary])) { $cfg.auth = @{} }
                                $cfg.auth.requireApiKey = $true
                                if (-not ($cfg.auth.ContainsKey('apiKey') -and $cfg.auth.apiKey)) {
                                    $generatedApiKey = New-ApiKey
                                    $cfg.auth.apiKey = $generatedApiKey
                                }
                            }
                            if (-not $cfg.ContainsKey('schemaVersion')) { $cfg.schemaVersion = 'v1' }
                            ($cfg | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $cfgPath -Encoding UTF8
                            Write-HostLog ("setup.config wrote settings.json with {0} local root(s); requireApiKey={1}" -f @($newRoots).Count, ($body.ContainsKey('requireApiKey') -and [bool]$body.requireApiKey))
                            Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                success = $true
                                data = @{
                                    needsSetup      = $false
                                    settingsPath    = $cfgPath
                                    localRootCount  = @($newRoots).Count
                                    generatedApiKey = $generatedApiKey
                                    restartRequired = ($null -ne $generatedApiKey)
                                }
                            }
                        }
                    }
                }
                'GET /api/status' {
                    $q = Parse-QueryString -Query $req.Query
                    $settings = Get-HostSettings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultMaxDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 2 }
                    $defaultIncludeNonGit = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('includeNonGitFolders')) { [bool]$settings.inventory.includeNonGitFolders } else { $false }
                    $configuredGitHubUser = if ($settings.ContainsKey('reconcile') -and $settings.reconcile.ContainsKey('gitHubOwner') -and $settings.reconcile.gitHubOwner) { [string]$settings.reconcile.gitHubOwner } else { '' }

                    $localRoots = if ($q.ContainsKey('localRoots') -and $q.localRoots) { @($q.localRoots -split ';|,') } else { $defaultRoots }
                    $maxDepth = if ($q.ContainsKey('maxDepth') -and $q.maxDepth) { [int]$q.maxDepth } else { $defaultMaxDepth }
                    $includeNonGit = if ($q.ContainsKey('includeNonGitFolders')) { Parse-Bool -Value $q.includeNonGitFolders -Default $defaultIncludeNonGit } else { $defaultIncludeNonGit }
                    $refresh = if ($q.ContainsKey('refresh')) { Parse-Bool -Value $q.refresh -Default $false } else { $false }
                    # stale=true: return disk cache immediately regardless of TTL (stale-while-revalidate)
                    $stale = if ($q.ContainsKey('stale')) { Parse-Bool -Value $q.stale -Default $false } else { $false }
                    $ttlSeconds = Get-StatusCacheTtlSeconds -Settings $settings
                    $cacheKey = Get-StatusCacheKey -LocalRoots $localRoots -MaxDepth $maxDepth -IncludeNonGitFolders $includeNonGit

                    # A fresh hit answers immediately and nothing else happens.
                    $result = $null
                    $cacheHit = $null
                    if (-not $refresh) {
                        if ($stale -or ($ttlSeconds -gt 0)) {
                            $cacheHit = Get-StatusFromCache -Key $cacheKey -TtlSeconds $ttlSeconds -IgnoreTtl:$stale
                            if ($cacheHit.hit) {
                                $result = Add-StatusCacheMeta -Result $cacheHit.response -CacheMeta (Get-StatusCacheMeta -Hit $true -Source $cacheHit.source -TtlSeconds $ttlSeconds -AgeSeconds $cacheHit.ageSeconds -BypassRequested:$false -CachedAt $cacheHit.cachedAt)
                            }
                        }
                    }

                    if ($null -eq $result) {
                        # THE fix for the freeze. This used to run the scan
                        # inline. With a 120s TTL and a 196.7s sweep, that meant
                        # the single request thread was busy scanning more often
                        # than not, and every other route - /health/live
                        # included - queued behind it. The refresh interval was
                        # shorter than the refresh, so the portal could never
                        # settle. Measured 2026-08-11.
                        #
                        # The request no longer waits. It kicks an out-of-process
                        # refresh and answers with the best data on hand, saying
                        # plainly that it is stale and that a refresh is running.
                        $refreshStarted = Start-BackgroundStatusRefresh -LocalRoots $localRoots -MaxDepth $maxDepth -IncludeNonGitFolders:$includeNonGit
                        $refreshState = Get-StatusRefreshState

                        # Expired cache still beats no answer: an operator would
                        # rather see a two-minute-old portfolio labelled stale
                        # than a spinner for three minutes.
                        $expired = Get-StatusFromCache -Key $cacheKey -TtlSeconds $ttlSeconds -IgnoreTtl:$true
                        if ($expired.hit) {
                            $result = Add-StatusCacheMeta -Result $expired.response -CacheMeta (Get-StatusCacheMeta -Hit $true -Source 'stale-cache' -TtlSeconds $ttlSeconds -AgeSeconds $expired.ageSeconds -BypassRequested:$refresh -CachedAt $expired.cachedAt)
                        }
                        else {
                            # Cold start: nothing has ever been scanned. Answer
                            # 200 with an empty, explicitly-refreshing payload
                            # rather than 500 - there is no error here, only an
                            # absence the operator should see named.
                            $result = [pscustomobject]@{
                                success = $true
                                data    = [pscustomobject]@{ repos = @() }
                            }
                            $result = Add-StatusCacheMeta -Result $result -CacheMeta (Get-StatusCacheMeta -Hit $false -Source 'awaiting-first-scan' -TtlSeconds $ttlSeconds -AgeSeconds 0 -BypassRequested:$refresh -CachedAt $null)
                        }

                        if ($null -eq $result.meta) {
                            $result | Add-Member -NotePropertyName meta -NotePropertyValue @{} -Force
                        }
                        $result.meta.refreshing = [bool]($refreshStarted -or $refreshState.running)
                        $result.meta.refreshStartedAt = if ($null -ne $refreshState.startedAt) { ([datetime]$refreshState.startedAt).ToUniversalTime().ToString('o') } else { $null }

                        # meta.statusCache.source, not meta.cacheSource: the
                        # latter does not exist, and Set-StrictMode -Version
                        # Latest turns reading a missing key into a terminating
                        # error rather than $null, so the typo returned 500.
                        Write-HostLog ("[TRACE] status.cache miss correlationId={0} served={1} refreshing={2}" -f $correlationId, $result.meta.statusCache.source, $result.meta.refreshing)
                    }

                    if ($null -eq $result.meta) {
                        $result | Add-Member -NotePropertyName meta -NotePropertyValue @{} -Force
                    }
                    $result.meta.workspacePath = if (@($localRoots).Count -gt 0) { [string]$localRoots[0] } else { '' }
                    $result.meta.configuredGithubUser = $configuredGitHubUser
                    # Recomputed here rather than trusted from the adapter meta: a
                    # cache hit would otherwise replay the on-disk state from
                    # whenever the scan ran, and "does this folder exist right now"
                    # is exactly the question the operator needs answered.
                    $result.meta.missingRoots = @(@($localRoots) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Where-Object { -not (Test-Path -LiteralPath ([string]$_)) } | ForEach-Object { [string]$_ })

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode $(if ($result.success) { 200 } else { 500 }) -CorrelationId $correlationId -Payload $result
                }
                'POST /api/reconcile' {
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultOwnerType = if ($settings.ContainsKey('reconcile') -and $settings.reconcile.ContainsKey('ownerType') -and $settings.reconcile.ownerType) { [string]$settings.reconcile.ownerType } else { 'Auto' }
                    $defaultGitHubOwner = if ($settings.ContainsKey('reconcile') -and $settings.reconcile.ContainsKey('gitHubOwner') -and $settings.reconcile.gitHubOwner) { [string]$settings.reconcile.gitHubOwner } else { '' }
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $defaultIncludeNonGit = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('includeNonGitFolders')) { [bool]$settings.inventory.includeNonGitFolders } else { $true }

                    $localRoots = if ($body.ContainsKey('localRoots') -and $body.localRoots) { @($body.localRoots) } else { $defaultRoots }
                    $ownerType = if ($body.ContainsKey('ownerType') -and $body.ownerType) { [string]$body.ownerType } else { $defaultOwnerType }
                    $maxDepth = if ($body.ContainsKey('maxDepth') -and $body.maxDepth) { [int]$body.maxDepth } else { $defaultDepth }
                    $includeNonGit = if ($body.ContainsKey('includeNonGitFolders')) { [bool]$body.includeNonGitFolders } else { $defaultIncludeNonGit }
                    $outDir = if ($body.ContainsKey('outDir')) { [string]$body.outDir } else { '' }
                    $githubOwner = if ($body.ContainsKey('githubOwner')) { [string]$body.githubOwner } else { $defaultGitHubOwner }

                    $result = Invoke-ReconcileAdapter -LocalRoots $localRoots -GitHubOwner $githubOwner -OwnerType $ownerType -OutDir $outDir -MaxDepth $maxDepth -IncludeNonGitFolders:$includeNonGit -LogPath $LogPath
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode $(if ($result.success) { 200 } else { 500 }) -CorrelationId $correlationId -Payload $result
                }
                'POST /api/docreview/run' {
                    $body = Parse-JsonBody -Body $req.Body
                    $rootPath = if ($body.ContainsKey('rootPath') -and $body.rootPath) { [string]$body.rootPath } else { $WorkspaceRoot }
                    $maxDepth = if ($body.ContainsKey('maxDepth') -and $body.maxDepth) { [int]$body.maxDepth } else { 2 }
                    $outDir = if ($body.ContainsKey('outDir')) { [string]$body.outDir } else { '' }
                    $targetRepo = if ($body.ContainsKey('targetRepo')) { [string]$body.targetRepo } else { '' }
                    $generateQueue = if ($body.ContainsKey('generateQueue')) { [bool]$body.generateQueue } else { $true }
                    $generateBatchPlan = if ($body.ContainsKey('generateBatchPlan')) { [bool]$body.generateBatchPlan } else { $false }

                    $result = Invoke-DocReviewAdapter -RootPath $rootPath -MaxDepth $maxDepth -OutDir $outDir -TargetRepo $targetRepo -GenerateQueue:$generateQueue -GenerateBatchPlan:$generateBatchPlan -LogPath $LogPath
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode $(if ($result.success) { 200 } else { 500 }) -CorrelationId $correlationId -Payload $result
                }
                'GET /api/report/artifacts' {
                    $outputRoot = Join-Path $WorkspaceRoot 'backend\modules\output'
                    $files = @()
                    if (Test-Path -LiteralPath $outputRoot) {
                        $files = Get-ChildItem -Path $outputRoot -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 200 | ForEach-Object {
                            [pscustomobject]@{
                                name = $_.Name
                                path = $_.FullName
                                sizeBytes = $_.Length
                                lastWriteTime = $_.LastWriteTime.ToString('o')
                            }
                        }
                    }

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        artifacts = $files
                        outputRoot = $outputRoot
                    }
                }
                'GET /api/settings' {
                    $configPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
                    $config = @{}
                    if (Test-Path -LiteralPath $configPath) {
                        $config = ConvertFrom-JsonCompat -Json (Get-Content -LiteralPath $configPath -Raw)
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $config
                    }
                }
                'POST /api/settings' {
                    $body = Parse-JsonBody -Body $req.Body
                    $configPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
                    $existing = @{}
                    if (Test-Path -LiteralPath $configPath) {
                        $existing = ConvertFrom-JsonCompat -Json (Get-Content -LiteralPath $configPath -Raw)
                    }

                    if (-not $existing.ContainsKey('inventory')) { $existing.inventory = @{} }
                    if (-not $existing.ContainsKey('retention')) { $existing.retention = @{} }
                    if (-not $existing.ContainsKey('docReview')) { $existing.docReview = @{} }

                    if ($body.ContainsKey('basePath') -and $body.basePath) {
                        # A workspace path that does not exist produces a scan that
                        # returns zero repos and no error, which reads as "the tool
                        # is broken" rather than "that folder is not there".
                        # 'POST /api/setup' has always rejected a missing root; this
                        # route silently accepted one, so the two disagreed and the
                        # Settings dialog was the unguarded way in.
                        $requestedBasePath = ([string]$body.basePath).Trim()
                        if (-not (Test-Path -LiteralPath $requestedBasePath)) {
                            Add-MetricCounter -Name 'api_requests_total'
                            Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                                success  = $false
                                error    = ("Workspace path not found on disk: {0}. Nothing was saved — correct the path and try again." -f $requestedBasePath)
                                category = 'validation'
                                field    = 'basePath'
                            }
                            break
                        }
                        $existing.inventory.localRoots = @($requestedBasePath)
                    }
                    if ($body.ContainsKey('scanDepth')) {
                        $existing.inventory.maxDepth = [int]$body.scanDepth
                    }
                    if ($body.ContainsKey('daysInactive')) {
                        $existing.retention.days = [int]$body.daysInactive
                    }
                    if ($body.ContainsKey('githubUser')) {
                        if (-not $existing.ContainsKey('reconcile')) { $existing.reconcile = @{} }
                        $existing.reconcile.gitHubOwner = [string]$body.githubUser
                    }
                    # Storing a literal token is no longer supported: settings.json
                    # is git-tracked, so a secret written here leaks on commit.
                    if ($body.ContainsKey('githubToken') -and -not [string]::IsNullOrWhiteSpace([string]$body.githubToken)) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                            success  = $false
                            error    = "Storing a GitHub token in settings is not supported. Send 'gitHubTokenEnvVar' with the NAME of an environment variable holding the token instead."
                            category = 'validation'
                        }
                        break
                    }
                    if ($body.ContainsKey('gitHubTokenEnvVar') -and -not [string]::IsNullOrWhiteSpace([string]$body.gitHubTokenEnvVar)) {
                        $requestedEnvVar = ([string]$body.gitHubTokenEnvVar).Trim()
                        if ($requestedEnvVar -notmatch $script:EnvVarNamePattern) {
                            Add-MetricCounter -Name 'api_requests_total'
                            Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                                success  = $false
                                error    = ("'{0}' is not a valid environment variable name. Use letters, digits, and underscores, starting with a letter or underscore." -f $requestedEnvVar)
                                category = 'validation'
                            }
                            break
                        }
                        # Reject a value that looks like a token rather than a name —
                        # the most likely paste mistake, and the one that would put a
                        # secret in the tracked config.
                        if ($requestedEnvVar -match '^(gh[pousr]_|github_pat_)') {
                            Add-MetricCounter -Name 'api_requests_total'
                            Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                                success  = $false
                                error    = 'That looks like a token, not an environment variable name. Set the token in an environment variable and send that variable name here.'
                                category = 'validation'
                            }
                            break
                        }
                        if (-not $existing.ContainsKey('secrets')) { $existing.secrets = @{} }
                        $existing.secrets.gitHubTokenEnvVar = $requestedEnvVar
                    }
                    # Never let a previously stored token survive a settings write.
                    if ($existing.ContainsKey('secrets') -and
                        $existing.secrets -is [System.Collections.IDictionary] -and
                        $existing.secrets.ContainsKey('githubToken')) {
                        $existing.secrets.Remove('githubToken')
                    }

                    ($existing | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $configPath -Encoding UTF8
                    Clear-StatusCache

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $existing
                    }
                }
                'POST /api/init' {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 202 -CorrelationId $correlationId -Payload @{
                        success = $true
                        accepted = $true
                        message = 'Clone workflow placeholder accepted. Use existing local repo discovery and reconciliation workflows.'
                    }
                }
                'POST /api/update' {
                    $body = Parse-JsonBody -Body $req.Body
                    $repoNames = if ($body.ContainsKey('repoNames') -and $body.repoNames) { @($body.repoNames) } else { @() }
                    $repoPaths = if ($body.ContainsKey('repoPaths') -and $body.repoPaths) { @($body.repoPaths) } else { @() }
                    $result = Invoke-GitOperation -OperationType 'pull' -RepoNames $repoNames -RepoPaths $repoPaths
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $result
                    }
                }
                'POST /api/sync' {
                    $body = Parse-JsonBody -Body $req.Body
                    $repoNames = if ($body.ContainsKey('repoNames') -and $body.repoNames) { @($body.repoNames) } else { @() }
                    $repoPaths = if ($body.ContainsKey('repoPaths') -and $body.repoPaths) { @($body.repoPaths) } else { @() }
                    $result = Invoke-GitOperation -OperationType 'sync' -RepoNames $repoNames -RepoPaths $repoPaths
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $result
                    }
                }
                'POST /api/git/sync-default-branch' {
                    # Release 3.4 milestone 1, step 10 — the operator-facing door to
                    # Sync-RepoDefaultBranch. The operation and its refusal matrix
                    # shipped in PR #134 and were reachable only from the task
                    # runner: this host did not even dot-source the module, so no
                    # control an operator could click could reach it.
                    #
                    # This route adds NO policy. Every refusal below is the module's
                    # own decision, forwarded verbatim — only `behind` fast-forwards,
                    # `ahead` refuses as `default-branch-ahead`, `diverged` refuses
                    # because a fast-forward is impossible, and dirty tree, detached
                    # HEAD, unverifiable reading and an unapproved transition each
                    # refuse by name. Adding a second opinion here is exactly how the
                    # two would drift apart.
                    Write-HostLog ("[TRACE] git.sync-default-branch correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        Add-MetricCounter -Name 'api_requests_total'
                        $syncRepoName = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default '')
                        $syncRepoPath = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoPath' -Default '')
                        $syncBranch   = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'branch' -Default '')
                        $syncRemote   = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'remote' -Default 'origin')
                        # Approval is an INPUT on the operation, so it stays an input
                        # here. The route never approves on the caller's behalf, and
                        # an absent flag refuses as `approval-required` rather than
                        # defaulting to yes — the same shape as acknowledgeNoRunner
                        # and acknowledgeStaleBase.
                        $syncApproved = ($body.ContainsKey('approved') -and [bool]$body.approved)

                        if ([string]::IsNullOrWhiteSpace($syncRepoPath) -and [string]::IsNullOrWhiteSpace($syncRepoName)) {
                            throw 'repoName or repoPath is required for /api/git/sync-default-branch'
                        }

                        # An explicit repoPath wins; the roadmap cache is the
                        # fallback, resolved exactly as the submit-PR path does.
                        # Cache entries rehydrate as hashtables from disk and arrive
                        # as PSCustomObjects from a fresh scan; reading only the
                        # object form yields an empty path on a warm cache.
                        if ([string]::IsNullOrWhiteSpace($syncRepoPath)) {
                            $syncSettings = Get-HostSettings
                            $syncCache = Get-RoadmapFromCache -TtlSeconds (Get-RoadmapCacheTtlSeconds -Settings $syncSettings)
                            if ($syncCache.hit -and $syncCache.entries) {
                                $syncEntry = @($syncCache.entries) | Where-Object { [string]$_.repoName -eq $syncRepoName } | Select-Object -First 1
                                if ($null -ne $syncEntry) {
                                    $syncRepoPath = if ($syncEntry -is [System.Collections.IDictionary]) {
                                        [string](Get-ValueOrDefault $syncEntry['repoPath'] '')
                                    } else {
                                        [string](Get-ValueOrDefault $syncEntry.repoPath '')
                                    }
                                }
                            }
                        }

                        if ([string]::IsNullOrWhiteSpace($syncRepoPath)) {
                            Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                                success  = $false
                                error    = ("No local checkout is known for '{0}'. Run a scan first, or pass repoPath." -f $syncRepoName)
                                category = 'repo-not-found'
                            }
                        }
                        else {
                            $syncResult = Sync-RepoDefaultBranch -RepoPath $syncRepoPath -BranchName $syncBranch `
                                -Remote $syncRemote -Approved $syncApproved
                            $syncPayload = @{
                                synced   = [bool]$syncResult.synced
                                refused  = [bool]$syncResult.refused
                                category = [string]$syncResult.category
                                reason   = [string]$syncResult.reason
                                remedy   = [string]$syncResult.remedy
                                state    = [string]$syncResult.state
                                branch   = [string]$syncResult.branch
                                remote   = [string]$syncResult.remote
                                fromSha  = $syncResult.fromSha
                                toSha    = $syncResult.toSha
                                repoPath = $syncRepoPath
                            }
                            if ($syncResult.refused) {
                                # 409, same as the dispatch and stale-base refusals:
                                # the request was well-formed and the state says no.
                                Write-HostLog ("[TRACE] git.sync-default-branch correlationId={0} repo={1} REFUSED category={2}" -f $correlationId, $syncRepoName, $syncResult.category)
                                Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                                    success  = $false
                                    error    = [string]$syncResult.reason
                                    category = [string]$syncResult.category
                                    data     = $syncPayload
                                }
                            }
                            else {
                                Write-HostLog ("[TRACE] git.sync-default-branch correlationId={0} repo={1} state={2} from={3} to={4}" -f $correlationId, $syncRepoName, $syncResult.state, $syncResult.fromSha, $syncResult.toSha)
                                Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                    success = $true
                                    data    = $syncPayload
                                }
                            }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'git.sync-default-branch'
                    }
                }
                'POST /api/git/cleanup-branch' {
                    # Release 3.4 milestone 5 — the operator-facing door to
                    # Remove-MergedRepoBranch, same contract as the sync route
                    # above: the route adds NO policy, refusals are the module's
                    # own category/reason/remedy forwarded verbatim as 409, and
                    # approval is an input that an absent flag refuses on.
                    Write-HostLog ("[TRACE] git.cleanup-branch correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        Add-MetricCounter -Name 'api_requests_total'
                        $cbRepoName = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default '')
                        $cbRepoPath = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoPath' -Default '')
                        $cbBranch   = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'branch' -Default '')
                        $cbMergedHeadSha = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'mergedHeadSha' -Default '')
                        $cbDeleteRemote = ($body.ContainsKey('deleteRemote') -and (Parse-Bool -Value $body.deleteRemote -Default $false))
                        $cbApproved = ($body.ContainsKey('approved') -and [bool]$body.approved)

                        if ([string]::IsNullOrWhiteSpace($cbRepoPath) -and [string]::IsNullOrWhiteSpace($cbRepoName)) {
                            throw 'repoName or repoPath is required for /api/git/cleanup-branch'
                        }
                        if ([string]::IsNullOrWhiteSpace($cbBranch)) {
                            throw 'branch is required for /api/git/cleanup-branch'
                        }

                        if ([string]::IsNullOrWhiteSpace($cbRepoPath)) {
                            $cbSettings = Get-HostSettings
                            $cbCache = Get-RoadmapFromCache -TtlSeconds (Get-RoadmapCacheTtlSeconds -Settings $cbSettings)
                            if ($cbCache.hit -and $cbCache.entries) {
                                $cbEntry = @($cbCache.entries) | Where-Object { [string]$_.repoName -eq $cbRepoName } | Select-Object -First 1
                                if ($null -ne $cbEntry) {
                                    $cbRepoPath = if ($cbEntry -is [System.Collections.IDictionary]) {
                                        [string](Get-ValueOrDefault $cbEntry['repoPath'] '')
                                    } else {
                                        [string](Get-ValueOrDefault $cbEntry.repoPath '')
                                    }
                                }
                            }
                        }

                        if ([string]::IsNullOrWhiteSpace($cbRepoPath)) {
                            Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                                success  = $false
                                error    = ("No local checkout is known for '{0}'. Run a scan first, or pass repoPath." -f $cbRepoName)
                                category = 'repo-not-found'
                            }
                        }
                        else {
                            $cbToken = Get-ConfiguredGitHubToken -Settings (Get-HostSettings)
                            $cbResult = Remove-MergedRepoBranch -RepoPath $cbRepoPath -Branch $cbBranch `
                                -MergedHeadSha $cbMergedHeadSha -DeleteRemote $cbDeleteRemote `
                                -Token $cbToken -Approved $cbApproved
                            $cbPayload = @{
                                deleted       = [bool]$cbResult.deleted
                                refused       = [bool]$cbResult.refused
                                category      = [string]$cbResult.category
                                reason        = [string]$cbResult.reason
                                remedy        = [string]$cbResult.remedy
                                branch        = [string]$cbResult.branch
                                tipSha        = $cbResult.tipSha
                                remoteDeleted = [bool]$cbResult.remoteDeleted
                                remoteResult  = [string]$cbResult.remoteResult
                                repoPath      = $cbRepoPath
                            }
                            if ($cbResult.refused) {
                                Write-HostLog ("[TRACE] git.cleanup-branch correlationId={0} repo={1} branch={2} REFUSED category={3}" -f $correlationId, $cbRepoName, $cbBranch, $cbResult.category)
                                Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                                    success  = $false
                                    error    = [string]$cbResult.reason
                                    category = [string]$cbResult.category
                                    data     = $cbPayload
                                }
                            }
                            else {
                                Write-HostLog ("[TRACE] git.cleanup-branch correlationId={0} repo={1} branch={2} deleted remote={3}" -f $correlationId, $cbRepoName, $cbBranch, $cbResult.remoteDeleted)
                                Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                    success = $true
                                    data    = $cbPayload
                                }
                            }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'git.cleanup-branch'
                    }
                }
                'POST /api/export' {
                    $body = Parse-JsonBody -Body $req.Body
                    $sourceLabel = if ($body.ContainsKey('sourceLabel') -and $body.sourceLabel) { [string]$body.sourceLabel } else { 'Repository dashboard export' }
                    $portfolioEntries = if ($body.ContainsKey('portfolioEntries') -and $body.portfolioEntries) { @($body.portfolioEntries) } else { @() }
                    if (@($portfolioEntries).Count -gt 0) {
                        $result = Export-PortfolioCollectionStatusReport -Entries $portfolioEntries -SourceLabel $sourceLabel -ReportsRoot (Get-ReportsRootPath)
                    } else {
                        $repos = if ($body.ContainsKey('repos') -and $body.repos) { @($body.repos) } else { @() }
                        $result = Export-RepoStatusReports -Repos $repos -SourceLabel $sourceLabel
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $result
                    }
                }
                'POST /api/archive' {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 202 -CorrelationId $correlationId -Payload @{
                        success = $true
                        accepted = $true
                        message = 'Archive workflow is currently a planned operation in this host.'
                    }
                }
                'POST /api/github/status' {
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $owner = if ($body.ContainsKey('githubUser') -and $body.githubUser) {
                        [string]$body.githubUser
                    }
                    elseif ($settings.ContainsKey('reconcile') -and $settings.reconcile.ContainsKey('gitHubOwner') -and $settings.reconcile.gitHubOwner) {
                        [string]$settings.reconcile.gitHubOwner
                    }
                    else {
                        ''
                    }
                    $limit = if ($body.ContainsKey('repoLimit') -and $body.repoLimit) { [int]$body.repoLimit } else { 50 }
                    $includePrivate = if ($body.ContainsKey('includePrivate')) { [bool]$body.includePrivate } else { $true }
                    $includeForks = if ($body.ContainsKey('includeForks')) { [bool]$body.includeForks } else { $false }
                    $includeArchived = if ($body.ContainsKey('includeArchived')) { [bool]$body.includeArchived } else { $true }
                    $fetchExtendedMetrics = if ($body.ContainsKey('fetchExtendedMetrics')) { [bool]$body.fetchExtendedMetrics } else { $true }
                    if ([string]::IsNullOrWhiteSpace($owner)) {
                        throw 'githubUser is required for /api/github/status'
                    }
                    # Tokens are never accepted over the wire. Reject rather than
                    # ignore, so an old client fails loudly instead of silently
                    # falling back to unauthenticated rate limits.
                    if ($body.ContainsKey('apiKey') -and -not [string]::IsNullOrWhiteSpace([string]$body.apiKey)) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                            success  = $false
                            error    = ("This host does not accept a GitHub token in the request body. Set the token in the environment variable named by settings.secrets.gitHubTokenEnvVar (currently '{0}') and restart the host." -f (Get-GitHubTokenEnvVarName -Settings $settings))
                            category = 'validation'
                        }
                        break
                    }
                    $token = Get-ConfiguredGitHubToken -Settings $settings

                    if (-not [string]::IsNullOrWhiteSpace($token)) {
                        $apiResult = Get-GitHubReposViaApi -Owner $owner -Token $token -RepoLimit $limit -IncludePrivate:$includePrivate -IncludeForks:$includeForks -IncludeArchived:$includeArchived -FetchCommitMetrics:$fetchExtendedMetrics
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload $apiResult
                        break
                    }

                    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
                        throw 'GitHub token not configured and GitHub CLI (gh) is not available.'
                    }

                    $openPrCounts = @{}
                    try {
                        $openPrCounts = Get-GitHubOpenPrCountsViaGh -Owner $owner
                    }
                    catch {
                        Write-HostLog ("[TRACE] github.openpr gh aggregation failed owner={0} error={1}" -f $owner, $_.Exception.Message)
                    }

                    # gh writes its auth failure to stderr and exits non-zero.
                    # Merging that into the JSON string and parsing blind used to
                    # surface a raw "Unexpected character ... T" parse error - the
                    # first letter of gh's "To get started with GitHub CLI" notice -
                    # which told the operator nothing. Check the exit code and the
                    # payload shape first and name the real cause: neither the
                    # configured env var nor the gh credential resolved.
                    $ghOutput = ((& gh repo list $owner --limit $limit --json name,nameWithOwner,url,isArchived,isPrivate,isFork,defaultBranchRef,updatedAt,pushedAt 2>&1) | Out-String).Trim()
                    $ghExit = $LASTEXITCODE
                    if ($ghExit -ne 0 -or -not ($ghOutput.StartsWith('[') -or $ghOutput.StartsWith('{'))) {
                        $ghDetail = @($ghOutput -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -First 1
                        throw ("GitHub is not authenticated for this host. {0} The 'gh' CLI fallback also failed{1}" -f
                            (Get-GitHubTokenMissHint -EnvVarName (Get-GitHubTokenEnvVarName -Settings $settings)),
                            $(if ($ghDetail) { ": $ghDetail" } else { " (exit code $ghExit)." }))
                    }
                    $reposRaw = $ghOutput | ConvertFrom-Json
                    $repos = @($reposRaw | ForEach-Object {
                        if ((-not $includeForks) -and [bool]$_.isFork) { return }
                        if ((-not $includeArchived) -and [bool]$_.isArchived) { return }

                        $repoOpenPrCount = 0
                        if ($openPrCounts.ContainsKey($_.name)) {
                            $repoOpenPrCount = [int]$openPrCounts[$_.name]
                        }

                        [pscustomobject]@{
                            name = $_.name
                            branch = if ($_.defaultBranchRef) { $_.defaultBranchRef.name } else { 'main' }
                            status = 'clean'
                            lastCommitDate = if ($_.pushedAt) { $_.pushedAt } else { $_.updatedAt }
                            lastCommitMessage = ''
                            lastCommitAuthor = $owner
                            commitsLastWeek = 0
                            commitsLastMonth = 0
                            uncommittedChanges = 0
                            isArchived = [bool]$_.isArchived
                            # GitHub-only listing: no local clone, so unknown —
                            # resolved through the same function as every other
                            # path rather than asserted as "not stale".
                            staleness = (Resolve-RepoStaleness -LocalCommitDate $null -RemotePushedAt (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'pushedAt' -Default $null))
                            isStale = [bool](Resolve-RepoStaleness -LocalCommitDate $null -RemotePushedAt (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'pushedAt' -Default $null)).isStale
                            localAhead = 0
                            remoteAhead = 0
                            openPrCount = $repoOpenPrCount
                            htmlUrl = $_.url
                            owner = $owner
                            visibility = if ([bool]$_.isPrivate) { 'private' } else { 'public' }
                        }
                    })

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        source = 'github'
                        username = $owner
                        totalRepos = @($repos).Count
                        fetchedRepos = @($repos).Count
                        repos = $repos
                        # The gh fallback has no response object to read headers
                        # from, so ask GitHub directly. GET /rate_limit does not
                        # itself consume quota. Best-effort: a failure here
                        # leaves the readout blank, exactly as before, and must
                        # never fail the repo listing that already succeeded.
                        rateLimit = $(
                            try {
                                $ghRateRaw = ((& gh api rate_limit 2>$null) | Out-String).Trim()
                                if ($LASTEXITCODE -eq 0) { ConvertFrom-GitHubRateLimitPayload -Payload $ghRateRaw } else { $null }
                            } catch { $null }
                        )
                    }
                }
                'GET /api/status/cache' {
                    $settings = Get-HostSettings
                    $ttlSeconds = Get-StatusCacheTtlSeconds -Settings $settings
                    $cacheFile = Get-StatusCacheFilePath
                    $memoryKeys = @($script:StatusCacheMemory.Keys)
                    $diskInfo = $null
                    if (Test-Path -LiteralPath $cacheFile) {
                        try {
                            $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
                            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                                $diskEntry = ConvertFrom-JsonCompat -Json $raw
                                if ($diskEntry -and $diskEntry.ContainsKey('createdAtUtc')) {
                                    $nowUtc = (Get-Date).ToUniversalTime()
                                    $createdAt = [datetime]$diskEntry.createdAtUtc
                                    $diskInfo = @{
                                        key = [string]$diskEntry.key
                                        createdAtUtc = $diskEntry.createdAtUtc
                                        ageSeconds = [math]::Round(($nowUtc - $createdAt).TotalSeconds, 1)
                                        expired = (($nowUtc - $createdAt).TotalSeconds -gt $ttlSeconds)
                                    }
                                }
                            }
                        } catch { }
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        ttlSeconds = $ttlSeconds
                        memoryEntries = $memoryKeys.Count
                        memoryKeys = $memoryKeys
                        disk = $diskInfo
                    }
                }
                'POST /api/status/cache/clear' {
                    Clear-StatusCache
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        message = 'Status cache cleared. Next GET /api/status will perform a fresh scan.'
                    }
                }
                'POST /api/roadmap-agent/preview' {
                    $body = Parse-JsonBody -Body $req.Body
                    $repository = if ($body.ContainsKey('repository') -and $body.repository) { [string]$body.repository } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repository)) {
                        throw 'repository is required for /api/roadmap-agent/preview'
                    }

                    $baseBranch = if ($body.ContainsKey('baseBranch') -and $body.baseBranch) { [string]$body.baseBranch } else { '' }
                    $customAgent = if ($body.ContainsKey('customAgent') -and $body.customAgent) { [string]$body.customAgent } else { '' }
                    $roadmapPath = if ($body.ContainsKey('roadmapPath') -and $body.roadmapPath) { [string]$body.roadmapPath } else { '' }

                    $scriptPath = Join-Path $WorkspaceRoot 'scripts\Start-RoadmapCopilotTask.ps1'
                    $scriptArgs = @('-Repository', $repository, '-PreviewOnly')
                    if (-not [string]::IsNullOrWhiteSpace($baseBranch)) { $scriptArgs += @('-BaseBranch', $baseBranch) }
                    if (-not [string]::IsNullOrWhiteSpace($customAgent)) { $scriptArgs += @('-CustomAgent', $customAgent) }
                    if (-not [string]::IsNullOrWhiteSpace($roadmapPath)) { $scriptArgs += @('-RoadmapPath', $roadmapPath) }

                    $runResult = Invoke-PowerShellScriptFile -ScriptPath $scriptPath -Arguments $scriptArgs
                    $previewData = Get-JsonObjectFromText -Text $runResult.Output

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $previewData
                    }
                }
                'POST /api/roadmap-agent/start' {
                    $body = Parse-JsonBody -Body $req.Body
                    $repository = if ($body.ContainsKey('repository') -and $body.repository) { [string]$body.repository } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repository)) {
                        throw 'repository is required for /api/roadmap-agent/start'
                    }

                    # Release 3.1 — the third road to the same queue file. This route
                    # reaches it indirectly, through Start-RoadmapCopilotTask.ps1 ->
                    # Add-RoadmapTaskToQueue.ps1, which is why gating the two direct
                    # writers left it open: it never names the queue itself. The
                    # precondition is identical, so the refusal is too.
                    $agentAcknowledgeNoRunner = $false
                    if ($body.ContainsKey('acknowledgeNoRunner')) { $agentAcknowledgeNoRunner = [bool]$body.acknowledgeNoRunner }
                    $agentPresence = Get-RunnerPresence -WorkspaceRoot $WorkspaceRoot
                    if (-not $agentPresence.present -and -not $agentAcknowledgeNoRunner) {
                        $agentBacklog = Get-QueuedTaskBacklog -WorkspaceRoot $WorkspaceRoot
                        Write-HostLog ("WARN roadmap-agent.start correlationId={0} refused - runner {1}, stranded={2} (nothing written)" -f `
                                $correlationId, $agentPresence.state, [int]$agentBacklog.queuedTotal)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                            success  = $false
                            error    = ("No operator runner can claim this task, so queueing it would strand it. {0} Start one with: pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1" -f [string]$agentPresence.message)
                            category = 'runner-absent'
                            data     = @{
                                runnerCommand = 'pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1'
                                runner        = $agentPresence
                                strandedCount = [int]$agentBacklog.queuedTotal
                                overrideField = 'acknowledgeNoRunner'
                                queuedNothing = $true
                            }
                        }
                        break
                    }

                    $baseBranch = if ($body.ContainsKey('baseBranch') -and $body.baseBranch) { [string]$body.baseBranch } else { '' }
                    $customAgent = if ($body.ContainsKey('customAgent') -and $body.customAgent) { [string]$body.customAgent } else { '' }
                    $roadmapPath = if ($body.ContainsKey('roadmapPath') -and $body.roadmapPath) { [string]$body.roadmapPath } else { '' }
                    $follow = if ($body.ContainsKey('follow')) { [bool]$body.follow } else { $false }

                    $scriptPath = Join-Path $WorkspaceRoot 'scripts\Start-RoadmapCopilotTask.ps1'
                    $scriptArgs = @('-Repository', $repository)
                    if (-not [string]::IsNullOrWhiteSpace($baseBranch)) { $scriptArgs += @('-BaseBranch', $baseBranch) }
                    if (-not [string]::IsNullOrWhiteSpace($customAgent)) { $scriptArgs += @('-CustomAgent', $customAgent) }
                    if (-not [string]::IsNullOrWhiteSpace($roadmapPath)) { $scriptArgs += @('-RoadmapPath', $roadmapPath) }
                    if ($follow) { $scriptArgs += '-Follow' }

                    $runResult = Invoke-PowerShellScriptFile -ScriptPath $scriptPath -Arguments $scriptArgs
                    $historyItems = Get-RoadmapTaskHistory -Limit 1
                    $latest = if ($historyItems.Count -gt 0) { $historyItems[0] } else { $null }

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            message = 'Task queued for the local Claude Code runner. Run scripts/Invoke-RoadmapTaskRunner.ps1 (as yourself) to execute it on the local repo.'
                            output = $runResult.Output
                            latestHistory = $latest
                        }
                    }
                }
                'GET /api/roadmap-agent/history' {
                    $q = Parse-QueryString -Query $req.Query
                    $limit = if ($q.ContainsKey('limit') -and $q.limit) { [int]$q.limit } else { 25 }
                    $items = Get-RoadmapTaskHistory -Limit $limit

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            items = $items
                            count = @($items).Count
                        }
                    }
                }
                'POST /api/roadmap-agent/approve-push' {
                    # Release 2.8: operator approves an 'awaiting-review' runner branch
                    # and the portal pushes it to origin. Only awaiting-review -> pushed
                    # is a legal transition (409 otherwise); push success is proven by
                    # the git exit code, never assumed.
                    $body = Parse-JsonBody -Body $req.Body
                    $approveRunId = if ($body.ContainsKey('runId') -and $body.runId) { [string]$body.runId } else { '' }
                    Add-MetricCounter -Name 'api_requests_total'
                    if ([string]::IsNullOrWhiteSpace($approveRunId) -or $approveRunId -notmatch '^[A-Za-z0-9._-]+$') {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = 'A valid runId is required for /api/roadmap-agent/approve-push'
                            category = 'validation'
                        }
                    }
                    else {
                        $approveSummaryPath = Join-Path (Join-Path $WorkspaceRoot 'output\roadmap-task-history\runs') ("{0}.summary.json" -f $approveRunId)
                        if (-not (Test-Path -LiteralPath $approveSummaryPath -PathType Leaf)) {
                            Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                                success = $false
                                error = ("No run summary found for runId '{0}'." -f $approveRunId)
                            }
                        }
                        else {
                            $approveSummary = Get-Content -LiteralPath $approveSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
                            $approveStatus = if ($approveSummary.PSObject.Properties.Name -contains 'status') { [string]$approveSummary.status } else { '' }
                            $approveBranch = if ($approveSummary.PSObject.Properties.Name -contains 'branch') { [string]$approveSummary.branch } else { '' }
                            $approveRepoPath = if ($approveSummary.PSObject.Properties.Name -contains 'localRepoPath') { [string]$approveSummary.localRepoPath } else { '' }
                            if ($approveStatus -ne 'awaiting-review') {
                                Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                                    success = $false
                                    error = ("Cannot approve & push run '{0}' in status '{1}' — only 'awaiting-review' runs can be pushed." -f $approveRunId, $approveStatus)
                                }
                            }
                            elseif ([string]::IsNullOrWhiteSpace($approveBranch) -or [string]::IsNullOrWhiteSpace($approveRepoPath) -or -not (Test-Path -LiteralPath (Join-Path $approveRepoPath '.git'))) {
                                Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                                    success = $false
                                    error = ("Run '{0}' summary is missing a usable branch/localRepoPath (branch='{1}', localRepoPath='{2}')." -f $approveRunId, $approveBranch, $approveRepoPath)
                                    category = 'validation'
                                }
                            }
                            else {
                                # The service account has no git credential manager: push with
                                # the configured GitHub token when present. A tokenless push
                                # still works for SSH remotes or an operator-run host.
                                $ghToken = Get-ConfiguredGitHubToken -Settings (Get-HostSettings)
                                $gitPushArgs = @('-C', $approveRepoPath)
                                if (-not [string]::IsNullOrWhiteSpace($ghToken)) {
                                    $basicToken = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("x-access-token:{0}" -f $ghToken)))
                                    $gitPushArgs += @('-c', ("http.extraheader=AUTHORIZATION: basic {0}" -f $basicToken))
                                }
                                $pushOutput = (& git @gitPushArgs push -u origin $approveBranch 2>&1) | Out-String
                                if ($LASTEXITCODE -ne 0) {
                                    throw ("git push failed for branch '{0}' in '{1}': {2}" -f $approveBranch, $approveRepoPath, $pushOutput.Trim())
                                }

                                # Release 3.4 milestone 3 — a pushed branch no longer ends at
                                # "open the PR from GitHub when ready". The PR opens here,
                                # through the same refusal matrix the roadmap-repair submit
                                # uses. A PR refusal after a proven push is a PARTIAL success:
                                # the push is reported as done and the refusal by name, never
                                # thrown away — an operator without a token still gets their
                                # branch pushed, plus the reason no PR appeared.
                                $approveOpenPr = if ($body.ContainsKey('openPr')) { Parse-Bool -Value $body.openPr -Default $true } else { $true }
                                $approveTask = if ($approveSummary.PSObject.Properties.Name -contains 'selectedTask') { [string]$approveSummary.selectedTask } else { '' }
                                $approvePr = $null
                                if ($approveOpenPr -and (Get-Command -Name 'Open-RepoBranchPullRequest' -ErrorAction SilentlyContinue)) {
                                    $approvePrTitle = if (-not [string]::IsNullOrWhiteSpace($approveTask)) { $approveTask } else { ("Roadmap task {0}" -f $approveRunId) }
                                    $approvePr = Open-RepoBranchPullRequest -RepoName (Split-Path -Leaf $approveRepoPath) `
                                        -RepoPath $approveRepoPath -Branch $approveBranch -Token $ghToken `
                                        -Title $approvePrTitle `
                                        -Body ("Automated roadmap task run ``{0}``.`n`n{1}`n`nGenerated by GitHubRepoManagement (Release 3.4). Review the diff before merging." -f $approveRunId, $approveTask)
                                }

                                $updatedSummary = @{}
                                foreach ($prop in $approveSummary.PSObject.Properties) { $updatedSummary[$prop.Name] = $prop.Value }
                                $updatedSummary['status'] = 'pushed'
                                $updatedSummary['pushedAt'] = (Get-Date).ToString('o')
                                if ($null -ne $approvePr -and -not $approvePr.refused -and $approvePr.prUrl) {
                                    $updatedSummary['prUrl'] = [string]$approvePr.prUrl
                                    $updatedSummary['prNumber'] = [int]$approvePr.prNumber
                                    $updatedSummary['prOpenedAt'] = (Get-Date).ToUniversalTime().ToString('o')
                                }
                                ($updatedSummary | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $approveSummaryPath -Encoding UTF8

                                $approveMessage = if ($null -eq $approvePr) {
                                    ("Branch '{0}' pushed to origin. PR opening was disabled for this approval." -f $approveBranch)
                                } elseif ($approvePr.refused) {
                                    ("Branch '{0}' pushed to origin, but the PR could not be opened ({1}): {2}" -f $approveBranch, $approvePr.category, $approvePr.reason)
                                } elseif ($approvePr.alreadyExisted) {
                                    ("Branch '{0}' pushed to origin. A pull request already exists: {1}" -f $approveBranch, $approvePr.prUrl)
                                } else {
                                    ("Branch '{0}' pushed to origin and PR #{1} opened: {2}" -f $approveBranch, $approvePr.prNumber, $approvePr.prUrl)
                                }
                                Write-HostLog ("[TRACE] roadmap-agent.approve-push correlationId={0} runId={1} branch={2} pushed=true prUrl={3}" -f $correlationId, $approveRunId, $approveBranch, $(if ($null -ne $approvePr -and $approvePr.prUrl) { $approvePr.prUrl } else { '(none)' }))
                                Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                    success = $true
                                    data = @{
                                        runId = $approveRunId
                                        branch = $approveBranch
                                        pushed = $true
                                        prUrl = $(if ($null -ne $approvePr -and $approvePr.prUrl) { [string]$approvePr.prUrl } else { $null })
                                        prNumber = $(if ($null -ne $approvePr -and $approvePr.prNumber) { [int]$approvePr.prNumber } else { $null })
                                        prRefusal = $(if ($null -ne $approvePr -and $approvePr.refused) { @{ category = [string]$approvePr.category; reason = [string]$approvePr.reason } } else { $null })
                                        prAlreadyExisted = [bool]($null -ne $approvePr -and $approvePr.alreadyExisted)
                                        message = $approveMessage
                                        output = $pushOutput.Trim()
                                    }
                                }
                            }
                        }
                    }
                }
                'GET /api/roadmap/index' {
                    Write-HostLog ("[TRACE] roadmap.index correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $refresh = if ($q.ContainsKey('refresh')) { Parse-Bool -Value $q.refresh -Default $false } else { $false }
                    $settings = Get-HostSettings
                    $ttlSeconds = Get-RoadmapCacheTtlSeconds -Settings $settings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $localRoots = if ($q.ContainsKey('localRoots') -and $q.localRoots) { @($q.localRoots -split ';|,') } else { $defaultRoots }
                    $maxDepth = if ($q.ContainsKey('maxDepth') -and $q.maxDepth) { [int]$q.maxDepth } else { $defaultDepth }
                    $useDefaultScope = ($maxDepth -eq $defaultDepth) -and ((@($localRoots) -join '|') -eq (@($defaultRoots) -join '|'))

                    $cacheHit = $null
                    if ($useDefaultScope -and (-not $refresh) -and ($ttlSeconds -gt 0)) {
                        $cacheHit = Get-RoadmapFromCache -TtlSeconds $ttlSeconds
                    }

                    if ($null -ne $cacheHit -and $cacheHit.hit) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] roadmap.index correlationId={0} done source=cache ageSeconds={1} durationMs={2}" -f $correlationId, [math]::Round($cacheHit.ageSeconds, 1), [int]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                entries = $cacheHit.entries
                                scannedAt = $cacheHit.scannedAt
                                count = @($cacheHit.entries).Count
                                cacheSource = $cacheHit.source
                                cacheAgeSeconds = [math]::Round($cacheHit.ageSeconds, 1)
                            }
                        }
                    } else {
                        $scannedAt = (Get-Date).ToUniversalTime().ToString('o')
                        $entries = Invoke-RoadmapScan -LocalRoots $localRoots -MaxDepth $maxDepth
                        if ($useDefaultScope) {
                            Save-RoadmapCache -Entries $entries -ScannedAt $scannedAt
                        }
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] roadmap.index correlationId={0} done source=fresh-scan count={1} durationMs={2}" -f $correlationId, @($entries).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                entries = $entries
                                scannedAt = $scannedAt
                                count = @($entries).Count
                                cacheSource = 'fresh-scan'
                                cacheAgeSeconds = 0
                            }
                        }
                    }
                }
                'GET /api/roadmap/content' {
                    Write-HostLog ("[TRACE] roadmap.content correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $repoName = if ($q.ContainsKey('repo') -and $q.repo) { [System.Uri]::UnescapeDataString([string]$q.repo) } else { '' }
                    $requestedPath = if ($q.ContainsKey('path') -and $q.path) { [System.Uri]::UnescapeDataString([string]$q.path) } else { '' }

                    $targetPath = $requestedPath
                    if ([string]::IsNullOrWhiteSpace($targetPath) -and -not [string]::IsNullOrWhiteSpace($repoName)) {
                        $settings = Get-HostSettings
                        $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                        $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                        $ttlSeconds = Get-RoadmapCacheTtlSeconds -Settings $settings
                        $cached = Get-RoadmapFromCache -TtlSeconds $ttlSeconds
                        $indexEntries = if ($cached.hit) { @($cached.entries) } else { @(Invoke-RoadmapScan -LocalRoots $defaultRoots -MaxDepth $defaultDepth) }
                        $match = $indexEntries | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1
                        if ($null -ne $match) { $targetPath = [string]$match.roadmapPath }
                    }

                    if ([string]::IsNullOrWhiteSpace($targetPath) -or -not (Test-Path -LiteralPath $targetPath)) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = @{ category = 'validation'; message = 'ROADMAP file not found for the specified repo or path.' }
                        }
                    } else {
                        $fileInfo = Get-Item -LiteralPath $targetPath
                        $content = Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8 -ErrorAction Stop
                        $inferredRepoName = if (-not [string]::IsNullOrWhiteSpace($repoName)) { $repoName } else { $fileInfo.Directory.Name }
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] roadmap.content correlationId={0} done repo={1} sizeBytes={2} durationMs={3}" -f $correlationId, $inferredRepoName, $fileInfo.Length, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                repoName = $inferredRepoName
                                content = $content
                                path = $targetPath
                                sizeBytes = [long]$fileInfo.Length
                                lastModified = $fileInfo.LastWriteTime.ToString('o')
                            }
                        }
                    }
                }
                'GET /api/readme/content' {
                    Write-HostLog ("[TRACE] readme.content correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $repoName = if ($q.ContainsKey('repo') -and $q.repo) { [System.Uri]::UnescapeDataString([string]$q.repo) } else { '' }
                    $requestedPath = if ($q.ContainsKey('path') -and $q.path) { [System.Uri]::UnescapeDataString([string]$q.path) } else { '' }

                    $targetPath = $requestedPath
                    if ([string]::IsNullOrWhiteSpace($targetPath) -and -not [string]::IsNullOrWhiteSpace($repoName)) {
                        $indexPayload = Get-PortfolioIndexPayload -WorkspaceRoot $WorkspaceRoot
                        if ($null -ne $indexPayload -and ($indexPayload.PSObject.Properties.Name -contains 'repos')) {
                            $indexMatch = @($indexPayload.repos | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1)
                            if ($indexMatch.Count -gt 0) {
                                $localPath = [string](Get-ObjectPropertyValue -InputObject $indexMatch[0] -PropertyName 'localPath' -Default '')
                                if (-not [string]::IsNullOrWhiteSpace($localPath)) {
                                    $candidatePath = Join-Path $localPath 'README.md'
                                    if (Test-Path -LiteralPath $candidatePath) {
                                        $targetPath = $candidatePath
                                    }
                                }
                            }
                        }

                        if ([string]::IsNullOrWhiteSpace($targetPath)) {
                            foreach ($cacheKey in @($script:StatusCacheMemory.Keys)) {
                                $entry = $script:StatusCacheMemory[$cacheKey]
                                if ($null -eq $entry -or $null -eq $entry.Response) { continue }
                                $cachedRepos = if ($entry.Response.PSObject.Properties['repos']) { @($entry.Response.repos) } else { @() }
                                $match = $cachedRepos | Where-Object { $_.name -eq $repoName } | Select-Object -First 1
                                if ($null -eq $match -or [string]::IsNullOrWhiteSpace([string]$match.localPath)) { continue }
                                $candidatePath = Join-Path ([string]$match.localPath) 'README.md'
                                if (Test-Path -LiteralPath $candidatePath) {
                                    $targetPath = $candidatePath
                                    break
                                }
                            }
                        }
                    }

                    if ([string]::IsNullOrWhiteSpace($targetPath) -or -not (Test-Path -LiteralPath $targetPath)) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = @{ category = 'validation'; message = 'README file not found for the specified repo or path.' }
                        }
                    } else {
                        $fileInfo = Get-Item -LiteralPath $targetPath
                        $content = Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8 -ErrorAction Stop
                        $inferredRepoName = if (-not [string]::IsNullOrWhiteSpace($repoName)) { $repoName } else { $fileInfo.Directory.Name }
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] readme.content correlationId={0} done repo={1} sizeBytes={2} durationMs={3}" -f $correlationId, $inferredRepoName, $fileInfo.Length, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                repoName = $inferredRepoName
                                content = $content
                                path = $targetPath
                                sizeBytes = [long]$fileInfo.Length
                                lastModified = $fileInfo.LastWriteTime.ToString('o')
                            }
                        }
                    }
                }
                'POST /api/roadmap/scan' {
                    Write-HostLog ("[TRACE] roadmap.scan correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $targetRepoName = if ($body.ContainsKey('repoName') -and $body.repoName) { [string]$body.repoName } elseif ($body.ContainsKey('targetRepo') -and $body.targetRepo) { [string]$body.targetRepo } else { '' }
                    $localRoots = if ($body.ContainsKey('localRoots') -and $body.localRoots) { @($body.localRoots) } else { $defaultRoots }
                    $maxDepth = if ($body.ContainsKey('maxDepth') -and $body.maxDepth) { [int]$body.maxDepth } else { $defaultDepth }
                    $isScopedRepoScan = -not [string]::IsNullOrWhiteSpace($targetRepoName)

                    if ($isScopedRepoScan) {
                        $resolved = Resolve-OperationsRepoRecord -RepoId $targetRepoName
                        if ($resolved.found) {
                            $recordPath = [string](Get-ObjectPropertyValue -InputObject $resolved.record -PropertyName 'localPath' -Default '')
                            if (-not [string]::IsNullOrWhiteSpace($recordPath) -and (Test-Path -LiteralPath $recordPath)) {
                                $localRoots = @($recordPath)
                                if (-not ($body.ContainsKey('maxDepth') -and $body.maxDepth)) {
                                    $maxDepth = 6
                                }
                            }
                        }
                    }

                    $useDefaultScope = (-not $isScopedRepoScan) -and ($maxDepth -eq $defaultDepth) -and ((@($localRoots) -join '|') -eq (@($defaultRoots) -join '|'))
                    $scannedAt = (Get-Date).ToUniversalTime().ToString('o')
                    $entries = Invoke-RoadmapScan -LocalRoots $localRoots -MaxDepth $maxDepth

                    if ($isScopedRepoScan) {
                        $targetLower = $targetRepoName.ToLowerInvariant()
                        $entries = @($entries | Where-Object {
                            $entryRepoName = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')
                            $entryPath = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoPath' -Default '')
                            $entryRepoName.ToLowerInvariant() -eq $targetLower -or
                            ((-not [string]::IsNullOrWhiteSpace($entryPath)) -and $entryPath.ToLowerInvariant().EndsWith("\\$targetLower"))
                        })
                    }

                    if ($useDefaultScope) {
                        Save-RoadmapCache -Entries $entries -ScannedAt $scannedAt
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] roadmap.scan correlationId={0} done count={1} scopedRepo={2} durationMs={3}" -f $correlationId, @($entries).Count, $(if ($isScopedRepoScan) { $targetRepoName } else { 'none' }), [int]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            entries = $entries
                            scannedAt = $scannedAt
                            count = @($entries).Count
                            scopedRepo = if ($isScopedRepoScan) { $targetRepoName } else { $null }
                            cacheSource = 'fresh-scan'
                            cacheAgeSeconds = 0
                        }
                    }
                }
                'GET /api/roadmap/cache' {
                    $settings = Get-HostSettings
                    $ttlSeconds = Get-RoadmapCacheTtlSeconds -Settings $settings
                    $cacheFile = Get-RoadmapCacheFilePath
                    $diskInfo = $null
                    if (Test-Path -LiteralPath $cacheFile) {
                        try {
                            $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
                            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                                $disk = ConvertFrom-JsonCompat -Json $raw
                                if ($disk -and $disk.ContainsKey('createdAtUtc')) {
                                    $nowUtc = (Get-Date).ToUniversalTime()
                                    $created = [datetime]$disk.createdAtUtc
                                    $diskInfo = @{
                                        scannedAt = [string]$disk.scannedAt
                                        createdAtUtc = $disk.createdAtUtc
                                        ageSeconds = [math]::Round(($nowUtc - $created).TotalSeconds, 1)
                                        expired = (($nowUtc - $created).TotalSeconds -gt $ttlSeconds)
                                        entryCount = @($disk.entries).Count
                                    }
                                }
                            }
                        } catch { }
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        ttlSeconds = $ttlSeconds
                        memoryEntries = $script:RoadmapCacheMemory.Count
                        disk = $diskInfo
                    }
                }
                'POST /api/roadmap/cache/clear' {
                    Clear-RoadmapCache
                    Add-MetricCounter -Name 'api_requests_total'
                    Write-HostLog ("[TRACE] roadmap.cache.clear correlationId={0}" -f $correlationId)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        message = 'Roadmap cache cleared. Next GET /api/roadmap/index will perform a fresh scan.'
                    }
                }
                'GET /api/roadmap/standard' {
                    Write-HostLog ("[TRACE] roadmap.standard correlationId={0} start" -f $correlationId)
                    $standard = Get-RoadmapStandard
                    Add-MetricCounter -Name 'api_requests_total'
                    if ($null -eq $standard) {
                        Write-HostLog ("[TRACE] roadmap.standard correlationId={0} not-found" -f $correlationId)
                        Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error   = 'Roadmap standard assets not found. Ensure standards/roadmap/roadmap-audit-rules.json exists in the workspace.'
                        }
                    } else {
                        Write-HostLog ("[TRACE] roadmap.standard correlationId={0} done ruleCount={1}" -f $correlationId, $standard.ruleCount)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $standard
                        }
                    }
                }
                'GET /api/docs-audit' {
                    Write-HostLog ("[TRACE] docs-audit.index correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $refresh = if ($q.ContainsKey('refresh')) { Parse-Bool -Value $q.refresh -Default $false } else { $false }
                    $settings = Get-HostSettings
                    $ttlSeconds = Get-DocAuditCacheTtlSeconds -Settings $settings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $localRoots = if ($q.ContainsKey('localRoots') -and $q.localRoots) { @($q.localRoots -split ';|,') } else { $defaultRoots }
                    $maxDepth = if ($q.ContainsKey('maxDepth') -and $q.maxDepth) { [int]$q.maxDepth } else { $defaultDepth }
                    $useDefaultScope = ($maxDepth -eq $defaultDepth) -and ((@($localRoots) -join '|') -eq (@($defaultRoots) -join '|'))

                    $cacheHit = $null
                    if ($useDefaultScope -and (-not $refresh) -and ($ttlSeconds -gt 0)) {
                        $cacheHit = Get-DocAuditFromCache -TtlSeconds $ttlSeconds
                    }

                    if ($null -ne $cacheHit -and $cacheHit.hit) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] docs-audit.index correlationId={0} done source=cache ageSeconds={1}" -f $correlationId, [math]::Round($cacheHit.ageSeconds, 1))
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                entries = $cacheHit.entries
                                auditedAt = $cacheHit.auditedAt
                                count = @($cacheHit.entries).Count
                                cacheSource = $cacheHit.source
                                cacheAgeSeconds = [math]::Round($cacheHit.ageSeconds, 1)
                            }
                        }
                    } else {
                        $auditedAt = (Get-Date).ToUniversalTime().ToString('o')
                        $entries = Invoke-DocAuditScan -LocalRoots $localRoots -MaxDepth $maxDepth
                        if ($useDefaultScope) {
                            Save-DocAuditCache -Entries $entries -AuditedAt $auditedAt
                        }
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] docs-audit.index correlationId={0} done source=fresh-scan count={1} durationMs={2}" -f $correlationId, @($entries).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                entries = $entries
                                auditedAt = $auditedAt
                                count = @($entries).Count
                                cacheSource = 'fresh-scan'
                                cacheAgeSeconds = 0
                            }
                        }
                    }
                }
                'POST /api/docs-audit/scan' {
                    Write-HostLog ("[TRACE] docs-audit.scan correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $localRoots = if ($body.ContainsKey('localRoots') -and $body.localRoots) { @($body.localRoots) } else { $defaultRoots }
                    $maxDepth = if ($body.ContainsKey('maxDepth') -and $body.maxDepth) { [int]$body.maxDepth } else { $defaultDepth }
                    $useDefaultScope = ($maxDepth -eq $defaultDepth) -and ((@($localRoots) -join '|') -eq (@($defaultRoots) -join '|'))
                    $auditedAt = (Get-Date).ToUniversalTime().ToString('o')
                    $entries = Invoke-DocAuditScan -LocalRoots $localRoots -MaxDepth $maxDepth
                    if ($useDefaultScope) {
                        Save-DocAuditCache -Entries $entries -AuditedAt $auditedAt
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] docs-audit.scan correlationId={0} done count={1} durationMs={2}" -f $correlationId, @($entries).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            entries = $entries
                            auditedAt = $auditedAt
                            count = @($entries).Count
                            cacheSource = 'fresh-scan'
                            cacheAgeSeconds = 0
                        }
                    }
                }
                'POST /api/repository-improvement/preview' {
                    Write-HostLog ("[TRACE] repository-improvement.preview correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $repoName = if ($body.ContainsKey('repoName') -and $body.repoName) { [string]$body.repoName } else { '' }
                    $repoPath = if ($body.ContainsKey('repoPath') -and $body.repoPath) { [string]$body.repoPath } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repoName)) { throw 'repoName is required for /api/repository-improvement/preview' }
                    if ([string]::IsNullOrWhiteSpace($repoPath)) { throw 'repoPath is required for /api/repository-improvement/preview' }

                    $standardsPath = Join-Path $WorkspaceRoot 'backend\config\doc-standards.json'
                    $preview = New-RepositoryImprovementPreview `
                        -RepoName $repoName `
                        -RepoPath $repoPath `
                        -DocStandards (Get-DocStandards -StandardsPath $standardsPath) `
                        -RoadmapAuditRules (Get-RoadmapStandard)

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] repository-improvement.preview correlationId={0} done repoName={1} findingCount={2}" -f $correlationId, $repoName, $preview.findingCount)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $preview
                    }
                }
                'GET /api/portfolio/assessment' {
                    Write-HostLog ("[TRACE] portfolio.assessment correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $refresh = if ($q.ContainsKey('refresh')) { Parse-Bool -Value $q.refresh -Default $false } else { $false }
                    if ($forcedRefreshAll) { $refresh = $true }
                    $includeCuration = if ($q.ContainsKey('includeCuration')) { Parse-Bool -Value $q.includeCuration -Default $false } else { $false }
                    if ($forcedRefreshAll) { $includeCuration = $true }
                    $scanModeRaw = if ($q.ContainsKey('scanMode')) { [string]$q.scanMode } else { 'full' }
                    $scanMode = if ([string]::IsNullOrWhiteSpace($scanModeRaw)) { 'full' } else { $scanModeRaw.Trim().ToLowerInvariant() }
                    if ($scanMode -notin @('full', 'differential')) { $scanMode = 'full' }
                    $useDifferentialScan = (-not $refresh) -and ($scanMode -eq 'differential')

                    $settings   = Get-HostSettings
                    $ttlSeconds = Get-PortfolioAssessmentCacheTtlSeconds -Settings $settings

                    if (-not $refresh -and -not $useDifferentialScan -and $ttlSeconds -gt 0) {
                        $cacheHit = Get-PortfolioAssessmentFromCache -TtlSeconds $ttlSeconds
                        if ($cacheHit.hit) {
                            $cacheHitEntries = @($cacheHit.entries)
                            if ($includeCuration) {
                                # Curation is operator-authored and can change between scans;
                                # merge the current map even on cache hits so toggles are
                                # visible without forcing a rescan.
                                $cacheHitEntries = Add-PortfolioCurationToAssessments -Assessments $cacheHitEntries
                            }
                            Add-MetricCounter -Name 'api_requests_total'
                            Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                            Write-HostLog ("[TRACE] portfolio.assessment correlationId={0} done source=cache ageSeconds={1}" -f $correlationId, [math]::Round($cacheHit.ageSeconds, 1))
                            $readBudget = New-PortfolioReadBudgetResult -CacheSource 'memory' `
                                -MeasuredMs ([double]((Get-Date) - $requestStart).TotalMilliseconds) -Settings $settings
                            Write-HostLog (Format-PortfolioReadBudgetLog -Result $readBudget -CorrelationId $correlationId -Route '/api/portfolio/assessment')
                            if (-not $readBudget.withinBudget) {
                                Write-HostLog ("WARN portfolio.assessment read budget exceeded correlationId={0} class={1} measuredMs={2} budgetMs={3} overByMs={4}" -f $correlationId, $readBudget.readClass, $readBudget.measuredMs, $readBudget.budgetMs, $readBudget.overByMs)
                            }
                            Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                success = $true
                                data = @{
                                    entries         = $cacheHitEntries
                                    summary         = $cacheHit.summary
                                    signalSources   = $cacheHit.signalSources
                                    generatedAt     = $cacheHit.generatedAt
                                    count           = @($cacheHitEntries).Count
                                    cacheSource     = 'memory'
                                    cacheAgeSeconds = [math]::Round($cacheHit.ageSeconds, 1)
                                    performance     = $readBudget
                                }
                            }
                            break
                        }
                    }

                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }

                    # Pull cached signal sources where available; otherwise enumerate live for that signal only.
                    $signalSources = @{}

                    # 1) Local repo inventory (status)
                    $statusTtl = Get-StatusCacheTtlSeconds -Settings $settings
                    $statusKey = Get-StatusCacheKey -LocalRoots $defaultRoots -MaxDepth $defaultDepth -IncludeNonGitFolders $false
                    $statusResult = $null
                    if (-not $refresh -and $statusTtl -gt 0) {
                        $statusCached = Get-StatusFromCache -Key $statusKey -TtlSeconds $statusTtl
                        if ($statusCached.hit) {
                            $statusResult = $statusCached.response
                            $signalSources['status'] = 'cache'
                        }
                    }
                    if ($null -eq $statusResult) {
                        # Same fix as GET /api/status: this route must not run a
                        # portfolio sweep on the request thread either, or it
                        # reintroduces the freeze through the other door. Both
                        # routes read the same cache, so one background worker
                        # serves both.
                        $assessmentRefreshStarted = Start-BackgroundStatusRefresh -LocalRoots $defaultRoots -MaxDepth $defaultDepth
                        $assessmentRefreshState = Get-StatusRefreshState

                        $staleStatus = Get-StatusFromCache -Key $statusKey -TtlSeconds $statusTtl -IgnoreTtl:$true
                        if ($staleStatus.hit) {
                            $statusResult = $staleStatus.response
                            $signalSources['status'] = 'stale-cache'
                        }
                        else {
                            $statusResult = $null
                            $signalSources['status'] = 'awaiting-first-scan'
                        }

                        $signalSources['statusRefreshing'] = [bool]($assessmentRefreshStarted -or $assessmentRefreshState.running)
                        Write-HostLog ("[TRACE] portfolio.assessment correlationId={0} status-cache miss served={1} refreshing={2}" -f $correlationId, $signalSources['status'], $signalSources['statusRefreshing'])
                    }
                    else {
                        # A cache hit already carries the GitHub metadata the
                        # worker joined in. Re-joining it here would put those
                        # sequential API calls back on the request thread - the
                        # very cost this change removed.
                        $signalSources['statusRefreshing'] = $false
                    }
                    $localRepos = if ($null -ne $statusResult -and $statusResult.success -and $null -ne $statusResult.data) { @($statusResult.data.repos) } else { @() }

                    # 2) Roadmap entries
                    $roadmapTtl     = Get-RoadmapCacheTtlSeconds -Settings $settings
                    $roadmapEntries = @()
                    if (-not $useDifferentialScan) {
                        if (-not $refresh) {
                            $rmCached = Get-RoadmapFromCache -TtlSeconds $roadmapTtl
                            if ($rmCached.hit) {
                                $roadmapEntries = @($rmCached.entries)
                                $signalSources['roadmap'] = 'cache'
                            }
                        }
                        if (@($roadmapEntries).Count -eq 0) {
                            # Was a fresh inline scan measured at prepMs=40669 on
                            # this workspace - and it never wrote the cache, so
                            # every request paid it again. The worker owns this
                            # scan now; serve whatever it last produced.
                            $null = Start-BackgroundStatusRefresh -LocalRoots $defaultRoots -MaxDepth $defaultDepth
                            $rmStale = Get-RoadmapFromCache -TtlSeconds ([int]::MaxValue)
                            if ($rmStale.hit) {
                                $roadmapEntries = @($rmStale.entries)
                                $signalSources['roadmap'] = 'stale-cache'
                            } else {
                                $roadmapEntries = @()
                                $signalSources['roadmap'] = 'awaiting-first-scan'
                            }
                            Write-HostLog ("[TRACE] portfolio.assessment correlationId={0} roadmap-cache miss served={1}" -f $correlationId, $signalSources['roadmap'])
                        }
                    } else {
                        $signalSources['roadmap'] = 'deferred-differential'
                    }

                    # 3) Doc audit entries
                    $docAuditTtl     = Get-DocAuditCacheTtlSeconds -Settings $settings
                    $docAuditEntries = @()
                    if (-not $useDifferentialScan) {
                        if (-not $refresh) {
                            $daCached = Get-DocAuditFromCache -TtlSeconds $docAuditTtl
                            if ($daCached.hit) {
                                $docAuditEntries = @($daCached.entries)
                                $signalSources['docAudit'] = 'cache'
                            }
                        }
                        if (@($docAuditEntries).Count -eq 0) {
                            # Same move as the roadmap branch above: the worker
                            # scans, the request serves.
                            $null = Start-BackgroundStatusRefresh -LocalRoots $defaultRoots -MaxDepth $defaultDepth
                            $daStale = Get-DocAuditFromCache -TtlSeconds ([int]::MaxValue)
                            if ($daStale.hit) {
                                $docAuditEntries = @($daStale.entries)
                                $signalSources['docAudit'] = 'stale-cache'
                            } else {
                                $docAuditEntries = @()
                                $signalSources['docAudit'] = 'awaiting-first-scan'
                            }
                            Write-HostLog ("[TRACE] portfolio.assessment correlationId={0} doc-audit-cache miss served={1}" -f $correlationId, $signalSources['docAudit'])
                        }
                    } else {
                        $signalSources['docAudit'] = 'deferred-differential'
                    }

                    # 4) Roadmap audit entries (maturity).
                    $roadmapAuditEntries = @()
                    $rmAuditTtl = Get-RoadmapAuditCacheTtlSeconds -Settings $settings
                    if (-not $useDifferentialScan) {
                        if (-not $refresh) {
                            $raCached = Get-RoadmapAuditFromCache -TtlSeconds $rmAuditTtl
                            if ($raCached.hit) {
                                $roadmapAuditEntries = @($raCached.entries)
                                $signalSources['roadmapAudit'] = 'cache'
                            }
                        }
                        if (@($roadmapAuditEntries).Count -eq 0) {
                            # The last of the four sweeps this route ran inline.
                            # With the other three moved, this one alone still
                            # held the request for prepMs=27799.
                            $null = Start-BackgroundStatusRefresh -LocalRoots $defaultRoots -MaxDepth $defaultDepth
                            $raStale = Get-RoadmapAuditFromCache -TtlSeconds ([int]::MaxValue)
                            if ($raStale.hit) {
                                $roadmapAuditEntries = @($raStale.entries)
                                $signalSources['roadmapAudit'] = 'stale-cache'
                            } else {
                                $roadmapAuditEntries = @()
                                $signalSources['roadmapAudit'] = 'awaiting-first-scan'
                            }
                            Write-HostLog ("[TRACE] portfolio.assessment correlationId={0} roadmap-audit-cache miss served={1}" -f $correlationId, $signalSources['roadmapAudit'])
                        }
                    } else {
                        $signalSources['roadmapAudit'] = 'deferred-differential'
                    }

                    # 5) Execution ledger entries
                    $executionEntries = @()
                    try {
                        $ledger = Read-ExecutionLedger -WorkspaceRoot $WorkspaceRoot
                        $executionEntries = @($ledger.entries)
                        $signalSources['execution'] = 'ledger'
                    } catch {
                        $signalSources['execution'] = 'unavailable'
                    }

                    # 6) GitHub repos for enrichment. GitHub-only repos remain opt-in.
                    $githubRepos = @()
                    $signalSources['github'] = 'not-evaluated'
                    $includeGithub = if ($q.ContainsKey('includeGithub')) { Parse-Bool -Value $q.includeGithub -Default $false } else { $false }
                    $owner = if ($settings.ContainsKey('reconcile') -and $settings.reconcile.ContainsKey('gitHubOwner') -and $settings.reconcile.gitHubOwner) {
                        [string]$settings.reconcile.gitHubOwner
                    } else { '' }
                    if (-not [string]::IsNullOrWhiteSpace($owner)) {
                        try {
                            $token = Get-ConfiguredGitHubToken -Settings $settings
                            if (-not [string]::IsNullOrWhiteSpace($token)) {
                                $apiResult = Get-GitHubReposViaApi -Owner $owner -Token $token -RepoLimit 100 -IncludePrivate:$true -IncludeForks:$false -IncludeArchived:$true -FetchCommitMetrics:$false
                                if ($null -ne $apiResult -and $apiResult.PSObject.Properties.Name -contains 'repos') {
                                    $githubRepos = @($apiResult.repos)
                                    $signalSources['github'] = 'api'
                                } else {
                                    $signalSources['github'] = 'unavailable'
                                }
                            } else {
                                $signalSources['github'] = 'no-token'
                            }
                        } catch {
                            $signalSources['github'] = 'error'
                            Write-HostLog ("[TRACE] portfolio.assessment github fetch failed: {0}" -f $_.Exception.Message)
                        }
                    } else {
                        $signalSources['github'] = 'no-owner-configured'
                    }

                    $githubReposForAssessment = @($githubRepos)
                    if (-not $includeGithub -and @($githubReposForAssessment).Count -gt 0) {
                        $localRepoNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($repo in @($localRepos)) {
                            if ($null -eq $repo) { continue }
                            $repoName = if ($repo.PSObject.Properties.Name -contains 'name') { [string]$repo.name } else { '' }
                            if (-not [string]::IsNullOrWhiteSpace($repoName)) {
                                [void]$localRepoNames.Add($repoName)
                            }
                        }
                        $githubReposForAssessment = @($githubReposForAssessment | Where-Object { $localRepoNames.Contains([string]$_.name) })
                    }

                    $previousIndexPayload = $null
                    $previousRepos = @()
                    $previousRepoMap = @{}
                    $previousAssessments = @()
                    $unchangedAssessments = @()
                    $localReposForAssessment = @($localRepos)
                    $githubReposForAssessmentSubset = @($githubReposForAssessment)
                    $differentialChangedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $differentialDecisionMap = @{}
                    $scanSummary = [ordered]@{
                        reused = 0
                        reindexed = 0
                        failed = 0
                        durationMs = 0
                    }

                    if ($useDifferentialScan) {
                        $previousIndexPayload = Get-PortfolioIndexPayload -WorkspaceRoot $WorkspaceRoot
                        $previousRepos = if ($null -ne $previousIndexPayload -and $previousIndexPayload.PSObject.Properties.Name -contains 'repos') { @($previousIndexPayload.repos) } else { @() }
                        if (@($previousRepos).Count -gt 0) {
                            foreach ($prev in @($previousRepos)) {
                                if ($null -eq $prev) { continue }
                                $prevName = [string](Get-ObjectPropertyValue -InputObject $prev -PropertyName 'repoName' -Default '')
                                if ([string]::IsNullOrWhiteSpace($prevName)) { continue }
                                $previousRepoMap[$prevName.ToLowerInvariant()] = $prev
                            }

                            $currentLocalMap = @{}
                            foreach ($repo in @($localRepos)) {
                                if ($null -eq $repo) { continue }
                                $name = [string](Get-ObjectPropertyValue -InputObject $repo -PropertyName 'name' -Default '')
                                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                                $currentLocalMap[$name.ToLowerInvariant()] = $repo
                            }
                            $currentGithubMap = @{}
                            foreach ($repo in @($githubReposForAssessment)) {
                                if ($null -eq $repo) { continue }
                                $name = [string](Get-ObjectPropertyValue -InputObject $repo -PropertyName 'name' -Default '')
                                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                                $currentGithubMap[$name.ToLowerInvariant()] = $repo
                            }

                            $allNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                            foreach ($name in $previousRepoMap.Keys) { [void]$allNames.Add($name) }
                            foreach ($name in $currentLocalMap.Keys) { [void]$allNames.Add($name) }
                            foreach ($name in $currentGithubMap.Keys) { [void]$allNames.Add($name) }

                            foreach ($nameKey in $allNames) {
                                $currentLocal = if ($currentLocalMap.ContainsKey($nameKey)) { $currentLocalMap[$nameKey] } else { $null }
                                $currentGithub = if ($currentGithubMap.ContainsKey($nameKey)) { $currentGithubMap[$nameKey] } else { $null }
                                $currentSourceCoverage = if ($null -ne $currentLocal -and $null -ne $currentGithub) { 'local+github' } elseif ($null -ne $currentLocal) { 'local' } elseif ($null -ne $currentGithub) { 'github' } else { 'none' }
                                $currentLocalPath = if ($null -ne $currentLocal) { [string](Get-ObjectPropertyValue -InputObject $currentLocal -PropertyName 'path' -Default '') } else { '' }
                                $currentHeadCommitSha = if ($null -ne $currentLocal) { [string](Get-ObjectPropertyValue -InputObject $currentLocal -PropertyName 'headCommitSha' -Default '') } else { '' }
                                $currentHeadCommitDate = if ($null -ne $currentLocal) { [string](Get-ObjectPropertyValue -InputObject $currentLocal -PropertyName 'lastCommitDate' -Default '') } else { '' }
                                $currentHeadBranch = if ($null -ne $currentLocal) { [string](Get-ObjectPropertyValue -InputObject $currentLocal -PropertyName 'branch' -Default '') } else { '' }
                                $currentFingerprint = if ($currentSourceCoverage -eq 'none') { '' } else { Get-PortfolioScanFingerprintFromSignals -LocalRepo $currentLocal -GitHubRepo $currentGithub -LocalPath $currentLocalPath -SourceCoverage $currentSourceCoverage }

                                $previousRepo = if ($previousRepoMap.ContainsKey($nameKey)) { $previousRepoMap[$nameKey] } else { $null }
                                $previousFingerprint = if ($null -ne $previousRepo) { Get-PortfolioScanFingerprintFromIndexedRepo -IndexedRepo $previousRepo } else { '' }
                                $previousHeadCommitSha = if ($null -ne $previousRepo) { [string](Get-ObjectPropertyValue -InputObject $previousRepo -PropertyName 'lastIndexedCommitSha' -Default (Get-ObjectPropertyValue -InputObject $previousRepo -PropertyName 'headCommitSha' -Default '')) } else { '' }
                                $previousHeadCommitDate = if ($null -ne $previousRepo) { [string](Get-ObjectPropertyValue -InputObject $previousRepo -PropertyName 'lastIndexedCommitDate' -Default (Get-ObjectPropertyValue -InputObject $previousRepo -PropertyName 'localLastCommitDate' -Default '')) } else { '' }
                                $previousHeadBranch = if ($null -ne $previousRepo) { [string](Get-ObjectPropertyValue -InputObject $previousRepo -PropertyName 'lastIndexedBranch' -Default (Get-ObjectPropertyValue -InputObject $previousRepo -PropertyName 'currentBranch' -Default '')) } else { '' }
                                $previousMetadataHash = if ($null -ne $previousRepo) { [string](Get-ObjectPropertyValue -InputObject $previousRepo -PropertyName 'lastMetadataHash' -Default $previousFingerprint) } else { '' }

                                $scanDecisionReason = 'reused-cache'
                                $changeState = 'unchanged'
                                $changed = $false

                                if ($null -eq $previousRepo) {
                                    $scanDecisionReason = 'cache-miss'
                                    $changeState = 'needs-rescan'
                                    $changed = $true
                                }
                                elseif ($currentSourceCoverage -eq 'none') {
                                    $scanDecisionReason = 'cache-invalid'
                                    $changeState = 'needs-rescan'
                                    $changed = $true
                                }
                                elseif ([string]::IsNullOrWhiteSpace($previousFingerprint) -or [string]::IsNullOrWhiteSpace($currentFingerprint)) {
                                    $scanDecisionReason = 'cache-invalid'
                                    $changeState = 'needs-rescan'
                                    $changed = $true
                                }
                                elseif (-not [string]::IsNullOrWhiteSpace($currentHeadCommitSha) -and -not [string]::IsNullOrWhiteSpace($previousHeadCommitSha) -and $currentHeadCommitSha -ne $previousHeadCommitSha) {
                                    $scanDecisionReason = 'new-commit'
                                    $changeState = 'new-commits'
                                    $changed = $true
                                }
                                elseif ($currentFingerprint -ne $previousFingerprint) {
                                    $scanDecisionReason = 'metadata-changed'
                                    $changeState = 'metadata-changed'
                                    $changed = $true
                                }

                                if ($changed) {
                                    [void]$differentialChangedSet.Add($nameKey)
                                }

                                $differentialDecisionMap[$nameKey] = [pscustomobject]@{
                                    changeState            = $changeState
                                    scanDecisionReason     = $scanDecisionReason
                                    headCommitSha          = if ([string]::IsNullOrWhiteSpace($currentHeadCommitSha)) { $null } else { $currentHeadCommitSha }
                                    headCommitDate         = if ([string]::IsNullOrWhiteSpace($currentHeadCommitDate)) { $null } else { $currentHeadCommitDate }
                                    headBranch             = if ([string]::IsNullOrWhiteSpace($currentHeadBranch)) { $null } else { $currentHeadBranch }
                                    currentMetadataHash    = if ([string]::IsNullOrWhiteSpace($currentFingerprint)) { $null } else { $currentFingerprint }
                                    lastIndexedCommitSha   = if ([string]::IsNullOrWhiteSpace($previousHeadCommitSha)) { $null } else { $previousHeadCommitSha }
                                    lastIndexedCommitDate  = if ([string]::IsNullOrWhiteSpace($previousHeadCommitDate)) { $null } else { $previousHeadCommitDate }
                                    lastIndexedBranch      = if ([string]::IsNullOrWhiteSpace($previousHeadBranch)) { $null } else { $previousHeadBranch }
                                    lastMetadataHash       = if ([string]::IsNullOrWhiteSpace($previousMetadataHash)) { $null } else { $previousMetadataHash }
                                    lastScannedAt          = if ($null -ne $previousRepo) { (Get-ObjectPropertyValue -InputObject $previousRepo -PropertyName 'lastScannedAt' -Default $null) } else { $null }
                                    lastScanStatus         = if ($null -ne $previousRepo) { [string](Get-ObjectPropertyValue -InputObject $previousRepo -PropertyName 'lastScanStatus' -Default 'ok') } else { 'ok' }
                                    lastScanError          = if ($null -ne $previousRepo) { (Get-ObjectPropertyValue -InputObject $previousRepo -PropertyName 'lastScanError' -Default $null) } else { $null }
                                }
                            }

                            $localReposForAssessment = @($localRepos | Where-Object {
                                $repoName = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'name' -Default '')
                                -not [string]::IsNullOrWhiteSpace($repoName) -and $differentialChangedSet.Contains($repoName)
                            })

                            $githubReposForAssessmentSubset = @($githubReposForAssessment | Where-Object {
                                $repoName = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'name' -Default '')
                                -not [string]::IsNullOrWhiteSpace($repoName) -and $differentialChangedSet.Contains($repoName)
                            })

                            $previousAssessments = Convert-PortfolioIndexReposToAssessments -IndexRepos $previousRepos
                            $currentNameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                            foreach ($repo in @($localRepos)) {
                                $repoName = [string](Get-ObjectPropertyValue -InputObject $repo -PropertyName 'name' -Default '')
                                if (-not [string]::IsNullOrWhiteSpace($repoName)) { [void]$currentNameSet.Add($repoName) }
                            }
                            foreach ($repo in @($githubReposForAssessment)) {
                                $repoName = [string](Get-ObjectPropertyValue -InputObject $repo -PropertyName 'name' -Default '')
                                if (-not [string]::IsNullOrWhiteSpace($repoName)) { [void]$currentNameSet.Add($repoName) }
                            }
                            $unchangedAssessments = @($previousAssessments | Where-Object {
                                $repoName = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')
                                -not [string]::IsNullOrWhiteSpace($repoName) -and $currentNameSet.Contains($repoName) -and (-not $differentialChangedSet.Contains($repoName))
                            })

                            Write-HostLog ("[TRACE] portfolio.assessment differential selection changed={0} unchanged={1} totalCurrent={2}" -f $differentialChangedSet.Count, @($unchangedAssessments).Count, $currentNameSet.Count)
                            $signalSources['scanMode'] = 'differential'
                            $signalSources['differentialChangedCount'] = $differentialChangedSet.Count
                            $signalSources['differentialUnchangedCount'] = @($unchangedAssessments).Count
                        } else {
                            $signalSources['scanMode'] = 'differential-fallback-full'
                        }
                    }

                    if ($useDifferentialScan) {
                        if (@($previousRepos).Count -eq 0) {
                            $roadmapEntries = @(Invoke-RoadmapScan -LocalRoots $defaultRoots -MaxDepth $defaultDepth)
                            $signalSources['roadmap'] = 'fresh-scan'
                            $docAuditEntries = @(Invoke-DocAuditScan -LocalRoots $defaultRoots -MaxDepth $defaultDepth)
                            $signalSources['docAudit'] = 'fresh-scan'
                            $auditedAt = (Get-Date).ToUniversalTime().ToString('o')
                            if ($docAuditTtl -gt 0) { Save-DocAuditCache -Entries $docAuditEntries -AuditedAt $auditedAt }

                            $roadmapAuditEntries = @()
                            $raCached = Get-RoadmapAuditFromCache -TtlSeconds $rmAuditTtl
                            if ($raCached.hit) {
                                $roadmapAuditEntries = @($raCached.entries)
                                $signalSources['roadmapAudit'] = 'cache'
                            } else {
                                $signalSources['roadmapAudit'] = 'unavailable'
                            }
                        } elseif (@($localReposForAssessment).Count -gt 0) {
                            $changedLocalRoots = @($localReposForAssessment | ForEach-Object { [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'path' -Default '') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                            if (@($changedLocalRoots).Count -gt 0) {
                                $roadmapEntries = @(Invoke-RoadmapScan -LocalRoots $changedLocalRoots -MaxDepth 3)
                                $signalSources['roadmap'] = 'differential-scan'

                                Clear-DocAuditCache
                                Clear-RoadmapCache
                                $docAuditEntries = @(Invoke-DocAuditScan -LocalRoots $changedLocalRoots -MaxDepth 3)
                                $signalSources['docAudit'] = 'differential-scan'

                                $auditedAt = (Get-Date).ToUniversalTime().ToString('o')
                                if ($docAuditTtl -gt 0) { Save-DocAuditCache -Entries $docAuditEntries -AuditedAt $auditedAt }
                            }

                            $raCached = Get-RoadmapAuditFromCache -TtlSeconds $rmAuditTtl
                            if ($raCached.hit) {
                                $roadmapAuditEntries = @($raCached.entries | Where-Object {
                                    $repoName = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')
                                    -not [string]::IsNullOrWhiteSpace($repoName) -and $differentialChangedSet.Contains($repoName)
                                })
                                $signalSources['roadmapAudit'] = 'cache-filtered'
                            } else {
                                $roadmapAuditEntries = @()
                                $signalSources['roadmapAudit'] = 'unavailable'
                            }
                        } else {
                            $roadmapEntries = @()
                            $docAuditEntries = @()
                            $roadmapAuditEntries = @()
                            $signalSources['roadmap'] = 'differential-noop'
                            $signalSources['docAudit'] = 'differential-noop'
                            $signalSources['roadmapAudit'] = 'differential-noop'
                        }
                    }

                    # 7) Structure standards
                    $standardsPath = Join-Path $WorkspaceRoot 'backend\config\repo-structure-standards.json'
                    $structStandards = Get-RepoStructureStandards -StandardsPath $standardsPath
                    $valueScoringPath = Join-Path $WorkspaceRoot 'backend\config\value-scoring.json'
                    $valueScoringConfig = Get-PortfolioValueScoringConfig -ConfigPath $valueScoringPath

                    # Run the assessment
                    $assessmentLocalRepos = if ($useDifferentialScan) { @($localReposForAssessment) } else { @($localRepos) }
                    $assessmentGithubRepos = if ($useDifferentialScan) { @($githubReposForAssessmentSubset) } else { @($githubReposForAssessment) }

                    # Cross-cutting — scan performance budget: prep (discovery +
                    # git status + GitHub API + prior scans) up to here, then the
                    # assessment (audit + scoring) and index-write phases below.
                    $scanBudgetPrepMs = [int]((Get-Date) - $requestStart).TotalMilliseconds
                    $swAssess = [System.Diagnostics.Stopwatch]::StartNew()
                    $assessedChanged = Invoke-PortfolioAssessment `
                        -LocalRepos          $assessmentLocalRepos `
                        -RoadmapEntries      $roadmapEntries `
                        -DocAuditEntries     $docAuditEntries `
                        -RoadmapAuditEntries $roadmapAuditEntries `
                        -ExecutionEntries    $executionEntries `
                        -GitHubRepos         $assessmentGithubRepos `
                        -StructureStandards  $structStandards `
                        -ValueScoringConfig  $valueScoringConfig
                    $swAssess.Stop()

                    $assessments = if ($useDifferentialScan -and @($previousRepos).Count -gt 0) {
                        @(@($assessedChanged) + @($unchangedAssessments))
                    } else {
                        @($assessedChanged)
                    }

                    if ($useDifferentialScan -and @($previousRepos).Count -gt 0) {
                        foreach ($assessment in @($assessments)) {
                            if ($null -eq $assessment) { continue }
                            $repoName = [string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'repoName' -Default '')
                            if ([string]::IsNullOrWhiteSpace($repoName)) { continue }
                            $key = $repoName.ToLowerInvariant()
                            if (-not $differentialDecisionMap.ContainsKey($key)) { continue }

                            $decision = $differentialDecisionMap[$key]
                            $assessment | Add-Member -NotePropertyName changeState -NotePropertyValue ([string](Get-ObjectPropertyValue -InputObject $decision -PropertyName 'changeState' -Default 'needs-rescan')) -Force
                            $assessment | Add-Member -NotePropertyName scanDecisionReason -NotePropertyValue ([string](Get-ObjectPropertyValue -InputObject $decision -PropertyName 'scanDecisionReason' -Default 'cache-invalid')) -Force
                            $assessment | Add-Member -NotePropertyName headCommitSha -NotePropertyValue (Get-ObjectPropertyValue -InputObject $decision -PropertyName 'headCommitSha' -Default $null) -Force
                            $assessment | Add-Member -NotePropertyName headCommitDate -NotePropertyValue (Get-ObjectPropertyValue -InputObject $decision -PropertyName 'headCommitDate' -Default $null) -Force
                            $assessment | Add-Member -NotePropertyName headBranch -NotePropertyValue (Get-ObjectPropertyValue -InputObject $decision -PropertyName 'headBranch' -Default $null) -Force
                            $assessment | Add-Member -NotePropertyName currentMetadataHash -NotePropertyValue (Get-ObjectPropertyValue -InputObject $decision -PropertyName 'currentMetadataHash' -Default $null) -Force
                            $assessment | Add-Member -NotePropertyName lastIndexedCommitSha -NotePropertyValue (Get-ObjectPropertyValue -InputObject $decision -PropertyName 'lastIndexedCommitSha' -Default $null) -Force
                            $assessment | Add-Member -NotePropertyName lastIndexedCommitDate -NotePropertyValue (Get-ObjectPropertyValue -InputObject $decision -PropertyName 'lastIndexedCommitDate' -Default $null) -Force
                            $assessment | Add-Member -NotePropertyName lastIndexedBranch -NotePropertyValue (Get-ObjectPropertyValue -InputObject $decision -PropertyName 'lastIndexedBranch' -Default $null) -Force
                            $assessment | Add-Member -NotePropertyName lastMetadataHash -NotePropertyValue (Get-ObjectPropertyValue -InputObject $decision -PropertyName 'lastMetadataHash' -Default $null) -Force
                            $assessment | Add-Member -NotePropertyName lastScannedAt -NotePropertyValue (Get-ObjectPropertyValue -InputObject $decision -PropertyName 'lastScannedAt' -Default $null) -Force
                            $assessment | Add-Member -NotePropertyName lastScanStatus -NotePropertyValue ([string](Get-ObjectPropertyValue -InputObject $decision -PropertyName 'lastScanStatus' -Default 'ok')) -Force
                            $assessment | Add-Member -NotePropertyName lastScanError -NotePropertyValue (Get-ObjectPropertyValue -InputObject $decision -PropertyName 'lastScanError' -Default $null) -Force
                        }

                        $scanSummary.reused = @($unchangedAssessments).Count
                        $scanSummary.reindexed = @($assessedChanged).Count
                        $scanSummary.failed = 0
                    } else {
                        foreach ($assessment in @($assessments)) {
                            if ($null -eq $assessment) { continue }
                            $assessment | Add-Member -NotePropertyName changeState -NotePropertyValue 'needs-rescan' -Force
                            $assessment | Add-Member -NotePropertyName scanDecisionReason -NotePropertyValue $(if ($refresh) { 'forced-refresh' } else { 'cache-miss' }) -Force
                        }
                        $scanSummary.reused = 0
                        $scanSummary.reindexed = @($assessments).Count
                        $scanSummary.failed = 0
                    }

                    $localRepoByName = @{}
                    foreach ($repo in @($localRepos)) {
                        if ($null -eq $repo) { continue }
                        $repoName = [string](Get-ObjectPropertyValue -InputObject $repo -PropertyName 'name' -Default '')
                        if ([string]::IsNullOrWhiteSpace($repoName)) { continue }
                        $localRepoByName[$repoName.ToLowerInvariant()] = $repo
                    }

                    $githubRepoByName = @{}
                    foreach ($repo in @($githubReposForAssessment)) {
                        if ($null -eq $repo) { continue }
                        $repoName = [string](Get-ObjectPropertyValue -InputObject $repo -PropertyName 'name' -Default '')
                        if ([string]::IsNullOrWhiteSpace($repoName)) { continue }
                        $githubRepoByName[$repoName.ToLowerInvariant()] = $repo
                    }

                    foreach ($assessment in @($assessments)) {
                        if ($null -eq $assessment) { continue }
                        $repoName = [string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'repoName' -Default '')
                        if ([string]::IsNullOrWhiteSpace($repoName)) { continue }

                        $nameKey = $repoName.ToLowerInvariant()
                        $localRepo = if ($localRepoByName.ContainsKey($nameKey)) { $localRepoByName[$nameKey] } else { $null }
                        $githubRepo = if ($githubRepoByName.ContainsKey($nameKey)) { $githubRepoByName[$nameKey] } else { $null }
                        $localPath = [string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'localPath' -Default (Get-ObjectPropertyValue -InputObject $localRepo -PropertyName 'path' -Default ''))
                        $sourceCoverage = [string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'sourceCoverage' -Default $(if ($null -ne $localRepo -and $null -ne $githubRepo) { 'local+github' } elseif ($null -ne $localRepo) { 'local' } elseif ($null -ne $githubRepo) { 'github' } else { 'none' }))
                        $headCommitSha = [string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'headCommitSha' -Default (Get-ObjectPropertyValue -InputObject $localRepo -PropertyName 'headCommitSha' -Default ''))
                        $headCommitDate = [string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'headCommitDate' -Default (Get-ObjectPropertyValue -InputObject $localRepo -PropertyName 'lastCommitDate' -Default ''))
                        $headBranch = [string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'headBranch' -Default (Get-ObjectPropertyValue -InputObject $localRepo -PropertyName 'branch' -Default (Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'branch' -Default '')))
                        $currentMetadataHash = [string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'currentMetadataHash' -Default '')
                        if ([string]::IsNullOrWhiteSpace($currentMetadataHash) -and $sourceCoverage -ne 'none') {
                            $currentMetadataHash = Get-PortfolioScanFingerprintFromSignals -LocalRepo $localRepo -GitHubRepo $githubRepo -LocalPath $localPath -SourceCoverage $sourceCoverage
                        }

                        $assessment | Add-Member -NotePropertyName headCommitSha -NotePropertyValue $(if ([string]::IsNullOrWhiteSpace($headCommitSha)) { $null } else { $headCommitSha }) -Force
                        $assessment | Add-Member -NotePropertyName headCommitDate -NotePropertyValue $(if ([string]::IsNullOrWhiteSpace($headCommitDate)) { $null } else { $headCommitDate }) -Force
                        $assessment | Add-Member -NotePropertyName headBranch -NotePropertyValue $(if ([string]::IsNullOrWhiteSpace($headBranch)) { $null } else { $headBranch }) -Force
                        $assessment | Add-Member -NotePropertyName currentMetadataHash -NotePropertyValue $(if ([string]::IsNullOrWhiteSpace($currentMetadataHash)) { $null } else { $currentMetadataHash }) -Force

                        if ([string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'lastIndexedCommitSha' -Default ''))) {
                            $assessment | Add-Member -NotePropertyName lastIndexedCommitSha -NotePropertyValue $(if ([string]::IsNullOrWhiteSpace($headCommitSha)) { $null } else { $headCommitSha }) -Force
                        }
                        if ([string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'lastIndexedCommitDate' -Default ''))) {
                            $assessment | Add-Member -NotePropertyName lastIndexedCommitDate -NotePropertyValue $(if ([string]::IsNullOrWhiteSpace($headCommitDate)) { $null } else { $headCommitDate }) -Force
                        }
                        if ([string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'lastIndexedBranch' -Default ''))) {
                            $assessment | Add-Member -NotePropertyName lastIndexedBranch -NotePropertyValue $(if ([string]::IsNullOrWhiteSpace($headBranch)) { $null } else { $headBranch }) -Force
                        }
                        if ([string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'lastMetadataHash' -Default ''))) {
                            $assessment | Add-Member -NotePropertyName lastMetadataHash -NotePropertyValue $(if ([string]::IsNullOrWhiteSpace($currentMetadataHash)) { $null } else { $currentMetadataHash }) -Force
                        }
                        if ([string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'lastScanStatus' -Default ''))) {
                            $assessment | Add-Member -NotePropertyName lastScanStatus -NotePropertyValue 'ok' -Force
                        }
                        if ([string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue -InputObject $assessment -PropertyName 'lastScannedAt' -Default ''))) {
                            $assessment | Add-Member -NotePropertyName lastScannedAt -NotePropertyValue $null -Force
                        }
                    }

                    $assessments = @($assessments | Sort-Object `
                        @{ Expression = { [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '') }; Ascending = $true },
                        @{ Expression = { [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'sourceCoverage' -Default '') }; Ascending = $true })

                    if ($includeCuration) {
                        $assessments = Add-PortfolioCurationToAssessments -Assessments $assessments
                    }

                    $summary = Get-PortfolioAssessmentSummary -Assessments $assessments
                    $generatedAt = (Get-Date).ToUniversalTime().ToString('o')
                    $scanId = [guid]::NewGuid().ToString('n')

                    try {
                        $snapshotResult = Write-AppDbPortfolioAssessmentSnapshot -Assessments $assessments -ScanId $scanId -CapturedAt $generatedAt
                        if (-not $snapshotResult.success) {
                            Write-HostLog ("WARN portfolio.assessment persistence snapshot skipped: {0}" -f $snapshotResult.reason)
                        }
                    } catch {
                        Write-HostLog ("WARN portfolio.assessment persistence snapshot failed: {0}" -f $_.Exception.Message)
                    }

                    try {
                        $changedRepoNames = if ($useDifferentialScan) {
                            @($differentialChangedSet | ForEach-Object { [string]$_ })
                        } else {
                            @($assessments | ForEach-Object { [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        }
                        $scanSummaryResult = Write-AppDbDifferentialScanSnapshot `
                            -ScanId $scanId `
                            -ScanMode $(if ($useDifferentialScan) { 'differential' } else { 'full' }) `
                            -StartedAt ($requestStart.ToUniversalTime().ToString('o')) `
                            -CompletedAt $generatedAt `
                            -ReposTotal @($assessments).Count `
                            -ReposChanged $(if ($useDifferentialScan) { $differentialChangedSet.Count } else { @($assessments).Count }) `
                            -ChangedRepoNames $changedRepoNames
                        if (-not $scanSummaryResult.success) {
                            Write-HostLog ("WARN portfolio.assessment differential snapshot skipped: {0}" -f $scanSummaryResult.reason)
                        }
                    } catch {
                        Write-HostLog ("WARN portfolio.assessment differential snapshot failed: {0}" -f $_.Exception.Message)
                    }

                    $swIndex = [System.Diagnostics.Stopwatch]::StartNew()
                    try {
                        $curationMap = Get-PortfolioCurationMap -WorkspaceRoot $WorkspaceRoot
                        $indexArtifacts = Save-PortfolioIndexArtifacts `
                            -WorkspaceRoot $WorkspaceRoot `
                            -Assessments $assessments `
                            -LocalRepos $localRepos `
                            -GitHubRepos $githubReposForAssessment `
                            -Summary $summary `
                            -SignalSources $signalSources `
                            -CurationByRepoId $curationMap `
                            -GeneratedAt $generatedAt
                        Write-HostLog ("[TRACE] portfolio.assessment index-written path={0} artifact={1} count={2}" -f $indexArtifacts.indexPath, $indexArtifacts.artifactPath, $indexArtifacts.repoCount)
                    } catch {
                        Write-HostLog ("WARN portfolio.assessment index write skipped: {0}" -f $_.Exception.Message)
                    }
                    $swIndex.Stop()

                    if ($ttlSeconds -gt 0) {
                        Save-PortfolioAssessmentCache -Entries $assessments -Summary $summary -SignalSources $signalSources -GeneratedAt $generatedAt
                    }

                    $scanSummary.durationMs = [int]((Get-Date) - $requestStart).TotalMilliseconds

                    # Release 2.3 Phase 5F observability: one greppable line per scan
                    # proving how many repos were reused from cache vs fully reindexed.
                    $scanSummaryMode = if ($useDifferentialScan) { 'differential' } elseif ($refresh) { $(if ($forcedRefreshAll) { 'forced-refresh-all' } else { 'forced-full' }) } else { 'full' }
                    Write-HostLog ("[TRACE] portfolio.assessment scan-summary correlationId={0} mode={1} reused={2} reindexed={3} failed={4} durationMs={5}" -f $correlationId, $scanSummaryMode, $scanSummary.reused, $scanSummary.reindexed, $scanSummary.failed, $scanSummary.durationMs)
                    # Cross-cutting — per-phase scan performance budget log.
                    Write-HostLog ("[TRACE] portfolio.assessment scan-budget correlationId={0} prepMs={1} assessMs={2} indexWriteMs={3} totalMs={4} reposAssessed={5}" -f $correlationId, $scanBudgetPrepMs, [int]$swAssess.ElapsedMilliseconds, [int]$swIndex.ElapsedMilliseconds, $scanSummary.durationMs, @($assessments).Count)

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] portfolio.assessment correlationId={0} done count={1} ready={2} blocked={3} durationMs={4}" -f $correlationId, @($assessments).Count, $summary.readyForWorkCount, $summary.blockedCount, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                    $readBudget = New-PortfolioReadBudgetResult -CacheSource 'fresh-scan' `
                        -MeasuredMs ([double]((Get-Date) - $requestStart).TotalMilliseconds) -Settings $settings
                    Write-HostLog (Format-PortfolioReadBudgetLog -Result $readBudget -CorrelationId $correlationId -Route '/api/portfolio/assessment')
                    if (-not $readBudget.withinBudget) {
                        Write-HostLog ("WARN portfolio.assessment read budget exceeded correlationId={0} class={1} measuredMs={2} budgetMs={3} overByMs={4}" -f $correlationId, $readBudget.readClass, $readBudget.measuredMs, $readBudget.budgetMs, $readBudget.overByMs)
                    }
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            entries         = $assessments
                            summary         = $summary
                            signalSources   = $signalSources
                            generatedAt     = $generatedAt
                            count           = @($assessments).Count
                            cacheSource     = 'fresh-scan'
                            cacheAgeSeconds = 0
                            scanSummary     = $scanSummary
                            performance     = $readBudget
                        }
                    }
                }
                'GET /api/portfolio/trend' {
                    Write-HostLog ("[TRACE] portfolio.trend correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $requestedDays = if ($q.ContainsKey('days') -and $q.days -match '^\d+$') { [int]$q.days } else { 90 }
                    if ($requestedDays -lt 7) { $requestedDays = 7 }
                    if ($requestedDays -gt 180) { $requestedDays = 180 }

                    $settings = Get-HostSettings
                    $trendSeed = Get-PortfolioTrendSeedPayload -Settings $settings
                    if (-not $trendSeed.available) {
                        Write-HostLog ("WARN portfolio.trend correlationId={0} no seed payload available" -f $correlationId)
                        Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = $trendSeed.error
                        }
                        break
                    }

                    try {
                        $trendPayload = Get-PortfolioTrendPayload `
                            -Assessments @($trendSeed.entries) `
                            -Summary $trendSeed.summary `
                            -GeneratedAt ([string]$trendSeed.generatedAt) `
                            -SeedSource ([string]$trendSeed.seedSource) `
                            -WorkspaceRoot $WorkspaceRoot `
                            -RequestedDays $requestedDays

                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] portfolio.trend correlationId={0} done status={1} seed={2} availableDays={3}" -f $correlationId, $trendPayload.trendStatus, $trendPayload.seedSource, $trendPayload.availableDays)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = $trendPayload
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'portfolio.trend'
                    }
                }
                'GET /api/operations/repos' {
                    Write-HostLog ("[TRACE] operations.repos correlationId={0} start" -f $correlationId)

                    $settings = Get-HostSettings
                    $opsPayload = Get-OperationsReposPayload -Settings $settings
                    if (-not $opsPayload.available) {
                        Write-HostLog ("WARN operations.repos correlationId={0} index unavailable and no cached assessment was found" -f $correlationId)
                        Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = $opsPayload.error
                        }
                        break
                    }

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] operations.repos correlationId={0} done source={1} count={2} durationMs={3}" -f $correlationId, $opsPayload.cacheSource, @($opsPayload.entries).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                    $readBudget = New-PortfolioReadBudgetResult -CacheSource ([string]$opsPayload.cacheSource) `
                        -MeasuredMs ([double]((Get-Date) - $requestStart).TotalMilliseconds) -Settings $settings
                    Write-HostLog (Format-PortfolioReadBudgetLog -Result $readBudget -CorrelationId $correlationId -Route '/api/operations/repos')
                    if (-not $readBudget.withinBudget) {
                        Write-HostLog ("WARN operations.repos read budget exceeded correlationId={0} class={1} measuredMs={2} budgetMs={3} overByMs={4}" -f $correlationId, $readBudget.readClass, $readBudget.measuredMs, $readBudget.budgetMs, $readBudget.overByMs)
                    }
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            entries = @($opsPayload.entries)
                            generatedAt = $opsPayload.generatedAt
                            count = $opsPayload.count
                            cacheSource = $opsPayload.cacheSource
                            summary = $opsPayload.summary
                            performance = $readBudget
                        }
                    }
                }
                'POST /api/copilot-task/preview' {
                    Write-HostLog ("[TRACE] copilot-task.preview correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $repoName = if ($body.ContainsKey('repoName') -and $body.repoName) { [string]$body.repoName } else { '' }
                    $roadmapPath = if ($body.ContainsKey('roadmapPath') -and $body.roadmapPath) { [string]$body.roadmapPath } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error   = 'repoName is required for /api/copilot-task/preview'
                        }
                        break
                    }

                    # Look up doc audit entry from cache (no-TTL miss is acceptable; null → packet built without findings)
                    $settings   = Get-HostSettings
                    $auditTtl   = Get-DocAuditCacheTtlSeconds -Settings $settings
                    $auditCache = Get-DocAuditFromCache -TtlSeconds $auditTtl
                    $auditEntry = $null
                    if ($auditCache.hit -and $auditCache.entries) {
                        $auditEntry = @($auditCache.entries) | Where-Object {
                            $n = if ($_ -is [System.Collections.IDictionary]) { [string]$_['repoName'] } else { [string]$_.repoName }
                            $n -eq $repoName
                        } | Select-Object -First 1
                    }

                    $assessmentEntry = Find-PortfolioAssessmentEntry -RepoName $repoName -Settings $settings

                    $packet = Build-CopilotTaskPacket -RepoName $repoName -RoadmapPath $roadmapPath -AuditEntry $auditEntry -AssessmentEntry $assessmentEntry
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] copilot-task.preview correlationId={0} done repoName={1} runId={2}" -f $correlationId, $repoName, $packet.runId)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = $packet
                    }
                }
                'POST /api/operations/prompt/refine' {
                    Write-HostLog ("[TRACE] operations.prompt.refine correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $repoName = if ($body.ContainsKey('repoName') -and $body.repoName) { [string]$body.repoName } else { '' }
                    $roadmapPath = if ($body.ContainsKey('roadmapPath') -and $body.roadmapPath) { [string]$body.roadmapPath } else { '' }
                    $selectedTaskText = if ($body.ContainsKey('selectedTaskText') -and $body.selectedTaskText) { [string]$body.selectedTaskText } else { '' }
                    $selectedTaskSection = if ($body.ContainsKey('selectedTaskSection') -and $body.selectedTaskSection) { [string]$body.selectedTaskSection } else { '' }
                    $additionalConstraints = if ($body.ContainsKey('additionalConstraints')) { @($body.additionalConstraints) } else { @() }
                    $emphasisAreas = if ($body.ContainsKey('emphasisAreas')) { @($body.emphasisAreas) } else { @() }
                    $operatorInstructions = if ($body.ContainsKey('operatorInstructions') -and $body.operatorInstructions) { [string]$body.operatorInstructions } else { '' }

                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = 'repoName is required for /api/operations/prompt/refine'
                        }
                        break
                    }

                    $settings = Get-HostSettings
                    $auditTtl = Get-DocAuditCacheTtlSeconds -Settings $settings
                    $auditCache = Get-DocAuditFromCache -TtlSeconds $auditTtl
                    $auditEntry = $null
                    if ($auditCache.hit -and $auditCache.entries) {
                        $auditEntry = @($auditCache.entries) | Where-Object {
                            $n = if ($_ -is [System.Collections.IDictionary]) { [string]$_['repoName'] } else { [string]$_.repoName }
                            $n -eq $repoName
                        } | Select-Object -First 1
                    }

                    $assessmentEntry = Find-PortfolioAssessmentEntry -RepoName $repoName -Settings $settings

                    $result = Invoke-OperationsPromptRefine `
                        -RepoName $repoName `
                        -RoadmapPath $roadmapPath `
                        -SelectedTaskText $selectedTaskText `
                        -SelectedTaskSection $selectedTaskSection `
                        -AdditionalConstraints @($additionalConstraints) `
                        -EmphasisAreas @($emphasisAreas) `
                        -OperatorInstructions $operatorInstructions `
                        -AuditEntry $auditEntry `
                        -AssessmentEntry $assessmentEntry

                    $refineRecord = Write-OperationsPromptRefinementHistory -RepoName $repoName -Result $result
                    $result.runId = $refineRecord.runId
                    $result.createdAt = $refineRecord.createdAt

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] operations.prompt.refine correlationId={0} done repoName={1} runId={2} warnings={3}" -f $correlationId, $repoName, $refineRecord.runId, @($result.warnings).Count)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $result
                    }
                }
                'GET /api/copilot-task/history' {
                    $q     = Parse-QueryString -Query $req.Query
                    $limit = if ($q.ContainsKey('limit') -and $q.limit) { [int]$q.limit } else { 25 }
                    $rawItems = Get-RoadmapTaskHistory -Limit $limit

                    $items = @($rawItems | ForEach-Object {
                        @{
                            runId       = [string]$_.runId
                            status      = [string]$_.status
                            repoName    = [string]$_.repository
                            roadmapItem = [string]$_.selectedTask
                            roadmapPath = [string]$_.roadmapPath
                            startedAt   = [string]$_.startedAt
                            completedAt = [string]$_.completedAt
                            error       = [string]$_.error
                            summaryPath = [string]$_.summaryPath
                        }
                    })

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            items = $items
                            count = @($items).Count
                        }
                    }
                }
                'GET /api/roadmap/maturity-history' {
                    try {
                        $q = Parse-QueryString -Query $req.Query
                        $repoName = if ($q.ContainsKey('repoName')) { [string]$q.repoName } else { '' }
                        $days = if ($q.ContainsKey('days') -and $q.days) { [int]$q.days } else { 30 }
                        if ($days -lt 1) { $days = 1 }
                        if ($days -gt 3650) { $days = 3650 }

                        $history = Get-AppDbRoadmapMaturityHistory -RepoName $repoName -Days $days
                        if ($history.available) {
                            Add-MetricCounter -Name 'api_requests_total'
                            Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                success = $true
                                data = @($history.entries)
                                count = @($history.entries).Count
                                source = 'sqlite'
                            }
                            break
                        }

                        $auditCache = Get-RoadmapAuditFromCache -TtlSeconds 86400
                        $fallbackEntries = @()
                        if ($auditCache.hit) {
                            $fallbackEntries = @($auditCache.entries | Where-Object {
                                $name = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')
                                [string]::IsNullOrWhiteSpace($repoName) -or $name -eq $repoName
                            } | ForEach-Object {
                                [pscustomobject]@{
                                    repoName      = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')
                                    roadmapPath   = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'roadmapPath' -Default '')
                                    maturityLevel = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'maturityLevel' -Default '')
                                    maturityScore = [double](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'maturityScore' -Default 0)
                                    pendingCount  = [int](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'pendingCount' -Default 0)
                                    capturedAt    = [string]$auditCache.auditedAt
                                }
                            })
                        }

                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @($fallbackEntries)
                            count = @($fallbackEntries).Count
                            source = if ($auditCache.hit) { 'roadmap-audit-cache' } else { 'none' }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.maturity-history'
                    }
                }
                'GET /api/cache/diagnostics' {
                    # Cross-cutting — stale-cache diagnostics across the index-backed
                    # views (status / roadmap / roadmap-audit / doc-audit / index).
                    Add-MetricCounter -Name 'api_requests_total'
                    $settings = Get-HostSettings
                    $roadmapTtl = Get-RoadmapCacheTtlSeconds -Settings $settings
                    $caches = @{
                        status         = Get-CacheDiagnosticEntry -Path (Get-StatusCacheFilePath) -TtlSeconds (Get-StatusCacheTtlSeconds -Settings $settings)
                        roadmap        = Get-CacheDiagnosticEntry -Path (Get-RoadmapCacheFilePath) -TtlSeconds $roadmapTtl
                        roadmapAudit   = Get-CacheDiagnosticEntry -Path (Get-RoadmapAuditCacheFilePath) -TtlSeconds $roadmapTtl
                        docAudit       = Get-CacheDiagnosticEntry -Path (Get-DocAuditCacheFilePath) -TtlSeconds $roadmapTtl
                        portfolioIndex = Get-CacheDiagnosticEntry -Path (Join-Path $WorkspaceRoot 'output\index\repos.index.json') -TtlSeconds 0
                    }
                    $staleCount = @($caches.Values | Where-Object { $_.stale }).Count
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{ caches = $caches; staleCount = $staleCount; generatedAt = (Get-Date).ToUniversalTime().ToString('o') }
                    }
                }
                'GET /api/analytics/cost' {
                    # Release 2.3 Phase 4 — report-time cost/burn analytics DERIVED
                    # from run observations. Never persisted back into the
                    # append-only event log (derivedOnly=true).
                    $q = Parse-QueryString -Query $req.Query
                    $days = if ($q.ContainsKey('days') -and $q.days) { [int]$q.days } else { 30 }
                    if ($days -lt 1) { $days = 1 }
                    if ($days -gt 3650) { $days = 3650 }
                    $agentRunsJsonDir = Join-Path $WorkspaceRoot 'output\agent-runs\runs'
                    $history = Get-AppDbAgentRunMetricsHistory -RepoName '' -Days $days -SeedFromRunsDirectory $agentRunsJsonDir
                    $entries = if ($history.available) { @($history.entries) } else { @() }
                    $byRepo = [System.Collections.Generic.List[object]]::new()
                    foreach ($grp in ($entries | Group-Object -Property repoName)) {
                        $cost = 0.0; $tokens = 0
                        foreach ($e in $grp.Group) {
                            $cost += [double](Get-ValueOrDefault $e.directCostUsd 0)
                            $tokens += [int](Get-ValueOrDefault $e.tokensReported 0)
                        }
                        $byRepo.Add([pscustomobject]@{ repoName = [string]$grp.Name; runCount = $grp.Count; totalCostUsd = [math]::Round($cost, 4); totalTokens = $tokens })
                    }
                    $byPhase = [System.Collections.Generic.List[object]]::new()
                    foreach ($grp in ($entries | Group-Object -Property { ("{0} / {1}" -f [string]$_.releaseName, [string]$_.phaseName) })) {
                        $cost = 0.0
                        foreach ($e in $grp.Group) { $cost += [double](Get-ValueOrDefault $e.directCostUsd 0) }
                        $byPhase.Add([pscustomobject]@{ phase = [string]$grp.Name; runCount = $grp.Count; costUsd = [math]::Round($cost, 4) })
                    }
                    $burn = Get-AppDbQuotaBurnHistory -RepoName '' -Days $days
                    $starvationCount = 0
                    if ($burn.available) { $starvationCount = @($burn.entries | Where-Object { -not [bool]$_.allowed }).Count }
                    $totalCost = 0.0
                    foreach ($e in $entries) { $totalCost += [double](Get-ValueOrDefault $e.directCostUsd 0) }
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            days            = $days
                            totalCostUsd    = [math]::Round($totalCost, 4)
                            runCount        = @($entries).Count
                            starvationCount = $starvationCount
                            byRepo          = $byRepo.ToArray()
                            byPhase         = $byPhase.ToArray()
                            derivedOnly     = $true
                            generatedAt     = (Get-Date).ToUniversalTime().ToString('o')
                        }
                        source = if ($history.available) { 'sqlite' } else { 'unavailable' }
                    }
                }
                'GET /api/agent-runs/metrics-history' {
                    try {
                        $q = Parse-QueryString -Query $req.Query
                        $repoName = if ($q.ContainsKey('repoName')) { [string]$q.repoName } else { '' }
                        $days = if ($q.ContainsKey('days') -and $q.days) { [int]$q.days } else { 30 }
                        if ($days -lt 1) { $days = 1 }
                        if ($days -gt 3650) { $days = 3650 }

                        $agentRunsJsonDir = Join-Path $WorkspaceRoot 'output\agent-runs\runs'
                        $history = Get-AppDbAgentRunMetricsHistory -RepoName $repoName -Days $days -SeedFromRunsDirectory $agentRunsJsonDir
                        if ($history.available) {
                            Add-MetricCounter -Name 'api_requests_total'
                            Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                success = $true
                                data = @($history.entries)
                                count = @($history.entries).Count
                                source = 'sqlite'
                            }
                            break
                        }

                        # SQLite unavailable: serve the same contract straight from the
                        # authoritative JSON runs ledger. _AppDbIsoTimestamp keeps the
                        # timestamps sortable regardless of string/[datetime] shape.
                        $sinceIso = (Get-Date).ToUniversalTime().AddDays(-$days).ToString('o')
                        $fallbackEntries = @(Get-AgentRuns -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -Limit 1000 | ForEach-Object {
                            $runMetrics = Get-ObjectPropertyValue -InputObject $_ -PropertyName 'metrics' -Default $null
                            if ($null -eq $runMetrics) { $runMetrics = [pscustomobject]@{} }
                            [pscustomobject]@{
                                runId                = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'runId' -Default '')
                                repoName             = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '')
                                status               = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'status' -Default '')
                                dispatchedAt         = _AppDbIsoTimestamp -Value (Get-ObjectPropertyValue -InputObject $runMetrics -PropertyName 'dispatchedAt' -Default $null)
                                startedAt            = _AppDbIsoTimestamp -Value (Get-ObjectPropertyValue -InputObject $runMetrics -PropertyName 'agentStartedAt' -Default $null)
                                completedAt          = _AppDbIsoTimestamp -Value (Get-ObjectPropertyValue -InputObject $runMetrics -PropertyName 'agentCompletedAt' -Default $null)
                                timeToDeliverSeconds = Get-ObjectPropertyValue -InputObject $runMetrics -PropertyName 'timeToDeliverSeconds' -Default $null
                                promptCount          = Get-ObjectPropertyValue -InputObject $runMetrics -PropertyName 'promptCount' -Default $null
                                retryCount           = Get-ObjectPropertyValue -InputObject $runMetrics -PropertyName 'retries' -Default $null
                                tokensReported       = Get-ObjectPropertyValue -InputObject $runMetrics -PropertyName 'tokenUsage' -Default $null
                                directCostUsd        = Get-ObjectPropertyValue -InputObject $runMetrics -PropertyName 'apiSpendUsd' -Default $null
                                workUnitsEstimated   = Get-ObjectPropertyValue -InputObject $runMetrics -PropertyName 'workUnitsEstimated' -Default $null
                                workUnitsActual      = Get-ObjectPropertyValue -InputObject $runMetrics -PropertyName 'workUnitsActual' -Default $null
                                releaseName          = Get-ObjectPropertyValue -InputObject $_ -PropertyName 'plannedReleaseName' -Default $null
                                phaseName            = Get-ObjectPropertyValue -InputObject $_ -PropertyName 'plannedPhaseName' -Default $null
                                sectionName          = Get-ObjectPropertyValue -InputObject $_ -PropertyName 'selectedTaskSection' -Default $null
                                updatedAt            = _AppDbIsoTimestamp -Value (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'updatedAt' -Default $null)
                            }
                        } | Where-Object {
                            $ts = [string]$_.dispatchedAt
                            [string]::IsNullOrWhiteSpace($ts) -or ([string]::CompareOrdinal($ts, $sinceIso) -ge 0)
                        } | Sort-Object { [string]$_.dispatchedAt })

                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @($fallbackEntries)
                            count = @($fallbackEntries).Count
                            source = 'agent-runs-json'
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'agent-runs.metrics-history'
                    }
                }
                'GET /api/agent-runs/quota-burn-history' {
                    try {
                        $q = Parse-QueryString -Query $req.Query
                        $repoName = if ($q.ContainsKey('repoName')) { [string]$q.repoName } else { '' }
                        $days = if ($q.ContainsKey('days') -and $q.days) { [int]$q.days } else { 30 }
                        if ($days -lt 1) { $days = 1 }
                        if ($days -gt 3650) { $days = 3650 }

                        $history = Get-AppDbQuotaBurnHistory -RepoName $repoName -Days $days
                        # Quota-burn snapshots exist only in SQLite; without a provider the
                        # raw quota.* JSONL events remain the debugging artifact, so the
                        # fallback is truthfully empty rather than synthesized.
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @($history.entries)
                            count = @($history.entries).Count
                            source = if ($history.available) { 'sqlite' } else { 'none' }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'agent-runs.quota-burn-history'
                    }
                }
                'GET /api/operations/prompt/history' {
                    Write-HostLog ("[TRACE] operations.prompt.history correlationId={0} start" -f $correlationId)
                    $q        = Parse-QueryString -Query $req.Query
                    $repoName = if ($q.ContainsKey('repoName') -and $q.repoName) { [string]$q.repoName } else { '' }
                    $limit    = if ($q.ContainsKey('limit') -and $q.limit) { [int]$q.limit } else { 20 }

                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error   = 'repoName query parameter is required for /api/operations/prompt/history'
                        }
                        break
                    }

                    $items = @(Get-OperationsPromptRefinementHistory -RepoName $repoName -Limit $limit)

                    Add-MetricCounter -Name 'api_requests_total'
                    Write-HostLog ("[TRACE] operations.prompt.history correlationId={0} done repoName={1} count={2}" -f $correlationId, $repoName, @($items).Count)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            repoName = $repoName
                            items    = @($items)
                            count    = @($items).Count
                        }
                    }
                }
                'POST /api/ai/docs/improve/preview' {
                    Write-HostLog ("[TRACE] ai.docs.improve.preview correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $repoName     = if ($body.ContainsKey('repoName') -and $body.repoName) { [string]$body.repoName } else { '' }
                    $docTypeRaw   = if ($body.ContainsKey('docType') -and $body.docType) { ([string]$body.docType).ToLowerInvariant() } else { 'readme' }
                    $docType      = if ($docTypeRaw -eq 'roadmap') { 'roadmap' } else { 'readme' }
                    $templateId   = if ($body.ContainsKey('templateId') -and $body.templateId) { [string]$body.templateId } else { '' }
                    $customPrompt = if ($body.ContainsKey('customPrompt') -and $body.customPrompt) { [string]$body.customPrompt } else { '' }
                    $provider     = if ($body.ContainsKey('provider') -and $body.provider) { [string]$body.provider } else { '' }
                    $currentContent = if ($body.ContainsKey('currentContent') -and $null -ne $body.currentContent) { [string]$body.currentContent } else { '' }
                    $requestedPath  = if ($body.ContainsKey('path') -and $body.path) { [string]$body.path } else { '' }

                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error   = 'repoName is required for /api/ai/docs/improve/preview'
                        }
                        break
                    }

                    $settings = Get-HostSettings

                    # Resolve current content when the caller did not supply it inline.
                    if ([string]::IsNullOrWhiteSpace($currentContent)) {
                        $targetPath = $requestedPath
                        $docFileName = if ($docType -eq 'roadmap') { 'ROADMAP.md' } else { 'README.md' }

                        if ([string]::IsNullOrWhiteSpace($targetPath) -and $docType -eq 'roadmap') {
                            $roadmapTtl   = Get-RoadmapCacheTtlSeconds -Settings $settings
                            $roadmapCache = Get-RoadmapFromCache -TtlSeconds $roadmapTtl
                            if ($roadmapCache.hit -and $roadmapCache.entries) {
                                $rEntry = @($roadmapCache.entries) | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1
                                if ($null -ne $rEntry) {
                                    $rp = if ($rEntry -is [System.Collections.IDictionary]) { [string]$rEntry['roadmapPath'] } else { [string]$rEntry.roadmapPath }
                                    if (-not [string]::IsNullOrWhiteSpace($rp)) { $targetPath = $rp }
                                }
                            }
                        }

                        if ([string]::IsNullOrWhiteSpace($targetPath)) {
                            $indexPayload = Get-PortfolioIndexPayload -WorkspaceRoot $WorkspaceRoot
                            if ($null -ne $indexPayload -and ($indexPayload.PSObject.Properties.Name -contains 'repos')) {
                                $indexMatch = @($indexPayload.repos | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1)
                                if ($indexMatch.Count -gt 0) {
                                    $localPath = [string](Get-ObjectPropertyValue -InputObject $indexMatch[0] -PropertyName 'localPath' -Default '')
                                    if (-not [string]::IsNullOrWhiteSpace($localPath)) {
                                        $candidatePath = Join-Path $localPath $docFileName
                                        if (Test-Path -LiteralPath $candidatePath) { $targetPath = $candidatePath }
                                    }
                                }
                            }
                        }

                        if (-not [string]::IsNullOrWhiteSpace($targetPath) -and (Test-Path -LiteralPath $targetPath)) {
                            try {
                                $currentContent = Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8 -ErrorAction Stop
                            } catch {
                                $currentContent = ''
                            }
                        }
                    }

                    $preview = Invoke-AiDocImprovePreview `
                        -WorkspaceRoot $WorkspaceRoot `
                        -RepoName $repoName `
                        -DocType $docType `
                        -CurrentContent $currentContent `
                        -TemplateId $templateId `
                        -CustomPrompt $customPrompt `
                        -Provider $provider `
                        -Settings $settings

                    $null = Write-AiDocImprovementHistory -WorkspaceRoot $WorkspaceRoot -Preview $preview

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] ai.docs.improve.preview correlationId={0} done repoName={1} docType={2} provider={3} scoreDelta={4}" -f $correlationId, $repoName, $docType, $preview.providerId, $preview.estimatedScore.delta)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = $preview
                    }
                }
                'GET /api/ai/docs/improve/history' {
                    Write-HostLog ("[TRACE] ai.docs.improve.history correlationId={0} start" -f $correlationId)
                    $q        = Parse-QueryString -Query $req.Query
                    $repoName = if ($q.ContainsKey('repoName') -and $q.repoName) { [System.Uri]::UnescapeDataString([string]$q.repoName) } else { '' }
                    $docType  = if ($q.ContainsKey('docType') -and $q.docType) { ([string]$q.docType).ToLowerInvariant() } else { '' }
                    $limit    = if ($q.ContainsKey('limit') -and $q.limit) { [int]$q.limit } else { 20 }

                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error   = 'repoName query parameter is required for /api/ai/docs/improve/history'
                        }
                        break
                    }

                    $items = @(Get-AiDocImprovementHistory -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -DocType $docType -Limit $limit)

                    Add-MetricCounter -Name 'api_requests_total'
                    Write-HostLog ("[TRACE] ai.docs.improve.history correlationId={0} done repoName={1} count={2}" -f $correlationId, $repoName, @($items).Count)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            repoName = $repoName
                            items    = @($items)
                            count    = @($items).Count
                        }
                    }
                }
                'POST /api/ai/docs/improve/apply' {
                    Write-HostLog ("[TRACE] ai.docs.improve.apply correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $repoName        = if ($body.ContainsKey('repoName') -and $body.repoName) { [string]$body.repoName } else { '' }
                    $docTypeRaw      = if ($body.ContainsKey('docType') -and $body.docType) { ([string]$body.docType).ToLowerInvariant() } else { 'readme' }
                    $docType         = if ($docTypeRaw -eq 'roadmap') { 'roadmap' } else { 'readme' }
                    $previewId       = if ($body.ContainsKey('previewId') -and $body.previewId) { [string]$body.previewId } else { '' }
                    $proposedContent = if ($body.ContainsKey('proposedContent') -and $null -ne $body.proposedContent) { [string]$body.proposedContent } else { '' }
                    $requestedPath   = if ($body.ContainsKey('path') -and $body.path) { [string]$body.path } else { '' }

                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error   = 'repoName is required for /api/ai/docs/improve/apply'
                        }
                        break
                    }
                    if ([string]::IsNullOrWhiteSpace($proposedContent)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error   = 'proposedContent is required for /api/ai/docs/improve/apply — apply writes only operator-approved content'
                        }
                        break
                    }

                    $settings = Get-HostSettings

                    # Resolve the target file the same way the preview route resolves
                    # current content: explicit path, then roadmap cache, then index.
                    $targetPath = $requestedPath
                    $docFileName = if ($docType -eq 'roadmap') { 'ROADMAP.md' } else { 'README.md' }

                    if ([string]::IsNullOrWhiteSpace($targetPath) -and $docType -eq 'roadmap') {
                        $roadmapTtl   = Get-RoadmapCacheTtlSeconds -Settings $settings
                        $roadmapCache = Get-RoadmapFromCache -TtlSeconds $roadmapTtl
                        if ($roadmapCache.hit -and $roadmapCache.entries) {
                            $rEntry = @($roadmapCache.entries) | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1
                            if ($null -ne $rEntry) {
                                $rp = if ($rEntry -is [System.Collections.IDictionary]) { [string]$rEntry['roadmapPath'] } else { [string]$rEntry.roadmapPath }
                                if (-not [string]::IsNullOrWhiteSpace($rp)) { $targetPath = $rp }
                            }
                        }
                    }

                    if ([string]::IsNullOrWhiteSpace($targetPath)) {
                        $indexPayload = Get-PortfolioIndexPayload -WorkspaceRoot $WorkspaceRoot
                        if ($null -ne $indexPayload -and ($indexPayload.PSObject.Properties.Name -contains 'repos')) {
                            $indexMatch = @($indexPayload.repos | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1)
                            if ($indexMatch.Count -gt 0) {
                                $localPath = [string](Get-ObjectPropertyValue -InputObject $indexMatch[0] -PropertyName 'localPath' -Default '')
                                if (-not [string]::IsNullOrWhiteSpace($localPath) -and (Test-Path -LiteralPath $localPath -PathType Container)) {
                                    $targetPath = Join-Path $localPath $docFileName
                                }
                            }
                        }
                    }

                    if ([string]::IsNullOrWhiteSpace($targetPath)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error   = "Could not resolve a $docFileName target path for repo '$repoName'. Supply an explicit 'path' or run a portfolio scan first."
                        }
                        break
                    }

                    try {
                        $applyResult = Invoke-AiDocImproveApply `
                            -WorkspaceRoot $WorkspaceRoot `
                            -RepoName $repoName `
                            -TargetPath $targetPath `
                            -ProposedContent $proposedContent `
                            -DocType $docType `
                            -PreviewId $previewId
                    } catch {
                        Write-HostLog ("[WARN ] ai.docs.improve.apply correlationId={0} failed repoName={1} docType={2} error={3}" -f $correlationId, $repoName, $docType, $_.Exception.Message)
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error   = "Apply failed: $($_.Exception.Message)"
                        }
                        break
                    }

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] ai.docs.improve.apply correlationId={0} done repoName={1} docType={2} target={3} backup={4}" -f $correlationId, $repoName, $docType, $applyResult.targetPath, $applyResult.backupPath)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = $applyResult
                    }
                }
                'GET /api/agent-runs' {
                    Write-HostLog ("[TRACE] agent-runs.list correlationId={0} start" -f $correlationId)
                    $q        = Parse-QueryString -Query $req.Query
                    $statusFilter = if ($q.ContainsKey('status') -and $q.status) { [string]$q.status } else { '' }
                    $repoFilter   = if ($q.ContainsKey('repoName') -and $q.repoName) { [System.Uri]::UnescapeDataString([string]$q.repoName) } else { '' }
                    $limit        = if ($q.ContainsKey('limit') -and $q.limit) { [int]$q.limit } else { 50 }

                    $runs = @(Get-AgentRuns -WorkspaceRoot $WorkspaceRoot -Status $statusFilter -RepoName $repoFilter -Limit $limit)

                    $byStatus = @{}
                    foreach ($run in $runs) {
                        $s = [string](Get-ObjectPropertyValue -InputObject $run -PropertyName 'status' -Default 'unknown')
                        if (-not $byStatus.ContainsKey($s)) { $byStatus[$s] = 0 }
                        $byStatus[$s] = [int]$byStatus[$s] + 1
                    }

                    Add-MetricCounter -Name 'api_requests_total'
                    Write-HostLog ("[TRACE] agent-runs.list correlationId={0} done count={1}" -f $correlationId, @($runs).Count)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            items    = @($runs)
                            count    = @($runs).Count
                            byStatus = $byStatus
                        }
                    }
                }
                'GET /api/ai/docs/templates' {
                    $templates = Get-AiDocTemplates -WorkspaceRoot $WorkspaceRoot
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            readmeTemplates  = @(Get-ObjectPropertyValue -InputObject $templates -PropertyName 'readmeTemplates' -Default @())
                            roadmapTemplates = @(Get-ObjectPropertyValue -InputObject $templates -PropertyName 'roadmapTemplates' -Default @())
                        }
                    }
                }
                'POST /api/roadmap/dispatch/check' {
                    Write-HostLog ("[TRACE] roadmap.dispatch.check correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $repoName  = if ($body.ContainsKey('repoName')  -and $body.repoName)  { [string]$body.repoName }  else { '' }
                    $localPath = if ($body.ContainsKey('localPath') -and $body.localPath) { [string]$body.localPath } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        throw 'repoName is required for /api/roadmap/dispatch/check'
                    }

                    # Resolve roadmap path from cache (same pattern as Build-RoadmapRepairPreview)
                    $settings     = Get-HostSettings
                    $roadmapTtl   = Get-RoadmapCacheTtlSeconds -Settings $settings
                    $roadmapCache = Get-RoadmapFromCache -TtlSeconds $roadmapTtl
                    $roadmapEntry = $null
                    if ($roadmapCache.hit -and $roadmapCache.entries) {
                        $roadmapEntry = @($roadmapCache.entries) | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1
                    }

                    $effectiveRoadmapPath = ''
                    if ($null -ne $roadmapEntry) {
                        $rp = if ($roadmapEntry -is [System.Collections.IDictionary]) { $roadmapEntry['roadmapPath'] } else { $roadmapEntry.roadmapPath }
                        if (-not [string]::IsNullOrWhiteSpace([string]$rp)) { $effectiveRoadmapPath = [string]$rp }
                    }

                    if ([string]::IsNullOrWhiteSpace($effectiveRoadmapPath) -or -not (Test-Path -LiteralPath $effectiveRoadmapPath)) {
                        throw "Cannot check dispatch readiness: roadmap file not found for repo '$repoName'. Run a roadmap scan first."
                    }

                    # Resolve localPath
                    if ([string]::IsNullOrWhiteSpace($localPath) -and $null -ne $roadmapEntry) {
                        $rpp = if ($roadmapEntry -is [System.Collections.IDictionary]) { [string]$roadmapEntry['repoPath'] } else { [string]$roadmapEntry.repoPath }
                        if (-not [string]::IsNullOrWhiteSpace($rpp)) { $localPath = $rpp }
                        elseif (-not [string]::IsNullOrWhiteSpace($effectiveRoadmapPath)) {
                            $localPath = Split-Path -Path $effectiveRoadmapPath -Parent
                        }
                    }

                    # Parse, normalize, audit
                    $rawContent   = Get-Content -LiteralPath $effectiveRoadmapPath -Raw -Encoding UTF8 -ErrorAction Stop
                    $parsedResult = Invoke-ParseRoadmapContent -Content $rawContent -SourcePath $effectiveRoadmapPath
                    $repoPath     = if (-not [string]::IsNullOrWhiteSpace($localPath)) { $localPath } else { Split-Path -Path $effectiveRoadmapPath -Parent }
                    $auditRules   = Get-RoadmapStandard
                    $contract     = Invoke-NormalizeRoadmapContract `
                                        -ParsedResult $parsedResult `
                                        -RawContent   $rawContent `
                                        -RepoName     $repoName `
                                        -RepoPath     $repoPath `
                                        -RoadmapPath  $effectiveRoadmapPath `
                                        -AuditRules   $auditRules
                    if ($null -ne $auditRules) {
                        $contract = Invoke-AuditRoadmapContract -Contract $contract -AuditRules $auditRules
                    }

                    Write-HostLog ("[TRACE] roadmap.dispatch.check correlationId={0} repoName={1} maturity={2}" -f $correlationId, $repoName, $contract.maturityLevel)

                    # Maturity gate: L3+ required for dispatch
                    $dispatchReady   = $contract.maturityLevel -in @('L3-Contract-Ready', 'L4-Orchestration-Ready')
                    $repairPreview   = $null
                    $releasePacket   = $null

                    if (-not $dispatchReady) {
                        # Below L3 — generate repair preview so the UI can surface it
                        $repairPreview = Build-RoadmapRepairPreview -RepoName $repoName -RoadmapPath $effectiveRoadmapPath
                    } else {
                        # L3+ — build release dispatch packet (no GitHub slug at check-time)
                        $releasePacket = Build-ReleaseDispatchPacket `
                            -RepoName     $repoName `
                            -RoadmapContent $rawContent `
                            -RoadmapPath  $effectiveRoadmapPath `
                            -GitHubRepo   '' `
                            -AuditContract $contract
                    }

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] roadmap.dispatch.check correlationId={0} done repoName={1} dispatchReady={2}" -f $correlationId, $repoName, $dispatchReady)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            repoName      = $repoName
                            maturityLevel = [string]$contract.maturityLevel
                            maturityScore = [int]$contract.maturityScore
                            dispatchReady = $dispatchReady
                            localPath     = $localPath
                            roadmapPath   = $effectiveRoadmapPath
                            repairPreview = $repairPreview
                            releasePacket = $releasePacket
                        }
                    }
                }
                'POST /api/roadmap/dispatch/execute' {
                    Write-HostLog ("[TRACE] roadmap.dispatch.execute correlationId={0} start" -f $correlationId)
                    $body       = Parse-JsonBody -Body $req.Body
                    $repoName   = if ($body.ContainsKey('repoName')   -and $body.repoName)   { [string]$body.repoName }   else { '' }
                    $prompt     = if ($body.ContainsKey('prompt')     -and $body.prompt)     { [string]$body.prompt }     else { '' }
                    $localPath  = if ($body.ContainsKey('localPath')  -and $body.localPath)  { [string]$body.localPath }  else { '' }
                    $baseBranch = if ($body.ContainsKey('baseBranch') -and $body.baseBranch) { [string]$body.baseBranch } else { '' }
                    $promptRefinementRunId = if ($body.ContainsKey('promptRefinementRunId') -and $body.promptRefinementRunId) { [string]$body.promptRefinementRunId } else { '' }
                    $follow     = if ($body.ContainsKey('follow'))  { [bool]$body.follow }  else { $false }

                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        throw 'repoName is required for /api/roadmap/dispatch/execute'
                    }
                    if ([string]::IsNullOrWhiteSpace($prompt)) {
                        throw 'prompt is required for /api/roadmap/dispatch/execute'
                    }

                    # Release 3.0 — a caller may not ask the host to run cloud
                    # dispatch in-process. Refused with a 409 that names the
                    # runner rather than accepted and failed at the last step,
                    # which is the shape this release exists to remove.
                    $requestedInProcess = $false
                    if ($body.ContainsKey('inProcess')) { $requestedInProcess = [bool]$body.inProcess }
                    elseif ($body.ContainsKey('dispatchMode') -and ([string]$body.dispatchMode).Trim().ToLowerInvariant() -in @('in-process', 'inprocess', 'service')) {
                        $requestedInProcess = $true
                    }
                    if ($requestedInProcess) {
                        $inProcessVerdict = Test-InProcessCloudDispatchAllowed -Caller 'POST /api/roadmap/dispatch/execute' -RunningAsService ([bool]$script:RunningAsService)
                        Write-HostLog ("WARN roadmap.dispatch.execute correlationId={0} refused in-process cloud dispatch (runningAsService={1})" -f $correlationId, $inProcessVerdict.runningAsService)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                            success  = $false
                            error    = [string]$inProcessVerdict.message
                            category = [string]$inProcessVerdict.code
                            data     = @{
                                runnerCommand = 'pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1'
                                runner        = (Get-RunnerPresence -WorkspaceRoot $WorkspaceRoot)
                            }
                        }
                        break
                    }

                    # Release 3.1 — nothing may be queued into an empty room.
                    #
                    # This route already read Get-RunnerPresence, but AFTER
                    # writing the queue line, so the response explained the
                    # problem the operator now had instead of preventing it.
                    # Six entries sat at `queued` from 2026-08-01 to 2026-08-11
                    # for exactly that reason: no runner had ever reported in,
                    # and every one of those dispatches returned 200.
                    #
                    # The read moves ahead of every write AND ahead of the
                    # planning context and quota evaluation below, so the
                    # refusal costs the operator nothing and arrives before the
                    # review effort, not after it.
                    $acknowledgeNoRunner = $false
                    if ($body.ContainsKey('acknowledgeNoRunner')) { $acknowledgeNoRunner = [bool]$body.acknowledgeNoRunner }

                    $runnerPresence = Get-RunnerPresence -WorkspaceRoot $WorkspaceRoot
                    $runnerBacklog  = Get-QueuedTaskBacklog -WorkspaceRoot $WorkspaceRoot
                    # Stranded means queued with nothing able to claim it. With a
                    # runner present the backlog is a queue; without one it is a
                    # pile. Same number, different fact - so it is only reported
                    # as stranded in the second case.
                    $strandedCount  = if ($runnerPresence.present) { 0 } else { [int]$runnerBacklog.queuedTotal }

                    if (-not $runnerPresence.present -and -not $acknowledgeNoRunner) {
                        # Refused, not silently accepted. The unmet precondition
                        # is named in the message rather than left for the
                        # operator to infer from a control that does nothing:
                        # a greyed button with no reason is worse than a failing
                        # one, because broken and not-yet-applicable look alike.
                        $refusalMessage = ("No operator runner can claim this task, so queueing it would strand it. {0} Start one with: pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1{1}" -f `
                            [string]$runnerPresence.message,
                            $(if ($strandedCount -gt 0) { " $strandedCount task(s) are already queued and waiting." } else { '' }))
                        Write-HostLog ("WARN roadmap.dispatch.execute correlationId={0} refused - runner {1}, stranded={2} (nothing written)" -f $correlationId, $runnerPresence.state, $strandedCount)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                            success  = $false
                            error    = $refusalMessage
                            category = 'runner-absent'
                            data     = @{
                                runnerCommand      = 'pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1'
                                runner             = $runnerPresence
                                strandedCount      = $strandedCount
                                queuedTotal        = [int]$runnerBacklog.queuedTotal
                                queuedClaude       = [int]$runnerBacklog.queuedClaude
                                queuedCopilot      = [int]$runnerBacklog.queuedCopilot
                                # Named in the payload so the surface offering
                                # the override does not have to hardcode it, and
                                # so a deliberate queue-then-start-a-runner stays
                                # possible. Capability explained, not removed.
                                overrideField      = 'acknowledgeNoRunner'
                                queuedNothing      = $true
                            }
                        }
                        break
                    }

                    $settingsForFallback = Get-HostSettings
                    $roadmapTtl   = Get-RoadmapCacheTtlSeconds -Settings $settingsForFallback
                    $roadmapCache = Get-RoadmapFromCache -TtlSeconds $roadmapTtl
                    $roadmapEntry = $null
                    if ($roadmapCache.hit -and $roadmapCache.entries) {
                        $roadmapEntry = @($roadmapCache.entries) | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1
                    }

                    # Resolve localPath from body or roadmap cache
                    if ([string]::IsNullOrWhiteSpace($localPath)) {
                        if ($null -ne $roadmapEntry) {
                            $rpp = if ($roadmapEntry -is [System.Collections.IDictionary]) { [string]$roadmapEntry['repoPath'] } else { [string]$roadmapEntry.repoPath }
                            if (-not [string]::IsNullOrWhiteSpace($rpp)) { $localPath = $rpp }
                            else {
                                $rp = if ($roadmapEntry -is [System.Collections.IDictionary]) { [string]$roadmapEntry['roadmapPath'] } else { [string]$roadmapEntry.roadmapPath }
                                if (-not [string]::IsNullOrWhiteSpace($rp)) { $localPath = Split-Path -Path $rp -Parent }
                            }
                        }
                    }

                    if ([string]::IsNullOrWhiteSpace($localPath)) {
                        throw "localPath could not be resolved for repo '$repoName'. Provide localPath in the request or run a roadmap scan first."
                    }
                    if (-not (Test-Path -LiteralPath $localPath -PathType Container)) {
                        throw "localPath '$localPath' was not found for repo '$repoName'."
                    }

                    $effectiveRoadmapPath = Resolve-RoadmapPathForRepo -RepoName $repoName -LocalPath $localPath -RoadmapEntry $roadmapEntry
                    $assessmentEntry = Find-PortfolioAssessmentEntry -RepoName $repoName -Settings $settingsForFallback
                    $planningContext = Get-DispatchPlanningContext `
                        -RepoName $repoName `
                        -RoadmapPath $effectiveRoadmapPath `
                        -PromptRefinementRunId $promptRefinementRunId `
                        -AssessmentEntry $assessmentEntry

                    $budgetConfig = Get-AgentBudgetLedgerConfig -WorkspaceRoot $WorkspaceRoot -Settings $settingsForFallback
                    $quotaResult = Test-AgentDispatchQuota `
                        -WorkspaceRoot $WorkspaceRoot `
                        -RepoName $repoName `
                        -EstimatedWorkUnits ([double]$planningContext.workUnitsEstimated) `
                        -BudgetConfig $budgetConfig `
                        -PlannedReleaseName ([string](Get-ValueOrDefault $planningContext.releaseName '')) `
                        -PlannedPhaseName ([string](Get-ValueOrDefault $planningContext.plannedPhaseName ''))

                    # Release 2.1 Phase 3: persist every dispatch quota evaluation —
                    # allowed, warned, or blocked — as a quota-burn snapshot so burn-down
                    # is queryable over time. Best-effort; the quota.* JSONL events remain
                    # the raw debugging artifact and dispatch never fails on a mirror error.
                    try { $null = Write-AppDbQuotaBurnSnapshot -RepoName $repoName -Evaluation $quotaResult } catch { }

                    $quotaEventBase = [ordered]@{
                        budgetPeriod            = [string]$quotaResult.period
                        estimatedWorkUnits      = [double]$quotaResult.estimatedWorkUnits
                        estimateSource          = [string](Get-ValueOrDefault $planningContext.workUnitsEstimateSource '')
                        selectedTaskText        = if (-not [string]::IsNullOrWhiteSpace([string]$planningContext.selectedTaskText)) { [string]$planningContext.selectedTaskText } else { $null }
                        selectedTaskSection     = if (-not [string]::IsNullOrWhiteSpace([string]$planningContext.selectedTaskSection)) { [string]$planningContext.selectedTaskSection } else { $null }
                        plannedReleaseName      = if ($null -ne $planningContext.releaseName) { [string]$planningContext.releaseName } else { $null }
                        plannedPhaseName        = if ($null -ne $planningContext.plannedPhaseName) { [string]$planningContext.plannedPhaseName } else { $null }
                        projectQuotaBudgetUnits = [double]$quotaResult.project.monthlyQuotaBudgetUnits
                        projectUnitsConsumed    = [double]$quotaResult.usage.unitsConsumed
                        remainingBefore         = [double]$quotaResult.usage.remainingBefore
                        remainingAfter          = [double]$quotaResult.usage.remainingAfter
                    }

                    if (-not $quotaResult.allowed) {
                        $pendingWorkSnapshot = @(Get-QuotaPendingWorkSnapshot -Settings $settingsForFallback -ExcludeRepoName $repoName)
                        $quotaEventData = [ordered]@{}
                        foreach ($keyName in $quotaEventBase.Keys) { $quotaEventData[$keyName] = $quotaEventBase[$keyName] }
                        $quotaEventData['reasonCode'] = [string](Get-ValueOrDefault $quotaResult.blockedCode '')
                        $quotaEventData['pendingReadyRepos'] = @($pendingWorkSnapshot)
                        $quotaEventData['creditPromptRepos'] = @($quotaResult.usage.creditPromptRepos)
                        $null = Write-AgentRunEvent `
                            -WorkspaceRoot $WorkspaceRoot `
                            -EventType 'quota.exhausted' `
                            -RunId '' `
                            -RepoName $repoName `
                            -Summary ([string]$quotaResult.message) `
                            -Data $quotaEventData

                        Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = @{
                                category = 'conflict'
                                code = 'quota-exhausted'
                                message = [string]$quotaResult.message
                                data = $quotaEventData
                            }
                        }
                        break
                    }

                    # Release 3.0 — the host no longer attempts cloud dispatch
                    # itself. `gh agent-task` requires an OAuth credential that a
                    # LocalSystem service structurally cannot hold, so the token
                    # check that used to stand here was answering the wrong
                    # question: a PAT would have passed it and the dispatch would
                    # still have failed at the last step of the wizard. The route
                    # now enqueues for the operator-session runner.

                    # Resolve GitHub owner/repo from git remote, falling back to settings owner
                    $fallbackOwner = ''
                    if ($settingsForFallback.ContainsKey('reconcile') -and $settingsForFallback.reconcile.ContainsKey('gitHubOwner')) {
                        $fallbackOwner = [string]$settingsForFallback.reconcile.gitHubOwner
                    }
                    $githubRepo = Resolve-GitHubRepoIdentity `
                        -LocalPath        $localPath `
                        -FallbackOwner    $fallbackOwner `
                        -FallbackRepoName $repoName

                    Write-HostLog ("[TRACE] roadmap.dispatch.execute correlationId={0} repoName={1} githubRepo={2}" -f $correlationId, $repoName, $githubRepo)

                    if (@($quotaResult.warnings).Count -gt 0) {
                        $quotaWarningData = [ordered]@{}
                        foreach ($keyName in $quotaEventBase.Keys) { $quotaWarningData[$keyName] = $quotaEventBase[$keyName] }
                        $quotaWarningData['warningMessages'] = @($quotaResult.warnings)
                        $null = Write-AgentRunEvent `
                            -WorkspaceRoot $WorkspaceRoot `
                            -EventType 'quota.warning' `
                            -RunId '' `
                            -RepoName $repoName `
                            -Summary ([string]$quotaResult.warnings[0]) `
                            -Data $quotaWarningData
                    }

                    # Release 3.0 — enqueue for the operator runner instead of
                    # invoking Start-GitHubCopilotTask.ps1 in-process.
                    #
                    # The in-process call could never succeed from the service:
                    # `gh agent-task create` requires an OAuth token, gh ignores
                    # its stored credential whenever GH_TOKEN/GITHUB_TOKEN is
                    # set, and LocalSystem has neither a stored credential nor an
                    # interactive login to obtain one. So the wizard reliably
                    # dead-ended at its final step, after the operator had
                    # already spent the refinement work.
                    #
                    # Both halves are written together — the queue line AND the
                    # `queued` run summary the runner claims on. One without the
                    # other is a task nothing ever picks up, which is the same
                    # defence Phase C's Submit-PackagedItemToRunner applies.
                    $runId = New-PackagedItemDispatchRunId
                    $startedAt = (Get-Date).ToUniversalTime().ToString('o')
                    $dispatchBranch = "roadmap/$runId"

                    $queueEntry = New-RoadmapQueueEntry `
                        -RunId $runId `
                        -Repository $githubRepo `
                        -LocalRepoPath $localPath `
                        -RoadmapPath $effectiveRoadmapPath `
                        -SelectedTask ([string](Get-ValueOrDefault $planningContext.selectedTaskText '')) `
                        -TaskDescription $prompt `
                        -Branch $dispatchBranch `
                        -QueuedAt $startedAt `
                        -DispatchTarget 'copilot' `
                        -BaseBranch $baseBranch
                    $dispatchQueuePath = Join-Path $WorkspaceRoot 'output\roadmap-task-queue.jsonl'
                    $dispatchQueueDir = Split-Path -Parent $dispatchQueuePath
                    if (-not (Test-Path -LiteralPath $dispatchQueueDir)) { $null = New-Item -ItemType Directory -Path $dispatchQueueDir -Force }
                    Add-Content -LiteralPath $dispatchQueuePath -Value ([pscustomobject]$queueEntry | ConvertTo-Json -Depth 8 -Compress) -Encoding UTF8

                    $dispatchRunsDir = Join-Path $WorkspaceRoot 'output\roadmap-task-history\runs'
                    if (-not (Test-Path -LiteralPath $dispatchRunsDir)) { $null = New-Item -ItemType Directory -Path $dispatchRunsDir -Force }
                    ([ordered]@{
                        runId             = $runId
                        status            = 'queued'
                        dispatchTarget    = 'copilot'
                        startedAt         = $startedAt
                        repository        = $githubRepo
                        roadmapPath       = $effectiveRoadmapPath
                        localRepoPath     = $localPath
                        baseBranch        = $baseBranch
                        branch            = $dispatchBranch
                        selectedTask      = [string](Get-ValueOrDefault $planningContext.selectedTaskText '')
                        queuedBy          = 'release-dispatch-api'
                    } | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $dispatchRunsDir ("{0}.summary.json" -f $runId)) -Encoding UTF8

                    # Presence was read BEFORE any of this was written (see the
                    # gate above), and that same reading is what the response
                    # reports. Re-reading here would answer a different question
                    # than the one the write was authorised against.

                    if (-not [string]::IsNullOrWhiteSpace($promptRefinementRunId) -and -not [string]::IsNullOrWhiteSpace($runId)) {
                        $null = Write-OperationsPromptDispatchRecord `
                            -RepoName $repoName `
                            -PromptRefinementRunId $promptRefinementRunId `
                            -DispatchRunId $runId `
                            -GitHubRepo $githubRepo `
                            -Status 'queued' `
                            -StartedAt $startedAt `
                            -LocalPath $localPath `
                            -BaseBranch $baseBranch
                    }

                    # Release 2.0: record the dispatch in the agent-run ledger
                    # (non-fatal — a ledger failure must not undo the dispatch).
                    $agentRunId = ''
                    try {
                        $agentRun = New-AgentRunRecord `
                            -WorkspaceRoot $WorkspaceRoot `
                            -RepoName $repoName `
                            -GitHubRepo $githubRepo `
                            -LocalPath $localPath `
                            -DispatchRunId $runId `
                            -PromptRefinementRunId $promptRefinementRunId `
                            -SelectedTaskText ([string](Get-ValueOrDefault $planningContext.selectedTaskText '')) `
                            -SelectedTaskSection ([string](Get-ValueOrDefault $planningContext.selectedTaskSection '')) `
                            -PlannedReleaseName ([string](Get-ValueOrDefault $planningContext.releaseName '')) `
                            -PlannedPhaseName ([string](Get-ValueOrDefault $planningContext.plannedPhaseName '')) `
                            -BaseBranch $baseBranch `
                            -WorkUnitsEstimated ([double]$planningContext.workUnitsEstimated) `
                            -WorkUnitsEstimateSource ([string](Get-ValueOrDefault $planningContext.workUnitsEstimateSource ''))
                        $agentRunId = [string]$agentRun.runId
                    } catch {
                        Write-HostLog ("[WARN ] roadmap.dispatch.execute correlationId={0} agent-run ledger write failed: {1}" -f $correlationId, $_.Exception.Message)
                    }

                    # Say what actually happened. "Dispatched" would be a claim
                    # with nothing behind it — the task is queued, and whether it
                    # runs depends on a runner existing.
                    $dispatchMessage = if ($runnerPresence.present) {
                        "Queued for the operator runner on $($runnerPresence.hostname)\$($runnerPresence.user); it will create the GitHub agent task for $githubRepo."
                    }
                    else {
                        # Reachable only via acknowledgeNoRunner, so it says what
                        # the operator chose rather than reporting a surprise.
                        "Queued for $githubRepo with no runner reporting in, at your explicit request — it will sit at 'queued' until one runs. $($runnerPresence.message)"
                    }
                    if (@($quotaResult.warnings).Count -gt 0) {
                        $dispatchMessage += " Quota warning: $([string]$quotaResult.warnings[0])"
                    }

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] roadmap.dispatch.execute correlationId={0} done repoName={1} runId={2} agentRunId={3} target=copilot runnerState={4}" -f $correlationId, $repoName, $runId, $agentRunId, $runnerPresence.state)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            runId          = $runId
                            agentRunId     = $agentRunId
                            status         = 'queued'
                            dispatchTarget = 'copilot'
                            githubRepo     = $githubRepo
                            branch         = $dispatchBranch
                            startedAt      = $startedAt
                            runner         = $runnerPresence
                            # True only when the operator overrode the gate, so
                            # the surface can say "you queued this into an empty
                            # room" rather than presenting it as ordinary.
                            queuedWithoutRunner = (-not $runnerPresence.present)
                            # Counted before this write, so the task just queued
                            # is added back in. Reporting the pre-write figure
                            # would under-report the pile by exactly the entry
                            # the operator is looking at.
                            strandedCount  = if ($runnerPresence.present) { 0 } else { $strandedCount + 1 }
                            message        = $dispatchMessage
                            quota      = @{
                                estimatedWorkUnits = [double]$quotaResult.estimatedWorkUnits
                                estimateSource = [string](Get-ValueOrDefault $planningContext.workUnitsEstimateSource '')
                                warning = if (@($quotaResult.warnings).Count -gt 0) { [string]$quotaResult.warnings[0] } else { $null }
                                projectBudgetUnitsRemaining = [double]$quotaResult.usage.remainingAfter
                                plannedReleaseName = if ($null -ne $planningContext.releaseName) { [string]$planningContext.releaseName } else { $null }
                                plannedPhaseName = if ($null -ne $planningContext.plannedPhaseName) { [string]$planningContext.plannedPhaseName } else { $null }
                            }
                        }
                    }
                }
                'POST /api/repo/git-status-detail' {
                    Write-HostLog ("[TRACE] repo.git-status-detail correlationId={0} start" -f $correlationId)
                    $body      = Parse-JsonBody -Body $req.Body
                    $repoName  = if ($body.ContainsKey('repoName')  -and $body.repoName)  { [string]$body.repoName }  else { '' }
                    $localPath = if ($body.ContainsKey('localPath') -and $body.localPath) { [string]$body.localPath } else { '' }

                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        throw 'repoName is required for /api/repo/git-status-detail'
                    }

                    # Resolve localPath: body → status cache lookup
                    if ([string]::IsNullOrWhiteSpace($localPath)) {
                        foreach ($cacheKey in @($script:StatusCacheMemory.Keys)) {
                            $entry = $script:StatusCacheMemory[$cacheKey]
                            if ($null -ne $entry -and $null -ne $entry.Response) {
                                $cachedRepos = if ($entry.Response.PSObject.Properties['repos']) { @($entry.Response.repos) } else { @() }
                                $match = $cachedRepos | Where-Object { $_.name -eq $repoName } | Select-Object -First 1
                                if ($null -ne $match -and -not [string]::IsNullOrWhiteSpace($match.localPath)) {
                                    $localPath = [string]$match.localPath
                                    break
                                }
                            }
                        }
                    }

                    if ([string]::IsNullOrWhiteSpace($localPath)) {
                        throw "Could not resolve localPath for repo '$repoName' — provide localPath in the request body or ensure a status cache entry exists"
                    }

                    $detail = Get-RepoGitStatusDetail -LocalPath $localPath -RepoName $repoName

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] repo.git-status-detail correlationId={0} done repoName={1} staged={2} unstaged={3} untracked={4}" -f $correlationId, $repoName, $detail.stagedCount, $detail.unstagedCount, $detail.untrackedCount)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = $detail
                    }
                }
                'POST /api/repo/git-stash' {
                    Write-HostLog ("[TRACE] repo.git-stash correlationId={0} start" -f $correlationId)
                    $body      = Parse-JsonBody -Body $req.Body
                    $repoName  = if ($body.ContainsKey('repoName')  -and $body.repoName)  { [string]$body.repoName }  else { '' }
                    $localPath = if ($body.ContainsKey('localPath') -and $body.localPath) { [string]$body.localPath } else { '' }

                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        throw 'repoName is required for /api/repo/git-stash'
                    }

                    # Resolve localPath from cache if not provided
                    if ([string]::IsNullOrWhiteSpace($localPath)) {
                        foreach ($cacheKey in @($script:StatusCacheMemory.Keys)) {
                            $entry = $script:StatusCacheMemory[$cacheKey]
                            if ($null -ne $entry -and $null -ne $entry.Response) {
                                $cachedRepos = if ($entry.Response.PSObject.Properties['repos']) { @($entry.Response.repos) } else { @() }
                                $match = $cachedRepos | Where-Object { $_.name -eq $repoName } | Select-Object -First 1
                                if ($null -ne $match -and -not [string]::IsNullOrWhiteSpace($match.localPath)) {
                                    $localPath = [string]$match.localPath
                                    break
                                }
                            }
                        }
                    }

                    if ([string]::IsNullOrWhiteSpace($localPath)) {
                        throw "Could not resolve localPath for repo '$repoName'"
                    }

                    $stashResult = Invoke-GitStash -LocalPath $localPath

                    # Invalidate status cache entry for this repo
                    $keysToRemove = @($script:StatusCacheMemory.Keys | Where-Object {
                        $entry = $script:StatusCacheMemory[$_]
                        $null -ne $entry -and $null -ne $entry.Response -and
                        $entry.Response.PSObject.Properties['repos'] -and
                        (@($entry.Response.repos) | Where-Object { $_.name -eq $repoName }).Count -gt 0
                    })
                    foreach ($k in $keysToRemove) { $script:StatusCacheMemory.Remove($k) }

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] repo.git-stash correlationId={0} done repoName={1} success={2}" -f $correlationId, $repoName, $stashResult.success)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $stashResult.success
                        data    = @{
                            output   = $stashResult.output
                            stashRef = $stashResult.stashRef
                        }
                    }
                }
                'POST /api/repo/git-discard' {
                    Write-HostLog ("[TRACE] repo.git-discard correlationId={0} start" -f $correlationId)
                    $body             = Parse-JsonBody -Body $req.Body
                    $repoName         = if ($body.ContainsKey('repoName')         -and $body.repoName)         { [string]$body.repoName }                        else { '' }
                    $localPath        = if ($body.ContainsKey('localPath')        -and $body.localPath)        { [string]$body.localPath }                       else { '' }
                    $includeUntracked = if ($body.ContainsKey('includeUntracked'))                             { [bool]$body.includeUntracked }                  else { $false }

                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        throw 'repoName is required for /api/repo/git-discard'
                    }

                    # Resolve localPath from cache if not provided
                    if ([string]::IsNullOrWhiteSpace($localPath)) {
                        foreach ($cacheKey in @($script:StatusCacheMemory.Keys)) {
                            $entry = $script:StatusCacheMemory[$cacheKey]
                            if ($null -ne $entry -and $null -ne $entry.Response) {
                                $cachedRepos = if ($entry.Response.PSObject.Properties['repos']) { @($entry.Response.repos) } else { @() }
                                $match = $cachedRepos | Where-Object { $_.name -eq $repoName } | Select-Object -First 1
                                if ($null -ne $match -and -not [string]::IsNullOrWhiteSpace($match.localPath)) {
                                    $localPath = [string]$match.localPath
                                    break
                                }
                            }
                        }
                    }

                    if ([string]::IsNullOrWhiteSpace($localPath)) {
                        throw "Could not resolve localPath for repo '$repoName'"
                    }

                    $discardResult = Invoke-GitDiscard -LocalPath $localPath -IncludeUntracked $includeUntracked

                    # Invalidate status cache entry for this repo
                    $keysToRemove = @($script:StatusCacheMemory.Keys | Where-Object {
                        $entry = $script:StatusCacheMemory[$_]
                        $null -ne $entry -and $null -ne $entry.Response -and
                        $entry.Response.PSObject.Properties['repos'] -and
                        (@($entry.Response.repos) | Where-Object { $_.name -eq $repoName }).Count -gt 0
                    })
                    foreach ($k in $keysToRemove) { $script:StatusCacheMemory.Remove($k) }

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] repo.git-discard correlationId={0} done repoName={1} success={2} includeUntracked={3}" -f $correlationId, $repoName, $discardResult.success, $includeUntracked)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $discardResult.success
                        data    = @{
                            output        = $discardResult.output
                            filesRestored = $discardResult.filesRestored
                            filesRemoved  = $discardResult.filesRemoved
                        }
                    }
                }
                # Release 1.5 — Copilot-Assisted README Generation
                # -------------------------------------------------------
                'POST /api/readme/generate' {
                    Write-HostLog ("[TRACE] readme.generate correlationId={0} start" -f $correlationId)
                    try {
                        $body      = Parse-JsonBody -Body $req.Body
                        $repoName  = if ($body.ContainsKey('repoName')  -and $body.repoName)  { [string]$body.repoName }  else { '' }
                        $localPath = if ($body.ContainsKey('localPath') -and $body.localPath) { [string]$body.localPath } else { '' }

                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName is required for /api/readme/generate'
                        }

                        # Resolve localPath: body → status cache lookup
                        if ([string]::IsNullOrWhiteSpace($localPath)) {
                            foreach ($cacheKey in @($script:StatusCacheMemory.Keys)) {
                                $entry = $script:StatusCacheMemory[$cacheKey]
                                if ($null -ne $entry -and $null -ne $entry.Response) {
                                    $cachedRepos = if ($entry.Response.PSObject.Properties['repos']) { @($entry.Response.repos) } else { @() }
                                    $match = $cachedRepos | Where-Object { $_.name -eq $repoName } | Select-Object -First 1
                                    if ($null -ne $match -and -not [string]::IsNullOrWhiteSpace($match.localPath)) {
                                        $localPath = [string]$match.localPath
                                        break
                                    }
                                }
                            }
                        }

                        if ([string]::IsNullOrWhiteSpace($localPath)) {
                            throw "Could not resolve localPath for repo '$repoName' — provide localPath in the request body or ensure a status cache entry exists"
                        }

                        $settings = Get-HostSettings
                        $result = Invoke-CopilotReadmeGeneration -RepoName $repoName -LocalPath $localPath -Settings $settings
                        Write-HostLog ("[TRACE] readme.generate correlationId={0} done repoName={1} repoType={2}" -f $correlationId, $repoName, $result.repoType)
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $result
                        }
                    } catch {
                        $errMsg = $_.Exception.Message
                        if ($errMsg -match '^412:') {
                            Send-HttpJson -Stream $req.Stream -StatusCode 412 -CorrelationId $correlationId -Payload @{
                                success            = $false
                                preconditionFailed = $true
                                message            = $errMsg -replace '^412:\s*', ''
                            }
                        } else {
                            $statusCode = Get-ErrorStatusCode -Message $errMsg -DefaultStatusCode 500
                            Send-ErrorJson -Stream $req.Stream -StatusCode $statusCode -ErrorMessage $errMsg -CorrelationId $correlationId -Operation 'readme.generate'
                        }
                    }
                }
                'POST /api/readme/generate/apply' {
                    Write-HostLog ("[TRACE] readme.generate.apply correlationId={0} start" -f $correlationId)
                    try {
                        $body         = Parse-JsonBody -Body $req.Body
                        $repoName     = if ($body.ContainsKey('repoName')     -and $body.repoName)     { [string]$body.repoName }     else { '' }
                        $localPath    = if ($body.ContainsKey('localPath')    -and $body.localPath)    { [string]$body.localPath }    else { '' }
                        $generationId = if ($body.ContainsKey('generationId') -and $body.generationId) { [string]$body.generationId } else { '' }
                        $content      = if ($body.ContainsKey('content')      -and $body.content)      { [string]$body.content }      else { '' }

                        if ([string]::IsNullOrWhiteSpace($repoName))     { throw 'repoName is required' }
                        if ([string]::IsNullOrWhiteSpace($generationId)) { throw 'generationId is required' }
                        if ([string]::IsNullOrWhiteSpace($content))      { throw 'content is required' }

                        # Resolve localPath: body → status cache lookup
                        if ([string]::IsNullOrWhiteSpace($localPath)) {
                            foreach ($cacheKey in @($script:StatusCacheMemory.Keys)) {
                                $entry = $script:StatusCacheMemory[$cacheKey]
                                if ($null -ne $entry -and $null -ne $entry.Response) {
                                    $cachedRepos = if ($entry.Response.PSObject.Properties['repos']) { @($entry.Response.repos) } else { @() }
                                    $match = $cachedRepos | Where-Object { $_.name -eq $repoName } | Select-Object -First 1
                                    if ($null -ne $match -and -not [string]::IsNullOrWhiteSpace($match.localPath)) {
                                        $localPath = [string]$match.localPath
                                        break
                                    }
                                }
                            }
                        }

                        if ([string]::IsNullOrWhiteSpace($localPath)) {
                            throw "Could not resolve localPath for repo '$repoName' — provide localPath in the request body or ensure a status cache entry exists"
                        }

                        $readmePath = Join-Path $localPath 'README.md'
                        if (Test-Path -LiteralPath $readmePath) {
                            Send-HttpJson -Stream $req.Stream -StatusCode 409 -CorrelationId $correlationId -Payload @{
                                success       = $false
                                alreadyExists = $true
                                readmePath    = $readmePath
                            }
                            break
                        }

                        Set-Content -LiteralPath $readmePath -Value $content -Encoding UTF8
                        $writtenAt = (Get-Date).ToUniversalTime().ToString('o')
                        Write-ReadmeGenerationHistoryEntry -WorkspaceRoot $WorkspaceRoot -Entry @{
                            generationId = $generationId
                            repoName     = $repoName
                            localPath    = $localPath
                            event        = 'apply'
                            appliedAt    = $writtenAt
                            readmePath   = $readmePath
                        }

                        Write-HostLog ("[TRACE] readme.generate.apply correlationId={0} done repoName={1} readmePath={2}" -f $correlationId, $repoName, $readmePath)
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{
                                repoName   = $repoName
                                readmePath = $readmePath
                                writtenAt  = $writtenAt
                            }
                        }
                    } catch {
                        $statusCode = Get-ErrorStatusCode -Message $_.Exception.Message -DefaultStatusCode 500
                        Send-ErrorJson -Stream $req.Stream -StatusCode $statusCode -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'readme.generate.apply'
                    }
                }
                'GET /api/readme/generate/history' {
                    Write-HostLog ("[TRACE] readme.generate.history correlationId={0} start" -f $correlationId)
                    try {
                        $q     = Parse-QueryString -Query $req.Query
                        $limit = if ($q.ContainsKey('limit') -and $q.limit -match '^\d+$') { [int]$q.limit } else { 25 }
                        if ($limit -gt 100) { $limit = 100 }
                        $items = Get-ReadmeGenerationHistory -WorkspaceRoot $WorkspaceRoot -Limit $limit
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{ items = @($items); count = @($items).Count }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'readme.generate.history'
                    }
                }
                'GET /api/roadmap/audit' {
                    Write-HostLog ("[TRACE] roadmap.audit.index correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $refresh = if ($q.ContainsKey('refresh')) { Parse-Bool -Value $q.refresh -Default $false } else { $false }
                    $settings = Get-HostSettings
                    $ttlSeconds = Get-RoadmapAuditCacheTtlSeconds -Settings $settings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $localRoots = if ($q.ContainsKey('localRoots') -and $q.localRoots) { @($q.localRoots -split ';|,') } else { $defaultRoots }
                    $maxDepth = if ($q.ContainsKey('maxDepth') -and $q.maxDepth) { [int]$q.maxDepth } else { $defaultDepth }
                    $useDefaultScope = ($maxDepth -eq $defaultDepth) -and ((@($localRoots) -join '|') -eq (@($defaultRoots) -join '|'))

                    $cacheHit = $null
                    if ($useDefaultScope -and (-not $refresh) -and ($ttlSeconds -gt 0)) {
                        $cacheHit = Get-RoadmapAuditFromCache -TtlSeconds $ttlSeconds
                    }

                    if ($null -ne $cacheHit -and $cacheHit.hit) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] roadmap.audit.index correlationId={0} done source=cache ageSeconds={1}" -f $correlationId, [math]::Round($cacheHit.ageSeconds, 1))
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success   = $true
                            data      = @{
                                entries       = $cacheHit.entries
                                auditedAt     = $cacheHit.auditedAt
                                count         = @($cacheHit.entries).Count
                                cacheSource   = $cacheHit.source
                                cacheAgeSeconds = [math]::Round($cacheHit.ageSeconds, 1)
                            }
                        }
                    } else {
                        $auditedAt = (Get-Date).ToUniversalTime().ToString('o')
                        $entries = Invoke-RoadmapAuditScan -LocalRoots $localRoots -MaxDepth $maxDepth
                        if ($useDefaultScope) {
                            Save-RoadmapAuditCache -Entries $entries -AuditedAt $auditedAt
                        }
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] roadmap.audit.index correlationId={0} done source=fresh-scan count={1} durationMs={2}" -f $correlationId, @($entries).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{
                                entries         = $entries
                                auditedAt       = $auditedAt
                                count           = @($entries).Count
                                cacheSource     = 'fresh-scan'
                                cacheAgeSeconds = 0
                            }
                        }
                    }
                }
                'POST /api/roadmap/audit/scan' {
                    Write-HostLog ("[TRACE] roadmap.audit.scan correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $localRoots = if ($body.ContainsKey('localRoots') -and $body.localRoots) { @($body.localRoots) } else { $defaultRoots }
                    $maxDepth = if ($body.ContainsKey('maxDepth') -and $body.maxDepth) { [int]$body.maxDepth } else { $defaultDepth }
                    $useDefaultScope = ($maxDepth -eq $defaultDepth) -and ((@($localRoots) -join '|') -eq (@($defaultRoots) -join '|'))
                    $auditedAt = (Get-Date).ToUniversalTime().ToString('o')
                    $entries = Invoke-RoadmapAuditScan -LocalRoots $localRoots -MaxDepth $maxDepth
                    if ($useDefaultScope) {
                        Save-RoadmapAuditCache -Entries $entries -AuditedAt $auditedAt
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] roadmap.audit.scan correlationId={0} done count={1} durationMs={2}" -f $correlationId, @($entries).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            entries         = $entries
                            auditedAt       = $auditedAt
                            count           = @($entries).Count
                            cacheSource     = 'fresh-scan'
                            cacheAgeSeconds = 0
                        }
                    }
                }
                'POST /api/roadmap/repair/preview' {
                    Write-HostLog ("[TRACE] roadmap.repair.preview correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $repoName = if ($body.ContainsKey('repoName') -and $body.repoName) { [string]$body.repoName } else { '' }
                    $roadmapPath = if ($body.ContainsKey('roadmapPath') -and $body.roadmapPath) { [string]$body.roadmapPath } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ error = 'repoName is required for /api/roadmap/repair/preview' }
                    } else {
                        $preview = Build-RoadmapRepairPreview -RepoName $repoName -RoadmapPath $roadmapPath
                        Add-MetricCounter -Name 'api_requests_total'
                        Write-HostLog ("[TRACE] roadmap.repair.preview correlationId={0} done repoName={1} previewId={2} previewState={3}" -f $correlationId, $repoName, $preview.previewId, $preview.previewState)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $preview
                        }
                    }
                }
                'POST /api/roadmap/repair/apply' {
                    Write-HostLog ("[TRACE] roadmap.repair.apply correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $repoName       = if ($body.ContainsKey('repoName') -and $body.repoName)             { [string]$body.repoName }             else { '' }
                    $previewId      = if ($body.ContainsKey('previewId') -and $body.previewId)           { [string]$body.previewId }            else { '' }
                    $proposedContent = if ($body.ContainsKey('proposedContent') -and $body.proposedContent) { [string]$body.proposedContent } else { '' }
                    $roadmapPath    = if ($body.ContainsKey('roadmapPath') -and $body.roadmapPath)       { [string]$body.roadmapPath }          else { '' }
                    $origLevel      = if ($body.ContainsKey('originalMaturityLevel') -and $body.originalMaturityLevel) { [string]$body.originalMaturityLevel } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repoName) -or [string]::IsNullOrWhiteSpace($previewId) -or [string]::IsNullOrWhiteSpace($proposedContent)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ error = 'repoName, previewId, and proposedContent are required for /api/roadmap/repair/apply' }
                    } else {
                        $result = Apply-RoadmapRepair -RepoName $repoName -PreviewId $previewId -ProposedContent $proposedContent -RoadmapPath $roadmapPath -OriginalMaturityLevel $origLevel
                        Add-MetricCounter -Name 'api_requests_total'
                        Write-HostLog ("[TRACE] roadmap.repair.apply correlationId={0} done repoName={1} previewId={2} appliedAt={3}" -f $correlationId, $repoName, $previewId, $result.appliedAt)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $result
                        }
                    }
                }
                'GET /api/roadmap/repair/history' {
                    Write-HostLog ("[TRACE] roadmap.repair.history correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $limit = if ($q.ContainsKey('limit') -and $q.limit -match '^\d+$') { [int]$q.limit } else { 25 }
                    if ($limit -gt 100) { $limit = 100 }
                    $historyItems = Get-RoadmapRepairHistory -Limit $limit
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            items = @($historyItems)
                            count = @($historyItems).Count
                        }
                    }
                }
                'POST /api/roadmap/repair/submit-pr' {
                    # Release 2.4 — build a PR for a roadmap repair. Dry-run by
                    # default (returns the planned branch/title/body). A live PR
                    # (createPr=true) is an explicit operator action needing a git
                    # checkout + GitHub write access, so it is never pushed here.
                    $body = Parse-JsonBody -Body $req.Body
                    $repoName = if ($null -ne $body -and $body.ContainsKey('repoName') -and $body.repoName) { [string]$body.repoName } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ success = $false; error = 'repoName is required'; category = 'validation' }
                    }
                    else {
                        $previewId = if ($body.ContainsKey('previewId')) { [string]$body.previewId } else { '' }
                        $createPr = ($body.ContainsKey('createPr') -and [bool]$body.createPr)
                        $submitProposed = if ($body.ContainsKey('proposedContent') -and $body.proposedContent) { [string]$body.proposedContent } else { '' }
                        $submitRoadmapPath = if ($body.ContainsKey('roadmapPath') -and $body.roadmapPath) { [string]$body.roadmapPath } else { '' }
                        # repoPath is overridable for the same reason roadmapPath is:
                        # the roadmap index only covers the CONFIGURED localRoots, so a
                        # repo outside them (this repo itself, for one) is unresolvable
                        # from the cache no matter how many scans run. Without this the
                        # route could only ever submit for repos inside the portfolio root.
                        $submitRepoPathOverride = if ($body.ContainsKey('repoPath') -and $body.repoPath) { [string]$body.repoPath } else { '' }
                        $submitBase = if ($body.ContainsKey('baseBranch') -and $body.baseBranch) { [string]$body.baseBranch } else { '' }
                        $branch = Get-RoadmapRepairBranchName
                        $plan = @{
                            repoName   = $repoName
                            previewId  = $previewId
                            branch     = $branch
                            baseBranch = $(if ($submitBase) { $submitBase } else { 'main' })
                            title      = "Roadmap repair: $repoName"
                            body       = ("Automated roadmap repair for {0}.{1}" -f $repoName, $(if ($previewId) { " Based on repair preview $previewId." } else { '' }))
                        }

                        # Release 3.1 — the dry run is where an operator decides
                        # whether to submit at all, so it has to know whether the
                        # base is stale. Probing here means the warning arrives
                        # before the live call rather than as its refusal.
                        $dryRunFreshness = $null
                        if (-not $createPr) {
                            # Resolve the clone the same way the live path does —
                            # explicit repoPath wins, the roadmap cache is the
                            # fallback. Without the fallback the warning would only
                            # ever fire for callers that already pass a path, which
                            # the repair modal does not: a warning that cannot
                            # appear in the normal flow is not a warning.
                            $dryRunRepoPath = $submitRepoPathOverride
                            if ([string]::IsNullOrWhiteSpace($dryRunRepoPath)) {
                                $dryRunCache = Get-RoadmapFromCache -TtlSeconds (Get-RoadmapCacheTtlSeconds -Settings (Get-HostSettings))
                                if ($dryRunCache.hit -and $dryRunCache.entries) {
                                    $dryRunEntry = @($dryRunCache.entries) | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1
                                    if ($null -ne $dryRunEntry) {
                                        $dryRunRepoPath = if ($dryRunEntry -is [System.Collections.IDictionary]) {
                                            [string](Get-ValueOrDefault $dryRunEntry['repoPath'] '')
                                        } else {
                                            [string](Get-ValueOrDefault $dryRunEntry.repoPath '')
                                        }
                                    }
                                }
                            }
                            if (-not [string]::IsNullOrWhiteSpace($dryRunRepoPath)) {
                                $dryRunFreshness = Get-RepoBaseFreshness -RepoPath $dryRunRepoPath -BaseBranch ([string]$plan.baseBranch)
                            }
                        }

                        if (-not $createPr) {
                            Add-MetricCounter -Name 'api_requests_total'
                            Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                success = $true
                                data = @{
                                    dryRun = $true; created = $false; prUrl = $null; plan = $plan
                                    baseFreshness = $dryRunFreshness
                                    note = 'dry-run: set createPr=true (with proposedContent and a GitHub write token) to open a live PR'
                                }
                            }
                        }
                        else {
                            # Release 2.7 Phase A — the live round trip. Resolve the
                            # repo's checkout + roadmap path the same way the repair
                            # preview does, then branch/commit/push/open the PR.
                            $submitSettings = Get-HostSettings
                            $submitToken = Get-ConfiguredGitHubToken -Settings $submitSettings
                            $submitRepoPath = $submitRepoPathOverride
                            $submitRoadmapTtl = Get-RoadmapCacheTtlSeconds -Settings $submitSettings
                            $submitCache = Get-RoadmapFromCache -TtlSeconds $submitRoadmapTtl
                            # An explicit repoPath wins; the cache is the fallback.
                            if ([string]::IsNullOrWhiteSpace($submitRepoPath) -and $submitCache.hit -and $submitCache.entries) {
                                $submitEntry = @($submitCache.entries) | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1
                                if ($null -ne $submitEntry) {
                                    # Cache entries come back as hashtables when
                                    # rehydrated from disk and as PSCustomObjects
                                    # when freshly scanned. Build-RoadmapRepairPreview
                                    # already guards both; reading only the object
                                    # form silently yielded an empty repoPath and a
                                    # "run a scan first" refusal on a warm cache.
                                    $submitRepoPath = if ($submitEntry -is [System.Collections.IDictionary]) {
                                        [string](Get-ValueOrDefault $submitEntry['repoPath'] '')
                                    } else {
                                        [string](Get-ValueOrDefault $submitEntry.repoPath '')
                                    }
                                    if ([string]::IsNullOrWhiteSpace($submitRoadmapPath)) {
                                        $submitRoadmapPath = if ($submitEntry -is [System.Collections.IDictionary]) {
                                            [string](Get-ValueOrDefault $submitEntry['roadmapPath'] '')
                                        } else {
                                            [string](Get-ValueOrDefault $submitEntry.roadmapPath '')
                                        }
                                    }
                                }
                            }

                            # Release 3.1 — the deliberate stale-base override, same
                            # shape as acknowledgeNoRunner on the dispatch path:
                            # absent means refuse, and the operator has to say so.
                            # ContainsKey first: under StrictMode, reading an absent
                            # property throws before Get-ValueOrDefault can default it,
                            # which turned this route's 409 refusals into 500s. Every
                            # other field in this route is read the same way.
                            $submitAckStale = ($body.ContainsKey('acknowledgeStaleBase') -and [bool]$body.acknowledgeStaleBase)

                            $submitResult = Invoke-RoadmapRepairPrSubmission `
                                -RepoName $repoName -RepoPath $submitRepoPath -RoadmapPath $submitRoadmapPath `
                                -ProposedContent $submitProposed -PreviewId $previewId -Token $submitToken `
                                -BaseBranch $submitBase -BranchName $branch `
                                -ApiHeaders (Get-GitHubApiHeaders -Token $submitToken) `
                                -AcknowledgeStaleBase:$submitAckStale

                            Add-MetricCounter -Name 'api_requests_total'
                            if ($submitResult.refused) {
                                # A refusal is a 409, never a 200-with-created=false:
                                # the caller must not be able to read "no PR" as success.
                                Write-HostLog ("[TRACE] roadmap.repair.submit-pr correlationId={0} repoName={1} REFUSED category={2}" -f $correlationId, $repoName, $submitResult.category)
                                Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                                    success = $false
                                    error = [string]$submitResult.reason
                                    category = [string]$submitResult.category
                                    data = @{
                                        dryRun = $false; created = $false; prUrl = $null; plan = $plan
                                        # A refusal the caller cannot explain to the
                                        # operator is only half a refusal.
                                        baseFreshness = (Get-ObjectPropertyValue -InputObject $submitResult -PropertyName 'baseFreshness' -Default $null)
                                        canAcknowledgeStaleBase = ([string]$submitResult.category -eq 'stale-base')
                                    }
                                }
                            }
                            else {
                                Save-RoadmapRepairHistoryEntry -PreviewId $previewId -RepoName $repoName `
                                    -RoadmapPath $submitRoadmapPath -PreviewState 'submitted' -OriginalMaturityLevel '' `
                                    -Event 'submit-pr' -PrUrl ([string]$submitResult.prUrl) `
                                    -PrNumber ([string]$submitResult.prNumber) -Branch ([string]$submitResult.branch) `
                                    -RepoSlug ([string]$submitResult.slug)
                                Write-HostLog ("[TRACE] roadmap.repair.submit-pr correlationId={0} repoName={1} created=true pr={2}" -f $correlationId, $repoName, $submitResult.prUrl)
                                Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                    success = $true
                                    data = @{
                                        dryRun = $false
                                        created = $true
                                        prUrl = [string]$submitResult.prUrl
                                        prNumber = $submitResult.prNumber
                                        branch = [string]$submitResult.branch
                                        baseBranch = [string]$submitResult.baseBranch
                                        repoSlug = [string]$submitResult.slug
                                        plan = $plan
                                        note = 'live PR opened; nothing was merged'
                                    }
                                }
                            }
                        }
                    }
                }
                # -------------------------------------------------------
                # Release 1.2 — Scheduled Scan and Execution Metrics
                # -------------------------------------------------------
                'GET /api/scan/schedule' {
                    Add-MetricCounter -Name 'api_requests_total'
                    # Release 2.7 Phase B — surface the automation config alongside the
                    # scan schedule. Actual interval firing is delegated to an external
                    # cron hitting POST /api/automation/run (as with the digest webhook).
                    $schedSettings = Get-HostSettings
                    $autoCfg = if ($schedSettings.ContainsKey('automation') -and $schedSettings.automation -is [System.Collections.IDictionary]) { $schedSettings.automation } else { $null }
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            enabled         = $script:AutoScanState.Enabled
                            intervalMinutes = $script:AutoScanState.IntervalMinutes
                            nextScanAt      = if ($script:AutoScanState.NextScanAt -lt [datetime]::MaxValue) { $script:AutoScanState.NextScanAt.ToString('o') } else { $null }
                            lastScanAt      = if ($null -ne $script:AutoScanState.LastScanAt) { ([datetime]$script:AutoScanState.LastScanAt).ToString('o') } else { $null }
                            automation      = @{
                                enabled           = if ($null -ne $autoCfg -and $autoCfg.ContainsKey('enabled')) { [bool]$autoCfg.enabled } else { $false }
                                docRefinement     = if ($null -ne $autoCfg -and $autoCfg.ContainsKey('docRefinement')) { [bool]$autoCfg.docRefinement } else { $false }
                                intervalMinutes   = if ($null -ne $autoCfg -and $autoCfg.ContainsKey('intervalMinutes')) { [int]$autoCfg.intervalMinutes } else { 0 }
                                scope             = 'favorites+candidates'
                                previewOnly       = $true
                                webhookConfigured = ($null -ne $autoCfg -and $autoCfg.ContainsKey('webhookUrl') -and -not [string]::IsNullOrWhiteSpace([string]$autoCfg.webhookUrl))
                                runEndpoint       = 'POST /api/automation/run'
                                historyEndpoint   = 'GET /api/automation/history'
                            }
                        }
                    }
                }
                'GET /api/execution/metrics' {
                    Write-HostLog ("[TRACE] execution.metrics correlationId={0} start" -f $correlationId)
                    try {
                        $ledger     = Read-ExecutionLedger -WorkspaceRoot $WorkspaceRoot
                        $now        = Get-Date
                        $todayStart = $now.Date
                        $weekStart  = $now.Date.AddDays(-7)
                        $history    = @($ledger.history)

                        $completedHistory = @($history | Where-Object { $_.event -eq 'completed' -and $_.outcome -eq 'success' })
                        $cancelledHistory = @($history | Where-Object { $_.event -eq 'completed' -and $_.outcome -ne 'success' })

                        $completedToday    = @($completedHistory | Where-Object {
                            $_.timestamp -and [datetime]$_.timestamp -ge $todayStart
                        }).Count
                        $completedThisWeek = @($completedHistory | Where-Object {
                            $_.timestamp -and [datetime]$_.timestamp -ge $weekStart
                        }).Count

                        # Average minutes a currently-running task has been in flight
                        $runningEntries  = @($ledger.entries | Where-Object { $_.executionState -eq 'running' -and $_.assignedAt })
                        $avgRunningMins  = $null
                        if ($runningEntries.Count -gt 0) {
                            $sumMins = ($runningEntries | ForEach-Object {
                                ($now - [datetime]$_.assignedAt).TotalMinutes
                            } | Measure-Object -Sum).Sum
                            $avgRunningMins = [math]::Round($sumMins / $runningEntries.Count, 1)
                        }

                        $totalAttempted = $completedHistory.Count + $cancelledHistory.Count
                        $errorRatePct   = if ($totalAttempted -gt 0) {
                            [math]::Round($cancelledHistory.Count / $totalAttempted * 100, 1)
                        } else { 0.0 }

                        $stateCounts = @{}
                        foreach ($st in @('idle','ready','running','blocked','complete')) {
                            $stateCounts[$st] = @($ledger.entries | Where-Object { $_.executionState -eq $st }).Count
                        }

                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{
                                completedToday    = $completedToday
                                completedThisWeek = $completedThisWeek
                                totalCompleted    = $completedHistory.Count
                                totalCancelled    = $cancelledHistory.Count
                                avgCurrentRunMins = $avgRunningMins
                                errorRatePct      = $errorRatePct
                                stateCounts       = $stateCounts
                                computedAt        = $now.ToString('o')
                            }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage ("Failed to compute execution metrics: {0}" -f $_.Exception.Message) -CorrelationId $correlationId -Operation 'execution.metrics'
                    }
                }

                # -------------------------------------------------------
                # Release 1.0 — Execution Queue API Routes
                # -------------------------------------------------------
                'GET /api/execution/queue' {
                    Write-HostLog ("[TRACE] execution.queue correlationId={0} start" -f $correlationId)
                    try {
                        $queueSummary = Get-ExecutionQueueSummary -WorkspaceRoot $WorkspaceRoot
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $queueSummary
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'execution.queue'
                    }
                }
                'POST /api/execution/sync' {
                    Write-HostLog ("[TRACE] execution.sync correlationId={0} start" -f $correlationId)
                    try {
                        # Sync ledger from current doc-audit + roadmap-audit data.
                        $settings = Get-HostSettings
                        $localRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                        $maxDepth   = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 2 }

                        # Invoke-DocAuditScan returns an array, not an envelope with an entries property.
                        $docAuditResult = $null
                        try {
                            $docAuditResult = Invoke-DocAuditScan -LocalRoots $localRoots -MaxDepth $maxDepth
                        } catch { $docAuditResult = $null }

                        [object[]]$docEntries = @()
                        if ($null -ne $docAuditResult) {
                            $docEntries = @($docAuditResult)
                        }

                        # Prefer the cached roadmap audit envelope and fall back to a fresh scan.
                        [object[]]$roadmapAuditEntries = @()
                        $roadmapAuditCacheTtlSeconds = Get-RoadmapAuditCacheTtlSeconds -Settings $settings
                        $cachedAudit = $null
                        try {
                            $cachedAudit = Get-RoadmapAuditFromCache -TtlSeconds $roadmapAuditCacheTtlSeconds
                        } catch { $cachedAudit = $null }

                        if ($null -ne $cachedAudit -and $cachedAudit.hit) {
                            $roadmapAuditEntries = @($cachedAudit.entries)
                        } else {
                            try {
                                $roadmapAuditEntries = @(Invoke-RoadmapAuditScan -LocalRoots $localRoots -MaxDepth $maxDepth)
                            } catch {
                                $roadmapAuditEntries = @()
                            }
                        }

                        $syncedLedger = Sync-LedgerFromAudit -WorkspaceRoot $WorkspaceRoot -DocAuditEntries $docEntries -RoadmapAuditEntries $roadmapAuditEntries
                        $queueSummary = Get-ExecutionQueueSummary -WorkspaceRoot $WorkspaceRoot

                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $queueSummary
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'execution.sync'
                    }
                }
                'POST /api/execution/assign' {
                    Write-HostLog ("[TRACE] execution.assign correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        $repoName = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default $null)
                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName is required for /api/execution/assign'
                        }
                        $runId = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'runId' -Default '')
                        $taskText = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'taskText' -Default '')
                        $taskSection = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'taskSection' -Default '')

                        $result = Invoke-AssignLane -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -RunId $runId -TaskText $taskText -TaskSection $taskSection
                        $statusCode = if ($result.success) { 200 } else { 409 }
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode $statusCode -CorrelationId $correlationId -Payload @{
                            success = $result.success
                            data    = if ($result.success) { @{ laneSlot = $result.laneSlot; runId = $result.runId; entry = $result.entry } } else { $null }
                            error   = if (-not $result.success) { @{ message = $result.error } } else { $null }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'execution.assign'
                    }
                }
                'POST /api/execution/complete' {
                    Write-HostLog ("[TRACE] execution.complete correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        $repoName = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default $null)
                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName is required for /api/execution/complete'
                        }
                        $outcome = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'outcome' -Default 'success')
                        $hasRemainingWork = [bool](Get-ObjectPropertyValue -InputObject $body -PropertyName 'hasRemainingWork' -Default $false)

                        $result = Invoke-CompleteTask -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -Outcome $outcome -HasRemainingWork $hasRemainingWork
                        $statusCode = if ($result.success) { 200 } else { 409 }
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode $statusCode -CorrelationId $correlationId -Payload @{
                            success = $result.success
                            data    = if ($result.success) { @{ newState = $result.newState } } else { $null }
                            error   = if (-not $result.success) { @{ message = $result.error } } else { $null }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'execution.complete'
                    }
                }
                'POST /api/execution/cancel' {
                    Write-HostLog ("[TRACE] execution.cancel correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        $repoName = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default $null)
                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName is required for /api/execution/cancel'
                        }
                        $reason = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'reason' -Default 'cancelled')
                        $maxRetries = [int](Get-ObjectPropertyValue -InputObject $body -PropertyName 'maxRetries' -Default 3)

                        $result = Invoke-CancelTask -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -Reason $reason -MaxRetries $maxRetries
                        $statusCode = if ($result.success) { 200 } else { 409 }
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode $statusCode -CorrelationId $correlationId -Payload @{
                            success = $result.success
                            data    = if ($result.success) { @{ newState = $result.newState; retryCount = $result.retryCount } } else { $null }
                            error   = if (-not $result.success) { @{ message = $result.error } } else { $null }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'execution.cancel'
                    }
                }
                'POST /api/execution/requeue' {
                    Write-HostLog ("[TRACE] execution.requeue correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        $repoName = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default $null)
                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName is required for /api/execution/requeue'
                        }
                        $force = [bool](Get-ObjectPropertyValue -InputObject $body -PropertyName 'force' -Default $false)

                        $result = Invoke-RequeueRepo -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -Force $force
                        $statusCode = if ($result.success) { 200 } else { 409 }
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode $statusCode -CorrelationId $correlationId -Payload @{
                            success = $result.success
                            data    = if ($result.success) { @{ newState = $result.newState } } else { $null }
                            error   = if (-not $result.success) { @{ message = $result.error } } else { $null }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'execution.requeue'
                    }
                }
                # -------------------------------------------------------
                # Release 1.1 — Roadmap Linting
                # -------------------------------------------------------
                'GET /api/roadmap/lint' {
                    Write-HostLog ("[TRACE] roadmap.lint correlationId={0} start" -f $correlationId)
                    try {
                        $q = Parse-QueryString -Query $req.Query
                        $repoName = if ($q.ContainsKey('repoName') -and $q.repoName) { [string]$q.repoName } else { $null }
                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName query parameter is required'
                        }
                        # Load roadmap content from index cache
                        $roadmapPath = $null
                        $rawContent  = ''
                        $roadmapIndexEntries = @()
                        if ($null -ne $script:RoadmapCacheMemory -and $script:RoadmapCacheMemory.ContainsKey('entries')) {
                            $roadmapIndexEntries = @($script:RoadmapCacheMemory.entries)
                        } else {
                            $settings = Get-HostSettings
                            $localRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                            $maxDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                            $ttlSeconds = Get-RoadmapCacheTtlSeconds -Settings $settings
                            $cached = Get-RoadmapFromCache -TtlSeconds $ttlSeconds
                            if ($cached.hit) {
                                $roadmapIndexEntries = @($cached.entries)
                            } else {
                                $roadmapIndexEntries = @(Invoke-RoadmapScan -LocalRoots $localRoots -MaxDepth $maxDepth)
                                Save-RoadmapCache -Entries $roadmapIndexEntries -ScannedAt ((Get-Date).ToUniversalTime().ToString('o'))
                            }
                        }
                        $entry = $roadmapIndexEntries | Where-Object { $_.repoName -eq $repoName } | Select-Object -First 1
                        if ($null -ne $entry -and $entry.roadmapPath -and (Test-Path -LiteralPath $entry.roadmapPath)) {
                            $roadmapPath = $entry.roadmapPath
                            $rawContent  = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                            if ($null -eq $rawContent) { $rawContent = '' }
                        }
                        $lintResult = Invoke-LintRoadmapContent -RawContent $rawContent -RepoName $repoName
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $lintResult
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.lint'
                    }
                }
                'POST /api/roadmap/lint/scan' {
                    Write-HostLog ("[TRACE] roadmap.lint.scan correlationId={0} start" -f $correlationId)
                    try {
                        $results = [System.Collections.Generic.List[object]]::new()
                        $roadmapIndexEntries = @()
                        if ($null -ne $script:RoadmapCacheMemory -and $script:RoadmapCacheMemory.ContainsKey('entries')) {
                            $roadmapIndexEntries = @($script:RoadmapCacheMemory.entries)
                        } else {
                            $settings = Get-HostSettings
                            $localRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                            $maxDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                            $ttlSeconds = Get-RoadmapCacheTtlSeconds -Settings $settings
                            $cached = Get-RoadmapFromCache -TtlSeconds $ttlSeconds
                            if ($cached.hit) {
                                $roadmapIndexEntries = @($cached.entries)
                            } else {
                                $roadmapIndexEntries = @(Invoke-RoadmapScan -LocalRoots $localRoots -MaxDepth $maxDepth)
                                Save-RoadmapCache -Entries $roadmapIndexEntries -ScannedAt ((Get-Date).ToUniversalTime().ToString('o'))
                            }
                        }
                        foreach ($entry in $roadmapIndexEntries) {
                            $rawContent = ''
                            if ($entry.roadmapPath -and (Test-Path -LiteralPath $entry.roadmapPath)) {
                                try {
                                    $rawContent = Get-Content -LiteralPath $entry.roadmapPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                                    if ($null -eq $rawContent) { $rawContent = '' }
                                } catch { $rawContent = '' }
                            }
                            $lintResult = Invoke-LintRoadmapContent -RawContent $rawContent -RepoName $entry.repoName
                            $results.Add($lintResult)
                        }
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success   = $true
                            data      = @{
                                results   = @($results)
                                count     = $results.Count
                                scannedAt = (Get-Date).ToUniversalTime().ToString('o')
                            }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.lint.scan'
                    }
                }
                # -------------------------------------------------------
                # Release 1.1 — README Standardization
                # -------------------------------------------------------
                'POST /api/readme/standardize/preview' {
                    Write-HostLog ("[TRACE] readme.standardize.preview correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        $repoName = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default $null)
                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName is required for /api/readme/standardize/preview'
                        }
                        $repoPath = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoPath' -Default '')

                        # Try to find repo path from roadmap index if not provided
                        if ([string]::IsNullOrWhiteSpace($repoPath)) {
                            $roadmapIndexEntries = @()
                            if ($null -ne $script:RoadmapCacheMemory -and $script:RoadmapCacheMemory.ContainsKey('entries')) {
                                $roadmapIndexEntries = @($script:RoadmapCacheMemory.entries)
                            }
                            $indexEntry = $roadmapIndexEntries | Where-Object {
                                [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '') -eq $repoName
                            } | Select-Object -First 1
                            $indexedRepoPath = [string](Get-ObjectPropertyValue -InputObject $indexEntry -PropertyName 'repoPath' -Default '')
                            if (-not [string]::IsNullOrWhiteSpace($indexedRepoPath)) {
                                $repoPath = $indexedRepoPath
                            }
                        }

                        $preview = Invoke-PreviewReadmeStandardization -RepoName $repoName -RepoPath $repoPath
                        Write-HostLog ("[TRACE] readme.standardize.preview repoName={0} previewState={1}" -f $repoName, $preview.previewState)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $preview
                        }
                    } catch {
                        $statusCode = Get-ErrorStatusCode -Message $_.Exception.Message -DefaultStatusCode 500
                        Send-ErrorJson -Stream $req.Stream -StatusCode $statusCode -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'readme.standardize.preview'
                    }
                }
                'POST /api/readme/standardize/apply' {
                    Write-HostLog ("[TRACE] readme.standardize.apply correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        $repoName        = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default $null)
                        $previewId       = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'previewId' -Default $null)
                        $proposedContent = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'proposedContent' -Default $null)
                        $repoPath        = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoPath' -Default '')
                        if ([string]::IsNullOrWhiteSpace($repoName))       { throw 'repoName is required' }
                        if ([string]::IsNullOrWhiteSpace($previewId))      { throw 'previewId is required' }
                        if ([string]::IsNullOrWhiteSpace($proposedContent)) { throw 'proposedContent is required' }

                        if ([string]::IsNullOrWhiteSpace($repoPath)) {
                            $roadmapIndexEntries = @()
                            if ($null -ne $script:RoadmapCacheMemory -and $script:RoadmapCacheMemory.ContainsKey('entries')) {
                                $roadmapIndexEntries = @($script:RoadmapCacheMemory.entries)
                            }
                            $indexEntry = $roadmapIndexEntries | Where-Object {
                                [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'repoName' -Default '') -eq $repoName
                            } | Select-Object -First 1
                            $indexedRepoPath = [string](Get-ObjectPropertyValue -InputObject $indexEntry -PropertyName 'repoPath' -Default '')
                            if (-not [string]::IsNullOrWhiteSpace($indexedRepoPath)) {
                                $repoPath = $indexedRepoPath
                            }
                        }

                        $applyResult = Invoke-ApplyReadmeStandardization -RepoName $repoName -PreviewId $previewId -ProposedContent $proposedContent -RepoPath $repoPath
                        Write-HostLog ("[TRACE] readme.standardize.apply repoName={0} success={1}" -f $repoName, $applyResult.success)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $applyResult
                        }
                    } catch {
                        $statusCode = Get-ErrorStatusCode -Message $_.Exception.Message -DefaultStatusCode 500
                        Send-ErrorJson -Stream $req.Stream -StatusCode $statusCode -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'readme.standardize.apply'
                    }
                }
                'GET /api/readme/standardize/history' {
                    Write-HostLog ("[TRACE] readme.standardize.history correlationId={0} start" -f $correlationId)
                    try {
                        $q = Parse-QueryString -Query $req.Query
                        $limit = if ($q.ContainsKey('limit') -and $q.limit -match '^\d+$') { [int]$q.limit } else { 25 }
                        if ($limit -gt 200) { $limit = 200 }
                        $historyPath = Join-Path $WorkspaceRoot 'output\readme-standardization-history\standardization-history.jsonl'
                        $items = [System.Collections.Generic.List[object]]::new()
                        if (Test-Path -LiteralPath $historyPath) {
                            $lines = Get-Content -LiteralPath $historyPath -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -Last $limit
                            foreach ($line in $lines) {
                                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                                try {
                                    $entry = $line | ConvertFrom-Json
                                    $items.Add([pscustomobject]@{
                                        previewId = [string](Get-ObjectPropertyValue -InputObject $entry -PropertyName 'previewId' -Default '')
                                        repoName  = [string](Get-ObjectPropertyValue -InputObject $entry -PropertyName 'repoName' -Default '')
                                        repoPath  = [string](Get-ObjectPropertyValue -InputObject $entry -PropertyName 'repoPath' -Default $null)
                                        event     = [string](Get-ObjectPropertyValue -InputObject $entry -PropertyName 'event' -Default 'apply')
                                        timestamp = [string](Get-ObjectPropertyValue -InputObject $entry -PropertyName 'timestamp' -Default (Get-ObjectPropertyValue -InputObject $entry -PropertyName 'appliedAt' -Default ''))
                                        appliedAt = [string](Get-ObjectPropertyValue -InputObject $entry -PropertyName 'appliedAt' -Default $null)
                                    })
                                } catch { }
                            }
                        }
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{ items = @($items); count = $items.Count }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'readme.standardize.history'
                    }
                }
                # -------------------------------------------------------
                # Release 1.2 — Cross-Repo Dependency Tracking
                # -------------------------------------------------------
                'GET /api/roadmap/dependencies' {
                    Write-HostLog ("[TRACE] roadmap.dependencies correlationId={0} start" -f $correlationId)
                    try {
                        $settings    = Get-HostSettings
                        $gitHubOwner = if ($settings.ContainsKey('reconcile') -and $settings.reconcile.ContainsKey('gitHubOwner')) { [string]$settings.reconcile.gitHubOwner } else { '' }

                        # Reuse the roadmap cache for content
                        $ttlSeconds   = Get-RoadmapCacheTtlSeconds -Settings $settings
                        $roadmapCache = Get-RoadmapFromCache -TtlSeconds $ttlSeconds
                        $entries      = if ($roadmapCache.hit) { @($roadmapCache.entries) } else {
                            $defaultRoots    = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                            $defaultMaxDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth')) { [int]$settings.inventory.maxDepth } else { 3 }
                            $scannedAt = (Get-Date).ToUniversalTime().ToString('o')
                            $scanned = Invoke-RoadmapScan -LocalRoots $defaultRoots -MaxDepth $defaultMaxDepth
                            Save-RoadmapCache -Entries $scanned -ScannedAt $scannedAt
                            @($scanned)
                        }

                        $depResult = Invoke-ScanRoadmapDependencies -RoadmapEntries $entries -GitHubOwner $gitHubOwner
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{
                                graph      = $depResult.graph
                                summary    = $depResult.summary
                                totalEdges = $depResult.totalEdges
                                scannedAt  = $depResult.scannedAt
                            }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage ("Failed to scan roadmap dependencies: {0}" -f $_.Exception.Message) -CorrelationId $correlationId -Operation 'roadmap.dependencies'
                    }
                }

                # -------------------------------------------------------
                # Release 1.1 — Contract Drift Alerts
                # -------------------------------------------------------
                'GET /api/roadmap/drift' {
                    Write-HostLog ("[TRACE] roadmap.drift correlationId={0} start" -f $correlationId)
                    try {
                        $roadmapAuditEntries = @()
                        $cachedAudit = $script:RoadmapAuditCacheMemory
                        if ($null -ne $cachedAudit -and $cachedAudit.ContainsKey('entries')) {
                            $roadmapAuditEntries = @($cachedAudit.entries)
                        }
                        $driftResult = Get-MaturityDrift -WorkspaceRoot $WorkspaceRoot -CurrentAuditEntries $roadmapAuditEntries
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $driftResult
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.drift'
                    }
                }
                'POST /api/roadmap/drift/baseline' {
                    Write-HostLog ("[TRACE] roadmap.drift.baseline correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        $repoName = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default $null)
                        $targetLevel = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'targetLevel' -Default $null)
                        if ([string]::IsNullOrWhiteSpace($repoName))    { throw 'repoName is required' }
                        if ([string]::IsNullOrWhiteSpace($targetLevel)) { throw 'targetLevel is required' }
                        $result = Set-MaturityBaseline -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -TargetLevel $targetLevel
                        Write-HostLog ("[TRACE] roadmap.drift.baseline repoName={0} targetLevel={1}" -f $repoName, $targetLevel)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $result
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.drift.baseline'
                    }
                }
                'POST /api/roadmap/drift/acknowledge' {
                    Write-HostLog ("[TRACE] roadmap.drift.acknowledge correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        $repoName = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default $null)
                        if ([string]::IsNullOrWhiteSpace($repoName)) { throw 'repoName is required' }
                        $result = Confirm-MaturityDriftAcknowledged -WorkspaceRoot $WorkspaceRoot -RepoName $repoName
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $result
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.drift.acknowledge'
                    }
                }
                # -------------------------------------------------------
                # Release 1.1 — Notification Webhooks
                # -------------------------------------------------------
                'GET /api/notifications/webhooks' {
                    Write-HostLog ("[TRACE] notifications.webhooks.get correlationId={0} start" -f $correlationId)
                    try {
                        $webhooks = Get-NotificationWebhooks -WorkspaceRoot $WorkspaceRoot
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{ webhooks = @($webhooks); count = @($webhooks).Count }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'notifications.webhooks.get'
                    }
                }
                'POST /api/notifications/webhooks' {
                    Write-HostLog ("[TRACE] notifications.webhooks.register correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        $webhookUrl = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'url' -Default $null)
                        $label = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'label' -Default '')
                        $events = @(Get-ObjectPropertyValue -InputObject $body -PropertyName 'events' -Default @())
                        if ([string]::IsNullOrWhiteSpace($webhookUrl)) { throw 'url is required' }
                        $result = Register-NotificationWebhook -WorkspaceRoot $WorkspaceRoot -WebhookUrl $webhookUrl -Events $events -Label $label
                        Write-HostLog ("[TRACE] notifications.webhooks.register id={0} url={1}" -f $result.id, $webhookUrl)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $result
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'notifications.webhooks.register'
                    }
                }
                'POST /api/notifications/webhooks/remove' {
                    Write-HostLog ("[TRACE] notifications.webhooks.remove correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        $webhookId = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'id' -Default $null)
                        if ([string]::IsNullOrWhiteSpace($webhookId)) { throw 'id is required' }
                        $result = Remove-NotificationWebhook -WorkspaceRoot $WorkspaceRoot -WebhookId $webhookId
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $result
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'notifications.webhooks.remove'
                    }
                }
                # -------------------------------------------------------
                # Release 1.4 — Repo Evaluation Pipeline
                # -------------------------------------------------------
                'POST /api/repo/evaluate' {
                    Write-HostLog ("[TRACE] repo.evaluate correlationId={0} start" -f $correlationId)
                    try {
                        $body     = Parse-JsonBody -Body $req.Body
                        $repoName = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default '')
                        $localPath = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'localPath' -Default '')

                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName is required for /api/repo/evaluate'
                        }

                        # Resolve local path from roadmap index if not supplied
                        if ([string]::IsNullOrWhiteSpace($localPath)) {
                            $settings     = Get-HostSettings
                            $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                            $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                            $ttlSeconds   = Get-RoadmapCacheTtlSeconds -Settings $settings
                            $cached       = Get-RoadmapFromCache -TtlSeconds $ttlSeconds
                            $indexEntries = if ($cached.hit) { @($cached.entries) } else { @(Invoke-RoadmapScan -LocalRoots $defaultRoots -MaxDepth $defaultDepth) }
                            $match        = $indexEntries | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1
                            if ($null -ne $match -and -not [string]::IsNullOrWhiteSpace($match.localPath)) {
                                $localPath = [string]$match.localPath
                            } elseif ($null -ne $match -and -not [string]::IsNullOrWhiteSpace($match.roadmapPath)) {
                                # Fall back to the directory containing the roadmap
                                $localPath = [System.IO.Path]::GetDirectoryName([string]$match.roadmapPath)
                            }
                        }

                        if ([string]::IsNullOrWhiteSpace($localPath) -or -not (Test-Path -LiteralPath $localPath -PathType Container)) {
                            throw "Local path for repo '$repoName' could not be resolved. Pass localPath explicitly or ensure a roadmap scan has been run."
                        }

                        $result = Invoke-RepoEvaluation -RepoName $repoName -LocalPath $localPath -HistoryRoot $script:RepoEvaluationHistoryRoot
                        Add-MetricCounter -Name 'api_requests_total'
                        Write-HostLog ("[TRACE] repo.evaluate correlationId={0} done repoName={1} findings={2} hasRoadmap={3}" -f $correlationId, $repoName, $result.findingCount, $result.hasExistingRoadmap)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $result
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'repo.evaluate'
                    }
                }
                'GET /api/repo/evaluate/history' {
                    Write-HostLog ("[TRACE] repo.evaluate.history correlationId={0} start" -f $correlationId)
                    try {
                        $q        = Parse-QueryString -Query $req.Query
                        $limit    = if ($q.ContainsKey('limit') -and $q.limit -match '^\d+$') { [int]$q.limit } else { 25 }
                        if ($limit -gt 100) { $limit = 100 }
                        $filterRepo = if ($q.ContainsKey('repoName') -and $q.repoName) { [System.Uri]::UnescapeDataString([string]$q.repoName) } else { '' }
                        $items = @(Get-RepoEvaluationHistory -HistoryRoot $script:RepoEvaluationHistoryRoot -Limit $limit -RepoName $filterRepo)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{ items = @($items); count = @($items).Count }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'repo.evaluate.history'
                    }
                }
                'POST /api/repo/roadmap/create' {
                    Write-HostLog ("[TRACE] repo.roadmap.create correlationId={0} start" -f $correlationId)
                    try {
                        $body      = Parse-JsonBody -Body $req.Body
                        $repoName  = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default '')
                        $localPath = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'localPath' -Default '')
                        $content   = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'content' -Default '')

                        if ([string]::IsNullOrWhiteSpace($repoName)) { throw 'repoName is required' }
                        if ([string]::IsNullOrWhiteSpace($content))  { throw 'content is required' }

                        # Resolve local path from index if not supplied
                        if ([string]::IsNullOrWhiteSpace($localPath)) {
                            $settings     = Get-HostSettings
                            $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                            $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                            $ttlSeconds   = Get-RoadmapCacheTtlSeconds -Settings $settings
                            $cached       = Get-RoadmapFromCache -TtlSeconds $ttlSeconds
                            $indexEntries = if ($cached.hit) { @($cached.entries) } else { @(Invoke-RoadmapScan -LocalRoots $defaultRoots -MaxDepth $defaultDepth) }
                            $match        = $indexEntries | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1
                            if ($null -ne $match -and -not [string]::IsNullOrWhiteSpace($match.localPath)) {
                                $localPath = [string]$match.localPath
                            } elseif ($null -ne $match -and -not [string]::IsNullOrWhiteSpace($match.roadmapPath)) {
                                $localPath = [System.IO.Path]::GetDirectoryName([string]$match.roadmapPath)
                            }
                        }

                        if ([string]::IsNullOrWhiteSpace($localPath) -or -not (Test-Path -LiteralPath $localPath -PathType Container)) {
                            throw "Local path for repo '$repoName' could not be resolved. Pass localPath explicitly."
                        }

                        $roadmapPath = Join-Path $localPath 'ROADMAP.md'
                        if (Test-Path -LiteralPath $roadmapPath -PathType Leaf) {
                            throw "ROADMAP.md already exists for '$repoName'. Use roadmap repair/apply to update it."
                        }

                        Set-Content -LiteralPath $roadmapPath -Value $content -Encoding UTF8 -NoNewline:$false
                        # Invalidate roadmap cache so next scan picks up the new file
                        $script:RoadmapCacheMemory = @{}
                        Add-MetricCounter -Name 'api_requests_total'
                        Write-HostLog ("[TRACE] repo.roadmap.create correlationId={0} done repoName={1} path={2}" -f $correlationId, $repoName, $roadmapPath)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success  = $true
                            data     = @{ repoName = $repoName; roadmapPath = $roadmapPath; createdAt = (Get-Date).ToUniversalTime().ToString('o') }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'repo.roadmap.create'
                    }
                }
                # -------------------------------------------------------
                # Release 1.1 — Roadmap Completion Update Preview
                # -------------------------------------------------------
                'POST /api/roadmap/completion-preview' {
                    Write-HostLog ("[TRACE] roadmap.completion-preview correlationId={0} start" -f $correlationId)
                    try {
                        $body = Parse-JsonBody -Body $req.Body
                        $repoName = [string](Get-ObjectPropertyValue -InputObject $body -PropertyName 'repoName' -Default $null)
                        $completedItems = @(Get-ObjectPropertyValue -InputObject $body -PropertyName 'completedItems' -Default @())
                        if ([string]::IsNullOrWhiteSpace($repoName)) { throw 'repoName is required' }

                        # Load current roadmap content
                        $roadmapPath = $null
                        $rawContent  = ''
                        $roadmapIndexEntries = @()
                        if ($null -ne $script:RoadmapCacheMemory -and $script:RoadmapCacheMemory.ContainsKey('entries')) {
                            $roadmapIndexEntries = @($script:RoadmapCacheMemory.entries)
                        }
                        $indexEntry = $roadmapIndexEntries | Where-Object { $_.repoName -eq $repoName } | Select-Object -First 1
                        if ($null -ne $indexEntry -and $indexEntry.roadmapPath -and (Test-Path -LiteralPath $indexEntry.roadmapPath)) {
                            $roadmapPath = $indexEntry.roadmapPath
                            $rawContent  = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                            if ($null -eq $rawContent) { $rawContent = '' }
                        }

                        if ([string]::IsNullOrWhiteSpace($rawContent)) {
                            throw "No roadmap content found for repo '$repoName'"
                        }

                        # Release 3.1 — this used to carry its own inline
                        # `- [ ]` -> `- [x]` rewrite. Two generators for the
                        # same edit is how a gate gets bypassed: the moment
                        # someone adds an apply route for this preview, the
                        # merge-evidence gate would be nowhere near it. There
                        # is now exactly one generator, and the module smoke
                        # asserts that.
                        #
                        # This route stays PREVIEW-ONLY and ungated on purpose:
                        # it proposes an edit from a caller-supplied item list
                        # and writes nothing. Marking an item complete for real
                        # goes through /api/roadmap/write-back/*, which refuses
                        # without merge evidence.
                        $completionEdit = New-RoadmapCompletionEdit -Content $rawContent -ItemTexts @($completedItems | ForEach-Object { [string]$_ })

                        $previewId = [guid]::NewGuid().ToString('n')
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{
                                previewId        = $previewId
                                repoName         = $repoName
                                roadmapPath      = $roadmapPath
                                currentContent   = $rawContent
                                proposedContent  = [string]$completionEdit.proposedContent
                                markedCount      = $completionEdit.markedCount
                                completedItems   = @($completedItems)
                                alreadyComplete  = @($completionEdit.alreadyComplete)
                                notFound         = @($completionEdit.notFound)
                                diff             = @($completionEdit.diff)
                                generatedAt      = (Get-Date).ToUniversalTime().ToString('o')
                                note             = 'Preview only, and ungated: it writes nothing. Recording completion for real goes through POST /api/roadmap/write-back/apply, which refuses without merge evidence.'
                            }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.completion-preview'
                    }
                }
                # -------------------------------------------------------
                # Release 3.1 — roadmap completion write-back, gated on
                # merge evidence.
                #
                # Preview and apply share one resolver, and apply re-runs the
                # gate from scratch rather than trusting the preview it was
                # handed: a preview is a claim about a moment, and the moment
                # an operator clicks apply is a different one.
                #
                # A refusal is a 409 with its codes, never a 200 carrying
                # changed=false — the caller must not be able to read "nothing
                # was marked" as success.
                # -------------------------------------------------------
                'POST /api/roadmap/write-back/preview' {
                    Write-HostLog ("[TRACE] roadmap.write-back.preview correlationId={0} start" -f $correlationId)
                    try {
                        $wbBody = Parse-JsonBody -Body $req.Body
                        $wbId = [string](Get-ObjectPropertyValue -InputObject $wbBody -PropertyName 'id' -Default '')
                        if ([string]::IsNullOrWhiteSpace($wbId)) { throw 'id is required (a packetId, packaging runId, dispatch runId, or agent-run id).' }
                        $wbItemText = [string](Get-ObjectPropertyValue -InputObject $wbBody -PropertyName 'itemText' -Default '')
                        $wbRoadmapPath = [string](Get-ObjectPropertyValue -InputObject $wbBody -PropertyName 'roadmapPath' -Default '')

                        $wbCtx = Resolve-WriteBackContext -Id $wbId -ItemTextOverride $wbItemText -RoadmapPathOverride $wbRoadmapPath -CorrelationId $correlationId
                        Add-MetricCounter -Name 'api_requests_total'
                        if (-not $wbCtx.ok) {
                            Send-HttpJson -Stream $req.Stream -StatusCode $wbCtx.statusCode -StatusText $(if ($wbCtx.statusCode -eq 404) { 'Not Found' } else { 'Conflict' }) -CorrelationId $correlationId -Payload @{
                                success = $false; error = [string]$wbCtx.error; category = [string]$wbCtx.category
                            }
                        }
                        elseif (-not $wbCtx.gate.allowed) {
                            Write-HostLog ("[TRACE] roadmap.write-back.preview correlationId={0} id={1} REFUSED codes={2}" -f $correlationId, $wbId, (@($wbCtx.gate.refusalCodes) -join ','))
                            Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                                success  = $false
                                error    = ("Completion cannot be claimed for this item: {0}" -f (@($wbCtx.gate.refusals | ForEach-Object { [string]$_.message }) -join ' '))
                                category = 'write-back-refused'
                                data     = @{
                                    refused  = $true
                                    refusals = @($wbCtx.gate.refusals)
                                    evidence = $wbCtx.evidence
                                    itemText = [string]$wbCtx.itemText
                                }
                            }
                        }
                        else {
                            $wbContent = Get-Content -LiteralPath $wbCtx.roadmapPath -Raw -Encoding UTF8
                            if ($null -eq $wbContent) { $wbContent = '' }
                            $wbEdit = New-RoadmapCompletionEdit -Content $wbContent -ItemTexts @($wbCtx.itemText)
                            if (-not $wbEdit.changed) {
                                $wbWhy = if (@($wbEdit.alreadyComplete).Count -gt 0) {
                                    "'$($wbCtx.itemText)' is already marked complete in $($wbCtx.roadmapPath)."
                                } else {
                                    "No open checkbox matching '$($wbCtx.itemText)' exists in $($wbCtx.roadmapPath). Matching is exact on purpose — a fuzzy match would eventually tick the wrong line."
                                }
                                Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                                    success  = $false
                                    error    = $wbWhy
                                    category = $(if (@($wbEdit.alreadyComplete).Count -gt 0) { 'already-complete' } else { 'no-matching-item' })
                                    data     = @{ alreadyComplete = @($wbEdit.alreadyComplete); notFound = @($wbEdit.notFound) }
                                }
                            }
                            else {
                                $wbRecord = Write-RoadmapWriteBackRecord -WorkspaceRoot $WorkspaceRoot -RunId $wbCtx.dispatchRunId `
                                    -PacketId $wbCtx.packetId -RepoName $wbCtx.repoName -RoadmapPath $wbCtx.roadmapPath `
                                    -ItemText $wbCtx.itemText -MarkedCount $wbEdit.markedCount -Evidence $wbCtx.evidence -Gate $wbCtx.gate -Actor 'api'
                                Write-HostLog ("[TRACE] roadmap.write-back.preview correlationId={0} id={1} previewId={2} marked={3}" -f $correlationId, $wbId, $wbRecord.recordId, $wbEdit.markedCount)
                                Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                    success = $true
                                    data    = @{
                                        previewId       = [string]$wbRecord.recordId
                                        runId           = [string]$wbCtx.dispatchRunId
                                        repoName        = [string]$wbCtx.repoName
                                        roadmapPath     = [string]$wbCtx.roadmapPath
                                        itemText        = [string]$wbCtx.itemText
                                        markedCount     = $wbEdit.markedCount
                                        diff            = @($wbEdit.diff)
                                        proposedContent = [string]$wbEdit.proposedContent
                                        evidence        = $wbCtx.evidence
                                        applied         = $false
                                        note            = 'Preview only. POST /api/roadmap/write-back/apply re-checks the merge evidence before writing.'
                                    }
                                }
                            }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.write-back.preview'
                    }
                }
                'POST /api/roadmap/write-back/apply' {
                    Write-HostLog ("[TRACE] roadmap.write-back.apply correlationId={0} start" -f $correlationId)
                    try {
                        $wbaBody = Parse-JsonBody -Body $req.Body
                        $wbaId = [string](Get-ObjectPropertyValue -InputObject $wbaBody -PropertyName 'id' -Default '')
                        if ([string]::IsNullOrWhiteSpace($wbaId)) { throw 'id is required (a packetId, packaging runId, dispatch runId, or agent-run id).' }
                        $wbaItemText = [string](Get-ObjectPropertyValue -InputObject $wbaBody -PropertyName 'itemText' -Default '')
                        $wbaRoadmapPath = [string](Get-ObjectPropertyValue -InputObject $wbaBody -PropertyName 'roadmapPath' -Default '')
                        $wbaPreviewId = [string](Get-ObjectPropertyValue -InputObject $wbaBody -PropertyName 'previewId' -Default '')
                        # 'proposedContent' is still accepted in the body for caller
                        # compatibility but no longer read: this route stopped writing
                        # file content under Release 3.4 milestone 4, so there is no
                        # write for a stale preview to corrupt.

                        $wbaCtx = Resolve-WriteBackContext -Id $wbaId -ItemTextOverride $wbaItemText -RoadmapPathOverride $wbaRoadmapPath -CorrelationId $correlationId
                        Add-MetricCounter -Name 'api_requests_total'
                        if (-not $wbaCtx.ok) {
                            Send-HttpJson -Stream $req.Stream -StatusCode $wbaCtx.statusCode -StatusText $(if ($wbaCtx.statusCode -eq 404) { 'Not Found' } else { 'Conflict' }) -CorrelationId $correlationId -Payload @{
                                success = $false; error = [string]$wbaCtx.error; category = [string]$wbaCtx.category
                            }
                        }
                        elseif (-not $wbaCtx.gate.allowed) {
                            # Re-checked, not inherited. A preview that passed
                            # the gate five minutes ago proves nothing now.
                            Write-HostLog ("[TRACE] roadmap.write-back.apply correlationId={0} id={1} REFUSED codes={2}" -f $correlationId, $wbaId, (@($wbaCtx.gate.refusalCodes) -join ','))
                            Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                                success  = $false
                                error    = ("Completion cannot be claimed for this item: {0}" -f (@($wbaCtx.gate.refusals | ForEach-Object { [string]$_.message }) -join ' '))
                                category = 'write-back-refused'
                                data     = @{ refused = $true; refusals = @($wbaCtx.gate.refusals); evidence = $wbaCtx.evidence }
                            }
                        }
                        else {
                            # Release 3.4 milestone 4 — completion travels through the
                            # pull request, never after it. This route used to write the
                            # checkbox itself with a bare Set-Content on whatever branch
                            # was checked out — main, at this point in the loop. Now the
                            # runner commits the edit on the feature branch and the merge
                            # makes it authoritative; behind the merge-evidence gate this
                            # route VERIFIES the merged state and records it, and writes
                            # nothing. The two outcomes therefore invert: a checkbox that
                            # is already [x] is the success (the PR carried it), and one
                            # still open is the refusal (it did not).
                            $wbaContent = Get-Content -LiteralPath $wbaCtx.roadmapPath -Raw -Encoding UTF8
                            if ($null -eq $wbaContent) { $wbaContent = '' }
                            $wbaEdit = New-RoadmapCompletionEdit -Content $wbaContent -ItemTexts @($wbaCtx.itemText)
                            if (@($wbaEdit.alreadyComplete).Count -gt 0) {
                                $wbaRecord = Write-RoadmapWriteBackRecord -WorkspaceRoot $WorkspaceRoot -RunId $wbaCtx.dispatchRunId `
                                    -PacketId $wbaCtx.packetId -RepoName $wbaCtx.repoName -RoadmapPath $wbaCtx.roadmapPath `
                                    -ItemText $wbaCtx.itemText -Applied -Action 'verified-merged' -MarkedCount (@($wbaEdit.alreadyComplete).Count) `
                                    -Evidence $wbaCtx.evidence -Gate $wbaCtx.gate -Actor 'operator' -PreviewId $wbaPreviewId
                                Write-HostLog ("[TRACE] roadmap.write-back.apply correlationId={0} id={1} verified-merged path={2}" -f $correlationId, $wbaId, $wbaCtx.roadmapPath)
                                Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                                    success = $true
                                    data    = @{
                                        applied     = $false
                                        verified    = $true
                                        recordId    = [string]$wbaRecord.recordId
                                        runId       = [string]$wbaCtx.dispatchRunId
                                        repoName    = [string]$wbaCtx.repoName
                                        roadmapPath = [string]$wbaCtx.roadmapPath
                                        itemText    = [string]$wbaCtx.itemText
                                        markedCount = @($wbaEdit.alreadyComplete).Count
                                        diff        = @()
                                        evidence    = $wbaCtx.evidence
                                        message     = ("'{0}' is marked complete in the merged roadmap; completion recorded as verified." -f $wbaCtx.itemText)
                                    }
                                }
                            }
                            elseif ($wbaEdit.changed) {
                                # The checkbox is still open after the merge: the
                                # completion edit never travelled through the PR. The
                                # old behavior wrote it to the default branch right
                                # here; that path is closed by name.
                                Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                                    success  = $false
                                    error    = ("'{0}' is still unchecked in {1}, so the merged pull request did not carry its completion edit. Completion travels through the PR: the task runner commits the edit on the feature branch (Release 3.4). Land it through a PR — this route no longer writes to a default branch." -f $wbaCtx.itemText, $wbaCtx.roadmapPath)
                                    category = 'completion-not-merged'
                                }
                            }
                            else {
                                Send-HttpJson -Stream $req.Stream -StatusCode 409 -StatusText 'Conflict' -CorrelationId $correlationId -Payload @{
                                    success  = $false
                                    error    = "No open checkbox matching '$($wbaCtx.itemText)' exists in $($wbaCtx.roadmapPath)."
                                    category = 'no-matching-item'
                                }
                            }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.write-back.apply'
                    }
                }
                'GET /api/log/tail' {
                    $q = Parse-QueryString -Query $req.Query
                    $maxLines = if ($q.ContainsKey('lines') -and $q.lines) { [int]$q.lines } else { 100 }
                    if ($maxLines -gt 500) { $maxLines = 500 }
                    $level = if ($q.ContainsKey('level')) { [string]$q.level } else { '' }
                    $contains = if ($q.ContainsKey('contains')) { [string]$q.contains } else { '' }

                    # since accepts epoch milliseconds or ISO-8601
                    $sinceIso = ''
                    if ($q.ContainsKey('since') -and -not [string]::IsNullOrWhiteSpace([string]$q.since)) {
                        if ([string]$q.since -match '^\d+$') {
                            $sinceIso = ([datetime]::UnixEpoch.AddMilliseconds([double][long]$q.since)).ToUniversalTime().ToString('o')
                        } else {
                            try {
                                $sinceIso = ([datetime]::Parse([string]$q.since)).ToUniversalTime().ToString('o')
                            } catch {
                                $sinceIso = ''
                            }
                        }
                    }

                    $entries = [System.Collections.Generic.List[object]]::new()
                    $dbEntries = Get-AppDbOpsLogEntries -Since $sinceIso -Level $level -Contains $contains -MaxLines $maxLines
                    if ($dbEntries.available) {
                        foreach ($row in @($dbEntries.entries)) {
                            $entryTs = if ($row.timestamp) { [string]$row.timestamp } else { (Get-Date).ToUniversalTime().ToString('o') }
                            $entryMsg = if ($row.message) { [string]$row.message } else { '' }
                            $entries.Add([pscustomobject]@{
                                ts = $entryTs
                                level = ([string]$row.level).ToUpperInvariant()
                                msg = $entryMsg
                            })
                        }
                    } elseif ($null -ne $script:OpsLogPath -and (Test-Path -LiteralPath $script:OpsLogPath)) {
                        $sinceMs = if ($sinceIso -ne '') { [long](([datetime]$sinceIso).ToUniversalTime() - [datetime]::UnixEpoch).TotalMilliseconds } else { 0 }
                        try {
                            $rawLines = Get-Content -LiteralPath $script:OpsLogPath -Encoding UTF8 -ErrorAction Stop |
                                Select-Object -Last $maxLines
                            foreach ($rawLine in $rawLines) {
                                if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }
                                $parsed = $false
                                try {
                                    $obj = $rawLine | ConvertFrom-Json
                                    # Support both API-host JSONL ({ts,msg}) and structured module logs ({timestamp,message}).
                                    $entryTs = if ($obj.ts) { [string]$obj.ts } elseif ($obj.timestamp) { [string]$obj.timestamp } else { (Get-Date).ToUniversalTime().ToString('o') }
                                    if ($sinceMs -gt 0 -and $entryTs) {
                                        $lineMs = [long](([datetime]$entryTs).ToUniversalTime() - [datetime]::UnixEpoch).TotalMilliseconds
                                        if ($lineMs -le $sinceMs) { continue }
                                    }
                                    $entryLevel = ([string]$obj.level).ToUpperInvariant()
                                    if (-not [string]::IsNullOrWhiteSpace($level) -and $entryLevel -ne $level.ToUpperInvariant()) { continue }
                                    $entryMsg = if ($obj.msg) { [string]$obj.msg } elseif ($obj.message) { [string]$obj.message } else { [string]$rawLine }
                                    if (-not [string]::IsNullOrWhiteSpace($contains) -and $entryMsg.IndexOf($contains, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
                                    $entries.Add([pscustomobject]@{
                                        ts = $entryTs
                                        level = $entryLevel
                                        msg = $entryMsg
                                    })
                                    $parsed = $true
                                } catch { }
                                if (-not $parsed -and $rawLine -match '^\[(?<ts>[^\]]+)\]\s+\[(?<level>[^\]]+)\]\s+(?<msg>.*)$') {
                                    try {
                                        $entryTs = ([datetime]$matches['ts']).ToUniversalTime().ToString('o')
                                    } catch {
                                        $entryTs = (Get-Date).ToUniversalTime().ToString('o')
                                    }
                                    if ($sinceMs -gt 0) {
                                        $lineMs = [long](([datetime]$entryTs).ToUniversalTime() - [datetime]::UnixEpoch).TotalMilliseconds
                                        if ($lineMs -le $sinceMs) { continue }
                                    }
                                    $entryLevel = ([string]$matches['level']).ToUpperInvariant()
                                    if (-not [string]::IsNullOrWhiteSpace($level) -and $entryLevel -ne $level.ToUpperInvariant()) { continue }
                                    $entryMsg = [string]$matches['msg']
                                    if (-not [string]::IsNullOrWhiteSpace($contains) -and $entryMsg.IndexOf($contains, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
                                    $entries.Add([pscustomobject]@{
                                        ts = $entryTs
                                        level = $entryLevel
                                        msg = $entryMsg
                                    })
                                }
                            }
                        } catch { }
                    }

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        entries = @($entries)
                        count = $entries.Count
                        source = if ($dbEntries.available) { 'sqlite' } else { 'jsonl' }
                    }
                }
                default {
                    Add-MetricCounter -Name 'api_requests_total'
                    # Release 1.3 — static frontend serving + SPA catch-all
                    # For GET requests, try to serve from frontend/dist/ first, then SPA fallback.
                    $distIndexHtml = Join-Path $script:FrontendDistPath 'index.html'
                    if ($req.Method -eq 'GET' -and (Test-Path -LiteralPath $distIndexHtml -ErrorAction SilentlyContinue)) {
                        $requestedRelPath = if ([string]::IsNullOrEmpty($path)) { 'index.html' } else { $path.TrimStart('/').Replace('/', [System.IO.Path]::DirectorySeparatorChar) }
                        $distRoot      = [System.IO.Path]::GetFullPath($script:FrontendDistPath)
                        $candidatePath = [System.IO.Path]::GetFullPath((Join-Path $script:FrontendDistPath $requestedRelPath))
                        if ($candidatePath.StartsWith($distRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
                            $candidatePath -eq $distRoot) {
                            if ((Test-Path -LiteralPath $candidatePath -PathType Leaf -ErrorAction SilentlyContinue)) {
                                # Exact file found — serve it directly
                                Send-StaticFile -Stream $req.Stream -FilePath $candidatePath -RequestHeaders $req.Headers -CorrelationId $correlationId
                            } else {
                                # SPA fallback — serve index.html for client-side routes
                                Send-StaticFile -Stream $req.Stream -FilePath $distIndexHtml -RequestHeaders $req.Headers -CorrelationId $correlationId
                            }
                        } else {
                            # Path traversal attempt — serve index.html as safe fallback
                            Send-StaticFile -Stream $req.Stream -FilePath $distIndexHtml -RequestHeaders $req.Headers -CorrelationId $correlationId
                        }
                    } else {
                        Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{ error = 'Not Found'; method = $req.Method; path = $path }
                    }
                }            }
        }
        catch {
            if ($client.Connected) {
                $stream = $client.GetStream()
                $requestCorrelationId = [guid]::NewGuid().ToString('n')
                Send-ErrorJson -Stream $stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $requestCorrelationId -Operation 'api.request'
            }
        }
        finally {
            Clear-RequestDeadline -Controller $script:RequestDeadlineController
            # Symmetric with the deadline: whatever happened to the request, the
            # operation marker must not outlive it, or a completed scan keeps
            # suppressing restarts until it ages out.
            if (Test-PortalOperationActive) {
                $null = Complete-PortalOperation -WorkspaceRoot $WorkspaceRoot -Outcome 'request-ended'
            }
            $client.Close()
        }
    }
}
finally {
    Stop-RequestDeadlineWatchdog -Controller $script:RequestDeadlineController
    $listener.Stop()
    Write-HostLog 'Repo Management API host stopped'
}
