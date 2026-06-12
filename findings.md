# Findings

## 2026-06-12 (Release 2.0 Phase 4: Budget Guard + Scan Annotations)

- The live roadmap and planning files diverged again: `ROADMAP.md` already had Release 2.0 active with Phases 1-3 shipped, while `task_plan.md` was still tracking a completed Release 1.9 slice. The next logical work therefore has to start from the active Release 2.0 Phase 4 seam, not by extending the stale 1.9 plan.
- The smallest truthful remaining seam is backend-first. The repo already has the agent-run ledger, refresh flow, merge-readiness routes, and Operations UI; the missing Phase 4 behavior is budget/quota enforcement before dispatch plus roadmap-derived estimation metadata.
- `Invoke-ParseRoadmapContent` currently only returns checkbox sections, counts, and tags. It does not surface the roadmap template's `Phase plan` table or `Budget guardrail` annotations yet, so dispatch estimates still cannot come from managed-roadmap metadata.
- `New-AgentRunRecord` still hardcodes `workUnitsEstimated = 3`, and `POST /api/roadmap/dispatch/execute` launches Copilot before any budget/quota check. Phase 4 therefore needs to connect roadmap metadata, settings-backed budget config, and the dispatch route in one coherent path.
- The worktree is already dirty with unrelated line-ending churn and other edits (`README.md`, `ROADMAP.md`, `.github/*`, `Start-App.ps1`, `Portfolio.ValueScorer.ps1`, archive docs). Future validation and artifact updates need to stay scoped to touched files instead of assuming a clean tree.
- The first Phase 4 regression after implementation was real: ASCII `-` placeholders in phase-plan `Completed` cells were being treated as completion markers, which erased the active phase from annotated roadmaps. Normalizing placeholder cells fixed the parser and the module smoke.
- The new quota-refusal route works in isolated scratch-port validation, but the broad `Invoke-ApiHostSmokeTest.ps1` harness still does not return after entering that route. That points to an end-to-end harness/runtime interaction, not to missing core Phase 4 logic, so the verification notes need to distinguish those two facts.

## 2026-06-09 (Release 1.8: Operations Prompt Dispatch Tracking)

- The next unfinished Release 1.8 seam was not a new 1.9 capability. The live repo already had prompt refinement history and an older dispatch path, but there was no durable link between a refined Operations prompt and the Copilot run it launched.
- Adding a second history store inside the route body would have made the feature brittle. The safer approach was to append dispatch records alongside the existing per-repo refinement JSONL and merge them in `GET /api/operations/prompt/history` by refinement `runId`.
- The Operations UI did not need a brand-new dispatch modal to close this gap. The refined prompt was already editable in-panel, so the smallest viable slice was to add an explicit Dispatch action there while still requiring operator intent and honoring readiness/maturity gating in the UI.
- The first verification failure was not in the product code. The new smoke regression harness used `Split-Path -LiteralPath ... -Parent`, which PowerShell rejects as an invalid parameter combination; changing that to `-Path` fixed the harness and the full host smoke passed.

## 2026-05-28 (Roadmap Viewer Task-Source Mismatch)

- The ROADMAP modal had a real contract bug: the lower pane could load a local roadmap file successfully while the upper Preview Task / Start Task actions still attempted to rediscover roadmap content through the GitHub repository field.
- The failure was not in roadmap parsing. `RoadmapViewerModal.tsx` never passed the already-loaded local `content.path`, and `Start-RoadmapCopilotTask.ps1` treated every `-RoadmapPath` candidate as a GitHub contents path instead of honoring an explicit local file first.
- That mismatch produced the contradictory operator experience shown in the bug report: a visible roadmap in the modal plus a "No roadmap markdown file found in repository ..." error in the task-preview area.
- The fix path is now explicit and regression-covered: the modal passes the loaded local roadmap path, and the roadmap-agent script prefers a real local file before any GitHub lookup.

## 2026-05-28 (Release 1.8 Phase 1: Operations Workspace Foundation)

- Release 1.8 did not need a fresh UI buildout first. The live repo already had an Operations tab, an `OperationsWorkspaceView`, frontend types, and client wiring, so the real product gap was the missing backend route and proof that the view consumed a stable indexed model.
- The safest backend implementation was to reuse the persisted portfolio index instead of recomputing another repo-detail model in parallel. That kept the Operations workspace aligned with the same lifecycle, ranking, and GitHub signals already used by Portfolio Mission and Work Queue.
- A hard failure when the index was absent would have made the Operations tab fragile during startup or cache warmup. The route therefore needed an assessment-cache fallback so a recent portfolio warm path could still power the workspace.
- The most important validation point for this slice was not just PowerShell parse success. It was expanding `Invoke-ApiHostSmokeTest.ps1` so `/api/operations/repos` is exercised after `/api/portfolio/assessment`, proving the persisted-index handoff is live.

## 2026-05-28 (Phase 7B)

- The next real gap after differential scan completion was not another assessment tweak; the roadmap called for a collection-level reporting surface backed by the portfolio model, and the live app still exported only a generic repo-status snapshot.
- Replacing `/api/export` outright would have been a behavioral regression for non-portfolio scenarios, so the safe slice was to extend it for `portfolioEntries` while keeping the older repo-status path as a fallback.
- The documentation gap was real user-facing scope, not cleanup. Help, API reference, and the portfolio assessment reference all needed to describe the same scan → classify → rank → refine prompt → dispatch → report loop or the product story would remain internally inconsistent.
- Parser and build success were not enough for this phase because the risk was runtime wiring. The important proof point was the API smoke path opening the saved HTML report and confirming it served Collection Status Report content.

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
