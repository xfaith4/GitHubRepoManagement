<#
.SYNOPSIS
  Three rules to wire into tools/Test-RoadmapStructure.ps1.

  R020-MILESTONE-CHECK        every open milestone bullet carries a `check:` line
  R021-OPERATOR-GATE-IN-ROADMAP  no bullet in Current focus or §6/§7 names operator-only work
  R022-STATUS-PROSE-LENGTH    "Current Status (Agent Context)" prose before the first checkbox is bounded
  R023-COMPLETION-PROSE       a bullet in §6/§7 reading "done <date>" with no checkbox is archive text left behind

  Each function takes the file as a string[] and emits finding objects in the shape the
  existing script already aggregates: Rule, Severity, Line, Message. All three are
  Severity = 'error' so -FailOnError rejects the file; downgrade R022 to 'warning' if
  you want a grace period, but not the other two — they are the whole point.
#>

$script:OperatorOnlyPattern = @(
    # Not the ledger: evidence/operator-verification-log.jsonl is a file the roadmap
    # may name; 'operator-verify the ...' is the work it may not.
    'operator-verif(?!ication[-\s](?:log|ledger|record))',
    'eyes on',
    'elevated (shell|session|run|install)',
    'SYSTEM (rights|session|install)',
    'authenticated (operator )?(shell|session)',
    'physical (Android|device|phone)',
    'on the LAN',
    'grant(ed|s)? the PAT',
    "Ben's (next )?session",
    'needs Ben',
    'operator (batch|session|sign-off|approval)',
    'no agent may (claim|mark)'
) -join '|'

# Line number (1-based) of the first line matching a pattern after a given line,
# or 0 when nothing matches. Under StrictMode, reading .LineNumber from an empty
# Select-String result throws, which took the whole validator down on any
# roadmap lacking one of the headings these rules look for.
function Get-FirstMatchLineNumber {
    param([string[]]$Lines, [string]$Pattern, [int]$After = 0)
    $m = $Lines | Select-String -Pattern $Pattern | Where-Object { $_.LineNumber -gt $After } | Select-Object -First 1
    if ($null -ne $m) { return [int]$m.LineNumber }
    return 0
}

function Get-MilestoneBulletRange {
    param([string[]]$Lines)
    # Yields the line index of every top-level "- [ ]" bullet and the index where it ends.
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*-\s\[ \]') {
            $end = $i
            while ($end + 1 -lt $Lines.Count -and $Lines[$end + 1] -match '^\s{2,}\S' ) { $end++ }
            [pscustomobject]@{ Start = $i; End = $end }
        }
    }
}

function Test-R020MilestoneCheck {
    param([string[]]$Lines)
    foreach ($b in Get-MilestoneBulletRange -Lines $Lines) {
        $block = $Lines[$b.Start..$b.End] -join "`n"
        # Non-blockers and decision pointers are exempt; everything else must name its command.
        if ($block -match '\[non-blocker\]|open-decisions\.md') { continue }
        if ($block -notmatch '`check:\s*\S') {
            [pscustomobject]@{
                Rule     = 'R020-MILESTONE-CHECK'
                Severity = 'error'
                Line     = $b.Start + 1
                Message  = 'Open milestone has no `check:` line. A milestone without a runnable check is a question; move it to open-decisions.md or write the check.'
            }
        }
    }
}

function Test-R021OperatorGate {
    param([string[]]$Lines)
    # Scope: from "Current focus" through the end of §7. Guardrails (§8) legitimately
    # mention operator approval as a *merge* boundary and are excluded.
    $start = Get-FirstMatchLineNumber -Lines $Lines -Pattern '^\*\*Current focus'
    $stop  = Get-FirstMatchLineNumber -Lines $Lines -Pattern '^## 8\.'
    if (-not $start -or -not $stop) { return }
    foreach ($b in Get-MilestoneBulletRange -Lines $Lines) {
        if ($b.Start + 1 -lt $start -or $b.Start + 1 -ge $stop) { continue }
        $block = $Lines[$b.Start..$b.End] -join ' '
        if ($block -match $script:OperatorOnlyPattern) {
            [pscustomobject]@{
                Rule     = 'R021-OPERATOR-GATE-IN-ROADMAP'
                Severity = 'error'
                Line     = $b.Start + 1
                Message  = "Milestone names operator-only work ('$($Matches[0])'). Split it: keep the agent half here with its check, append the human half to docs/governance/operator-queue.md."
            }
        }
    }
}

