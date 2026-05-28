# Findings

## 2026-05-27

- `ROADMAP.md` and live code diverged: the roadmap already claimed Phase 3C shipped, but `WorkQueueView.tsx` still ignored the assessment value model and sorted only by docs-audit readiness.
- The smallest real next slice was Release 1.7.5 Phase 4, not a new release: consume `topValueItem` in Work Queue, show the rationale, and rank ready repos by value.
- Work Queue refresh behavior would have left stale value rankings in place because `getDocsAudit(true)` did not also invalidate `getPortfolioAssessment()`.
- Frontend verification was initially blocked by a missing Rollup optional dependency in `node_modules`, which the repo-local `npm run install:frontend` path repaired cleanly.

## 2026-04-26

- `ROADMAP.md` says the active release is `1.7.5` and Phase 2 is the next active target.
- Phase 2 scope is `Portfolio.ValueScorer.ps1`, `value-scoring.json`, and value score on each pending item in the assessment response.
- Existing worktree is heavily dirty with unrelated changes; edits must be scoped and avoid reverting user work.
- Existing portfolio assessment backend is `backend/modules/portfolio/Portfolio.Assessment.ps1`.
- Existing module smoke coverage for portfolio assessment starts around `scripts/Invoke-ModuleSmokeTest.ps1` release 1.7.5 section.
- Assessment entries now need additive fields only to preserve existing UI/API consumers: `pendingItems` and `topValueItem`.
