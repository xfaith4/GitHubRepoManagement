# =============================================================================
# Adapters.ps1 — unified adapter layer
# Merges: Adapter.Common.ps1, Status.Adapter.ps1,
#         Reconcile.Adapter.ps1, DocReview.Adapter.ps1
# =============================================================================

# ---------------------------------------------------------------------------
# Shared response envelope (was Adapter.Common.ps1)
# ---------------------------------------------------------------------------

function New-AdapterResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$CorrelationId,

        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [Parameter()]
        [object]$Data,

        # Renamed from $Error (Lane 0.8): a parameter named Error shadows the
        # automatic $Error collection inside this function — the one PSSA
        # Error-severity finding in the repo. The emitted JSON key is
        # unchanged, so the API contract is unaffected.
        [Parameter()]
        [string]$ErrorMessage,

        [Parameter()]
        [hashtable]$Meta
    )

    return [pscustomobject]@{
        operation = $Operation
        correlationId = $CorrelationId
        success = $Success
        timestamp = (Get-Date).ToString('o')
        data = $Data
        error = $ErrorMessage
        meta = if ($Meta) { $Meta } else { @{} }
    }
}

function Get-ErrorCategory {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return 'internal'
    }

    $text = $Message.ToLowerInvariant()
    if ($text -match 'validation|invalid|missing required|cannot bind') {
        return 'validation'
    }
    if ($text -match 'timeout|timed out') {
        return 'timeout'
    }
    if ($text -match 'gh|github|network|dns|socket|connection|api') {
        return 'dependency'
    }

    return 'internal'
}

# ---------------------------------------------------------------------------
# Status adapter (was Status.Adapter.ps1)
# ---------------------------------------------------------------------------

function Get-LocalRepoHeadCommitSha {
    [CmdletBinding()]
    param([Parameter()][string]$RepoPath = '')

    if ([string]::IsNullOrWhiteSpace($RepoPath)) { return '' }
    if (-not (Test-Path -LiteralPath $RepoPath -PathType Container -ErrorAction SilentlyContinue)) { return '' }

    try {
        $sha = & git -C $RepoPath rev-parse HEAD 2>$null
        if ($LASTEXITCODE -ne 0) { return '' }
        $text = [string]$sha
        if ([string]::IsNullOrWhiteSpace($text)) { return '' }
        return $text.Trim()
    } catch {
        return ''
    }
}

