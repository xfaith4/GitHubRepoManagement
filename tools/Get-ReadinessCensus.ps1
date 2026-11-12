#Requires -Version 7.0
<#
.SYNOPSIS
    How many repositories are legitimately ready for automated work, and what
    holds every other one.

.DESCRIPTION
    Reads the portfolio index and the execution ledger (read-only) and applies
    Get-RepositoryReadiness to every indexed repository: the lifecycle
    resolver reads ready-for-work, the dispatch-eligibility rule passes, an
    actionable agent item exists, and a GitHub remote can receive the pull
    request. Emits the census object; -OutputPath also writes it as JSON.
    Nothing is written anywhere else.

.PARAMETER IndexPath
    The portfolio index. Defaults to output/index/repos.index.json.

.PARAMETER LedgerPath
    The execution ledger. Defaults to output/execution/execution-ledger.json.
    A missing ledger is reported, not hidden: no repository is then held by it.

.EXAMPLE
    pwsh -NoProfile -File ./tools/Get-ReadinessCensus.ps1 -OutputPath ./output/readiness-census.json
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][string]$IndexPath = '',
    [Parameter()][string]$LedgerPath = '',
    [Parameter()][string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
. (Join-Path $WorkspaceRoot 'backend/modules/portfolio/Portfolio.Ranking.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/execution/Execution.Eligibility.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/portfolio/Portfolio.Readiness.ps1')

if (-not $IndexPath) { $IndexPath = Join-Path $WorkspaceRoot 'output/index/repos.index.json' }
if (-not $LedgerPath) { $LedgerPath = Join-Path $WorkspaceRoot 'output/execution/execution-ledger.json' }
if (-not (Test-Path -LiteralPath $IndexPath)) { throw "Portfolio index not found: $IndexPath. Run a portfolio scan first." }

$index = Get-Content -LiteralPath $IndexPath -Raw | ConvertFrom-Json
$repos = @($index.repos)
if ($repos.Count -eq 0) { throw "The portfolio index at $IndexPath holds no repositories; a census of zero is not a result." }

$ledgerEntries = @()
if (Test-Path -LiteralPath $LedgerPath) {
    $ledgerEntries = @((Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json).entries)
} else {
    Write-Warning "Execution ledger not found at $LedgerPath; no repository is held by a blocked ledger entry."
}

$generated = [string]$index.generatedAt
if ($index.generatedAt -is [datetime]) { $generated = $index.generatedAt.ToUniversalTime().ToString('o') }
$census = Get-ReadinessCensus -PortfolioEntries $repos -LedgerEntries $ledgerEntries -IndexGeneratedAt $generated

if ($OutputPath) {
    $dir = Split-Path -Parent $OutputPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir }
    $census | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    Write-Verbose "Census written to $OutputPath"
}

$census
