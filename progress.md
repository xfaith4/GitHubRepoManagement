# Progress

## 2026-07-03 (Release 2.1 Phase 1: SQLite Persistence Foundation)

- Reconciled the active roadmap and confirmed the next logical slice was
  Release 2.1 Phase 1: SQLite capability detection, `output/app.db`
  bootstrap with the schema-v1 tables, and a thin persistence boundary that
  leaves the JSON stores authoritative.
- Probed provider availability first: no `sqlite3` CLI and no
  `Microsoft.Data.Sqlite`, but the OS-shipped `winsqlite3.dll` (3.51.1) is
  present, so the new module uses a compiled zero-dependency native bridge
  (`NativeLibrary` + delegates) that also probes `libsqlite3` for WSL/Linux
  /macOS and degrades gracefully when no provider exists.
- Added `backend/modules/persistence/Persistence.Store.ps1`
  (`Get-SqliteCapability`, `Initialize-AppDatabase` with 11 idempotent
  schema-v1 tables in WAL mode, parameterized-only `Invoke-AppDbQuery` /
  `Invoke-AppDbNonQuery`, `Write-AppDbAgentRunEvent`), the dual-write seam
  in `Write-AgentRunEvent`, API-host startup bootstrap, and
  `GET /api/persistence/status`.
- Fixed two pre-existing module-smoke blockers introduced by the 2026-06-26
  standards-schema commit `db62f0b` (strict `recommendedSections` access in
  `DocAudit.Scanner.ps1`; `version` → `schemaVersion` rename in the
  structure-standards smoke) so the full module chain validates again; the
  section-authority audit wiring is recorded as deliberate follow-up work.
- Updated ApiDocsModal, api-host README, ROADMAP (milestone smoke-tested,
  Release 2.1 phase plan, Phase 2 current focus), CHANGELOG, and planning
  artifacts.

### Verification

- PowerShell parser diagnostics — clean for the persistence module, `AgentRuns.ps1`, `DocAudit.Scanner.ps1`, the API host, and both smoke scripts.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ModuleSmokeTest.ps1 -WorkspaceRoot "$(pwd)"` — passed end-to-end, including the new Release 2.1 sections (capability detection, bootstrap + idempotent re-init, 25 repeated writes, unicode/quote/NULL binding round-trip, dual-write seam).
- `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"` — passed end-to-end including the new persistence-status step (`provider=winsqlite3.dll`, 11 tables).
- Targeted scratch-port host check — `GET /api/persistence/status` returned `success=true` with `database.enabled=true` and all 11 tables; startup logged `Persistence: app database ready`.
- `npm run build` — passed.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md` — 0 errors, 0 warnings.

## 2026-06-27 (Test-harness fix: api-host smoke quota-refusal route)

- Cleared the carried-forward defect that blocked the broad
  `Invoke-ApiHostSmokeTest.ps1` harness from running end-to-end, so
  merge-readiness confidence no longer depends on isolated route checks.
- **Root cause:** the quota-refusal path in `POST /api/roadmap/dispatch/execute`
  logs pre-dispatch telemetry via `Write-AgentRunEvent ... -RunId ''` (no run
  exists yet because the dispatch is refused), but `Write-AgentRunEvent`
  declared `-RunId` as `[Parameter(Mandatory = $true)][string]`. PowerShell
  rejects an empty string for a mandatory string parameter, so the call threw
  *before* `Send-HttpJson -StatusCode 409`. The host's outer request handler
  caught it and returned HTTP 500 instead, so the harness's `expected HTTP 409`
  assertion failed at the quota step and the run never proceeded past it. The
  same empty `-RunId` is used by the `quota.warning` event, so both pre-dispatch
  telemetry paths were affected. The route was *not* leaking a stream or
  deadlocking — it failed fast (~0.2s) with a caught 500.
- **Fix:** made `-RunId` optional (`[Parameter()][string]$RunId = ''`) in
  `backend/modules/agent-runs/AgentRuns.ps1`, which is correct for pre-dispatch
  events that legitimately have no run id. The quota route now returns the
  intended HTTP 409 `quota-exhausted` / `session-cap-exceeded` payload. Change
  is backward compatible: all existing callers pass a real `RunId`.
- **Harness robustness (secondary):** `Invoke-ApiRequest` hard-coded
  `TimeoutSec = 30`, but the cold-cache `GET /api/portfolio/assessment` scan
  legitimately takes ~42s on a full workspace, which tripped a false timeout at
  an earlier step and prevented the harness from ever reaching the quota route.
  Added a `-RequestTimeoutSec` param (default 180) and a teardown sweep that
  force-stops any process still listening on the host port, so the harness
  always exits clean and a stopped job can't leave the listener holding the port
  (the "host did not exit after `[PASS]`" symptom).

### Verification

- `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"` ran start-to-finish, printed `[PASS] API host smoke completed`, and exited 0. The quota step logged `quota refusal -> reason=session-cap-exceeded est=8` (HTTP 409). No listener remained on the port and no background job lingered after teardown.
- `npm run build` passed.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md` returned 0 errors and 0 warnings.

## 2026-06-26 (Release 2.0 Closeout / Release 2.1 Promotion)

- Reconciled the roadmap, planning files, and live Operations UI and found
  the remaining work was release-closeout documentation rather than another
  code seam.
- Confirmed the only contradictory Release 2.0 milestone was the Agent Runs
  time/token visibility item: the UI already renders both fields, with token
  usage falling back to `n/a` when no provider/operator value exists.
- Updated `ROADMAP.md` to close Release 2.0, add a completion snapshot,
  promote Release 2.1 active, and point the new active-release current focus
  at Phase 1 SQLite/bootstrap work.
- Archived the full Release 2.0 detail in
  `docs/history/completed-releases.md` and added a closeout entry to
  `CHANGELOG.md`.

### Verification

- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md` passed with 0 errors.
- `git diff --check -- ROADMAP.md docs/history/completed-releases.md CHANGELOG.md task_plan.md progress.md findings.md` passed.

