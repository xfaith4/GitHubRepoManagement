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

# Wire-up example for the existing script's aggregation loop:
#   $findings += Test-R020MilestoneCheck   -Lines $lines
#   $findings += Test-R021OperatorGate     -Lines $lines
#   $findings += Test-R022StatusProseLength -Lines $lines
#   $findings += Test-R023CompletionProse   -Lines $lines
