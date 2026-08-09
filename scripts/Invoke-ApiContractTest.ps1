[CmdletBinding()]
param(
    [Parameter()]
    # Derived from this script's location rather than a hardcoded drive letter,
    # so the suite runs unmodified from any clone location (ROADMAP Lane 0.3).
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testPath = Join-Path $WorkspaceRoot 'backend\api-host\ApiHost.Contract.Tests.ps1'
if (-not (Test-Path -LiteralPath $testPath)) {
    throw "API contract test file not found: $testPath"
}

$result = Invoke-Pester -Path $testPath -Output Detailed -PassThru
if ($result.FailedCount -gt 0) {
    throw "API contract tests failed. FailedCount=$($result.FailedCount)"
}

Write-Host ("[PASS] API contract tests completed ({0} tests)." -f $result.PassedCount) -ForegroundColor Green
