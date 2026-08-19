<#
.SYNOPSIS
    Bounded storage for the append-only JSONL ledgers: archive-then-trim with
    the policy stated in config and the pruned range logged.

.DESCRIPTION
    Release 3.3 milestone 1. service-watchdog.jsonl reached 12 MB from
    one-minute probes (6.9 MB when the milestone was written) because nothing
    was allowed to touch it: the repo contract says ledgers are append-only
    and never rewritten or truncated. That contract's INTENT is that evidence
    is never silently destroyed -- not that a probe log grows forever.

    Archive-then-trim honors the intent:

      1. Lines older than the policy's keepDays are APPENDED VERBATIM to a
         year-bucketed archive file under the policy's archiveDir. Nothing is
         destroyed; the line's bytes survive unmodified.
      2. The live ledger is rewritten to its survivors via a temp file and an
         atomic move, so a crash mid-prune leaves the ORIGINAL ledger intact,
         never a truncated one.
      3. The operation reports the pruned range (first/last timestamp), the
         counts and the byte delta, and the caller logs it. A prune nobody
         can see happened is the same lie as a metric nobody can source.

    Fail-safe rules, each asserted by the module smoke:
      - A line whose timestamp cannot be parsed is KEPT. Never prune what you
        cannot date.
      - The newest minKeepLines survive regardless of age: a ledger that went
        quiet for a year must not be pruned to empty.
      - Every target path must resolve under the workspace's output\ tree.
        evidence\baseline\ is permanent by contract and unreachable here.
      - Scope is DECLARED, both ways: every .jsonl in the ledger homes must be
        a target or a named exclusion, so a new ledger cannot silently grow
        unbounded (the tripwire lives in the module smoke).
#>

Set-StrictMode -Version Latest

