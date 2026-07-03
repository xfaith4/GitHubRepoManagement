#Requires -Version 7
<#
.SYNOPSIS
  SessionStart hook: verifies the session's actual model against the
  expected model declared by Invoke-PhaseRun.ps1, and appends a
  model-validation record to the routing ledger.

  Registered for matchers 'startup' and 'compact' — the two SessionStart
  events where Claude Code includes a `model` field in hook input.
  (`clear`/`resume` do not carry it; those are logged as unverifiable.)
  SessionStart cannot block, so mismatches warn + record, never halt.
#>
$raw = [Console]::In.ReadToEnd()
try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$expected = $env:CLAUDE_EXPECTED_MODEL
if ([string]::IsNullOrWhiteSpace($expected)) { exit 0 }  # not a routed phase run

# model field may be absent, a string, or an object with id/display_name
$actual = $null
if ($null -ne $payload.model) {
    $actual = if ($payload.model -is [string]) { $payload.model }
              elseif ($payload.model.id)       { [string]$payload.model.id }
              elseif ($payload.model.display_name) { [string]$payload.model.display_name }
              else { [string]$payload.model }
}

function Normalize([string]$s) { ($s -replace '[^a-zA-Z0-9]', '').ToLowerInvariant() }

$verdict =
    if (-not $actual) { 'unverifiable' }
    elseif ((Normalize $actual).Contains((Normalize $expected)) -or
            (Normalize $expected).Contains((Normalize $actual))) { 'match' }
    else { 'MISMATCH' }

$ledger = $env:CLAUDE_ROUTING_LEDGER
if (-not $ledger) {
    $base = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $payload.cwd }
    $ledger = Join-Path $base 'output/model-routing-ledger.jsonl'
}
$null = New-Item -ItemType Directory -Force -Path (Split-Path $ledger)

$record = [ordered]@{
    ts        = (Get-Date).ToUniversalTime().ToString('o')
    event     = 'model-validation'
    phase     = $env:CLAUDE_PHASE_ID
    source    = $payload.source          # startup | compact | clear | resume
    sessionId = $payload.session_id
    expected  = $expected
    actual    = $actual
    verdict   = $verdict
}
($record | ConvertTo-Json -Compress) | Add-Content -Path $ledger

if ($verdict -eq 'MISMATCH') {
    @{
        systemMessage      = "MODEL ROUTING MISMATCH — expected '$expected', session is on '$actual' (phase $($env:CLAUDE_PHASE_ID)). Recorded to ledger."
        hookSpecificOutput = @{
            hookEventName     = 'SessionStart'
            additionalContext = "Model-routing policy for this phase step expects '$expected'. The session model differs. Pause and ask the operator before continuing implementation work."
        }
    } | ConvertTo-Json -Compress -Depth 4 | Write-Output
}
exit 0
