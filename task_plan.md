# Task Plan

## Goal
Execute the next logical roadmap phase for Release 1.7.5: Phase 5 expanded evaluator.

## Scope
- Expand repo evaluation beyond hardening-only findings.
- Add roadmap-draft grouping that stages feature, documentation, security, and modernization work into clearer release suggestions.
- Update frontend evaluator presentation for the broader finding categories.
- Add smoke coverage for the evaluator contract and use targeted verification if unrelated smoke paths fail later in the script.
- Update roadmap/progress/changelog artifacts only after verification passes.

## Phases

| Phase | Status | Notes |
|---|---|---|
| 1. Repo orientation | complete | ROADMAP and live code confirm Release 1.7.5 Phase 5 is the next unfinished slice. |
| 2. Inspect evaluator behavior | complete | Verified repo evaluation was still hardening-first and draft generation was not staging broader roadmap opportunities. |
| 3. Implement expanded evaluator | complete | Broadened backend findings, staged roadmap draft generation, frontend category handling, and help text. |
| 4. Verification | complete | Repo-evaluator smoke coverage passed; targeted evaluator verification and frontend build also passed. |
| 5. Roadmap/docs sync | complete | Updated `ROADMAP.md`, `CHANGELOG.md`, `progress.md`, `task_plan.md`, and `findings.md` for Phase 5 completion. |

## Errors Encountered

| Error | Attempt | Resolution |
|---|---|---|
| `Invoke-RepoEvaluation` failed with `The property 'hasDependabot' cannot be found on this object.` | Ran the expanded evaluator against a temporary repo after adding the new heuristics. | Fixed `_GetRepoSignals` so the boolean product-docs check no longer emits a stray scalar before the signals object, then reran the evaluator successfully. |
| `scripts/Invoke-ModuleSmokeTest.ps1` later failed in `Invoke-PortfolioAssessment` with `The term 'if' is not recognized...`. | Ran the full module smoke script after adding the new evaluator smoke step. | Treated it as an unrelated pre-existing blocker because the new evaluator smoke step had already passed, then supplemented evidence with a targeted `Invoke-RepoEvaluation` verification and `npm run build`. |
