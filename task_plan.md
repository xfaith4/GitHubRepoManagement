# Task Plan

## Goal
Continue Release 1.9 (AI Documentation Improvement Cycles) with Phase 2: the side-by-side diff viewer, custom improvement prompt UI, per-repo improvement-cycle history, and `GET /api/ai/docs/improve/history`. Phase 1 (provider foundation + preview route) shipped 2026-06-10 as commit `7b30f8c`.

## Scope

- Persist a compact improvement-cycle metadata record per preview (provider, template, score movement, change summary) to per-repo JSONL.
- Add `GET /api/ai/docs/improve/history` (per-repo, `docType` filter, limit) and `GET /api/ai/docs/templates`.
- Build the AI Documentation Improvement panel in the Operations workspace: docType/template/provider selection, custom prompt field, side-by-side Current vs Proposed comparison, run-another-cycle action, history tab.
- Extend smoke coverage to the templates and history routes.
- Update roadmap/changelog/progress artifacts after verification.
- Defer the explicit apply path with backup/restore (Phase 3).

## Phases

| Phase | Status | Notes |
| --- | --- | --- |
| 1. Commit Phase 1 | complete | `7b30f8c` on `main`. |
| 2. Backend history + routes | complete | `Write/Get-AiDocImprovementHistory` in the AI module; preview route persists per cycle; history + templates GET routes added to the host. |
| 3. Frontend contracts + panel | complete | Types, API client functions, and the AI Documentation Improvement panel with side-by-side diff, custom prompt, cycle re-run, and history tab. |
| 4. Smoke + docs surfaces | complete | Smoke asserts templates lists and the preview→history round trip; routes documented in `ApiDocsModal.tsx` and the api-host README. |
| 5. Verification | complete | Parser checks, `npm run build`, roadmap validator (0 errors), and live host checks of all three AI routes including the two-cycle flow. |
| 6. Roadmap and session-file updates | complete | Phase 2 milestones marked, phase plan + execution contract refreshed, CHANGELOG/progress/task_plan updated. |

## Errors Encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| History returned oldest-first for two previews within the same second. | Live route validation showed `newestMatchesCycle2=False`. | PowerShell 7 `ConvertFrom-Json` parses ISO timestamps into `[datetime]`; the `[string]` cast in the sort key dropped sub-second precision so same-second records tied and kept file order. Fixed by sorting on the raw value; regression-checked at module level. |
