# Task Plan

## Goal
Execute the next logical roadmap phase for Release 1.7.5: Phase 7B collection report + workflow documentation.

## Scope
- Add a portfolio-assessment-backed Collection Status Report export path that writes HTML and CSV artifacts.
- Keep the older repo-status export behavior available as a fallback so GitHub-only/report compatibility is not broken.
- Update Help and reference documentation so the north-star workflow is explicit and matches the live product behavior.
- Expand API host smoke coverage for the collection-report contract.
- Update roadmap/progress/changelog artifacts only after verification passes.

## Phases

| Phase | Status | Notes |
|---|---|---|
| 1. Repo orientation | complete | ROADMAP, progress notes, and live code confirmed Phase 7B was the next unfinished slice after differential scan completion. |
| 2. Inspect report/docs surfaces | complete | Verified the app still exported only a generic repo-status report and the Help/reference docs did not yet describe the full workflow loop. |
| 3. Implement collection report path | complete | Added `Portfolio.Report.ps1`, extended `/api/export` for portfolio entries, and updated the dashboard export flow to prefer portfolio assessment data. |
| 4. Update workflow documentation | complete | Refreshed Help, API docs, backend README, and portfolio reference docs so the scan → classify → rank → refine prompt → dispatch → report loop is explicit. |
| 5. Verification | complete | PowerShell parser checks, frontend build, `git diff --check`, and API host smoke all passed after the Phase 7B changes. |
| 6. Roadmap/docs sync | complete | Updated `ROADMAP.md`, `CHANGELOG.md`, `progress.md`, `task_plan.md`, and `findings.md` for Phase 7B completion and Release 1.7.5 closeout. |

## Errors Encountered

| Error | Attempt | Resolution |
|---|---|---|
| The dashboard still had to support non-portfolio export scenarios such as GitHub-only views. | Replaced the existing export path in a first draft. | Kept `/api/export` backward-compatible and taught the dashboard to fall back to the older repo-status export only when portfolio assessment entries are unavailable. |
| The new report contract needed runtime proof, not just parser/build success. | Added the report generator and frontend wiring first. | Expanded `scripts/Invoke-ApiHostSmokeTest.ps1` so it posts `portfolioEntries` to `/api/export` and asserts the served HTML contains Collection Status Report content. |