## 2026-06-12 (Release 2.0 Phase 4: Budget Guard + Scan Annotations)

- Reconciled the active roadmap against live code and found the planning files were stale: `ROADMAP.md` has Release 2.0 active with Phase 4 next, while `task_plan.md` was still describing a completed Release 1.9 slice.
- Read the Release 2.0 roadmap detail, `standards/roadmap/ROADMAP_BUDGET_MODEL.md`, the dispatch route, `AgentRuns.ps1`, `Roadmap.Parser.ps1`, and `Portfolio.Assessment.ps1` together to size the smallest remaining seam.
- Confirmed the actual missing contract is backend-first Phase 4 work: roadmap annotation parsing is absent, the dispatch route has no quota guard, and new agent runs still use a hardcoded estimated work-unit value.
- Updated `task_plan.md` and session findings so the active working notes now point at Release 2.0 Phase 4 instead of the already-shipped Release 1.9 work.
- Implemented the Phase 4 backend seam: `BudgetLedger.ps1`, roadmap release/phase/budget annotation parsing, portfolio-assessment pass-through, truthful estimated-unit capture on agent runs, and pre-dispatch quota enforcement with `quota.warning` / `quota.exhausted` telemetry in `POST /api/roadmap/dispatch/execute`.
- Extended the Operations-facing contracts so the UI and docs expose the new estimate metadata: dispatch success now reports quota/phase details, the Agent Runs panel shows section/phase/release and work-unit estimates, and the API reference documents the roadmap-scan annotation and quota-refusal payloads.

### Verification