function Get-LedgerRetentionPolicy {
    <#
    .SYNOPSIS
        Resolve the ledger retention policy from settings, validated.
    .OUTPUTS
        [pscustomobject] Enabled, KeepDays, MinKeepLines, ArchiveDir,
        Targets (Path/TimestampField/Name), Exclusions (Path/Reason).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Settings,
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot
    )

    $outputRoot = [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRoot 'output'))

    $ledgerConfig = $null
    if ($Settings.ContainsKey('retention') -and $Settings.retention -is [System.Collections.IDictionary] -and $Settings.retention.Contains('ledgers')) {
        $ledgerConfig = $Settings.retention['ledgers']
    }

    $enabled = $true
    $keepDays = 90
    $minKeepLines = 500
    $archiveRel = 'output\archive\ledgers'
    if ($null -ne $ledgerConfig) {
        if ($ledgerConfig.Contains('enabled')) { $enabled = [bool]$ledgerConfig['enabled'] }
        if ($ledgerConfig.Contains('keepDays') -and [int]$ledgerConfig['keepDays'] -gt 0) { $keepDays = [int]$ledgerConfig['keepDays'] }
        if ($ledgerConfig.Contains('minKeepLines') -and [int]$ledgerConfig['minKeepLines'] -ge 0) { $minKeepLines = [int]$ledgerConfig['minKeepLines'] }
        if ($ledgerConfig.Contains('archiveDir') -and -not [string]::IsNullOrWhiteSpace([string]$ledgerConfig['archiveDir'])) { $archiveRel = [string]$ledgerConfig['archiveDir'] }
    }

    # The targets and exclusions are code-declared, not config-declared: the
    # tripwire that keeps them exhaustive lives in the module smoke, and a
    # config file cannot be held to a tripwire. Config tunes the knobs.
    $targetSpecs = @(
        @{ Name = 'service-watchdog';  RelativePath = 'output\logs\service-watchdog.jsonl';           TimestampField = 'timestamp' }
        @{ Name = 'request-timeouts';  RelativePath = 'output\logs\request-timeouts.jsonl';           TimestampField = 'timestamp' }
        @{ Name = 'automation-runs';   RelativePath = 'output\automation\automation-runs.jsonl';      TimestampField = 'startedAt' }
        @{ Name = 'packaging-runs';    RelativePath = 'output\automation\packaging-runs.jsonl';       TimestampField = 'startedAt' }
        @{ Name = 'packaged-items';    RelativePath = 'output\automation\packaged-items.jsonl';       TimestampField = 'recordedAt' }
        @{ Name = 'roadmap-history';   RelativePath = 'output\roadmap-task-history\history.jsonl';    TimestampField = 'timestamp' }
    )
    $exclusionSpecs = @(
        @{ RelativePath = 'output\model-routing-ledger.jsonl';   Reason = 'Repo contract: dev-tooling ledger, append-only, never rewritten (CLAUDE.md).' }
        @{ RelativePath = 'output\roadmap-task-queue.jsonl';     Reason = 'Live claim state: the runner filters entries by summary status; pruning is a runner-semantics change, deferred by name.' }
        @{ RelativePath = 'output\roadmap-writeback.jsonl';      Reason = 'Write-back decision audit, currently ~4 KB; include when it grows enough to matter.' }
        @{ RelativePath = 'output\agent-runs\events.jsonl';      Reason = 'Agent-run activity feed the portal reads whole; small; include with a UI-aware window later.' }
    )

    $targets = @()
    foreach ($spec in $targetSpecs) {
        $full = [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRoot $spec.RelativePath))
        if (-not $full.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Ledger retention target '{0}' resolves outside {1}; retention must never reach past output\." -f $spec.RelativePath, $outputRoot)
        }
        $targets += [pscustomobject]@{ Name = $spec.Name; Path = $full; TimestampField = $spec.TimestampField }
    }
    $exclusions = @()
    foreach ($spec in $exclusionSpecs) {
        $exclusions += [pscustomobject]@{
            Path   = [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRoot $spec.RelativePath))
            Reason = $spec.Reason
        }
    }

    $archiveDir = [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRoot $archiveRel))
    if (-not $archiveDir.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Ledger archive dir '{0}' resolves outside {1}; archives stay inside output\." -f $archiveRel, $outputRoot)
    }

    return [pscustomobject]@{
        Enabled      = $enabled
        KeepDays     = $keepDays
        MinKeepLines = $minKeepLines
        ArchiveDir   = $archiveDir
        Targets      = $targets
        Exclusions   = $exclusions
    }
}

