[CmdletBinding()]
param([string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
. (Join-Path $WorkspaceRoot 'backend/modules/portfolio/Portfolio.Assessment.ps1')
$instant = [datetime]::SpecifyKind([datetime]'2026-01-12T05:25:34', [DateTimeKind]::Utc)
$assessment = [pscustomobject]@{ repoName = 'timestamp-fixture'; createdAt = $instant; updatedAt = $instant }
$payload = New-PortfolioIndexPayload -Assessments @($assessment) -GeneratedAt '2026-09-05T12:00:00Z'
foreach ($field in @('createdAt', 'updatedAt')) {
    if ($payload.repos[0].$field -ne '2026-01-12T05:25:34.0000000Z') {
        throw "Index projection lost the timezone basis: $field = $($payload.repos[0].$field)"
    }
}
Write-Host '[PASS] DateTime values survive index projection as UTC ISO 8601.'

. (Join-Path $WorkspaceRoot 'tools/Assert-JsonTimestampBasis.ps1')
foreach ($bad in @('01/12/2026 05:25:34', '2026-01-12T05:25:34', '2026-99-99T05:25:34Z')) {
    $rejected = $false
    try { $null = Assert-JsonTimestampBasis -Json ('{"createdAt":"' + $bad + '"}') } catch { $rejected = $true }
    if (-not $rejected) { throw "Timestamp gate accepted violating fixture: $bad" }
}
foreach ($good in @('2026-01-12T05:25:34Z', '2026-01-12T00:25:34-05:00')) {
    if ((Assert-JsonTimestampBasis -Json ('{"nested":[{"createdAt":"' + $good + '"}]}')) -ne 1) { throw 'Timestamp gate examined zero values.' }
    if ((ConvertTo-PortfolioTimestamp $good) -ne '2026-01-12T05:25:34.0000000Z') { throw 'Timestamp normalization changed the instant.' }
}
$warnings = @()
if ($null -ne (ConvertTo-PortfolioTimestamp '01/12/2026 05:25:34' -WarningVariable warnings)) { throw 'Unknown timezone was invented.' }
if ($warnings.Count -eq 0) { throw 'Unavailable timestamp was hidden.' }
$projected = @(Convert-PortfolioIndexReposToAssessments -IndexRepos $payload.repos)
if ($projected[0].createdAt -ne '2026-01-12T05:25:34.0000000Z') { throw 'Assessment projection lost the timezone.' }
Write-Host '[PASS] Raw JSON gate rejects naive/invalid timestamps, examines ISO dates, and preserves offset instants.'

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('portfolio-timestamp-' + [guid]::NewGuid().ToString('N'))
try {
    $indexDir = Join-Path $fixtureRoot 'output/index'
    $null = New-Item -ItemType Directory -Path $indexDir -Force
    $payload.repos[0].createdAt = '01/12/2026 05:25:34'
    $payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $indexDir 'repos.index.json') -Encoding UTF8
    $cached = Get-PortfolioIndexPayload -WorkspaceRoot $fixtureRoot
    if ([string]$cached.generatedAt -ne '2026-09-05T12:00:00.0000000Z') { throw 'Cached index generation time lost its timezone during string coercion.' }
    if ($null -eq $cached -or @($cached.repos).Count -ne 1) { throw 'Cached timestamp fixture was not examined.' }
    if ($null -ne $cached.repos[0].createdAt) { throw 'Cached index leaked a naive date.' }
    if ($cached.repos[0].updatedAt -ne '2026-01-12T05:25:34.0000000Z') { throw 'Cached index lost a known instant.' }
    Write-Host '[PASS] Cached index reads expose unavailable legacy dates without inventing a timezone.'
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