- `npm run build` passed.
- PowerShell parser checks passed for `backend/modules/roadmap/Roadmap.Parser.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ModuleSmokeTest.ps1 -WorkspaceRoot "$(pwd)"` passed, including the new annotated-roadmap and budget-ledger steps.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md` returned 0 errors and 3 advisory warnings.
- Targeted scratch-port host checks passed for the new Phase 4 route contracts: annotated roadmap scans returned the expected active phase and work-unit estimate, and dispatch execution refused with HTTP 409 `quota-exhausted` / `session-cap-exceeded` before any GitHub dependency was required.
- The full `Invoke-ApiHostSmokeTest.ps1` harness now reaches the new Phase 4 steps but still did not return past the quota-refusal route in this session, so the end-to-end harness issue is called out separately instead of being hidden.

## 2026-06-11 (Release 1.9 Phase 2: AI Documentation Improvement — Diff Viewer & History)

- Committed Phase 1 (`7b30f8c`) and proceeded to the next roadmap slice: Release 1.9 Phase 2 — side-by-side diff viewer, custom improvement prompt UI, improvement-cycle history, and `GET /api/ai/docs/improve/history`.
- Extended `backend/modules/ai/AiDocImprovement.ps1` with per-repo improvement-cycle history (compact metadata JSONL under `output/ai-doc-improvements/`, gitignored) written on every preview and read newest-first with an optional `docType` filter.
- Added `GET /api/ai/docs/improve/history` and `GET /api/ai/docs/templates` to the API host; the preview route now persists a history record per cycle.
- Built the AI Documentation Improvement panel in `frontend/components/OperationsWorkspaceView.tsx`: README/ROADMAP selector, template + provider selects, custom improvement prompt, side-by-side Current vs Proposed comparison with change summary / score movement / warnings, copy-proposed action, "Run Another Cycle on Proposed", and a History tab. Typed contracts and client functions added in `frontend/types.ts` / `frontend/services/apiClient.ts`; routes documented in `ApiDocsModal.tsx` and the api-host README.
- Extended the API host smoke with templates-route and history-route assertions (missing-`repoName` 400, preview-written record matched by `previewId`).
- Found and fixed a real ordering bug during live validation: PowerShell 7's `ConvertFrom-Json` parses ISO timestamps into `[datetime]`, and the `[string]` cast in the history sort key dropped sub-second precision, so two previews within the same second returned oldest-first. Sorting on the raw value fixes it; regression-checked at module level.

### Verification

- PowerShell parser diagnostics for the AI module, API host, and smoke script — clean.
- `npm run build` — passed.
- `pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md` — 0 errors, 2 pre-existing advisory warnings.
- Live host validation on a scratch port: templates → 4 README + 4 ROADMAP entries; preview → history round trip (matching `previewId`); two-cycle proposed-content flow idempotent at full coverage; history missing-`repoName` → 400; `docType` filter returns 0 for non-matching type.

## 2026-06-10 (Release 1.9 Phase 1: AI Documentation Improvement — Provider Foundation & Preview)

- Read the full ROADMAP and progress history; confirmed Release 1.8 had no remaining milestones, so the next logical phase was Release 1.9 (AI Documentation Improvement Cycles). Scoped a bounded Phase 1 — provider foundation + preview route — respecting token/context limits rather than attempting the whole release.
- Added a provider-agnostic documentation-improvement adapter contract in `backend/modules/ai/AiDocImprovement.ps1` with three adapters: a deterministic offline heuristic provider (the no-hard-roadblock fallback), an OpenAI raw-HTTP adapter, and an Anthropic raw-HTTP adapter (Messages API, `claude-opus-4-8`). Consulted the `claude-api` skill before writing the Anthropic integration (raw HTTP is the correct surface for PowerShell; no `temperature`/`top_p`, which current Opus rejects).
- Added data-driven built-in README/ROADMAP improvement templates in `backend/config/ai-doc-templates.json`.
- Wired `POST /api/ai/docs/improve/preview` into the API host. It resolves current README/ROADMAP content (inline body → roadmap cache → portfolio index), selects an available provider with graceful fallback to the heuristic provider, and returns current/proposed content, change summary, estimated score movement, and warnings — preview-only, no file mutation.
- Added an offline, deterministic AI-preview smoke step (heuristic provider) to `scripts/Invoke-ApiHostSmokeTest.ps1`.
- Promoted Release 1.9 to the active release in `ROADMAP.md`, marked Phase 1 milestones complete, added a phase plan, gave the active-release detail a full execution contract, and archived the completed Release 1.8 detail to `docs/history/completed-releases.md`.

### Verification

- PowerShell parser diagnostics for `backend/modules/ai/AiDocImprovement.ps1`, `backend/api-host/Start-RepoManagementApiHost.ps1`, and `scripts/Invoke-ApiHostSmokeTest.ps1` — clean.
- `npm run build` — passed.
- `pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md` — 0 errors, 2 pre-existing advisory warnings.
- Direct live-host validation of `POST /api/ai/docs/improve/preview`: missing-`repoName` → 400; heuristic README → 200 (score delta + change summary); ROADMAP docType → 200 (auto-selected template). Anthropic adapter additionally verified against the live Messages API.
- Note: the full `Invoke-ApiHostSmokeTest.ps1` run still times out at the pre-existing 30s docs-audit/portfolio warmup cap on this large local inventory (documented in earlier entries); the new AI-preview step passes when reached and was validated directly.
- Observation (surfaced, not acted on beyond cleanup): running the host/smoke during this session caused an IDE markdown/PowerShell formatter and the settings POST to incidentally rewrite `README.md`, `settings.json`, `Start-App.ps1`, `Portfolio.Assessment.ps1`, and `Portfolio.ValueScorer.ps1` (EOL/brace/table-alignment churn). These were unrelated to the task and were restored to HEAD so the change set contains only Phase 1 work.

## 2026-06-09 (Release 1.8: Operations Prompt Dispatch Tracking)

- Reconciled the active roadmap and confirmed the remaining Release 1.8 seam was not a new 1.9 feature but the missing linkage between Operations prompt refinement history and actual dispatch runs.
- Extended `POST /api/roadmap/dispatch/execute` so Operations dispatches can carry an originating prompt-refinement `runId`, and persisted linked dispatch records per repo under `output/roadmap-task-history/prompt-refinements/`.
- Updated `GET /api/operations/prompt/history` to merge those dispatch records back into each refinement entry, exposing dispatch counts, timestamps, and per-run metadata.
- Added direct dispatch to the Operations Prompt Refinement panel and expanded the History tab so operators can see which refined prompt launches actually went to Copilot.
- Updated smoke coverage and docs so the linked-history contract is regression-covered and described in the roadmap/API surfaces.

### Verification

- `npm run build`
- PowerShell parser diagnostics for `backend/api-host/Start-RepoManagementApiHost.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`

## 2026-06-07 (Release 1.8: Prompt Refinement Panel)

- Reconciled the active Release 1.8 prompt-refinement work and carried the feature from foundation-level route wiring to the full operator review workflow.
- Finalized `POST /api/operations/prompt/refine` so prompt generation stays aligned with operator-selected task overrides, emphasis areas, additional constraints, and operator instructions while persisting per-repo refinement history.
- Added `GET /api/operations/prompt/history` for the Operations workspace history tab and wired the frontend to load and display prior prompt refinements by repo.
- Updated the Operations prompt panel to support editable prompt review before copy/dispatch, while preserving the richer task/constraint/emphasis controls from the earlier foundation work.
- Updated API docs and roadmap/progress artifacts so the documented contract matches the merged implementation.

### Verification

- `npm run build`
- PowerShell parser diagnostics for `backend/api-host/Start-RepoManagementApiHost.ps1`

## 2026-06-02 (Release 1.8: Operations Prompt Refinement Foundation)

- Implemented the next unfinished active Release 1.8 slice by adding prompt refinement in the Operations workspace on top of the existing packet flow.
- Added `POST /api/operations/prompt/refine` in `backend/api-host/Start-RepoManagementApiHost.ps1`; the route reuses `Build-CopilotTaskPacket`, applies operator-directed selected-task overrides when possible, appends emphasis/constraints/instructions, and returns warnings plus an applied-input summary.
- Extended frontend contracts and API client (`frontend/types.ts`, `frontend/services/apiClient.ts`) with typed prompt refinement request/response models and route integration.
- Extended `frontend/components/OperationsWorkspaceView.tsx` with a Prompt Refinement panel: selected task fields, emphasis/constraint inputs, operator instruction input, warning display, refined prompt preview, and clipboard copy action.
- Added smoke coverage for `/api/operations/prompt/refine` in `scripts/Invoke-ApiHostSmokeTest.ps1` (missing-body and contract-shape checks).

### Verification

- `npm run build` (frontend) passed.
- `get_errors` checks for edited frontend/backend files returned no diagnostics.
- Full `Invoke-ApiHostSmokeTest.ps1` timed out on the existing 30s request cap during portfolio warmup in this run.
- Targeted route validation passed with longer request timeouts against a live local API host:
  - `/api/operations/prompt/refine` returned HTTP 500 for missing `repoName` (expected validation failure path).
  - `/api/operations/prompt/refine` returned HTTP 200 with `success=true`, `packet`, `refinedPrompt`, `warnings`, and `applied` fields for a valid repo/roadmap request.

## 2026-05-29 (Release 1.8: Operations Audit Findings Panel)

- Reconciled the active roadmap and implemented the next unfinished Release 1.8 UI milestone: audit findings visibility inside the Operations workspace.
- Extended `frontend/components/OperationsWorkspaceView.tsx` to render README findings, ROADMAP audit findings, structure findings, and dispatch blockers for the selected repository.
- Updated `frontend/components/Dashboard.tsx` so docs-audit and roadmap-audit data are loaded when the Operations tab opens and wired through to the Operations workspace component.
- Marked the corresponding Release 1.8 roadmap milestone complete in `ROADMAP.md` and documented the change in `CHANGELOG.md`.
- Verification passed:
  - `npm run build`
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`

