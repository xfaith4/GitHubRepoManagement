[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$LocalRoots = @('G:\Development'),

    [Parameter()]
    [string]$GitHubOwner,

    [Parameter()]
    [ValidateSet('User', 'Org', 'Auto')]
    [string]$OwnerType = 'Auto',

    [Parameter()]
    [string]$OutDir,

    [Parameter()]
    [string]$LogPath,

    [Parameter()]
    [switch]$IncludeNonGitFolders = $true,

    [Parameter()]
    [string[]]$IgnoreDirNames = @(
        'node_modules', 'vendor', 'dist', 'build', 'out', '.vs', '.idea', '.vscode',
        'bin', 'obj', '.venv', 'venv', '__pycache__', '.next', '.pytest_cache'
    ),

    [Parameter()]
    [string[]]$IgnorePathRegex = @(
        '[/\\]\.git([/\\]|$)'
    ),

    [Parameter()]
    [ValidateRange(1, 20)]
    [int]$MaxDepth = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = $PSScriptRoot
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $moduleRoot)
$correlationId = [guid]::NewGuid().ToString('n')

if (-not $OutDir) {
    $OutDir = Join-Path -Path $workspaceRoot -ChildPath 'output\reconciliation'
}

# Preserve caller parameters because dot-sourcing the legacy script defines a
# param block with overlapping variable names/defaults.
$callerLocalRoots = @($LocalRoots)
$callerGitHubOwner = $GitHubOwner
$callerOwnerType = $OwnerType
$callerOutDir = $OutDir
$callerLogPath = $LogPath
$callerIncludeNonGitFolders = $IncludeNonGitFolders
$callerIgnoreDirNames = @($IgnoreDirNames)
$callerIgnorePathRegex = @($IgnorePathRegex)
$callerMaxDepth = $MaxDepth

# Load shared logger
. (Join-Path $workspaceRoot 'modules\common\Logging.ps1')
. (Join-Path $workspaceRoot 'modules\common\Metrics.ps1')
. (Join-Path $workspaceRoot 'modules\common\Retry.ps1')

# Load proven function library from copied script without executing workflow
. (Join-Path $moduleRoot 'Invoke-Reconciliation.ps1') -LoadFunctionsOnly

# Restore caller values after function load.
$LocalRoots = $callerLocalRoots
$GitHubOwner = $callerGitHubOwner
$OwnerType = $callerOwnerType
$OutDir = $callerOutDir
$LogPath = $callerLogPath
$IncludeNonGitFolders = $callerIncludeNonGitFolders
$IgnoreDirNames = $callerIgnoreDirNames
$IgnorePathRegex = $callerIgnorePathRegex
$MaxDepth = $callerMaxDepth

# Load modular wrappers
. (Join-Path $moduleRoot 'Reconcile.Scanner.ps1')
. (Join-Path $moduleRoot 'Reconcile.Matcher.ps1')
. (Join-Path $moduleRoot 'Reconcile.Reporter.ps1')

Write-StructuredLog -Level Info -Component reconcile -Operation reconcile.run -CorrelationId $correlationId -Message 'Starting modular reconciliation run' -Details @{ LocalRoots = $LocalRoots; GitHubOwner = $GitHubOwner; OwnerType = $OwnerType; OutDir = $OutDir } -LogPath $LogPath
$runStart = Get-Date
Add-MetricCounter -Name 'reconcile_runs_total'

$localItems = Invoke-ReconcileScan `
    -LocalRoots $LocalRoots `
    -IgnoreDirNames $IgnoreDirNames `
    -IgnorePathRegex $IgnorePathRegex `
    -MaxDepth $MaxDepth `
    -IncludeNonGitFolders:$IncludeNonGitFolders

$gitHubItems = @()
$dependencyDegraded = $false
if (-not [string]::IsNullOrWhiteSpace($GitHubOwner)) {
    try {
        $gitHubItems = Invoke-WithRetry `
            -ScriptBlock { Get-GitHubRepoInventory -Owner $GitHubOwner -OwnerType $OwnerType } `
            -MaxAttempts 3 `
            -BaseDelayMs 300 `
            -MaxDelayMs 2000 `
            -Operation 'reconcile.github_inventory' `
            -Component 'reconcile' `
            -CorrelationId $correlationId `
            -LogPath $LogPath
    }
    catch {
        $dependencyDegraded = $true
        Add-MetricCounter -Name 'operation_failures_total'
        Write-StructuredLog -Level Warning -Component reconcile -Operation reconcile.github_inventory -CorrelationId $correlationId -Message 'GitHub inventory failed; continuing with local-only comparison' -Details @{ error = $_.Exception.Message } -LogPath $LogPath
    }
}

$matchResult = Invoke-ReconcileMatch -LocalItems $localItems -GitHubItems $gitHubItems
$paths = Invoke-ReconcileReportExport `
    -OutDir $OutDir `
    -LocalRoots $LocalRoots `
    -GitHubOwner $GitHubOwner `
    -LocalItems $localItems `
    -GitHubItems $gitHubItems `
    -Comparison $matchResult.Comparison `
    -PotentialDuplicates $matchResult.PotentialDuplicates

Write-StructuredLog -Level Info -Component reconcile -Operation reconcile.run -CorrelationId $correlationId -Message 'Modular reconciliation run completed' -Details @{ LocalItems = @($localItems).Count; GitHubItems = @($gitHubItems).Count; Comparison = @($matchResult.Comparison).Count; Duplicates = @($matchResult.PotentialDuplicates).Count; JsonPath = $paths.JsonPath } -LogPath $LogPath
Set-MetricGauge -Name 'reconcile_mismatch_items' -Value ([double](@($matchResult.Comparison | Where-Object { $_.Status -in @('LocalOnly', 'GitHubOnly') }).Count))
Set-MetricGauge -Name 'duplicate_candidates_total' -Value ([double]@($matchResult.PotentialDuplicates).Count)
Add-MetricHistogramValue -Name 'reconcile_run_duration_ms' -Value ([double]((Get-Date) - $runStart).TotalMilliseconds)

[pscustomobject]@{
    CorrelationId = $correlationId
    LocalItemsCount = @($localItems).Count
    GitHubItemsCount = @($gitHubItems).Count
    ComparisonCount = @($matchResult.Comparison).Count
    DuplicateCount = @($matchResult.PotentialDuplicates).Count
    JsonPath = $paths.JsonPath
    CsvPath = $paths.CsvPath
    DuplicatesCsvPath = $paths.DuplicatesCsvPath
    PartialResult = $dependencyDegraded
    Warnings = if ($dependencyDegraded) { @('GitHub inventory unavailable; emitted local-only comparison.') } else { @() }
}
