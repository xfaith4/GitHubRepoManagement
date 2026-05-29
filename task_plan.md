# Task Plan

## Goal
Execute the next logical roadmap phase for Release 1.8: Operations workspace foundation.

## Scope
- Back the existing Operations tab and repo workspace UI with a live `GET /api/operations/repos` backend route sourced from the portfolio index.
- Return an actionable fallback when the persisted index is missing but a warm portfolio assessment is available.
- Extend API/docs/help surfaces so the Operations workspace is part of the documented product contract.
- Expand API host smoke coverage for the operations repo-index route.
- Update roadmap/progress/changelog artifacts only after verification passes.

## Phases

| Phase | Status | Notes |
|---|---|---|
| 1. Repo orientation | complete | ROADMAP and live code confirmed Release 1.8 was the next active slice, and the existing Operations UI already existed but had no backend route. |
| 2. Verify current foundations | complete | Confirmed `Dashboard.tsx`, `OperationsWorkspaceView.tsx`, frontend types, and API client wiring were already present and only needed the host contract plus doc/smoke coverage. |
| 3. Implement operations route | complete | Added `/api/operations/repos` to the PowerShell host, serving persisted portfolio-index records with an assessment-cache fallback and stable `repoId` values. |
| 4. Update docs/help/smoke | complete | Extended API docs, Help copy, backend host README, and `Invoke-ApiHostSmokeTest.ps1` for the Operations workspace contract. |
| 5. Verification | complete | PowerShell parser checks, `npm run build`, `git diff --check`, and API host smoke all passed after the Operations foundation changes. |
| 6. Roadmap/docs sync | complete | Updated `ROADMAP.md`, `CHANGELOG.md`, `progress.md`, `task_plan.md`, and `findings.md` to promote Release 1.8 and mark the shipped foundation milestones truthfully. |

## Errors Encountered

| Error | Attempt | Resolution |
|---|---|---|
| The frontend build initially failed after the Help copy update. | Ran `npm run build` immediately after wiring the route/docs changes. | Fixed the apostrophe in the new Operations tip string and reran the build successfully. |
| The Operations UI already existed, so the risk was duplicating state or inventing another data model. | Considered adding a new backend-specific model path. | Reused `Get-PortfolioIndexPayload` and the existing indexed repo shape, adding only a stable `repoId` and an assessment-cache fallback at the route boundary. |
