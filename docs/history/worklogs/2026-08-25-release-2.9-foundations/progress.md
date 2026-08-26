# Release 2.9 foundations-first completion — 2026-08-25

## Goal

Finish and validate the existing execution-contract readiness, route naming, and L1/L2 repair-path implementation before beginning Release 3.6.

## Initial checkpoint

- Inspected: `ROADMAP.md`, the existing execution-contract evidence, changed source files, smoke scripts, and the worktree status.
- Existing implementation: the three Release 2.9 foundations-first milestones are UI-connected but remain open pending canonical module and API-host smoke evidence.
- Validation recorded before this run: targeted red/green module and isolated API proof passed; canonical WSL / Windows PowerShell runs stopped in pre-existing fixtures.
- Current issue: `git diff --check` reports whitespace on newly changed `Roadmap.Repairer.ps1` lines. Changed PowerShell worktree files are UTF-8 with BOM and CRLF; the index uses mixed newline conventions.

## Decisions

- Preserve all existing user work; do not begin Release 3.6 early.
- First establish whether the whitespace report is a real content defect or newline/index normalization artifact, then make only a scoped formatting correction if required.
- Run canonical smoke commands after the formatting boundary is clean. Record all outcomes here before stopping.

## Validation performed

- `git diff --check` reported CRLF terminators as trailing whitespace on newly added `Roadmap.Repairer.ps1` lines. Byte and character inspection confirmed there is no trailing space or tab; the file and its index version both use CRLF, and the workspace system Git configuration does not recognize CRLF-at-EOL. No formatting rewrite was made because it would create unrelated churn. The existing Lane 0.8 `.gitattributes` item remains the correct place to address this repository-wide condition.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ModuleSmokeTest.ps1` — **exit 0** on 2026-08-25. The shared execution-contract red/green gate, L1 repair preview, portfolio lifecycle, canonical naming, and packaging refusal/selection gates all passed.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1` — **exit 1** on 2026-08-25. It passed through the roadmap-agent preview, then failed at `scripts/Invoke-ApiHostSmokeTest.ps1:1325` because the isolated dispatch queue did not exist. The run had warned that `output/roadmap-task-runner.heartbeat.json` was unreadable. Diagnosis is in progress; no source change has been made for this failure.
- The first failure was reproducibly a real isolation defect: `/api/roadmap-agent/start` wrote its smoke fixture to `output/roadmap-task-queue.jsonl`, not the smoke queue. The fixture run IDs were `20260825-223852-bc0b23fe`, `20260825-224354-ae146bb7`, and `20260825-224719-22791e72`. Synthetic heartbeat files from the failed runs were moved into `output/smoke/api-host/` so they cannot impersonate an operator runner.
- Added an explicit `-QueuePath` hand-off: API host → `Start-RoadmapCopilotTask.ps1` → `Add-RoadmapTaskToQueue.ps1`. All changed scripts parse under PowerShell, and a direct launcher probe wrote exclusively to its explicit queue path. The full API-host smoke still failed before its success assertion: the host route did not forward the expected path. The harness now asserts that the nested writer’s returned output names the isolated queue, producing the exact unexpected path on the next run.

## Next action

Rerun `scripts/Invoke-ApiHostSmokeTest.ps1` once to capture the new precise queue-path assertion. Use that evidence to repair the API-host process boundary, then rerun API-host smoke to exit 0. Do not start Release 3.6 until that proof is green.

## Continuation prompt

Continue Release 2.9 foundations-first completion from this worklog. Preserve the current worktree, inspect validation results, address only proven regressions, run canonical module/API-host smoke in the supported Windows environment, and update this log with exact results.