## 2026-05-28 (Roadmap Viewer Task-Source Mismatch)

- Investigated a real modal contract bug where the ROADMAP viewer displayed local file content successfully but the Preview Task / Start Task flow still reported "No roadmap markdown file found" for the GitHub repository field.
- Updated `frontend/components/RoadmapViewerModal.tsx` so the loaded local roadmap path is passed through to roadmap-agent preview/start requests.
- Updated `scripts/Start-RoadmapCopilotTask.ps1` so an explicit local `-RoadmapPath` is resolved from disk before any GitHub contents lookup, eliminating the contradictory local-viewer/remote-preview split.
- Extended `scripts/Invoke-ApiHostSmokeTest.ps1` with a regression check for `/api/roadmap-agent/preview` using a local roadmap path.
- Verification passed:
  - PowerShell parser diagnostics for `scripts/Start-RoadmapCopilotTask.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`
  - Direct script validation: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Start-RoadmapCopilotTask.ps1 -Repository 'smoke-owner/smoke-repo' -RoadmapPath "$(pwd)/ROADMAP.md" -PreviewOnly`
  - `npm run build`
  - `git diff --check -- frontend/components/RoadmapViewerModal.tsx scripts/Start-RoadmapCopilotTask.ps1 scripts/Invoke-ApiHostSmokeTest.ps1`
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`

