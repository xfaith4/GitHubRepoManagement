<#
.SYNOPSIS
    Backup and restore for app.db: consistent snapshots, verified restores,
    and a stated schema story.

.DESCRIPTION
    Release 3.3 milestone 2. A lost or corrupted app.db was unrecoverable by
    any documented path -- 20+ days of maturity history existed exactly once,
    on one disk.

    Backup: SQLite's VACUUM INTO writes a consistent, compacted snapshot of a
    LIVE database to a new file -- no host shutdown, no partial pages. Each
    snapshot gets a manifest (schema version, row counts, size, source) so a
    backup can be judged without opening it, and the backup directory keeps
    the newest N snapshots, pruning older ones BY NAME in the report.

    Restore: verified before, safe during, verified after.
      - Before: the snapshot must pass PRAGMA integrity_check, and its schema
        version must not EXCEED what this code knows ($script:AppDbSchemaVersion
        in Persistence.Store.ps1). A newer-schema backup is refused by name --
        restoring it would hand the migrations a future they cannot parse.
      - During: the existing database is never destroyed. It moves aside to a
        pre-restore snapshot first; the backup then copies in via temp + move.
      - After: the restored file passes integrity_check again, through the
        same provider the host uses.

    The schema story, stated: a restore of an OLDER schema version is
    supported for every version >= 1, because Initialize-AppDatabase's
    migrations are idempotent and replay forward on the next host boot. A
    NEWER version is refused. That is the supported restore window.
#>

Set-StrictMode -Version Latest

function Get-AppDbBackupDir {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    return Join-Path $WorkspaceRoot 'output\backups\app-db'
}

function Test-AppDbBackup {
    <#
    .SYNOPSIS
        Judge a snapshot: integrity, schema version, and whether this code
        could restore it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)][string]$BackupPath)

    $issues = New-Object System.Collections.Generic.List[string]
    $schemaVersion = $null

    if (-not (Test-Path -LiteralPath $BackupPath)) {
        $issues.Add('backup-missing')
        return [pscustomobject]@{ ok = $false; schemaVersion = $null; issues = $issues.ToArray() }
    }

    try {
        $integrity = @(Invoke-AppDbQuery -DatabasePath $BackupPath -Sql 'PRAGMA integrity_check')
        $integrityValue = if (@($integrity).Count -gt 0) { [string]$integrity[0].integrity_check } else { '' }
        if ($integrityValue -ne 'ok') { $issues.Add(('integrity-failed: {0}' -f $integrityValue)) }
    }
    catch {
        $issues.Add(('integrity-unreadable: {0}' -f $_.Exception.Message))
    }

    if ($issues.Count -eq 0) {
        try {
            $versionRows = @(Invoke-AppDbQuery -DatabasePath $BackupPath -Sql 'SELECT MAX(version) AS v FROM schema_migrations')
            if (@($versionRows).Count -gt 0 -and $null -ne $versionRows[0].v) { $schemaVersion = [long]$versionRows[0].v }
        }
        catch {
            $issues.Add(('schema-unreadable: {0}' -f $_.Exception.Message))
        }
        if ($null -eq $schemaVersion) {
            if ($issues.Count -eq 0) { $issues.Add('schema-version-missing') }
        }
        elseif ($schemaVersion -gt [long]$script:AppDbSchemaVersion) {
            # Restoring a future schema would hand the migrations a database
            # they cannot parse; refused here, by name, before any file moves.
            $issues.Add(('schema-newer-than-code: backup v{0}, code v{1}' -f $schemaVersion, $script:AppDbSchemaVersion))
        }
    }

    return [pscustomobject]@{
        ok            = ($issues.Count -eq 0)
        schemaVersion = $schemaVersion
        issues        = $issues.ToArray()
    }
}

