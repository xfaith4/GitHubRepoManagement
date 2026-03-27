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
. (Join-Path $workspaceRoot 'modules\common\Validation.ps1')

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

# ---------------------------------------------------------------------------
# Inline helpers (formerly Reconcile.Scanner.ps1, Reconcile.Matcher.ps1,
# and Reconcile.Reporter.ps1)
# ---------------------------------------------------------------------------

function Invoke-ReconcileScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$LocalRoots,
        [Parameter(Mandatory = $true)]
        [string[]]$IgnoreDirNames,
        [Parameter(Mandatory = $true)]
        [string[]]$IgnorePathRegex,
        [Parameter(Mandatory = $true)]
        [int]$MaxDepth,
        [Parameter(Mandatory = $true)]
        [bool]$IncludeNonGitFolders
    )

    $items = Get-LocalFolderInventory `
        -Roots $LocalRoots `
        -IgnoreDirNames $IgnoreDirNames `
        -IgnorePathRegex $IgnorePathRegex `
        -MaxDepth $MaxDepth `
        -IncludeNonGitFolders:$IncludeNonGitFolders

    if ($null -eq $items) {
        return ,@()
    }

    return ,@($items)
}

function Invoke-ReconcileMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$LocalItems,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$GitHubItems
    )

    $comparison = Compare-LocalAndGitHub -LocalItems $LocalItems -GitHubItems $GitHubItems
    $duplicates = Get-PotentialLocalDuplicates -LocalItems $LocalItems

    return [pscustomobject]@{
        Comparison = @($comparison)
        PotentialDuplicates = @($duplicates)
    }
}

function Invoke-ReconcileReportExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutDir,
        [Parameter(Mandatory = $true)]
        [string[]]$LocalRoots,
        [Parameter()]
        [string]$GitHubOwner,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$LocalItems,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$GitHubItems,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Comparison,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$PotentialDuplicates
    )

    $shape = Test-ReconciliationArtifactShape `
        -LocalItems $LocalItems `
        -GitHubItems $GitHubItems `
        -Comparison $Comparison `
        -PotentialDuplicates $PotentialDuplicates

    if (-not $shape.IsValid) {
        throw "Validation failed before artifact write: $($shape.Reason)"
    }

    $null = New-Item -ItemType Directory -Path $OutDir -Force -ErrorAction Stop

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $jsonPath = Join-Path -Path $OutDir -ChildPath ("repo-reconciliation_{0}.json" -f $stamp)
    $csvPath = Join-Path -Path $OutDir -ChildPath ("repo-reconciliation_{0}.csv" -f $stamp)
    $dupesCsvPath = Join-Path -Path $OutDir -ChildPath ("repo-duplicates_{0}.csv" -f $stamp)

    [pscustomobject]@{
        GeneratedAt         = (Get-Date).ToString('o')
        LocalRoots          = @($LocalRoots)
        GitHubOwner         = $GitHubOwner
        LocalItemsCount     = @($LocalItems).Count
        GitHubItemsCount    = @($GitHubItems).Count
        MatchedCount        = @($Comparison | Where-Object { $_.Status -eq 'Matched' }).Count
        LocalOnlyCount      = @($Comparison | Where-Object { $_.Status -eq 'LocalOnly' }).Count
        GitHubOnlyCount     = @($Comparison | Where-Object { $_.Status -eq 'GitHubOnly' }).Count
        DuplicateCount      = @($PotentialDuplicates).Count
        LocalItems          = @($LocalItems)
        GitHubItems         = @($GitHubItems)
        Comparison          = @($Comparison)
        PotentialDuplicates = @($PotentialDuplicates)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $Comparison | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    $PotentialDuplicates | Export-Csv -LiteralPath $dupesCsvPath -NoTypeInformation -Encoding UTF8

    return [pscustomobject]@{
        JsonPath = $jsonPath
        CsvPath = $csvPath
        DuplicatesCsvPath = $dupesCsvPath
    }
}

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
