# Model routing for roadmap phase runs

One JSONL ledger answers: which model was *supposed* to run each phase step,
which model *actually* ran, and did they match.

## How the validation chain works

1. `Invoke-PhaseRun.ps1 -Phase 2.1-P2 -Step plan` resolves the step in
   `phase-model-routing.json`, appends a `launch-intent` record to
   `output/model-routing-ledger.jsonl`, exports `CLAUDE_EXPECTED_MODEL` /
   `CLAUDE_PHASE_ID`, and launches `claude --model <x> --permission-mode <y>`.
   The model flag is enforcement; the ledger line is the audit record.
2. The `Assert-ModelRouting.ps1` SessionStart hook fires on `startup` and
   again on every `compact`, compares the session's actual model against
   the expected one, and appends a `model-validation` record with a
   `match / MISMATCH / unverifiable` verdict. Compact-time re-checks catch
   mid-session drift — including the "Switch models when a message is
   flagged" auto-switch, which is enabled in your config.
3. On MISMATCH the hook warns you via systemMessage and tells Claude (via
   injected context) to pause implementation and ask — SessionStart cannot
   block, so this is warn-and-record by design.

Known limits: the `model` field is absent on `clear`/`resume` SessionStart
events, so those log as `unverifiable` rather than a false pass. Effort
level is recorded as intent but is not CLI-enforceable — verify in the
`/model` picker; the launch banner reminds you.

## Install

1. Copy `Invoke-PhaseRun.ps1`, `phase-model-routing.json`, and `prompts/`
   somewhere in the repo (e.g. `scripts/model-routing/`).
2. Copy `hooks/Assert-ModelRouting.ps1` to `.claude/hooks/`.
3. Merge into `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup",
        "hooks": [ { "type": "command",
          "command": "pwsh -NoProfile -File \"$CLAUDE_PROJECT_DIR/.claude/hooks/Assert-ModelRouting.ps1\"" } ] },
      { "matcher": "compact",
        "hooks": [ { "type": "command",
          "command": "pwsh -NoProfile -File \"$CLAUDE_PROJECT_DIR/.claude/hooks/Assert-ModelRouting.ps1\"" } ] }
    ]
  }
}
```

4. Run `/hooks` once in a session to confirm registration (Claude Code
   snapshots hook config at session start).

## Usage

```powershell
./Invoke-PhaseRun.ps1 -Phase 2.1-P2 -Step plan        # Fable, plan mode, kickoff prompt auto-fed
./Invoke-PhaseRun.ps1 -Phase 2.1-P2 -Step implement   # Sonnet, acceptEdits
./Invoke-PhaseRun.ps1 -Phase 2.1-P4 -Step plan -DryRun
```

## Ledger queries

```powershell
# Any mismatches, ever
Get-Content output/model-routing-ledger.jsonl |
  ConvertFrom-Json | Where-Object verdict -eq 'MISMATCH'

# Intent vs actual, joined per phase step
Get-Content output/model-routing-ledger.jsonl | ConvertFrom-Json |
  Group-Object phase | ForEach-Object {
    [pscustomobject]@{
      Phase    = $_.Name
      Intent   = ($_.Group | Where-Object event -eq 'launch-intent').expectedModel -join ','
      Verdicts = ($_.Group | Where-Object event -eq 'model-validation').verdict -join ','
    }
  }
```

The ledger uses the same append-only JSONL pattern as the agent-run event
stream, so when Release 2.1 Phase 3 adds run timing/token/cost persistence,
these records can dual-write into the same SQLite store with zero redesign.
