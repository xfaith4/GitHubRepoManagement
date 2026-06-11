# Task Plan

## Goal
Execute the next logical roadmap phase. Release 1.8 had no remaining milestones, so the next phase is Release 1.9 (AI Documentation Improvement Cycles). Deliver a bounded Phase 1 — AI provider adapter foundation + a preview-only improvement route — respecting token/context limits rather than the whole release.

## Scope

- Define a provider-agnostic documentation-improvement adapter contract.
- Implement a deterministic offline heuristic provider (no hard roadblock when no AI key is configured), plus OpenAI and Anthropic raw-HTTP adapters.
- Provide data-driven built-in README/ROADMAP improvement templates.
- Add `POST /api/ai/docs/improve/preview` (preview-only; no file mutation).
- Add offline, deterministic smoke coverage for the preview route.
- Promote Release 1.9 to active and update roadmap/changelog/progress artifacts after verification.
- Defer diff viewer + history (Phase 2) and explicit apply + backup/restore (Phase 3).

## Phases

| Phase                                  | Status   | Notes                                                                                                                                                              |
| -------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1. Repo orientation                    | complete | ROADMAP + progress confirmed Release 1.8 complete; Release 1.9 is the next implementation target. Consulted the `claude-api` skill before the Anthropic adapter.   |
| 2. Templates config                    | complete | `backend/config/ai-doc-templates.json` with README + ROADMAP improvement templates.                                                                                |
| 3. Provider module                     | complete | `backend/modules/ai/AiDocImprovement.ps1`: adapter contract + heuristic/OpenAI/Anthropic adapters + `Invoke-AiDocImprovePreview` orchestrator.                      |
| 4. Route wiring                        | complete | `POST /api/ai/docs/improve/preview` in the API host with current-content resolution and provider fallback.                                                          |
| 5. Smoke coverage                      | complete | Offline heuristic-provider smoke step in `Invoke-ApiHostSmokeTest.ps1`.                                                                                             |
| 6. Verification                        | complete | Parser checks, `npm run build`, roadmap validator (0 errors), and direct live-host validation of the route (incl. the Anthropic adapter against the live API).      |
| 7. Roadmap and session-file updates    | complete | Promoted Release 1.9 to active, added a phase plan + full active-release execution contract, archived Release 1.8, and updated CHANGELOG/progress/task_plan.         |

## Errors Encountered

| Error                                                                                              | Attempt                                                       | Resolution                                                                                                                                              |
| -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Full `Invoke-ApiHostSmokeTest.ps1` timed out at the 30s request cap during docs-audit warmup.       | Ran the full smoke; it failed before reaching the new AI step. | Pre-existing environmental slowness on a large local inventory (documented in prior entries). Validated the new route directly against a live host instead. |
| Unrelated files (`README.md`, `settings.json`, three `.ps1`) showed up as modified mid-session.     | Inspected diffs.                                             | Caused by the IDE markdown/PowerShell formatter and the smoke test's settings POST — not part of this task. Restored them to HEAD; change set now contains only Phase 1 work. |
