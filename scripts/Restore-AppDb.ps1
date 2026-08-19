<#
.SYNOPSIS
    Restore app.db from a verified snapshot. Operator-only; run with the API
    host STOPPED.

.DESCRIPTION
    Release 3.3 milestone 2. The documented restore path:

        pwsh .\scripts\Restore-AppDb.ps1 -BackupPath output\backups\app-db\app-<stamp>.db

    The snapshot is verified before anything moves (PRAGMA integrity_check +
    schema version), the existing database moves aside to a pre-restore
    snapshot rather than being destroyed, and the restored file is verified
    again through the same provider the host uses.

    Schema story: a snapshot with an OLDER schema version restores cleanly --
    Initialize-AppDatabase's idempotent migrations replay forward on the next
    host boot. A snapshot NEWER than this code's schema version is refused by
    name; upgrade the code first.

    Refuses to run while something is listening on the portal port, because
    the host holds the database this script would overwrite.

.PARAMETER BackupPath
    Path to the snapshot (.db) to restore.

.PARAMETER WorkspaceRoot
    Workspace whose app.db is being restored. Defaults to this repo.

.PARAMETER PortalPort
    Port probed to detect a running host. Default 7071.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][int]$PortalPort = 7071
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $WorkspaceRoot 'backend\modules\persistence\Persistence.Store.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\persistence\Persistence.Backup.ps1')

# A live host holds the database this restore would overwrite.
$portBusy = $false
try {
    $probe = [System.Net.Sockets.TcpClient]::new()
    $portBusy = $probe.ConnectAsync('127.0.0.1', $PortalPort).Wait(1500) -and $probe.Connected
    $probe.Dispose()
}
catch { $portBusy = $false }
if ($portBusy) {
    throw ("Something is listening on 127.0.0.1:{0}. Stop the API host (or pass the actual -PortalPort if it runs elsewhere) before restoring the database it holds." -f $PortalPort)
}

$capability = Get-SqliteCapability
if (-not $capability.available) {
    throw ("No SQLite provider available on this machine ({0}); the restore cannot be verified, so it does not run." -f $capability.providerDetail)
}

$result = Restore-AppDbBackup -BackupPath $BackupPath -WorkspaceRoot $WorkspaceRoot

if ($result.success -and $result.reason -eq 'what-if') {
    Write-Host ("WhatIf: would restore {0} (schema v{1}) over {2}, moving the existing database aside first." -f $BackupPath, $result.schemaVersion, $result.restoredPath)
    return $result
}
if (-not $result.success) {
    throw ("Restore refused: {0}" -f $result.reason)
}

Write-Host ("Restored {0} (schema v{1})." -f $result.restoredPath, $result.schemaVersion) -ForegroundColor Green
if ($result.preRestoreSnapshot) {
    Write-Host ("The previous database was kept at {0} -- remove it once the restore proves out." -f $result.preRestoreSnapshot) -ForegroundColor Yellow
}
Write-Host 'If the snapshot carried an older schema version, the next host start replays its migrations forward.' -ForegroundColor DarkGray
return $result
