#Requires -Version 7.0
<#
.SYNOPSIS
    Write the delivery report: what the product delivered, what it cost the
    operator, and what moved since the last report (loop step 8).

.DESCRIPTION
    One command reads the delivery ledger, the runner's run summaries, the
    docs audit cache and GitHub, and writes the report as JSON and Markdown.
    Every figure carries its unit, basis, window and source; one the records
    cannot compute reads "not measured" with its reason, never 0.

    Weekly (the default): figures count from the start of the records to now,
    so each report compares like with like against the previous one and says
    what moved. Reports land in <output root>\delivery\reports\<date>.*; the
    previous report is the newest there, or the baseline when there is none.

    -Baseline: the window ends 2026-10-17T00:00Z, the day after the
    2026-10-16 evaluation, and the report lands in
    evidence/baseline/2026-10-16/ beside each evaluation figure, saying where
    the computed figure matches it and why it differs where it does.

    GitHub is read for the state, merge time and head CI of every PR a
    product record names. With no token (or -Offline) the PR figures read
    "not measured" with that reason; nothing is guessed.

.PARAMETER DataRoot
    The repository whose output\ ledgers are read. Defaults to this
    repository. Point it at the live checkout to report on live records; it
    is only read.

.PARAMETER DestinationRoot
    Where reports are written: evidence\baseline\ for -Baseline, the output
    root's delivery\reports\ otherwise. Defaults to this repository.

.EXAMPLE
    pwsh ./tools/New-DeliveryReport.ps1

.EXAMPLE
    pwsh ./tools/New-DeliveryReport.ps1 -Baseline -DataRoot F:\path\to\live\checkout
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][string]$DataRoot = '',
    [Parameter()][string]$DestinationRoot = '',
    [Parameter()][switch]$Baseline,
    [Parameter()][string]$AsOfUtc = '',
    [Parameter()][string]$WindowStartUtc = '',
    [Parameter()][string]$WindowEndUtc = '',
    [Parameter()][string]$ProductRepository = '',
    [Parameter()][string]$AuditCachePath = '',
    [Parameter()][string]$Token = '',
    [Parameter()][switch]$Offline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
if (-not $DataRoot) { $DataRoot = $WorkspaceRoot }
if (-not $DestinationRoot) { $DestinationRoot = $WorkspaceRoot }
$DataRoot = (Resolve-Path -LiteralPath $DataRoot).Path
$DestinationRoot = (Resolve-Path -LiteralPath $DestinationRoot).Path

. (Join-Path $WorkspaceRoot 'backend\modules\common\Config.OutputRoot.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Snapshot.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\delivery\Delivery.Ledger.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\delivery\Delivery.Report.ps1')

$baselineDate = '2026-10-16'
$generatedAt = if ($AsOfUtc) { $AsOfUtc } else { [datetime]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture) }
$windowEnd = if ($WindowEndUtc) { $WindowEndUtc } elseif ($Baseline) { '2026-10-17T00:00:00Z' } else { $generatedAt }

# -- The product's own repository: excluded from "other repositories" ----------
if (-not $ProductRepository) {
    $origin = (& git -C $WorkspaceRoot remote get-url origin 2>$null | Out-String).Trim()
    $m = [regex]::Match($origin, 'github\.com[:/](?<r>[^/]+/[^/]+?)(\.git)?$')
    if (-not $m.Success) { throw "Cannot read the product repository from git origin '$origin'. Pass -ProductRepository owner/repo." }
    $ProductRepository = $m.Groups['r'].Value
}

# -- Records -------------------------------------------------------------------
$ledger = Get-DeliveryLedgerRecord -WorkspaceRoot $DataRoot
$runsDir = Join-Path (Get-OutputRoot -WorkspaceRoot $DataRoot) 'roadmap-task-history\runs'
$runs = Get-RunnerRunSummary -RunsDirectory $runsDir
$readErrors = [System.Collections.Generic.List[object]]::new()
if ($ledger.skipped -gt 0) { $readErrors.Add([pscustomobject]@{ target = $ledger.path; error = ('{0} unreadable ledger line(s) skipped' -f $ledger.skipped) }) }
if ($runs.skipped -gt 0) { $readErrors.Add([pscustomobject]@{ target = $runsDir; error = ('{0} unreadable run summary file(s) skipped' -f $runs.skipped) }) }