function Invoke-LedgerRetention {
    <#
    .SYNOPSIS
        Apply (or preview, with -WhatIf) the ledger retention policy.
    .OUTPUTS
        [pscustomobject] success, appliedAt, keepDays, minKeepLines, reports[]
        -- one report per target: name, path, kept, pruned, prunedFrom,
        prunedTo, archivePath, bytesBefore, bytesAfter, skippedReason.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Policy,
        [Parameter()][datetime]$Now = (Get-Date)
    )

    $reports = New-Object System.Collections.Generic.List[object]
    $cutoff = $Now.ToUniversalTime().AddDays(-1 * [int]$Policy.KeepDays)

    foreach ($target in @($Policy.Targets)) {
        $report = [ordered]@{
            name = $target.Name; path = $target.Path
            kept = 0; pruned = 0; prunedFrom = $null; prunedTo = $null
            archivePath = $null; bytesBefore = 0; bytesAfter = 0; skippedReason = $null
        }

        if (-not $Policy.Enabled) {
            $report.skippedReason = 'disabled-by-policy'
            $reports.Add([pscustomobject]$report); continue
        }
        if (-not (Test-Path -LiteralPath $target.Path)) {
            $report.skippedReason = 'file-absent'
            $reports.Add([pscustomobject]$report); continue
        }

        $report.bytesBefore = (Get-Item -LiteralPath $target.Path).Length
        $lines = @([System.IO.File]::ReadAllLines($target.Path))

        # Classify each line once. Unparseable timestamps are kept: never
        # prune what you cannot date.
        $classified = New-Object System.Collections.Generic.List[object]
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $stamp = $null
            try {
                $obj = $line | ConvertFrom-Json
                $raw = $null
                if ($null -ne $obj -and $obj.PSObject.Properties.Name -contains $target.TimestampField) {
                    $raw = [string]($obj.($target.TimestampField))
                }
                if (-not [string]::IsNullOrWhiteSpace($raw)) {
                    $parsed = [datetime]::MinValue
                    if ([datetime]::TryParse($raw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
                        $stamp = $parsed.ToUniversalTime()
                    }
                }
            }
            catch { $stamp = $null }
            $classified.Add([pscustomobject]@{ Line = $line; Stamp = $stamp })
        }

        # The newest minKeepLines survive regardless of age.
        $floorProtected = [System.Collections.Generic.HashSet[int]]::new()
        $floorCount = [Math]::Min([int]$Policy.MinKeepLines, $classified.Count)
        for ($i = $classified.Count - $floorCount; $i -lt $classified.Count; $i++) {
            if ($i -ge 0) { $null = $floorProtected.Add($i) }
        }

        $keep = New-Object System.Collections.Generic.List[string]
        $prune = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $classified.Count; $i++) {
            $entry = $classified[$i]
            $isOld = ($null -ne $entry.Stamp -and $entry.Stamp -lt $cutoff)
            if ($isOld -and -not $floorProtected.Contains($i)) {
                $prune.Add($entry)
            }
            else {
                $keep.Add($entry.Line)
            }
        }

        $report.kept = $keep.Count
        $report.pruned = $prune.Count
        if ($prune.Count -eq 0) {
            $report.bytesAfter = $report.bytesBefore
            $reports.Add([pscustomobject]$report); continue
        }

        $prunedStamps = @($prune | Where-Object { $null -ne $_.Stamp } | ForEach-Object { $_.Stamp } | Sort-Object)
        if (@($prunedStamps).Count -gt 0) {
            $report.prunedFrom = $prunedStamps[0].ToString('o')
            $report.prunedTo = $prunedStamps[-1].ToString('o')
        }
        $archiveFile = Join-Path $Policy.ArchiveDir ("{0}.{1}.jsonl" -f $target.Name, $Now.ToUniversalTime().ToString('yyyy'))
        $report.archivePath = $archiveFile

        if ($PSCmdlet.ShouldProcess($target.Path, ("Archive {0} line(s) to {1} and trim the live ledger" -f $prune.Count, $archiveFile))) {
            if (-not (Test-Path -LiteralPath $Policy.ArchiveDir)) {
                $null = New-Item -ItemType Directory -Path $Policy.ArchiveDir -Force
            }
            # Archive FIRST: if the archive append fails, the live ledger has
            # not been touched. Verbatim bytes, append-only.
            [System.IO.File]::AppendAllLines($archiveFile, [string[]]@($prune | ForEach-Object { $_.Line }))

            # Then the atomic swap: survivors to a temp file, move over the
            # original. A crash between the two writes leaves the original.
            $tempPath = $target.Path + '.retention-tmp'
            [System.IO.File]::WriteAllLines($tempPath, [string[]]$keep.ToArray())
            Move-Item -LiteralPath $tempPath -Destination $target.Path -Force
            $report.bytesAfter = (Get-Item -LiteralPath $target.Path).Length
        }
        else {
            # -WhatIf: report what would happen; touch nothing.
            $report.bytesAfter = $report.bytesBefore
        }

        $reports.Add([pscustomobject]$report)
    }

    return [pscustomobject]@{
        success      = $true
        appliedAt    = $Now.ToUniversalTime().ToString('o')
        keepDays     = [int]$Policy.KeepDays
        minKeepLines = [int]$Policy.MinKeepLines
        reports      = $reports.ToArray()
    }
}