function Test-R022StatusProseLength {
    param([string[]]$Lines, [int]$MaxLines = 25)
    $start = Get-FirstMatchLineNumber -Lines $Lines -Pattern '^## Current Status'
    if (-not $start) { return }
    $firstBox = Get-FirstMatchLineNumber -Lines $Lines -Pattern '^\s*-\s\[ \]' -After $start
    if (-not $firstBox) { return }
    $prose = $firstBox - $start - 1
    if ($prose -gt $MaxLines) {
        [pscustomobject]@{
            Rule     = 'R022-STATUS-PROSE-LENGTH'
            Severity = 'error'
            Line     = $start
            Message  = "$prose lines of narrative before the first actionable checkbox (limit $MaxLines). 'What changed (record, not an action)' paragraphs belong in CHANGELOG.md."
        }
    }
}

function Test-R023CompletionProse {
    param([string[]]$Lines)
    # Added 2026-09-13 after an agent closed E1 by turning "- [ ]" into "- " and leaving 14
    # lines of evidence prose in place. The archive rule says done items leave this file;
    # a checkbox-less bullet that announces completion is the workaround for "[x] is a mistake".
    $start = Get-FirstMatchLineNumber -Lines $Lines -Pattern '^## 6\.'
    $stop  = Get-FirstMatchLineNumber -Lines $Lines -Pattern '^## 8\.'
    if (-not $start -or -not $stop) { return }
    for ($i = $start; $i -lt $stop - 1; $i++) {
        $line = $Lines[$i]
        if ($line -match '^\s*-\s(?!\[)' -and $line -match '\b(done|closed|landed|shipped)\s+\d{4}-\d{2}-\d{2}') {
            [pscustomobject]@{
                Rule     = 'R023-COMPLETION-PROSE'
                Severity = 'error'
                Line     = $i + 1
                Message  = 'Completed item recorded as prose instead of archived. Move it verbatim to docs/history/completed-releases.md and leave at most a one-line pointer.'
            }
        }
    }
}

# --- R024: a built or verified milestone's check is a step CI runs ---------
# Ben, 2026-09-14, after M4b shipped `-Assert applicability` as its check line
# and the suite never ran it: a milestone called built on a check CI does not
# run is built on nobody's word. CI here is the canonical suite
# (scripts/Invoke-TestSuite.ps1, which ci-smoke.yml delegates to) plus every
# workflow `run:` line. A check is run when one CI line names the same target
# and carries every argument the check passes, switches included: a check run
# without -FailOnError cannot fail CI. The rule does nothing in a repository
# with no suite, so the validator stays usable on roadmaps elsewhere.

function Get-CiStepLine {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    $suitePath = Join-Path $RepoRoot 'scripts/Invoke-TestSuite.ps1'
    if (-not (Test-Path -LiteralPath $suitePath)) { return }
    foreach ($l in @(Get-Content -LiteralPath $suitePath -Encoding UTF8)) {
        if ($l -notmatch '^\s*#') { $l }
    }
    $workflowDir = Join-Path $RepoRoot '.github/workflows'
    if (Test-Path -LiteralPath $workflowDir) {
        foreach ($wf in @(Get-ChildItem -LiteralPath $workflowDir -File | Where-Object { $_.Extension -in '.yml', '.yaml' })) {
            foreach ($l in @(Get-Content -LiteralPath $wf.FullName -Encoding UTF8)) {
                if ($l -match '^\s*(-\s*)?run:\s*(.+)$') { $Matches[2] }
            }
        }
    }
}

