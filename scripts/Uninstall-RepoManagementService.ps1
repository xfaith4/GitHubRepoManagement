#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Stops and removes the GitHub Repo Management portal Windows service.

.DESCRIPTION
    Reverses Install-RepoManagementService.ps1: stops the service if running,
    then deletes it from the Service Control Manager. Log files under
    backend/modules/output/logs/ are left in place.

.PARAMETER ServiceName
    Windows service name to remove. Default: RepoMgmtPortal.
#>
[CmdletBinding()]
param(
    [string]$ServiceName = 'RepoMgmtPortal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "Service '$ServiceName' is not installed — nothing to do." -ForegroundColor Yellow
    exit 0
}

if ($svc.Status -ne 'Stopped') {
    Write-Host "  Stopping '$ServiceName'..." -ForegroundColor Cyan
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20; $i++) {
        $s = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $s -or $s.Status -eq 'Stopped') { break }
        Start-Sleep -Milliseconds 250
    }
}

& sc.exe delete $ServiceName | Out-Null
Start-Sleep -Seconds 1

if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    Write-Host "  [!!] '$ServiceName' still present. A process may hold it open; retry after a moment." -ForegroundColor Red
    exit 1
}

Write-Host "  [OK] Service '$ServiceName' removed. Portal will no longer start at boot." -ForegroundColor Green
