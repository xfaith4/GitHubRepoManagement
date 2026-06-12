# Task Plan

## Goal
Continue Release 2.0 with Phase 4: add budget ledger configuration, enforce the pre-dispatch quota guard on the route that launches coding-agent work, and parse roadmap budget/work-unit annotations so dispatch estimates come from managed-roadmap metadata instead of a hardcoded default.

## Scope

- Extend roadmap parsing so assessment and dispatch can see phase-plan work-unit annotations and budget-guardrail metadata from `ROADMAP.md`.
- Add a host-side budget ledger config surface that reads from `backend/config/settings.json` with safe defaults.
- Enforce quota checks in `POST /api/roadmap/dispatch/execute`, record `quota.*` telemetry, and carry truthful estimate metadata into new agent-run records.
- Update smoke/module coverage plus roadmap/progress/docs artifacts after verification.
- Keep changes narrowly scoped because the repo already has unrelated dirty files.

## Phases

| Phase | Status | Notes |
| --- | --- | --- |
| 1. Reconcile active roadmap slice | complete | Live `ROADMAP.md` already advanced to Release 2.0; stale Release 1.9 planning files replaced. |
| 2. Roadmap parser + assessment annotation flow | complete | Parser now returns release contexts, active phase-plan rows, budget guardrails, and estimated session units; assessment + roadmap-scan payloads carry them forward. |
| 3. Budget ledger + dispatch guard | complete | `BudgetLedger.ps1` landed, dispatch now enforces quota checks before GitHub dependencies, and new agent runs persist truthful estimate metadata. |
| 4. Smoke/docs/artifact updates | complete | Module/api smoke were extended, frontend/docs updated, and roadmap/session artifacts now reflect the Phase 4 implementation truthfully. |
| 5. Verification | complete | Build, parser checks, module smoke, roadmap structure, and targeted scratch-port route checks passed; the full api-host smoke harness still hangs after entering the quota-refusal step. |

## Errors Encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| Planning files still targeted Release 1.9 even though `ROADMAP.md` had already promoted Release 2.0. | 1 | Reconciled roadmap, progress, and live code first; replaced the active `task_plan.md` with the current release slice. |
| The full `Invoke-ApiHostSmokeTest.ps1` harness did not return after entering the new quota-refusal route step. | 1 | Verified the same Phase 4 contracts with targeted scratch-port route checks instead, and left the broader harness stall called out explicitly in roadmap/changelog notes. |