## 2026-05-28 (Release 1.8 Phase 1: Operations Workspace Foundation)

- Reconciled the active roadmap and confirmed Release 1.8 was the next logical slice after Release 1.7.5 closeout.
- Verified the Operations tab, repo workspace component, frontend types, and API client path already existed in the live codebase, so the real missing seam was the backend contract rather than new UI scaffolding.
- Added `GET /api/operations/repos` to `backend/api-host/Start-RepoManagementApiHost.ps1`, serving persisted portfolio-index records with a warm portfolio-assessment-cache fallback and stable `repoId` values for future repo-specific operations routes.
- Updated `scripts/Invoke-ApiHostSmokeTest.ps1` so the host smoke now validates the Operations repo-index contract after warming `/api/portfolio/assessment`.
- Refreshed `frontend/components/HelpModal.tsx`, `frontend/components/ApiDocsModal.tsx`, and `backend/api-host/README.md` so the Operations workspace is described as a first-class part of the app surface and API contract.
- Promoted Release 1.8 to the active release in `ROADMAP.md` and marked the shipped foundation milestones truthfully: Operations tab, repo detail workspace, GitHub panel, and `GET /api/operations/repos`.
- Verification passed:
  - PowerShell parser diagnostics for `backend/api-host/Start-RepoManagementApiHost.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`.
  - `npm run build`
  - `git diff --check -- backend/api-host/Start-RepoManagementApiHost.ps1 scripts/Invoke-ApiHostSmokeTest.ps1 frontend/components/ApiDocsModal.tsx frontend/components/HelpModal.tsx backend/api-host/README.md ROADMAP.md CHANGELOG.md progress.md task_plan.md findings.md`
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`

## 2026-05-28 (Phase 7B)

- Reconciled the active roadmap and confirmed Phase 7B collection report + workflow documentation was the next unfinished milestone after Phase 7A differential scan completion.
- Added `backend/modules/portfolio/Portfolio.Report.ps1` to generate Collection Status Report HTML and CSV artifacts from portfolio assessment entries, including lifecycle counts, blockers, recommended actions, and top-ranked work.
- Extended `/api/export` so the backend accepts `portfolioEntries` for the new collection-report path while preserving the older repo-status export behavior as a compatibility fallback.
- Updated the dashboard export flow to prefer portfolio assessment data for local collection reports and to fall back cleanly when that richer model is unavailable.
- Refreshed Help, API docs, backend host README, and the portfolio assessment reference doc so the scan → classify → rank → refine prompt → dispatch → report workflow is explicit and aligned across product surfaces.
- Updated `scripts/Invoke-ApiHostSmokeTest.ps1` so export smoke coverage now exercises the collection-report payload and verifies the served HTML contains Collection Status Report content.
- Verification passed:
  - PowerShell parser diagnostics for `backend/api-host/Start-RepoManagementApiHost.ps1`, `backend/modules/portfolio/Portfolio.Report.ps1`, and `scripts/Invoke-ApiHostSmokeTest.ps1`.
  - `npm run build`
  - `git diff --check -- backend/modules/portfolio/Portfolio.Report.ps1 backend/api-host/Start-RepoManagementApiHost.ps1 frontend/services/apiClient.ts frontend/components/Dashboard.tsx frontend/components/ActionBar.tsx frontend/components/HelpModal.tsx frontend/components/ApiDocsModal.tsx backend/api-host/README.md docs/reference/portfolio-assessment.md scripts/Invoke-ApiHostSmokeTest.ps1`
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`

## 2026-05-28 (Phase 7A)

- Reconciled the active roadmap and confirmed Phase 7A differential scan completion was the next active milestone after the Phase 6 packet foundation.
- Extended the `/api/portfolio/assessment` route to support `scanMode=differential` repo selection and changed-only reassessment using persisted index fingerprints.
- Added index helper coverage in `Portfolio.Assessment.ps1` for signal-derived fingerprints and conversion from persisted index records back to assessment-shaped entries for unchanged repo merge behavior.
- Updated `scripts/Invoke-ApiHostSmokeTest.ps1` to validate the differential route contract and scan-mode markers.
- Fixed a differential-mode cache bypass defect in `Start-RepoManagementApiHost.ps1` so `scanMode=differential` requests no longer short-circuit through the global memory cache.
- Verification passed:
  - PowerShell parser diagnostics for `backend/api-host/Start-RepoManagementApiHost.ps1`, `backend/modules/portfolio/Portfolio.Assessment.ps1`, and `scripts/Invoke-ApiHostSmokeTest.ps1`.
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"` confirmed `GET /api/portfolio/assessment?scanMode=differential` returns `success=true` with `signalSources.scanMode=differential-fallback-full`.

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
