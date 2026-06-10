<#
.SYNOPSIS
    Stops background processes started by Start-App.ps1 (silent mode).

.DESCRIPTION
    Reads backend/modules/output/runtime/app.pid, terminates the recorded
    processes, and removes the PID file. Safe to run even if processes have
    already exited.
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    if ($PSCommandPath) {
        $WorkspaceRoot = Split-Path -Parent $PSCommandPath
    }
    elseif ($MyInvocation.MyCommand.Path) {
        $WorkspaceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    else {
        $WorkspaceRoot = (Get-Location).Path
    }
}

$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)

$pidFile = Join-Path $WorkspaceRoot 'backend\modules\output\runtime\app.pid'

if (-not (Test-Path -LiteralPath $pidFile)) {
    Write-Host 'No app.pid found - nothing to stop.' -ForegroundColor Yellow
    exit 0
}

$info = Get-Content -LiteralPath $pidFile -Raw | ConvertFrom-Json

function Stop-TrackedProcess {
    param([int]$TrackedPid, [string]$Name)
    if ($TrackedPid -le 0) {
        Write-Host "  $Name : PID not tracked (debug mode - close its window manually)." -ForegroundColor Gray
        return
    }
    try {
        $proc = Get-Process -Id $TrackedPid -ErrorAction Stop
        $proc | Stop-Process -Force
        Write-Host "  $Name : stopped (PID $TrackedPid)." -ForegroundColor Green
    }
    catch {
        Write-Host "  $Name : process $TrackedPid not found (already exited)." -ForegroundColor Gray
    }
}

Write-Host ''
Write-Host 'Stopping GitHub Repo Management...' -ForegroundColor White
Stop-TrackedProcess -TrackedPid ([int]$info.frontendPid) -Name 'Frontend'
Stop-TrackedProcess -TrackedPid ([int]$info.backendPid) -Name 'Backend '

# Also clean up the wrapper script generated for silent frontend launch
$wrapperPath = Join-Path $WorkspaceRoot 'backend\modules\output\runtime\start-frontend.ps1'
if (Test-Path -LiteralPath $wrapperPath) {
    Remove-Item -LiteralPath $wrapperPath -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
Write-Host '  PID file removed.' -ForegroundColor Gray
Write-Host ''
