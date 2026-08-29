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

# These tests assert ROUTE CONTRACTS -- status codes, envelopes, payload shape --
# and send no credentials, because credentials are not what they measure. Auth
# enforcement is the Auth smoke's gate, and it sets these variables itself.
#
# Enable-SharedLanAccess.ps1 writes REPO_MGMT_API_KEY and REPO_MGMT_REQUIRE_API_KEY
# at MACHINE scope -- correctly; that is the Release 2.9 feature doing its job.
# But a machine-scope variable reaches every shell forever, so the host these
# tests start inherits it, enforces auth, and answers 401 to every unauthenticated
# request. Measured on a shared-LAN-enabled machine: 32 of 37 failed, all 401,
# none of them a contract violation.
#
# Left unhandled, the suite cannot pass on any machine running a configuration
# this repository ships and documents -- and the failure names none of that, it
# just reports 32 broken contracts. So the inherited value is cleared for this
# process only (never at User or Machine scope: the operator's LAN access must
# survive a test run), and the clear is announced rather than silent.
$clearedAuthNames = @('REPO_MGMT_REQUIRE_API_KEY', 'REPO_MGMT_API_KEY') |
    Where-Object { -not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($_)) }
foreach ($clearedAuthName in $clearedAuthNames) {
    [System.Environment]::SetEnvironmentVariable($clearedAuthName, $null, 'Process')
}
if (@($clearedAuthNames).Count -gt 0) {
    Write-Host ("  cleared inherited {0} for this process — the contract tests send no key by design; shared-LAN auth is untouched at User/Machine scope" -f ($clearedAuthNames -join ', ')) -ForegroundColor DarkYellow
}

$result = Invoke-Pester -Path $testPath -Output Detailed -PassThru
if ($result.FailedCount -gt 0) {
    throw "API contract tests failed. FailedCount=$($result.FailedCount)"
}

Write-Host ("[PASS] API contract tests completed ({0} tests)." -f $result.PassedCount) -ForegroundColor Green
