<#
.SYNOPSIS
    Runs both roadmap validators: JSON-backed contract maturity audit and
    structure/execution-hygiene linting.
#>

[CmdletBinding()]
param(
    [Parameter()][string]$Path = './ROADMAP.md',
    [Parameter()][string]$StandardsPath = './standards/roadmap',
    [Parameter()][string]$Config = '',
    [Parameter()][string]$ContractOut = '',
    [Parameter()][string]$FindingsOut = '',
    [Parameter()][ValidateSet('L0-Absent','L1-Informal','L2-Structured','L3-Contract-Ready','L4-Orchestration-Ready')]
    [string]$MinimumMaturity = 'L3-Contract-Ready',
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$contractScript = Join-Path $scriptRoot 'Test-RoadmapContract.ps1'
$structureScript = Join-Path $scriptRoot 'Test-RoadmapStructure.ps1'

if (-not (Test-Path -LiteralPath $contractScript)) { throw "Missing validator: $contractScript" }
if (-not (Test-Path -LiteralPath $structureScript)) { throw "Missing validator: $structureScript" }

$pwshPath = $null
try { $pwshPath = (Get-Process -Id $PID).Path } catch { $pwshPath = $null }
if ([string]::IsNullOrWhiteSpace($pwshPath)) {
    if ($PSVersionTable.PSEdition -eq 'Core') { $pwshPath = 'pwsh' } else { $pwshPath = 'powershell' }
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("roadmap-validation-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$contractFindings = if ([string]::IsNullOrWhiteSpace($FindingsOut)) { Join-Path $tempDir 'contract-findings.json' } else { Join-Path $tempDir 'contract-findings.json' }
$structureFindings = Join-Path $tempDir 'structure-findings.json'
$contractOutput = if ([string]::IsNullOrWhiteSpace($ContractOut)) { Join-Path $tempDir 'roadmap-contract.json' } else { $ContractOut }

$contractArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $contractScript,
    '-Path', $Path,
    '-StandardsPath', $StandardsPath,
    '-ContractOut', $contractOutput,
    '-JsonOut', $contractFindings,
    '-MinimumMaturity', $MinimumMaturity
)
if ($FailOnError) { $contractArgs += '-FailOnError' }
& $pwshPath @contractArgs
$contractExit = $LASTEXITCODE

$structureArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $structureScript,
    '-Path', $Path,
    '-JsonOut', $structureFindings
)
if (-not [string]::IsNullOrWhiteSpace($Config)) { $structureArgs += @('-Config', $Config) }
if ($FailOnError) { $structureArgs += '-FailOnError' }
& $pwshPath @structureArgs
$structureExit = $LASTEXITCODE

if (-not [string]::IsNullOrWhiteSpace($FindingsOut)) {
    $combined = [System.Collections.Generic.List[object]]::new()
    if (Test-Path -LiteralPath $contractFindings) {
        $contractJson = Get-Content -LiteralPath $contractFindings -Raw
        if (-not [string]::IsNullOrWhiteSpace($contractJson)) {
            foreach ($item in @($contractJson | ConvertFrom-Json)) {
                [void]$combined.Add([pscustomobject]@{
                    source = 'contract'
                    severity = $item.severity
                    code = $item.ruleId
                    message = $item.message
                    recommendedAction = $item.recommendedAction
                })
            }
        }
    }
    if (Test-Path -LiteralPath $structureFindings) {
        $structureJson = Get-Content -LiteralPath $structureFindings -Raw
        if (-not [string]::IsNullOrWhiteSpace($structureJson)) {
            foreach ($item in @($structureJson | ConvertFrom-Json)) {
                [void]$combined.Add([pscustomobject]@{
                    source = 'structure'
                    severity = $item.severity
                    code = $item.code
                    message = $item.message
                    recommendedAction = $item.recommendedAction
                })
            }
        }
    }
    $parent = Split-Path -Parent $FindingsOut
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $combined.ToArray() | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $FindingsOut -Encoding UTF8
}

if ($contractExit -ne 0 -or $structureExit -ne 0) { exit 1 }
exit 0
