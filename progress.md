# Progress

## 2026-05-28 (Phase 7A)

- Reconciled the active roadmap and confirmed Phase 7A differential scan completion was the next active milestone after the Phase 6 packet foundation.
- Extended the `/api/portfolio/assessment` route to support `scanMode=differential` repo selection and changed-only reassessment using persisted index fingerprints.
- Added index helper coverage in `Portfolio.Assessment.ps1` for signal-derived fingerprints and conversion from persisted index records back to assessment-shaped entries for unchanged repo merge behavior.
- Updated `scripts/Invoke-ApiHostSmokeTest.ps1` to validate the differential route contract and scan-mode markers.
- Fixed a differential-mode cache bypass defect in `Start-RepoManagementApiHost.ps1` so `scanMode=differential` requests no longer short-circuit through the global memory cache.
- Verification passed:
  - PowerShell parser diagnostics for `backend/api-host/Start-RepoManagementApiHost.ps1`, `backend/modules/portfolio/Portfolio.Assessment.ps1`, and `scripts/Invoke-ApiHostSmokeTest.ps1`.
  - Focused API host validation with scoped inventory settings confirmed `GET /api/portfolio/assessment?scanMode=differential` returns `success=true` and `signalSources.scanMode=differential-fallback-full`.

## 2026-05-28 (Phase 6)

- Reconciled the active roadmap against the live implementation and confirmed the next unfinished slice after the expanded evaluator was Phase 6: prompt context packet foundation.
- Extended `Build-CopilotTaskPacket` in `Start-RepoManagementApiHost.ps1` so task preview packets now carry README summary/headings, release goal and out-of-scope context, lifecycle/score context from portfolio assessment, explicit constraints, and value rationale.
- Updated task selection so the packet prefers the portfolio assessment's top-value roadmap item when that signal is available, while cleanly falling back to roadmap order if assessment context is absent.
- Expanded `CopilotTaskPreviewModal.tsx` and the frontend packet types to surface the new context blocks before prompt copy or dispatch.
- Updated `scripts/Invoke-ApiHostSmokeTest.ps1` to warm portfolio assessment before preview and validate the new packet fields.
- Verification passed:
  - `git diff --check -- backend/api-host/Start-RepoManagementApiHost.ps1 frontend/types.ts frontend/components/CopilotTaskPreviewModal.tsx scripts/Invoke-ApiHostSmokeTest.ps1`
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`
  - `npm run build`

## 2026-05-28

- Reconciled the active roadmap against live code and confirmed Release 1.7.5 Phase 5 was the next unfinished slice: repo evaluation still centered on hardening findings and single-release draft output.
- Expanded `Roadmap.Evaluator.ps1` to detect documentation, testing, security, modernization, feature-surface, and user-value opportunities for repos that need roadmap creation.
- Reworked evaluator draft generation so suggested roadmap content is grouped into staged releases instead of a single hardening-heavy dump.
- Updated the repo-evaluation modal, help copy, and frontend category types so the UI reflects the broader evaluator contract and summarizes findings by category.
- Added repo-evaluator smoke coverage to `scripts/Invoke-ModuleSmokeTest.ps1` and separately verified the evaluator against a temporary repo to confirm the new finding categories and staged roadmap output.
- `npm run build` passed after the UI/type changes.
- The full module smoke script later failed in an unrelated pre-existing portfolio-assessment smoke section with `The term 'if' is not recognized...`; the new evaluator smoke step had already passed before that blocker surfaced.

## 2026-05-27

- Reconciled the active roadmap against live code and confirmed Release 1.7.5 Phase 4 was still missing in the UI: the backend exposed `topValueItem`, but Work Queue still sorted only by dispatch readiness and showed no value rationale.
- Wired Work Queue to the portfolio assessment model so each ready repo shows its highest-value roadmap item, value score, value tier, and rationale tooltip.
- Updated Work Queue ordering to sort by readiness first and by `topValueItem.valueScore` within each readiness bucket, with pending-count and repo-name fallback ordering.
- Refreshed the Work Queue data path so docs-audit refresh and scan actions also refresh portfolio assessment data, preventing stale value ranking after an audit refresh.
- Updated `ROADMAP.md`, `CHANGELOG.md`, and `docs/reference/portfolio-assessment.md` to mark Release 1.7.5 Phase 4 complete and document the ranking contract.
- Verification passed:
  - `npm run install:frontend`
  - `npm run build`

## 2026-04-26

- Read active roadmap and completed-release archive.
- Identified Release 1.7.5 Phase 2 value ranking as the next roadmap phase.
- Created planning files for this multi-step release task.
- Added `backend/config/value-scoring.json`.
- Added `backend/modules/portfolio/Portfolio.ValueScorer.ps1`.
- Wired portfolio assessment to expose scored `pendingItems` and `topValueItem`.
- Updated API host wiring, frontend types, module smoke coverage, and API host smoke contract checks.
- Verification passed:
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ModuleSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`
  - `npm run build`
  - PowerShell parser check for API host and portfolio modules
- API host smoke printed `[PASS] API host smoke completed` and validated the expanded portfolio assessment contract; the process did not return after printing the summary, so it was terminated after pass output and no host/test process remains.
- Updated `ROADMAP.md` and `CHANGELOG.md` for Release 1.7.5 Phase 2.