if (-not $AuditCachePath) {
    $cacheRoot = [Environment]::GetEnvironmentVariable('REPO_MGMT_CACHE_ROOT')
    if ([string]::IsNullOrWhiteSpace($cacheRoot)) { $cacheRoot = Join-Path $DataRoot 'backend\modules\output\cache' }
    $AuditCachePath = Join-Path $cacheRoot 'docs-audit-cache.json'
}
$auditCache = $null
if (Test-Path -LiteralPath $AuditCachePath) {
    try { $auditCache = Get-Content -LiteralPath $AuditCachePath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { $readErrors.Add([pscustomobject]@{ target = $AuditCachePath; error = $_.Exception.Message }) }
}

# -- GitHub --------------------------------------------------------------------
$pullRequests = $null
$prReason = ''
if ($Offline) { $prReason = 'GitHub was not read (-Offline).' }
else {
    $get = $null
    if (-not $Token -and (Get-Command gh -ErrorAction Ignore)) {
        # gh resolves its own credential (GH_TOKEN, GITHUB_TOKEN, then the
        # keyring); a raw environment token can see fewer repositories.
        $get = {
            param([string]$ApiPath)
            $out = & gh api $ApiPath 2>&1
            if ($LASTEXITCODE -ne 0) { throw ('gh api {0}: {1}' -f $ApiPath, @(($out | Out-String).Trim() -split '\r?\n')[0]) }
            ($out | Out-String) | ConvertFrom-Json
        }
    }
    if (-not $get -and -not $Token) { $Token = [Environment]::GetEnvironmentVariable('GITHUB_TOKEN') }
    if (-not $get -and -not $Token) { $Token = [Environment]::GetEnvironmentVariable('GitHub_Token') }
    if (-not $get -and -not $Token) { $prReason = 'Neither gh nor a GitHub token (GITHUB_TOKEN, GitHub_Token) is available, so PR state and CI could not be read.' }
    elseif (-not $get) {
        $get = {
            param([string]$ApiPath)
            Invoke-RestMethod -Uri ('https://api.github.com{0}' -f $ApiPath) -Method Get -TimeoutSec 20 -Headers @{
                Authorization = ('Bearer {0}' -f $Token); 'User-Agent' = 'GitHubRepoManagement'; Accept = 'application/vnd.github+json'
            }
        }.GetNewClosure()
    }
    if ($get) {
        $resolved = Resolve-DeliveryProductPullRequest -Record $ledger.records -Run $runs.runs -ProductRepository $ProductRepository -GitHubGet $get
        $pullRequests = @($resolved.prs)
        foreach ($e in $resolved.errors) { $readErrors.Add($e) }
    }
}

# -- The previous report --------------------------------------------------------
$reportsDir = Join-Path (Get-OutputRoot -WorkspaceRoot $DestinationRoot) 'delivery\reports'
$baselineDir = Join-Path $DestinationRoot ('evidence\baseline\{0}' -f $baselineDate)
$previous = $null
if (-not $Baseline) {
    $candidates = @()
    if (Test-Path -LiteralPath $reportsDir) { $candidates = @(Get-ChildItem -LiteralPath $reportsDir -Filter '*.json' -File | Sort-Object Name -Descending) }
    if ($candidates.Count -eq 0 -and (Test-Path -LiteralPath (Join-Path $baselineDir 'delivery-report.json'))) { $candidates = @(Get-Item -LiteralPath (Join-Path $baselineDir 'delivery-report.json')) }
    if ($candidates.Count -gt 0) {
        try { $previous = Get-Content -LiteralPath $candidates[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String }
        catch { $readErrors.Add([pscustomobject]@{ target = $candidates[0].FullName; error = $_.Exception.Message }) }
    }
}

$report = New-DeliveryReport -GeneratedAtUtc $generatedAt -WindowStartUtc $WindowStartUtc -WindowEndUtc $windowEnd -Record $ledger.records -Run $runs.runs `
    -PullRequest $pullRequests -PullRequestReason $prReason -ReadError $readErrors.ToArray() -AuditCache $auditCache -Previous $previous

if ($Baseline) {
    # The evaluation's figures as recorded on 2026-10-16 (ROADMAP.md Current
    # Status and evidence/trials/proof-of-value-2026-11/README.md).
    $evaluation = @(
        @{ figure = 'prsInitiated'; evaluation = '11'; text = 'verified product-originated PRs created 2026-03-01 to 2026-10-16 (trial README)' }
        @{ figure = 'prsMerged'; evaluation = '10'; text = 'of those merged (trial README; ROADMAP.md said "about eight")' }
        @{ figure = 'prsPassedCi'; evaluation = 'not stated'; text = 'four merged with failing checks and one was open with failing checks (trial README)' }
        @{ figure = 'agentRuns'; evaluation = '80'; text = 'non-smoke runner runs' }
        @{ figure = 'agentRunsFailed'; evaluation = '51'; text = 'failed, blocked or refused (trial README; ROADMAP.md said 45 failed)' }
        @{ figure = 'proposalsRejected'; evaluation = 'not recorded'; text = 'no decision ledger existed' }
        @{ figure = 'operatorSeconds'; evaluation = 'not recorded'; text = 'operator minutes never recorded' }
        @{ figure = 'operatorSecondsPerMergedImprovement'; evaluation = 'not recorded'; text = 'operator minutes never recorded' }
        @{ figure = 'reposReady'; evaluation = '1 of 62'; text = 'PhotoToolboxv2 (trial README)' }
    )
    $comparison = foreach ($e in $evaluation) {
        $m = $report.figures.($e.figure)
        $value = if ($null -eq $m.value) { 'not measured' } elseif ($null -ne $m.basis) { ('{0} of {1}' -f $m.basis.numerator, $m.basis.denominator) } else { [string]$m.value }
        $note = if ($null -eq $m.value) { ('{0} Evaluation: {1}.' -f $m.reason, $e.text) }
        elseif ($value -eq $e.evaluation -or [string]$m.value -eq $e.evaluation) { ('Matches: {0}.' -f $e.text) }
        else { ('Differs from the evaluation ({0}): {1}' -f $e.text, $m.definition) }
        [pscustomobject]@{ figure = $e.figure; evaluation = $e.evaluation; report = $value; note = $note }
    }
    $report | Add-Member -NotePropertyName 'baselineComparison' -NotePropertyValue @($comparison)
    $destDir = $baselineDir
    $stem = 'delivery-report'
    $title = ('Delivery baseline: the {0} evaluation, recomputed' -f $baselineDate)
}
else {
    $destDir = $reportsDir
    $stem = ([datetime]::Parse($generatedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).ToString('yyyy-MM-dd')
    $title = ('Delivery report: {0}' -f $stem)
}

$jsonPath = Join-Path $destDir ('{0}.json' -f $stem)
$mdPath = Join-Path $destDir ('{0}.md' -f $stem)
if ($PSCmdlet.ShouldProcess($destDir, 'write the delivery report')) {
    $null = New-Item -ItemType Directory -Path $destDir -Force
    Set-Content -LiteralPath $jsonPath -Value ($report | ConvertTo-Json -Depth 12) -Encoding utf8NoBOM
    Set-Content -LiteralPath $mdPath -Value (ConvertTo-DeliveryReportMarkdown -Report $report -Title $title) -Encoding utf8NoBOM
}

[pscustomobject]@{
    json       = $jsonPath
    markdown   = $mdPath
    window     = $report.window.text
    figures    = @($report.figures.PSObject.Properties | ForEach-Object { [pscustomobject]@{ id = $_.Name; value = $_.Value.value; reason = $_.Value.reason } })
    readErrors = @($report.readErrors).Count
}
