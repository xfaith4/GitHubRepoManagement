[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement',
    [string]$BaseUrl = 'http://127.0.0.1:7071',
    [int]$TimeoutSeconds = 90,
    [switch]$NoStartApp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$outputRoot = Join-Path $WorkspaceRoot 'output\smoke\frontend'
$null = New-Item -ItemType Directory -Path $outputRoot -Force

$reportPath = Join-Path $outputRoot 'frontend-smoke.json'
$screenshotPath = Join-Path $outputRoot 'frontend-smoke.png'
$summaryPath = Join-Path $outputRoot 'frontend-smoke-summary.txt'
$backendLogPath = Join-Path $WorkspaceRoot 'backend\modules\output\logs\backend.log'
$opsLogPath = Join-Path $WorkspaceRoot 'backend\modules\output\logs\operations.jsonl'
$probeScriptPath = Join-Path $WorkspaceRoot 'scripts\frontend-smoke.cjs'

function Wait-HttpReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Uri -Method Get -TimeoutSec 5 -SkipHttpErrorCheck
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        } catch {
        }

        Start-Sleep -Milliseconds 500
    }

    throw "Endpoint did not become reachable within $TimeoutSeconds seconds: $Uri"
}

function Get-TailSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$Lines = 80
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return "[missing] $Path"
    }

    return (Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction SilentlyContinue) -join [Environment]::NewLine
}

$startedApp = $false

try {
    if (-not $NoStartApp) {
        Write-Host '[STEP] Starting application' -ForegroundColor Cyan
        $null = Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','Start-App.ps1','-NoBrowser' -WorkingDirectory $WorkspaceRoot
        $startedApp = $true
    }

    Write-Host '[STEP] Waiting for backend health endpoint' -ForegroundColor Cyan
    Wait-HttpReady -Uri "$BaseUrl/health/live" -TimeoutSeconds $TimeoutSeconds

    Write-Host '[STEP] Waiting for app shell' -ForegroundColor Cyan
    Wait-HttpReady -Uri $BaseUrl -TimeoutSeconds $TimeoutSeconds

    Write-Host '[STEP] Running headless frontend smoke' -ForegroundColor Cyan
    $env:FRONTEND_SMOKE_BASE_URL = $BaseUrl
    $env:FRONTEND_SMOKE_OUTPUT_DIR = $outputRoot
    $env:FRONTEND_SMOKE_SCREENSHOT = $screenshotPath
    $env:FRONTEND_SMOKE_REPORT = $reportPath
    $env:FRONTEND_SMOKE_TIMEOUT_MS = [string]($TimeoutSeconds * 1000)

    & node $probeScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Headless frontend probe exited with code $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        throw "Frontend smoke report was not written: $reportPath"
    }

    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    @(
        "Frontend smoke: PASS"
        "Base URL: $BaseUrl"
        "Screenshot: $screenshotPath"
        "Report: $reportPath"
        "Browser: $($report.browser)"
        "Backend online: $($report.backendOnline)"
        "Portfolio assessment loaded: $($report.portfolioAssessmentLoaded)"
        "Documentation health loaded: $($report.documentationHealthLoaded)"
    ) | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    Write-Host '[PASS] Frontend smoke completed' -ForegroundColor Green
} catch {
    $errorMessage = $_.Exception.Message
    $backendTail = Get-TailSafe -Path $backendLogPath
    $opsTail = Get-TailSafe -Path $opsLogPath
    @(
        "Frontend smoke: FAIL"
        "Base URL: $BaseUrl"
        "Error: $errorMessage"
        "Screenshot: $screenshotPath"
        "Report: $reportPath"
        ""
        "=== backend.log tail ==="
        $backendTail
        ""
        "=== operations.jsonl tail ==="
        $opsTail
    ) | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    Write-Error $errorMessage
} finally {
    Remove-Item Env:FRONTEND_SMOKE_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:FRONTEND_SMOKE_OUTPUT_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:FRONTEND_SMOKE_SCREENSHOT -ErrorAction SilentlyContinue
    Remove-Item Env:FRONTEND_SMOKE_REPORT -ErrorAction SilentlyContinue
    Remove-Item Env:FRONTEND_SMOKE_TIMEOUT_MS -ErrorAction SilentlyContinue

    if ($startedApp) {
        Write-Host '[STEP] Stopping application' -ForegroundColor Cyan
        & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $WorkspaceRoot 'Stop-App.ps1') | Out-Null
    }
}
