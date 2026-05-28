# Findings

## 2026-05-28 (Phase 6)

- The next real gap after the expanded evaluator was not a new route. The repo already had a `CopilotTaskPacket` preview path, but it only carried roadmap-item, doc-finding, acceptance-criteria, and guardrail basics.
- Phase 6 required enriching that existing packet in place with README context, release context, lifecycle and scoring context from portfolio assessment, explicit constraints, and value rationale.
- The older task-preview flow still selected the first pending roadmap item by file order. Phase 6 was the right place to teach the packet builder to prefer the portfolio-ranked top-value item when that context is available.
- API smoke initially looked like a contract failure, but the live `/api/copilot-task/preview` payload already contained the new fields; the real issue was that the smoke check treated an empty `constraints` array as "missing".

## 2026-05-28

- The live repo evaluator was still effectively hardening-first; Release 1.7.5 Phase 5 required broader opportunity detection for missing-roadmap repos, not just structural gap reporting.
- Phase 5 was not only about more findings. The roadmap also needed the generated draft roadmap to separate foundational hardening from user-value and modernization work so the output could drive realistic execution ordering.
- The frontend repo-evaluation surface and help text still described the feature as a structure/hardening tool, so the UI contract needed to expand alongside the backend.
- Full-module verification exposed an unrelated pre-existing failure later in the portfolio-assessment smoke path (`The term 'if' is not recognized...`), so the Phase 5 evidence had to rely on the new evaluator smoke step, targeted evaluator execution, and the frontend production build.

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
