# Task Plan

## Goal
Execute the next logical roadmap phase for Release 1.7.5: Phase 6 prompt context packet foundation.

## Scope
- Extend the existing Copilot task packet route with README, roadmap release, portfolio assessment, value rationale, and explicit constraint context.
- Prefer the ranked top-value roadmap item when portfolio assessment context is available.
- Update the preview modal so operators can review the richer packet foundation before dispatch.
- Expand API host smoke coverage for the prompt-context packet contract.
- Update roadmap/progress/changelog artifacts only after verification passes.

## Phases

| Phase | Status | Notes |
|---|---|---|
| 1. Repo orientation | complete | ROADMAP and live code confirm Release 1.7.5 Phase 6 is the next unfinished slice. |
| 2. Inspect task-packet path | complete | Verified an existing Copilot task packet route/modal already existed, but it stopped short of README, release, assessment, value, and constraints context. |
| 3. Implement prompt-context packet foundation | complete | Enriched the backend packet contract, preferred the ranked task when assessment context exists, and updated the preview modal to surface the new sections. |
| 4. Verification | complete | PowerShell parser checks, frontend build, and API host smoke all passed after the prompt-context contract changes. |
| 5. Roadmap/docs sync | complete | Updated `ROADMAP.md`, `CHANGELOG.md`, `progress.md`, `task_plan.md`, and `findings.md` for Phase 6 completion. |

## Errors Encountered

| Error | Attempt | Resolution |
|---|---|---|
| `git diff --check` reported hundreds of trailing-whitespace lines in `CopilotTaskPreviewModal.tsx`. | Ran a clean diff check after updating the prompt-context packet UI. | Normalized the file's line endings so the verification run reflected only the actual Phase 6 code changes. |
| The API smoke step reported `/api/copilot-task/preview returned success=true but packet fields missing`. | Ran the enriched API host smoke after the first implementation pass. | Inspected the live route payload, confirmed the new fields were present, then fixed the smoke assertion to test property presence instead of treating an empty `constraints` array as a missing field. |
