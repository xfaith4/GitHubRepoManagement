<#
.SYNOPSIS
    Pre-flight validation script to catch type mismatches before running the full scan.
.DESCRIPTION
    Loads the main dashboard script in function-only mode and validates a few
    critical edge cases without starting a repository scan.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host '=== PRE-FLIGHT VALIDATION ===' -ForegroundColor Cyan
Write-Host ''

$dashboardScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-Reconciliation.ps1'
if (-not (Test-Path -LiteralPath $dashboardScript)) {
    # Backward-compatible fallback for original repository layout.
    $dashboardScript = Join-Path -Path $PSScriptRoot -ChildPath '..\src\repo_reconciliation_dashboard.ps1'
}

Write-Host 'Loading main script...' -ForegroundColor White
if (-not (Test-Path -LiteralPath $dashboardScript)) {
    throw "Main script not found: $dashboardScript"
}

. $dashboardScript -LoadFunctionsOnly -ErrorAction Stop
Write-Host 'PASS: Script loaded in function-only mode' -ForegroundColor Green

Write-Host ''
Write-Host 'TEST 1: Array count behavior in strict mode' -ForegroundColor Yellow
try {
    $empty = @()
    $directCount = $empty.Count
    $safeCount = ($empty | Measure-Object).Count

    Write-Host "  Direct .Count result: $directCount" -ForegroundColor White
    Write-Host "  Measure-Object count: $safeCount" -ForegroundColor White
    Write-Host 'PASS: Count edge case evaluated' -ForegroundColor Green
}
catch {
    Write-Host "FAIL: $_" -ForegroundColor Red
}

Write-Host ''
Write-Host 'TEST 2: Duplicate detection with empty input' -ForegroundColor Yellow
try {
    $duplicateResult = Get-PotentialLocalDuplicates -LocalItems @()
    Write-Host "  Returned items: $(($duplicateResult | Measure-Object).Count)" -ForegroundColor White
    Write-Host 'PASS: Empty duplicate scan succeeded' -ForegroundColor Green
}
catch {
    Write-Host "FAIL: $_" -ForegroundColor Red
}

Write-Host ''
Write-Host 'TEST 3: Comparison with empty local and sample GitHub data' -ForegroundColor Yellow
try {
    $sampleGitHubRepo = [pscustomobject]@{
        RepoName      = 'test'
        NameWithOwner = 'sample/test'
        Url           = 'https://github.com/sample/test'
        UpdatedAt     = $null
        IsArchived    = $false
    }

    $comparisonResult = Compare-LocalAndGitHub -LocalItems @() -GitHubItems @($sampleGitHubRepo)
    Write-Host "  Returned items: $(($comparisonResult | Measure-Object).Count)" -ForegroundColor White
    Write-Host 'PASS: Comparison edge case succeeded' -ForegroundColor Green
}
catch {
    Write-Host "FAIL: $_" -ForegroundColor Red
}

Write-Host ''
Write-Host 'TEST 4: Export-Csv with empty collection' -ForegroundColor Yellow
try {
    $tempCsv = Join-Path -Path $env:TEMP -ChildPath ("preflight-{0}.csv" -f (Get-Random))
    @() | Export-Csv -LiteralPath $tempCsv -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    Remove-Item -LiteralPath $tempCsv -ErrorAction SilentlyContinue
    Write-Host 'PASS: Empty CSV export succeeded' -ForegroundColor Green
}
catch {
    Write-Host "FAIL: $_" -ForegroundColor Red
}

Write-Host ''
Write-Host 'TEST 5: HTML table generation with empty data' -ForegroundColor Yellow
try {
    $htmlTable = ConvertTo-HtmlTable -Data @() -Columns @('FolderName', 'LocalPath')
    if ($htmlTable -match '<table>') {
        Write-Host 'PASS: Empty HTML table generated' -ForegroundColor Green
    }
    else {
        Write-Host 'FAIL: HTML table output did not contain <table>' -ForegroundColor Red
    }
}
catch {
    Write-Host "FAIL: $_" -ForegroundColor Red
}

Write-Host ''
Write-Host '=== VALIDATION COMPLETE ===' -ForegroundColor Cyan
Write-Host 'Review any FAIL lines before running a full scan.' -ForegroundColor Yellow