# The command each npm script finally runs, following `npm run X --workspace W`
# into the workspace's own package.json.
function Resolve-NpmScriptCommand {
    param([Parameter(Mandatory = $true)][string]$RepoRoot, [Parameter(Mandatory = $true)][string]$ScriptName, [string]$PackageDir = '')
    $dir = if ($PackageDir) { Join-Path $RepoRoot $PackageDir } else { $RepoRoot }
    $pkgPath = Join-Path $dir 'package.json'
    if (-not (Test-Path -LiteralPath $pkgPath)) { return '' }
    $scripts = (Get-Content -LiteralPath $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties['scripts']
    if ($null -eq $scripts -or $null -eq $scripts.Value.PSObject.Properties[$ScriptName]) { return '' }
    $command = [string]$scripts.Value.PSObject.Properties[$ScriptName].Value
    if ($command -match '^npm run (?:--silent )?([\w:\-]+) --workspace[ =]([\w.\-/]+)$') {
        return Resolve-NpmScriptCommand -RepoRoot $RepoRoot -ScriptName $Matches[1] -PackageDir $Matches[2]
    }
    return $command
}

function ConvertTo-CiToken {
    param([string]$Text)
    return (($Text -replace '\\', '/') -replace '^\./', '').Trim("'", '"', ' ')
}

function Test-R024CheckRunsInCi {
    param([string[]]$Lines, [string]$RepoRoot = '')
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { return }
    # No suite, no rule. A suite that runs nothing is still a suite, and holds nothing.
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'scripts/Invoke-TestSuite.ps1'))) { return }
    $ciLines = @(Get-CiStepLine -RepoRoot $RepoRoot)
    $ciText = ($ciLines | ForEach-Object { ConvertTo-CiToken $_ }) -join "`n"
    # What each npm gate the suite runs actually executes.
    $npmCommands = @($ciLines | ForEach-Object {
            if ($_ -match "Invoke-NpmGate\b.*-ScriptName\s+'([\w:\-]+)'") { Resolve-NpmScriptCommand -RepoRoot $RepoRoot -ScriptName $Matches[1] }
            elseif ($_ -match '\bnpm run (?:--silent )?([\w:\-]+)') { Resolve-NpmScriptCommand -RepoRoot $RepoRoot -ScriptName $Matches[1] }
        } | Where-Object { $_ })
    # A script an npm gate runs is a step CI runs (ui:ratchet -> node tools/Measure-UiRatchet.mjs).
    if ($npmCommands.Count -gt 0) { $ciText += "`n" + (($npmCommands | ForEach-Object { ConvertTo-CiToken $_ }) -join "`n") }

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -notmatch '^\s*-\s\[( |x)\]') { continue }
        $end = $i
        while ($end + 1 -lt $Lines.Count -and $Lines[$end + 1] -match '^\s{2,}\S') { $end++ }
        $block = $Lines[$i..$end] -join "`n"
        if ($block -notmatch '\(state:\s*(built|verified)\b') { continue }
        foreach ($cm in [regex]::Matches($block, '`check:\s*([^`]+)`')) {
            $check = $cm.Groups[1].Value.Trim()
            $tokens = @($check -split '\s+' | Where-Object { $_ } | ForEach-Object { ConvertTo-CiToken $_ })
            $reason = $null
            if ($tokens.Count -ge 2 -and $tokens[0] -in 'npx', 'npm' -and ($tokens -contains 'vitest' -or $tokens[1] -eq 'test:unit' -or ($tokens[1] -eq 'run' -and $tokens.Count -ge 3 -and $tokens[2] -eq 'test:unit'))) {
                # A vitest path filter is a subset of the full run.
                if (-not ($npmCommands | Where-Object { $_ -match '\bvitest run\b' })) { $reason = 'CI runs no vitest suite' }
            }
            elseif ($tokens.Count -ge 3 -and $tokens[0] -eq 'npm' -and $tokens[1] -eq 'run') {
                $target = $tokens[2]
                if (-not ($ciLines | Where-Object { $_ -match "Invoke-NpmGate\b.*-ScriptName\s+'$([regex]::Escape($target))'" -or $_ -match "\bnpm run (?:--silent )?$([regex]::Escape($target))(\s|$)" })) { $reason = "CI runs no npm script '$target'" }
            }
            else {
                $targetIndex = -1
                for ($t = 0; $t -lt $tokens.Count; $t++) { if ($tokens[$t] -match '\.(ps1|mjs|cjs|js)$') { $targetIndex = $t; break } }
                if ($targetIndex -lt 0) {
                    $reason = 'the validator cannot tell which script it runs'
                }
                else {
                    $leaf = Split-Path $tokens[$targetIndex] -Leaf
                    $required = @($tokens | Select-Object -Skip ($targetIndex + 1))
                    $candidates = @($ciText -split "`n" | Where-Object { $_ -match "(?<![\w.\-])$([regex]::Escape($leaf))(?![\w.\-])" })
                    if ($candidates.Count -eq 0) { $reason = "CI never runs $leaf" }
                    else {
                        $matched = $candidates | Where-Object {
                            $line = $_
                            @($required | Where-Object { $line -notmatch "(?<![\w.\-/])$([regex]::Escape($_))(?![\w.\-/])" }).Count -eq 0
                        }
                        if (-not $matched) {
                            $missing = @($required | Where-Object { $tok = $_; -not ($candidates | Where-Object { $_ -match "(?<![\w.\-/])$([regex]::Escape($tok))(?![\w.\-/])" }) })
                            $reason = if ($missing.Count -gt 0) { "CI runs $leaf but never with $($missing -join ' ')" } else { "CI runs $leaf but no single step carries all of: $($required -join ' ')" }
                        }
                    }
                }
            }
            if ($reason) {
                [pscustomobject]@{
                    Rule     = 'R024-CHECK-RUNS-IN-CI'
                    Severity = 'error'
                    Line     = $i + 1
                    Message  = "Milestone is built or verified on a check CI does not run ($reason): $check. Wire it into scripts/Invoke-TestSuite.ps1 exactly as written, or return the milestone to planned."
                }
            }
        }
    }
}

# Wire-up example for the existing script's aggregation loop:
#   $findings += Test-R020MilestoneCheck   -Lines $lines
#   $findings += Test-R021OperatorGate     -Lines $lines
#   $findings += Test-R022StatusProseLength -Lines $lines
#   $findings += Test-R023CompletionProse   -Lines $lines