function Get-StatusAdapterResult {
    [CmdletBinding()]
    param(
        # No machine-specific default. This is a SCAN TARGET, not the tool's own
        # location, so there is nothing sensible to derive it from — the old
        # 'G:\Development' default silently scanned a drive that does not exist
        # on every machine, producing an empty result that read as "no repos"
        # rather than as a misconfiguration. Every caller passes this
        # explicitly; a caller that forgets now gets told so (ROADMAP Lane 0.3).
        [Parameter()]
        [string[]]$LocalRoots = @(),

        [Parameter()]
        [int]$MaxDepth = 2,

        [Parameter()]
        [switch]$IncludeNonGitFolders,

        [Parameter()]
        [string]$LogPath,

        # Progress tick threaded into the inventory walk so the API host can keep
        # its operation heartbeat fresh during a multi-minute scan; without it the
        # external watchdog reads a working host as frozen and restarts it
        # (portal restart-loop incident, 2026-08-10).
        [Parameter()]
        [scriptblock]$OnProgress
    )

    if (@($LocalRoots).Count -eq 0) {
        throw 'Get-StatusAdapterResult requires -LocalRoots: pass the configured workspace root(s) to scan.'
    }

    $correlationId = [guid]::NewGuid().ToString('n')
    $operation = 'status.scan'

    try {
        $scanStartedAt = Get-Date
        $callerLocalRoots = @($LocalRoots)
        $callerMaxDepth = $MaxDepth
        $callerIncludeNonGitFolders = $IncludeNonGitFolders
        # $LogPath belongs on this list too: Invoke-Reconciliation.ps1 declares
        # its own [string]$LogPath, so the dot-source below blanked the caller's
        # and every structured log in this function silently went to the default
        # path instead of the one the caller asked for. Nothing failed, which is
        # why it survived — the same dot-source-clobbers-caller-scope hazard that
        # killed the dispatch route's $runId outright. The module smoke now
        # derives this restore list from both param blocks, so a parameter added
        # to either script fails a gate instead of quietly eating a value.
        $callerLogPath = $LogPath

        . (Join-Path $PSScriptRoot '..\modules\common\Logging.ps1')
        . (Join-Path $PSScriptRoot '..\modules\reconcile\Invoke-Reconciliation.ps1') -LoadFunctionsOnly
        # Release 3.5 milestone 3 -- the scope classifier rides the producer, so
        # every consumer of this scan inherits the same classification.
        . (Join-Path $PSScriptRoot '..\modules\portfolio\Portfolio.Scope.ps1')

        # Restore caller values after dot-sourcing legacy script with overlapping params.
        $LocalRoots = $callerLocalRoots
        $MaxDepth = $callerMaxDepth
        $IncludeNonGitFolders = $callerIncludeNonGitFolders
        $LogPath = $callerLogPath

        $ignoreDirNames = @(
            'node_modules','vendor','dist','build','out','.vs','.idea','.vscode',
            'bin','obj','.venv','venv','__pycache__','.next','.pytest_cache'
        )
        $ignorePathRegex = @('[/\\]\.git([/\\]|$)')

        Write-StructuredLog -Level Info -Component adapter.status -Operation $operation -CorrelationId $correlationId -Message 'Starting status scan adapter call' -Details @{ LocalRoots = $LocalRoots; MaxDepth = $MaxDepth } -LogPath $LogPath

        # A root that is not on disk is skipped silently by the inventory walk, so
        # the scan succeeds with zero repos and the caller cannot tell a genuinely
        # empty workspace from a wrong path. Report it instead of swallowing it —
        # this is the only signal for a bad root that was saved before validation
        # existed, or for a path that has since been renamed or unmounted.
        $missingRoots = @(@($LocalRoots) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Where-Object { -not (Test-Path -LiteralPath ([string]$_)) } | ForEach-Object { [string]$_ })
        if (@($missingRoots).Count -gt 0) {
            Write-StructuredLog -Level Warning -Component adapter.status -Operation $operation -CorrelationId $correlationId -Message 'Configured local root(s) not found on disk; scan will report zero repositories for them' -Details @{ MissingRoots = $missingRoots } -LogPath $LogPath
        }

        $items = Get-LocalFolderInventory `
            -Roots $LocalRoots `
            -IgnoreDirNames $ignoreDirNames `
            -IgnorePathRegex $ignorePathRegex `
            -MaxDepth $MaxDepth `
            -IncludeNonGitFolders:$IncludeNonGitFolders `
            -OnProgress $OnProgress

        $repos = @(
            @($items) | Where-Object { $_.IsGitRepo } | ForEach-Object {
                $modifiedCount = if ($null -ne $_.ModifiedCount) { [int]$_.ModifiedCount } else { 0 }
                $untrackedCount = if ($null -ne $_.UntrackedCount) { [int]$_.UntrackedCount } else { 0 }
                $dirty = $modifiedCount + $untrackedCount
                [pscustomobject]@{
                    name = $_.GitRepoName
                    folderName = $_.FolderName
                    path = $_.LocalPath
                    branch = $_.CurrentBranch
                    headCommitSha = (Get-LocalRepoHeadCommitSha -RepoPath $_.LocalPath)
                    lastCommitDate = $_.LastCommitDate
                    lastCommitMessage = $_.LastCommitMessage
                    lastCommitAuthor = $_.LastCommitAuthor
                    commitsLastWeek = if ($null -ne $_.CommitsLastWeek) { [int]$_.CommitsLastWeek } else { 0 }
                    commitsLastMonth = if ($null -ne $_.CommitsLastMonth) { [int]$_.CommitsLastMonth } else { 0 }
                    modifiedCount = $modifiedCount
                    untrackedCount = $untrackedCount
                    dirtyCount = $dirty
                    status = if ($dirty -gt 0) { 'dirty' } else { 'clean' }
                    originUrl = $_.GitOriginUrl
                }
            }
        )

        # Release 3.5 milestone 3 -- classify every repo against the scope
        # policy at the producer, and never drop one: an out-of-scope repo is
        # visible behind a toggle, because a scan that silently removes
        # repositories is the same class of lie as a metric that silently
        # counts them. The policy reads from the application settings beside
        # this backend; absent settings fall back to shipped defaults.
        $scopeSettingsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\settings.json'
        $scopeSettings = $null
        if (Test-Path -LiteralPath $scopeSettingsPath) {
            try { $scopeSettings = Get-Content -LiteralPath $scopeSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $scopeSettings = $null }
        }
        $scopePolicy = Get-RepoScopePolicy -Settings $scopeSettings
        $scopeClassifications = [System.Collections.Generic.List[object]]::new()
        foreach ($repoRecord in @($repos)) {
            $classification = Get-RepoScopeClassification -LocalPath ([string]$repoRecord.path) -OriginUrl ([string]$repoRecord.originUrl) -Policy $scopePolicy
            $repoRecord | Add-Member -NotePropertyName 'scope' -NotePropertyValue $classification -Force
            $scopeClassifications.Add($classification) | Out-Null
        }
        $scopeSummary = Get-RepoScopeSummary -Classifications @($scopeClassifications)
        # Same repository, several checkouts: reproduced live 2026-08-15 as
        # Genesys.Core + Genesys.Core_AuditLogsApp (one remote, one root
        # commit). The root-sha subdivision is paid only by colliding groups.
        $duplicateIdentities = @(Group-RepoByRemoteIdentity -Repos @($repos))

        Write-StructuredLog -Level Info -Component adapter.status -Operation $operation -CorrelationId $correlationId -Message 'Status scan adapter call completed' -Details @{ RepoCount = @($repos).Count; ItemCount = @($items).Count; InScope = $scopeSummary.inScope; Excluded = $scopeSummary.excluded } -LogPath $LogPath

        $scanDurationMs = [math]::Round(((Get-Date) - $scanStartedAt).TotalMilliseconds, 0)
        return New-AdapterResponse -Operation $operation -CorrelationId $correlationId -Success $true -Data ([pscustomobject]@{ repos = $repos; scopeSummary = $scopeSummary; duplicateIdentities = $duplicateIdentities }) -Meta @{ localRoots = $LocalRoots; maxDepth = $MaxDepth; repoCount = @($repos).Count; itemCount = @($items).Count; scanDurationMs = $scanDurationMs; missingRoots = $missingRoots }
    }
    catch {
        $errorMessage = $_.Exception.Message
        return New-AdapterResponse `
            -Operation $operation `
            -CorrelationId $correlationId `
            -Success $false `
            -ErrorMessage $errorMessage `
            -Meta @{ errorCategory = (Get-ErrorCategory -Message $errorMessage) }
    }
}

# ---------------------------------------------------------------------------
# Reconcile adapter (was Reconcile.Adapter.ps1)
# ---------------------------------------------------------------------------

function Invoke-ReconcileAdapter {
    [CmdletBinding()]
    param(
        # Scan target, not the tool's own location — see Get-StatusAdapterResult.
        [Parameter()]
        [string[]]$LocalRoots = @(),

        [Parameter()]
        [string]$GitHubOwner,

        [Parameter()]
        [ValidateSet('User','Org','Auto')]
        [string]$OwnerType = 'Auto',

        [Parameter()]
        [string]$OutDir,

        [Parameter()]
        [int]$MaxDepth = 3,

        [Parameter()]
        [switch]$IncludeNonGitFolders = $true,

        [Parameter()]
        [string]$LogPath
    )

    if (@($LocalRoots).Count -eq 0) {
        throw 'Invoke-ReconcileAdapter requires -LocalRoots: pass the configured workspace root(s) to scan.'
    }

    $correlationId = [guid]::NewGuid().ToString('n')
    $operation = 'reconcile.run'

    try {
        . (Join-Path $PSScriptRoot '..\modules\common\Logging.ps1')

        if (-not $OutDir) {
            $OutDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'output\reconcile-adapter'
        }

        Write-StructuredLog -Level Info -Component adapter.reconcile -Operation $operation -CorrelationId $correlationId -Message 'Starting reconcile adapter call' -Details @{ LocalRoots = $LocalRoots; GitHubOwner = $GitHubOwner; OutDir = $OutDir } -LogPath $LogPath

        $result = & (Join-Path $PSScriptRoot '..\modules\reconcile\Invoke-Reconciliation.Modular.ps1') `
            -LocalRoots $LocalRoots `
            -GitHubOwner $GitHubOwner `
            -OwnerType $OwnerType `
            -OutDir $OutDir `
            -MaxDepth $MaxDepth `
            -IncludeNonGitFolders:$IncludeNonGitFolders `
            -LogPath $LogPath

        Write-StructuredLog -Level Info -Component adapter.reconcile -Operation $operation -CorrelationId $correlationId -Message 'Reconcile adapter call completed' -Details @{ JsonPath = $result.JsonPath; ComparisonCount = $result.ComparisonCount } -LogPath $LogPath

        return New-AdapterResponse -Operation $operation -CorrelationId $correlationId -Success $true -Data $result -Meta @{ outDir = $OutDir }
    }
    catch {
        $errorMessage = $_.Exception.Message
        return New-AdapterResponse `
            -Operation $operation `
            -CorrelationId $correlationId `
            -Success $false `
            -ErrorMessage $errorMessage `
            -Meta @{ errorCategory = (Get-ErrorCategory -Message $errorMessage) }
    }
}

# ---------------------------------------------------------------------------
# DocReview adapter (was DocReview.Adapter.ps1)
# ---------------------------------------------------------------------------

function Invoke-DocReviewAdapter {
    [CmdletBinding()]
    param(
        # Scan target, not the tool's own location — see Get-StatusAdapterResult.
        [Parameter()]
        [string]$RootPath = '',

        [Parameter()]
        [int]$MaxDepth = 3,

        [Parameter()]
        [string]$TargetRepo,

        [Parameter()]
        [string]$OutDir,

        [Parameter()]
        [switch]$GenerateQueue = $true,

        [Parameter()]
        [switch]$GenerateBatchPlan,

        [Parameter()]
        [string]$LogPath
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        throw 'Invoke-DocReviewAdapter requires -RootPath: pass the configured workspace root to scan.'
    }

    $correlationId = [guid]::NewGuid().ToString('n')
    $operation = 'docreview.run'

    try {
        . (Join-Path $PSScriptRoot '..\modules\common\Logging.ps1')

        if (-not $OutDir) {
            $OutDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'output\docreview-adapter'
        }
        $inventoryDir = Join-Path $OutDir 'inventory'
        $queueDir = Join-Path $OutDir 'queue'
        $workitemsDir = Join-Path $OutDir 'workitems'

        $null = New-Item -ItemType Directory -Force -Path $inventoryDir
        $null = New-Item -ItemType Directory -Force -Path $queueDir
        $null = New-Item -ItemType Directory -Force -Path $workitemsDir

        Write-StructuredLog -Level Info -Component adapter.docreview -Operation $operation -CorrelationId $correlationId -Message 'Starting doc-review adapter run' -Details @{ RootPath = $RootPath; OutDir = $OutDir; GenerateQueue = $GenerateQueue.IsPresent; GenerateBatchPlan = $GenerateBatchPlan.IsPresent; TargetRepo = $TargetRepo } -LogPath $LogPath

        & (Join-Path $PSScriptRoot '..\modules\docreview\Invoke-DocReviewInventory.ps1') `
            -RootPath $RootPath `
            -OutDir $inventoryDir `
            -MaxDepth $MaxDepth

        $manifestPath = Join-Path $inventoryDir 'doc-review-manifest.json'

        if ($GenerateQueue) {
            & (Join-Path $PSScriptRoot '..\modules\docreview\Build-DocReviewQueue.ps1') `
                -ManifestPath $manifestPath `
                -OutDir $queueDir `
                -MaxFilesPerBatch 5
        }

        if ($GenerateBatchPlan -and -not [string]::IsNullOrWhiteSpace($TargetRepo)) {
            & (Join-Path $PSScriptRoot '..\modules\docreview\Invoke-DocReviewBatchPlan.ps1') `
                -ManifestPath $manifestPath `
                -TargetRepo $TargetRepo `
                -OutDir $workitemsDir
        }

        Write-StructuredLog -Level Info -Component adapter.docreview -Operation $operation -CorrelationId $correlationId -Message 'Doc-review adapter run completed' -Details @{ ManifestPath = $manifestPath } -LogPath $LogPath

        return New-AdapterResponse -Operation $operation -CorrelationId $correlationId -Success $true -Data ([pscustomobject]@{
            inventoryManifestPath = $manifestPath
            inventorySummaryCsvPath = (Join-Path $inventoryDir 'doc-review-summary.csv')
            inventoryReportPath = (Join-Path $inventoryDir 'doc-review-report.md')
            queuePath = if ($GenerateQueue) { Join-Path $queueDir 'doc-review-queue.json' } else { $null }
            workitemsRoot = if ($GenerateBatchPlan -and $TargetRepo) { Join-Path $workitemsDir $TargetRepo } else { $null }
        }) -Meta @{ outDir = $OutDir }
    }
    catch {
        $errorMessage = $_.Exception.Message
        return New-AdapterResponse `
            -Operation $operation `
            -CorrelationId $correlationId `
            -Success $false `
            -ErrorMessage $errorMessage `
            -Meta @{ errorCategory = (Get-ErrorCategory -Message $errorMessage) }
    }
}