function New-AppDbBackup {
    <#
    .SYNOPSIS
        Write a consistent snapshot of the live app.db, with a manifest, and
        keep the newest KeepCount snapshots.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][string]$BackupDir = '',
        [Parameter()][ValidateRange(1, 365)][int]$KeepCount = 7,
        [Parameter()][datetime]$Now = (Get-Date)
    )

    $sourcePath = Get-AppDatabasePath -WorkspaceRoot $WorkspaceRoot
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        return [pscustomobject]@{
            success = $false; reason = 'source-missing'; sourcePath = $sourcePath
            backupPath = $null; manifestPath = $null; sizeBytes = 0; schemaVersion = $null; prunedBackups = @()
        }
    }

    if ([string]::IsNullOrWhiteSpace($BackupDir)) { $BackupDir = Get-AppDbBackupDir -WorkspaceRoot $WorkspaceRoot }
    $outputRoot = [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRoot 'output'))
    $backupDirFull = [System.IO.Path]::GetFullPath($BackupDir)
    if (-not $backupDirFull.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Backup dir '{0}' resolves outside {1}; backups stay inside output\." -f $BackupDir, $outputRoot)
    }
    if (-not (Test-Path -LiteralPath $backupDirFull)) {
        $null = New-Item -ItemType Directory -Path $backupDirFull -Force
    }

    $stampUtc = $Now.ToUniversalTime()
    $backupPath = Join-Path $backupDirFull ("app-{0}.db" -f $stampUtc.ToString('yyyyMMdd-HHmmss'))
    $manifestPath = [System.IO.Path]::ChangeExtension($backupPath, '.manifest.json')

    if (-not $PSCmdlet.ShouldProcess($sourcePath, ("Snapshot to {0} (VACUUM INTO), keep newest {1}" -f $backupPath, $KeepCount))) {
        return [pscustomobject]@{
            success = $true; reason = 'what-if'; sourcePath = $sourcePath
            backupPath = $backupPath; manifestPath = $manifestPath; sizeBytes = 0; schemaVersion = $null; prunedBackups = @()
        }
    }

    # VACUUM INTO takes a filename literal, not a bindable parameter. The
    # path is built above from Join-Path, never from user input; quotes are
    # doubled anyway because correctness is not situational.
    $literalTarget = $backupPath.Replace("'", "''")
    $null = Invoke-AppDbNonQuery -DatabasePath $sourcePath -Sql ("VACUUM INTO '{0}'" -f $literalTarget)

    $verify = Test-AppDbBackup -BackupPath $backupPath
    if (-not $verify.ok) {
        # A snapshot that fails verification is worse than no snapshot: it
        # reads as safety and restores as garbage. Remove it and say so.
        Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            success = $false; reason = ('snapshot-failed-verification: {0}' -f ($verify.issues -join '; '))
            sourcePath = $sourcePath; backupPath = $null; manifestPath = $null
            sizeBytes = 0; schemaVersion = $null; prunedBackups = @()
        }
    }

    $tableCounts = [ordered]@{}
    foreach ($countTable in @('maturity_history', 'execution_ledger', 'portfolio_index_history', 'agent_runs', 'foundation_coverage')) {
        try {
            $countRows = @(Invoke-AppDbQuery -DatabasePath $backupPath -Sql ("SELECT COUNT(*) AS c FROM {0}" -f $countTable))
            $tableCounts[$countTable] = [long]$countRows[0].c
        }
        catch { $tableCounts[$countTable] = $null }
    }

    $sizeBytes = (Get-Item -LiteralPath $backupPath).Length
    $manifest = [ordered]@{
        schemaVersion = $verify.schemaVersion
        createdAt     = $stampUtc.ToString('o')
        sourcePath    = $sourcePath
        sizeBytes     = $sizeBytes
        tableCounts   = $tableCounts
    } | ConvertTo-Json -Depth 4
    Set-Content -LiteralPath $manifestPath -Value $manifest -Encoding UTF8

    # Keep the newest KeepCount snapshots. Names sort chronologically by
    # construction, so name order IS age order.
    $pruned = @()
    $existing = @(Get-ChildItem -LiteralPath $backupDirFull -Filter 'app-*.db' -File | Sort-Object -Property Name -Descending)
    if ($existing.Count -gt $KeepCount) {
        foreach ($oldBackup in @($existing | Select-Object -Skip $KeepCount)) {
            Remove-Item -LiteralPath $oldBackup.FullName -Force
            $oldManifest = [System.IO.Path]::ChangeExtension($oldBackup.FullName, '.manifest.json')
            Remove-Item -LiteralPath $oldManifest -Force -ErrorAction SilentlyContinue
            $pruned += $oldBackup.Name
        }
    }

    return [pscustomobject]@{
        success = $true; reason = $null; sourcePath = $sourcePath
        backupPath = $backupPath; manifestPath = $manifestPath
        sizeBytes = $sizeBytes; schemaVersion = $verify.schemaVersion
        prunedBackups = $pruned
    }
}

function Restore-AppDbBackup {
    <#
    .SYNOPSIS
        Restore a verified snapshot over the workspace's app.db. The existing
        database is moved aside, never destroyed.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][datetime]$Now = (Get-Date)
    )

    $verify = Test-AppDbBackup -BackupPath $BackupPath
    if (-not $verify.ok) {
        return [pscustomobject]@{
            success = $false; reason = ($verify.issues -join '; ')
            restoredPath = $null; preRestoreSnapshot = $null; schemaVersion = $verify.schemaVersion
        }
    }

    $targetPath = Get-AppDatabasePath -WorkspaceRoot $WorkspaceRoot
    if (-not $PSCmdlet.ShouldProcess($targetPath, ("Restore from {0} (schema v{1}); existing database moves aside first" -f $BackupPath, $verify.schemaVersion))) {
        return [pscustomobject]@{
            success = $true; reason = 'what-if'
            restoredPath = $targetPath; preRestoreSnapshot = $null; schemaVersion = $verify.schemaVersion
        }
    }

    $targetDir = Split-Path -Parent $targetPath
    if (-not (Test-Path -LiteralPath $targetDir)) { $null = New-Item -ItemType Directory -Path $targetDir -Force }

    $preRestoreSnapshot = $null
    if (Test-Path -LiteralPath $targetPath) {
        $preRestoreSnapshot = ("{0}.pre-restore-{1}.db" -f $targetPath, $Now.ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
        Move-Item -LiteralPath $targetPath -Destination $preRestoreSnapshot
    }

    # Copy to temp beside the target, then move: a crash mid-copy leaves the
    # pre-restore snapshot as the recovery point and no half-written target.
    $tempPath = $targetPath + '.restore-tmp'
    Copy-Item -LiteralPath $BackupPath -Destination $tempPath -Force
    Move-Item -LiteralPath $tempPath -Destination $targetPath -Force

    $postVerify = Test-AppDbBackup -BackupPath $targetPath
    if (-not $postVerify.ok) {
        return [pscustomobject]@{
            success = $false; reason = ('post-restore-verification-failed: {0}' -f ($postVerify.issues -join '; '))
            restoredPath = $targetPath; preRestoreSnapshot = $preRestoreSnapshot; schemaVersion = $verify.schemaVersion
        }
    }

    return [pscustomobject]@{
        success = $true; reason = $null
        restoredPath = $targetPath; preRestoreSnapshot = $preRestoreSnapshot
        schemaVersion = $postVerify.schemaVersion
    }
}
