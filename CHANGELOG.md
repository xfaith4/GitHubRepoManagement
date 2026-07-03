# Changelog

All notable changes to this project are documented here.

## 2026-07-03 — Fix: api-host smoke harness runs clean end-to-end

### Changes

- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — three reliability fixes for the carried-forward "harness does not return past the quota-refusal route" defect. Forensics on the previous hung run showed the quota-refusal route itself was innocent (it returned its HTTP 409 and the run had moved on into the merge-readiness checks, which print under the same `[STEP]` banner); the harness was being killed by fragile connects plus hang-amplifying teardown. (1) Default `BaseUrl` is now `http://127.0.0.1:7071` instead of `http://localhost:7071`: the host binds IPv4 loopback only and the local firewall silently drops `[::1]:7071`, so every request paid a ~2 s dual-stack fallback (measured 2,050 ms vs 2 ms) and each connect depended on firewall timing. (2) The host job is launched with `-ShutdownSignalPath`, so its accept loop polls `Pending()` instead of parking forever inside a blocking `AcceptTcpClient()` call and exits cleanly when signaled. (3) Teardown is re-ordered to signal-file → bounded `Wait-Job` → force-kill of any process still listening on the port → `Stop-Job`/`Remove-Job` last — `Stop-Job` against a job blocked in native socket code could hang indefinitely, which is how the harness used to freeze after its last visible step and leave an orphaned host holding port 7071. All existing assertions, including the Release 2.0 quota-refusal checks, are unchanged. Side effect: full-harness host-side run time dropped from ~6.5 minutes to 102 seconds.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — `Send-StaticFile` now recognizes Vite hashes containing `-` (base64url alphabet), scoped to files in an `assets/` directory: the current bundle's `index-BbNsaX-S.js` previously fell back to `no-cache` instead of `public, max-age=31536000, immutable`, deterministically failing the smoke's Release 1.3 assertion late in every full run. Also restored a missing line-continuation backtick after `-BaseBranch $baseBranch` in the dispatch route's `New-AgentRunRecord` call — the orphaned `-WorkUnitsEstimated …` line threw a silent `CommandNotFoundException` on every successful dispatch, dropping work-unit estimate metadata and `agentRunId` capture.

### Testing

- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — ran start-to-finish, printed `[PASS] API host smoke completed`, and exited 0. Quota refusal returned HTTP 409 (`reason=session-cap-exceeded est=8`); `GET /assets/index-BbNsaX-S.js` served `Cache-Control: public, max-age=31536000, immutable`; the host log ends with `Repo Management API host stopped` (graceful signal shutdown) and no listener or job process remained.
- **`npm run build`** — passed.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — 0 errors, 0 warnings.

## 2026-07-03 — Release 2.1 Phase 1: SQLite Persistence Foundation

### Changes

- **`backend/modules/persistence/Persistence.Store.ps1`** (new) — SQLite persistence foundation. `Get-SqliteCapability` detects a provider with zero external dependencies via a compiled native bridge that probes the OS-shipped SQLite library (`winsqlite3.dll` on Windows; `libsqlite3` on WSL/Linux/macOS) and degrades gracefully — no provider means a truthful capability report, never an exception. `Initialize-AppDatabase` bootstraps `output/app.db` (WAL mode, 5s busy timeout) with the schema-v1 tables named in the Release 2.1 milestone: `execution_ledger`, `execution_history`, `maturity_history`, `ops_log`, `portfolio_index_history`, `repo_signals`, `differential_scans`, `merge_readiness_snapshots`, `agent_runs`, `agent_run_events`, plus `schema_migrations`; re-init is idempotent. `Invoke-AppDbQuery` / `Invoke-AppDbNonQuery` expose parameterized-SQL-only helpers (typed round-trip for INTEGER/REAL/TEXT/NULL, UTF-8 safe). `Write-AppDbAgentRunEvent` is the first migration seam.
- **`backend/modules/agent-runs/AgentRuns.ps1`** — `Write-AgentRunEvent` now best-effort mirrors each lifecycle event into the `agent_run_events` table after its authoritative JSONL append (dual-write seam, `INSERT OR IGNORE` on `event_id` for idempotent replays). The mirror only activates when the persistence module is loaded and the database is initialized; failures are non-fatal and reported via a `dbMirrored` flag.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — dot-sources the persistence module, initializes `output/app.db` at startup (non-fatal, logged), and adds `GET /api/persistence/status` reporting capability detection, database state, schema tables, and the mirrored agent-run-event count.
- **`backend/modules/docaudit/DocAudit.Scanner.ps1`** (fix) — the doc-standards `schemaVersion: v1` config (commit `db62f0b`, 2026-06-26) removed `readmeStandards.recommendedSections` in favor of section contracts in `ai-doc-templates.json`, and the scanner's strict property access then threw `The property 'recommendedSections' cannot be found`, breaking every doc audit and the module smoke chain. The scanner now resolves the property StrictMode-safely: old-style configs keep their section checks; v1 configs skip them until audit-time resolution of the canonical template sections is wired up as its own work item.
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — new Release 2.1 Phase 1 sections: capability detection, temp-workspace `app.db` bootstrap with expected-table assertions, idempotent re-init, 25 repeated writes, unicode/quote/NULL parameter-binding round-trip, and the agent-run-event dual-write seam (JSONL authoritative + mirror row present). Also fixed the portfolio-assessment section to accept the `schemaVersion` key that replaced `version` in `repo-structure-standards.json` (same `db62f0b` schema change).
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — new persistence-status step asserting the `GET /api/persistence/status` contract, the full expected table set when a provider is available, and the degraded contract when not.
- **`frontend/components/ApiDocsModal.tsx`** and **`backend/api-host/README.md`** — documented the new Persistence route group and rollout contract (JSON/JSONL stores remain authoritative during Release 2.1).
- **`ROADMAP.md`** — marked the Release 2.1 schema-bootstrap milestone smoke-tested, added the Release 2.1 phase plan (Phases 1-4), and pointed the active-release current focus at Phase 2 (execution ledger + ops log migration).

### Testing

- **PowerShell parser checks** — clean for the persistence module, `AgentRuns.ps1`, the API host, and both smoke scripts.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ModuleSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed end-to-end including all pre-existing sections and the new Release 2.1 Phase 1 steps.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed end-to-end including the new persistence-status step (`provider=winsqlite3.dll`, 11 tables).
- **Targeted scratch-port host check** — `GET /api/persistence/status` returned `success=true`, `capability.available=true`, `database.enabled=true`, and all 11 schema tables; host startup logged `Persistence: app database ready`.
- **`npm run build`** — passed.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — passed.

## 2026-06-27 — Fix: api-host smoke harness quota-refusal route

### Changes

- **`backend/modules/agent-runs/AgentRuns.ps1`** — made `Write-AgentRunEvent -RunId` optional (`[Parameter()][string]$RunId = ''`) instead of mandatory. Pre-dispatch telemetry (`quota.exhausted` / `quota.warning`) is emitted before any run exists, so it passes an empty `RunId`; the mandatory binding rejected the empty string and threw, which turned the quota-refusal route's intended HTTP 409 into a caught HTTP 500. This was the carried-forward defect that stopped `Invoke-ApiHostSmokeTest.ps1` from getting past the Release 2.0 quota-refusal step. Backward compatible — all existing callers pass a real `RunId`.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — added a `-RequestTimeoutSec` parameter (default 180) and used it for every request, so legitimately slow cold-cache routes (e.g. the `/api/portfolio/assessment` full-workspace scan, ~42s) no longer trip a false 30s timeout before later steps run. Hardened teardown to force-stop any process still listening on the host port after `Stop-Job`/`Remove-Job`, guaranteeing a clean exit and preventing a stopped job from leaving the listener holding the port (the "host did not exit after `[PASS]`" symptom). All existing smoke assertions, including the quota-refusal checks, are unchanged.

### Testing

- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — ran start-to-finish, reached the quota-refusal route (`reason=session-cap-exceeded est=8`, HTTP 409), printed `[PASS] API host smoke completed`, and exited 0 with no lingering listener or background job.
- **`npm run build`** — passed.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — 0 errors, 0 warnings.

## 2026-06-26 — Release 2.0 Closeout and Release 2.1 Promotion

### Changes

- **`ROADMAP.md`** — closed Release 2.0, added a completion snapshot, corrected the stale Agent Runs time/token milestone to match the live Operations UI, promoted Release 2.1 to the active release, and set its current focus to Phase 1 SQLite/bootstrap work.
- **`docs/history/completed-releases.md`** — archived the full Release 2.0 detail with completion dates and the settled milestone/phase-plan status.

### Testing

- **`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — passed with 0 errors.
- **`git diff --check -- ROADMAP.md docs/history/completed-releases.md CHANGELOG.md task_plan.md progress.md findings.md`** — passed.

## 2026-06-12 — Release 2.0 Phase 4: Budget Guard + Scan Annotations

### Changes

- **`backend/modules/agent-runs/BudgetLedger.ps1`** (new) — added the Release 2.0 budget-ledger helper module: settings-backed quota configuration with safe defaults, per-repo monthly budget resolution, current-period usage snapshots from the agent-run ledger, and `Test-AgentDispatchQuota` evaluation (credit-prompt stop, per-session cap, per-phase cap, monthly budget exhaustion, soft/hard remaining-unit thresholds).
- **`backend/modules/roadmap/Roadmap.Parser.ps1`** — roadmap parsing now returns structured release contexts, active phase-plan rows, budget-guardrail annotations, and `estimatedSessionWorkUnits`. Fixed a real Phase 4 parser defect where ASCII `-` placeholder cells in the phase-plan table were being misread as completion markers, which incorrectly erased the active phase.
- **`backend/modules/portfolio/Portfolio.Assessment.ps1`** and **`backend/modules/agent-runs/AgentRuns.ps1`** — portfolio assessment rows now carry active-release/phase/budget metadata through to the indexed model, and new agent-run records persist selected task section, planned release/phase, and estimate source instead of always hardcoding the default 3-unit estimate.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — `POST /api/roadmap/dispatch/execute` now resolves roadmap planning context before dispatch, enforces quota checks before any GitHub dependency is required, records `quota.warning` / `quota.exhausted` events, and returns a structured quota payload (`estimatedWorkUnits`, estimate source, remaining budget, planned release/phase). `POST /api/roadmap/scan` and the dispatch packet path now surface the new roadmap annotation fields.
- **`frontend/types.ts`**, **`frontend/components/OperationsWorkspaceView.tsx`**, **`frontend/components/ApiDocsModal.tsx`**, and **`backend/api-host/README.md`** — typed and documented the new roadmap-annotation / quota contracts; the Operations workspace now shows dispatch estimate metadata and richer agent-run planning details (section, phase, release, work-unit estimate, token count).
- **`scripts/Invoke-ModuleSmokeTest.ps1`** and **`scripts/Invoke-ApiHostSmokeTest.ps1`** — module smoke now covers annotated roadmap parsing and budget-ledger quota behavior; api-host smoke now checks roadmap-scan annotation fields and exercises the quota-refusal contract against an isolated temp repo fixture.

### Testing

- **PowerShell parser checks** — passed for `backend/modules/roadmap/Roadmap.Parser.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **`npm run build`** — passed.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ModuleSmokeTest.ps1 -WorkspaceRoot \"$(pwd)\"`** — passed, including the new annotated-roadmap and budget-ledger steps.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — 0 errors, 3 advisory warnings.
- **Targeted host checks on a scratch port** — roadmap-scan fixture returned `activePhasePlan='Phase 2: Quota guard'`, `estimatedSessionWorkUnits=8`, and `budgetGuardrail.maxUnitsPerPhase=10`; `POST /api/roadmap/dispatch/execute` returned HTTP 409 with `error.code=quota-exhausted` and `reasonCode=session-cap-exceeded` before any GitHub dependency was required.
- **Full `Invoke-ApiHostSmokeTest.ps1`** — the run now reaches the new Phase 4 roadmap-scan annotation step and enters the quota-refusal step, but in this session the broad end-to-end harness still did not return past that route; the isolated scratch-port route checks above passed.

## 2026-06-11 — Release 2.0 Phase 1: Agent-Run Ledger Foundation

### Changes

- **`backend/modules/agent-runs/AgentRuns.ps1`** (new) — agent-run ledger and append-only run-event telemetry. Editable current state lives as one JSON per run under `output/agent-runs/runs/`; lifecycle history is the schema-versioned, append-only `output/agent-runs/events.jsonl` stream (`run.dispatched` / `run.started` / `run.completed` / `run.failed` / `run.blocked` / `run.updated`). Run records carry the tier-1 metric fields from `standards/roadmap/ROADMAP_BUDGET_MODEL.md` (dispatch/start/completion timestamps, derived time-to-deliver, prompt count, retries, token usage, API spend, normalized work units) plus optional tier-2 operator observations; derived valuations are never stored. Functions: `New-AgentRunRecord`, `Get-AgentRuns`, `Get-AgentRunDetail`, `Update-AgentRunRecord` (validates status transitions, derives `timeToDeliverSeconds`), `Write-AgentRunEvent`.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — dot-sources the new module; `POST /api/roadmap/dispatch/execute` now records every dispatch in the agent-run ledger (non-fatal on ledger failure) and returns `agentRunId` alongside the existing `runId`; added `GET /api/agent-runs` (status/repoName filters, newest first, per-status rollup) and `GET /api/agent-runs/{runId}` (run + lifecycle events; 404 for unknown runs).
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — new agent-run ledger step against an isolated temp workspace: create → list (with status-filter negative check) → update (status transition, branch/PR association, time-to-deliver derivation) → detail (both lifecycle events present) → unknown-run null → invalid-status rejection; cleans up in `finally`.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — new step asserting the `GET /api/agent-runs` payload shape (`items`/`count`/`byStatus`) and the 404 contract for unknown run IDs.
- **`frontend/components/ApiDocsModal.tsx`** and **`backend/api-host/README.md`** — documented the new Agent Run Monitoring routes and storage model.
- **`ROADMAP.md`** — marked the Phase 1 milestones complete with completion dates, annotated the partially-delivered tier-1-metrics and event-stream milestones with what remains (Phase 2 refresh path), added the Release 2.0 phase plan (Phases 1-4), and updated the active-release current focus and traceability to the shipped surfaces.

### Testing

- **PowerShell parser checks** — passed for the new module, API host, and both smoke scripts.
- **`npm run build`** — passed.
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — full run passed, including the new agent-run ledger step (time-to-deliver derived correctly; both lifecycle events present; invalid status rejected).
- **Live host checks** — `GET /api/agent-runs` empty contract → `count=0`; after creating a run: filtered list returns it with `byStatus.dispatched=1`; `GET /api/agent-runs/{runId}` returns the record (status `dispatched`, `workUnitsEstimated=3`) plus its `run.dispatched` event; unknown runId → HTTP 404. Test ledger data removed afterward.
- **`tools/Test-RoadmapStructure.ps1`** — 0 errors.

## 2026-06-11 — Release 1.9 Phase 3: AI Documentation Improvement — Explicit Apply with Backup & Restore (Release 1.9 closed; Release 2.0 active)

### Changes

- **`backend/modules/ai/AiDocImprovement.ps1`** — added `Invoke-AiDocImproveApply`, the only function in the module that mutates a managed document. It refuses targets whose file name does not match the doc type (README.md / ROADMAP.md), backs up the current file to `output/ai-doc-improvements/backups/<repo>/` with a timestamped name, writes a restore-metadata JSON beside the backup (SHA-256 hashes of original and applied content plus a ready-to-run restore command), writes the operator-approved content, and appends an append-only `recordType=apply` / `applied=true` record to the per-repo improvement-history JSONL.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — added `POST /api/ai/docs/improve/apply`: 400 without `repoName` or `proposedContent`; resolves the target path exactly like the preview route (explicit `path` → roadmap cache → portfolio index) and 404s when unresolvable; apply failures return 400 with the reason.
- **`frontend/components/OperationsWorkspaceView.tsx`** — "Apply Proposed to Repo" action in the AI Documentation Improvement panel with an explicit confirmation dialog, success banner showing target/backup/restore-metadata paths, error surface, viewer-pane refresh after apply, and an "Applied" badge plus apply-record rendering in the History tab.
- **`frontend/types.ts`** and **`frontend/services/apiClient.ts`** — `AiDocImproveApplyRequest` / `AiDocImproveApplyResult` contracts, `applyAiDocImprovement` client, and `recordType` / `backupPath` on history items.
- **`frontend/components/ApiDocsModal.tsx`** and **`backend/api-host/README.md`** — documented the apply route.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — added a Release 1.9 Phase 3 smoke step: missing-`proposedContent` → 400, then a real apply against an isolated temp target asserting the written content, backup content, restore metadata (applyId match + restoreCommand), and the `applied=true` history record; cleans up all artifacts in a `finally` block so the smoke never mutates a real repo document.
- **`ROADMAP.md`** — Release 1.9 closed out and datetime-stamped (Phase 1 2026-06-10; Phases 2-3 2026-06-11); full release detail moved to the archive with per-milestone completion dates; Release 2.0 promoted to active with a full execution contract (current focus: agent-run ledger foundation with tier-1 budget-model metrics).
- **`docs/history/completed-releases.md`** — archived Release 1.9 with completion dates on every milestone and a dated phase plan, per the new roadmap-standard timeline convention.

### Testing

- **PowerShell parser checks** — passed for the AI module, API host, and smoke script.
- **`npm run build`** — passed.
- **`tools/Test-RoadmapStructure.ps1`** — 0 errors.
- **Live host checks** of `POST /api/ai/docs/improve/apply` — missing `proposedContent` → HTTP 400; real apply against a temp README target → HTTP 200 with the proposed content written, backup containing the original content, restore-metadata JSON with matching `applyId`, hashes, and working restore command; history returns the `applied=true` record with `backupPath`; docType/file-name mismatch guard (roadmap docType against a README.md path) → HTTP 400. (The full `Invoke-ApiHostSmokeTest.ps1` run still times out at the pre-existing 30s copilot-task/portfolio warmup cap on this large local inventory — before the AI steps are reached; tracked separately.)

## 2026-06-11 — Release 1.9 Phase 2: AI Documentation Improvement — Diff Viewer & History

### Changes

- **`backend/modules/ai/AiDocImprovement.ps1`** — added per-repo improvement-cycle history: `Write-AiDocImprovementHistory` appends a compact metadata record (provider, template, score movement, change summary — not full document bodies) to `output/ai-doc-improvements/<repo>.improvements.jsonl` on every preview, and `Get-AiDocImprovementHistory` reads it newest-first with an optional `docType` filter. Fixed a same-second ordering bug by sorting on the raw `[datetime]` value instead of a locale string cast.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — the preview route now persists a history record per cycle; added `GET /api/ai/docs/improve/history` (per-repo, `docType` filter, limit) and `GET /api/ai/docs/templates` (serves the data-driven built-in templates to the UI).
- **`frontend/components/OperationsWorkspaceView.tsx`** — new AI Documentation Improvement panel in the Operations repo detail: README/ROADMAP selector, template and provider selects, custom improvement prompt field, side-by-side Current vs Proposed comparison with change summary / score movement / warnings, copy-proposed action, "Run Another Cycle on Proposed" (feeds the proposal back in as the next cycle's input), and a History tab.
- **`frontend/types.ts`** and **`frontend/services/apiClient.ts`** — typed contracts and client functions for AI doc improvement preview, history, and templates.
- **`frontend/components/ApiDocsModal.tsx`** and **`backend/api-host/README.md`** — documented the three AI documentation routes.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — extended the AI smoke step: templates route returns non-empty README/ROADMAP template lists; history route 400s without `repoName` and returns the record written by the preceding preview call (matched by `previewId`).
- **`ROADMAP.md`** — marked the Release 1.9 Phase 2 milestones complete and updated the active-release execution contract; Phase 3 (explicit apply with backup/restore) is the remaining slice.

### Testing

- **PowerShell parser checks** — passed for the AI module, API host, and smoke script.
- **`npm run build`** — passed.
- **`tools/Test-RoadmapStructure.ps1`** — 0 errors (2 pre-existing advisory warnings).
- **Live host checks** — `GET /api/ai/docs/templates` → 4 README + 4 ROADMAP templates; preview → history round trip returns the matching `previewId`; two-cycle flow (proposed content fed back in) works and is idempotent at full section coverage; history missing-`repoName` → 400; `docType` filter excludes non-matching records; same-second ordering regression verified at module level.

## 2026-06-10 — Release 1.9 Phase 1: AI Documentation Improvement — Provider Foundation & Preview

### Changes

- **`backend/modules/ai/AiDocImprovement.ps1`** (new) — provider-agnostic AI documentation-improvement adapter contract plus three adapters: a deterministic offline **heuristic** provider (always available; scaffolds missing template sections and normalizes the title), an **OpenAI** raw-HTTP adapter (Chat Completions), and an **Anthropic** raw-HTTP adapter (Messages API, model `claude-opus-4-8`). `Invoke-AiDocImprovePreview` resolves a template, selects an available provider (explicit → settings → heuristic fallback), computes estimated section-coverage score movement, and returns a preview-only record. No file is written.
- **`backend/config/ai-doc-templates.json`** (new) — data-driven built-in README templates (product, developer/operator, open-source, portfolio) and ROADMAP templates (release-oriented, contract, agent-dispatch-ready, recovery/repair), each with improvement guidance and expected sections.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — dot-sources the new AI module and adds `POST /api/ai/docs/improve/preview`. The route resolves current README/ROADMAP content from an inline body, the roadmap cache, or the portfolio index, then returns current vs proposed content, a change summary, estimated score movement, and warnings. Preview-only — no README/ROADMAP mutation.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — added an AI-preview smoke step (missing-`repoName` 400 path plus a heuristic-provider contract check with inline content) that stays offline, deterministic, and free.
- **`ROADMAP.md`** — promoted Release 1.9 to the active release (Release 1.8 → `done`), marked the Phase 1 milestones complete, added a Release 1.9 phase plan, and gave the active-release detail a full execution contract (validation plan, risks, dependencies, known issues, traceability). Moved the completed Release 1.8 detail to the archive.
- **`docs/history/completed-releases.md`** — archived the full Release 1.8 detail.

### Testing

- **PowerShell parser checks** — passed for `backend/modules/ai/AiDocImprovement.ps1`, `backend/api-host/Start-RepoManagementApiHost.ps1`, and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **`npm run build`** — passed.
- **`tools/Test-RoadmapStructure.ps1`** — 0 errors (2 pre-existing advisory warnings).
- **Live host check** of `POST /api/ai/docs/improve/preview` — missing-`repoName` → HTTP 400; heuristic README → HTTP 200 with full preview contract (score delta, change summary); ROADMAP docType → HTTP 200 with auto-selected template. The Anthropic adapter was additionally exercised against the live Messages API. (The full `Invoke-ApiHostSmokeTest.ps1` run still times out earlier at the pre-existing 30s docs-audit/portfolio warmup cap on this large local inventory; the AI step passes when reached.)

## 2026-06-09 — Release 1.8: Operations Prompt Dispatch Tracking

### Changes

- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — added per-refinement dispatch-record persistence for Operations prompt history, merged those records into `GET /api/operations/prompt/history`, and taught `POST /api/roadmap/dispatch/execute` to accept an optional refinement run ID so Operations dispatches can be linked back to their originating prompt.
- **`frontend/components/OperationsWorkspaceView.tsx`** — added direct dispatch from the Prompt Refinement panel, surfaced dispatch success/error state inline, and expanded the History tab to show linked dispatch runs per refinement entry.
- **`frontend/types.ts`** and **`frontend/services/apiClient.ts`** — extended the Operations prompt history contract with dispatch metadata and allowed dispatch execution requests to carry an originating refinement run ID.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — added a regression check that synthesizes a linked dispatch record for a fresh refinement run and verifies `GET /api/operations/prompt/history` returns the merged dispatch metadata.
- **`frontend/components/ApiDocsModal.tsx`**, **`backend/api-host/README.md`**, and **`ROADMAP.md`** — documented the linked dispatch-history contract and marked the Release 1.8 closeout slice truthfully.

### Testing

- **`npm run build`** — passed.
- **PowerShell parser checks** — passed for `backend/api-host/Start-RepoManagementApiHost.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed, including the new Operations prompt-history dispatch-link regression.

## 2026-06-07 — Release 1.8: Prompt Refinement Panel

### Changes

- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — finalized `POST /api/operations/prompt/refine` around the existing packet flow, including operator-selected task overrides, emphasis areas, additional constraints, operator instructions, and per-repo refinement history persisted under `output/roadmap-task-history/prompt-refinements/`. Added `GET /api/operations/prompt/history` for history retrieval.
- **`frontend/components/OperationsWorkspaceView.tsx`** — extended the inline Prompt Refinement panel with editable selected-task controls, operator refinement inputs, editable refined-prompt review, copy action, and a History tab for prior refinements.
- **`frontend/types.ts`** and **`frontend/services/apiClient.ts`** — unified the prompt refinement request/response contracts, added history-item types, and added client helpers for both refine and history routes.
- **`frontend/components/ApiDocsModal.tsx`** — documented the final `POST /api/operations/prompt/refine` contract and `GET /api/operations/prompt/history`.
- **`ROADMAP.md`** — marked the Release 1.8 prompt-refinement milestones complete with the merged route and UI behavior.

### Testing

- **`npm run build`** — passed.
- **PowerShell parser diagnostics** — `Start-RepoManagementApiHost.ps1` passed with no parse errors.

## 2026-06-02 — Release 1.8: Operations Prompt Refinement Foundation

### Changes

- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — added `POST /api/operations/prompt/refine`, which reuses the existing packet assembly path, applies operator-directed task/constraint/emphasis instructions, and returns a refined prompt with warning metadata.
- **`frontend/types.ts`** and **`frontend/services/apiClient.ts`** — added typed request/response contracts and client integration for Operations prompt refinement.
- **`frontend/components/OperationsWorkspaceView.tsx`** — added an in-panel Prompt Refinement workflow with selected-task overrides, emphasis and constraint inputs, custom operator instruction field, warning display, refined prompt preview, and copy action.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — added route coverage for `/api/operations/prompt/refine` (missing-body validation and success-payload field checks).
- **`frontend/components/ApiDocsModal.tsx`** and **`backend/api-host/README.md`** — documented the new Operations prompt refinement endpoint and contract.
- **`ROADMAP.md`** — marked the corresponding Release 1.8 prompt-refinement milestones as completed (`ui-connected` for panel/preview/operator field, `backend-complete` for refine API route).

### Testing

- **`npm run build`** — passed.
- **Targeted API validation** — `POST /api/operations/prompt/refine` verified with long-timeout requests against a live host: expected missing-repo validation failure path plus successful response contract path.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — this run timed out during portfolio warmup under the script's existing 30-second request cap before reaching final summary.

## 2026-05-29 — Release 1.8: Operations Audit Findings Panel

### Changes

- **`OperationsWorkspaceView.tsx`** — added a new audit findings panel in Operations that shows README findings, ROADMAP findings, structure findings, and dispatch blockers for the selected repo.
- **`Dashboard.tsx`** — Operations view now primes docs-audit and roadmap-audit data on first open and passes those models into the Operations workspace.
- **`ROADMAP.md`** — marked the Release 1.8 audit findings panel milestone complete as `ui-connected`.

### Testing

- **`npm run build`** — passed.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed.

## 2026-05-28 — Roadmap Viewer Task-Source Mismatch Fix

### Changes

- **`RoadmapViewerModal.tsx`** — Preview Task and Start Task now pass the already-loaded local roadmap path to the roadmap-agent flow instead of forcing a second repo-only lookup.
- **`Start-RoadmapCopilotTask.ps1`** — explicit local `-RoadmapPath` values are now resolved from disk before any GitHub contents lookup, removing the contradiction where a local roadmap was visible in the modal but unreachable to task preview.
- **`Invoke-ApiHostSmokeTest.ps1`** — added regression coverage for `/api/roadmap-agent/preview` with a local roadmap path.

### Testing

- **PowerShell parser checks** — passed for `scripts/Start-RoadmapCopilotTask.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **Direct preview validation** — `Start-RoadmapCopilotTask.ps1 -PreviewOnly -RoadmapPath "$(pwd)/ROADMAP.md"` returned a preview payload and resolved the local roadmap path without requiring a GitHub content lookup.
- **`npm run build`** — passed.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed and validated the new local-roadmap preview route behavior.

## 2026-05-28 — Release 1.8 Phase 1: Operations Workspace Foundation

### Changes

- **`Start-RepoManagementApiHost.ps1`** — added `GET /api/operations/repos`, serving repo-specific indexed portfolio records for the Operations tab with a warm portfolio-assessment-cache fallback and stable `repoId` values.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — expanded API host smoke coverage to validate the Operations repo-index contract after warming `/api/portfolio/assessment`.
- **`HelpModal.tsx`**, **`ApiDocsModal.tsx`**, and **`backend/api-host/README.md`** — documented the Operations workspace as a first-class app surface and added the new backend route to the API reference.
- **`ROADMAP.md`** — promoted Release 1.8 to the active release and marked the shipped foundation milestones truthfully: Operations tab, repo detail workspace, GitHub panel, and `GET /api/operations/repos`.

### Testing

- **PowerShell parser checks** — passed for `backend/api-host/Start-RepoManagementApiHost.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **`npm run build`** — verified the frontend compiles with the updated Help and API docs copy.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed and validated `/api/operations/repos` alongside the existing portfolio, report, and static-host routes.
- **`git diff --check`** — passed for the touched Operations foundation files and the roadmap/progress artifact updates.

## 2026-05-28 — Release 1.7.5 Phase 7B: Collection Report and Workflow Documentation

### Phase 7B Changes

- **`Portfolio.Report.ps1`** — added a new portfolio reporting module that generates timestamped HTML and CSV Collection Status Reports from portfolio assessment entries, including lifecycle counts, blockers, recommended actions, and top-ranked work.
- **`Start-RepoManagementApiHost.ps1`** — `/api/export` now accepts `portfolioEntries` and emits the collection-status report path while preserving the older repo-status export path as a compatibility fallback.
- **`Dashboard.tsx`** and **`apiClient.ts`** — the Report action now prefers portfolio assessment data for local collection exports, falling back to legacy repo-status export only when the richer model is unavailable.
- **`HelpModal.tsx`**, **`ApiDocsModal.tsx`**, **`backend/api-host/README.md`**, and **`docs/reference/portfolio-assessment.md`** — updated end-user and reference documentation so the scan → classify → rank → refine prompt → dispatch → report workflow is explicit and the report contract is documented.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — export smoke coverage now exercises the collection-report payload and asserts the saved HTML report serves Collection Status Report content.

### Phase 7B Testing

- **PowerShell parser checks** — passed for `backend/api-host/Start-RepoManagementApiHost.ps1`, `backend/modules/portfolio/Portfolio.Report.ps1`, and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **`npm run build`** — verified the frontend compiles with the updated export flow, Help modal copy, and API docs.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed and validated `/api/export`, `/api/reports/:reportName`, `/api/portfolio/assessment`, and the static frontend bundle against the new collection-report path.

## 2026-05-28 — Release 1.7.5 Phase 7A: Differential Scan Completion

### Phase 7A Changes

- **`Start-RepoManagementApiHost.ps1`** — `/api/portfolio/assessment` now supports `scanMode=differential` and re-assesses only changed repos by comparing current signal fingerprints against the persisted index snapshot.
- **`Start-RepoManagementApiHost.ps1`** — differential mode now merges unchanged repos from the prior index payload and recalculates summary metrics on the combined result.
- **`Start-RepoManagementApiHost.ps1`** — fixed cache behavior so `scanMode=differential` requests bypass the route-level memory cache and surface differential signal metadata (`signalSources.scanMode`, changed/unchanged counters) correctly.
- **`Portfolio.Assessment.ps1`** — added scan fingerprint helpers, persisted fingerprint fields in index payload records, and index-to-assessment conversion helpers used by differential merge logic.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — added differential-route contract checks for `GET /api/portfolio/assessment?scanMode=differential`, including scan mode marker validation.

### Phase 7A Testing

- **PowerShell parser checks** — passed for `backend/api-host/Start-RepoManagementApiHost.ps1`, `backend/modules/portfolio/Portfolio.Assessment.ps1`, and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed and confirmed `GET /api/portfolio/assessment?scanMode=differential` returns `success=true` with `signalSources.scanMode=differential-fallback-full`.

## 2026-05-28 — Release 1.7.5 Phase 6: Prompt Context Packet Foundation

### Changed

- **`Start-RepoManagementApiHost.ps1`** — enriched `/api/copilot-task/preview` packets with README context, selected-release roadmap context, portfolio lifecycle and score context, explicit constraints, and value rationale for the selected task.
- **`Start-RepoManagementApiHost.ps1`** — when portfolio assessment context is available, task preview now prefers the assessment-ranked top-value roadmap item instead of always defaulting to raw roadmap order.
- **`frontend/types.ts`** and **`CopilotTaskPreviewModal.tsx`** — extended the task-packet contract and preview UI so operators can review README summary, release goal/out-of-scope, lifecycle context, value rationale, and constraints before copying the prompt.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — warmed portfolio assessment ahead of task preview and expanded the route contract check for the new prompt-context packet fields.

### Testing

- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed and validated the enriched `/api/copilot-task/preview` contract.
- **`npm run build`** — verified the frontend compiles with the prompt-context packet UI changes.
- **PowerShell parser check** — passed for `backend/api-host/Start-RepoManagementApiHost.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`.

## 2026-05-28 — Release 1.7.5 Phase 5: Expanded Evaluator

### Changed

- **`Roadmap.Evaluator.ps1`** — expanded repo evaluation beyond hardening-only checks so missing-roadmap repos now emit broader opportunity findings across documentation, testing, security, modernization, feature surface, and user-value gaps.
- **`Roadmap.Evaluator.ps1`** — roadmap draft generation now groups findings into staged release suggestions instead of collapsing everything into one foundational hardening release.
- **`RepoEvaluationModal.tsx`**, **`WorkQueueView.tsx`**, **`HelpModal.tsx`**, and **`frontend/types.ts`** — frontend copy and category handling now reflect the broader evaluator contract, including new finding categories and summary chips in the repo-evaluation modal.
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — added direct repo-evaluator smoke coverage that asserts the expanded finding categories and the staged roadmap-draft structure.

### Testing

- **Targeted `Invoke-RepoEvaluation` verification** — passed on a temporary repo and confirmed `documentation`, `testing`, `security`, `modernization`, `feature`, and `user-value` findings plus staged draft-release output.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ModuleSmokeTest.ps1 -WorkspaceRoot \"$(pwd)\"`** — reached and passed the new repo-evaluator smoke step, then later failed in an unrelated pre-existing portfolio-assessment smoke path with `The term 'if' is not recognized...`.
- **`npm run build`** — verified the frontend compiles with the expanded evaluator UI/category changes.

## 2026-05-27 — Release 1.7.5 Phase 4: Work Queue Value Display

### Changed

- **`WorkQueueView.tsx`** — ready repos now surface the highest-value pending roadmap item from `topValueItem`, show a value score card with rationale tooltip, and rerank within readiness buckets by value score before falling back to pending-count and name ordering.
- **`Dashboard.tsx`** — Work Queue now receives the live portfolio assessment model, and docs-audit refresh/scan flows also refresh portfolio assessment data so value ranking does not lag behind refreshed readiness data.
- **`docs/reference/portfolio-assessment.md`** — documented the `pendingItems` and `topValueItem` contract fields and how Work Queue ranking consumes them.

### Testing

- **`npm run install:frontend`** — repaired missing Rollup optional dependencies required by the repo's Vite build on this machine.
- **`npm run build`** — verified the frontend compiles with the new Work Queue value-ranking UI.

## 2026-04-26 — Release 1.7.5 Phase 2: Value-Ranked Work Planning

### Added

- **`Portfolio.ValueScorer.ps1`** — new deterministic portfolio value scorer for pending roadmap items. It scores impact, unblock potential, risk reduction, repo maturity, effort fit, dependency reduction, and recency.
- **`backend/config/value-scoring.json`** — data-driven weights and keyword rules for the value scoring model.
- **`/api/portfolio/assessment`** — assessment entries now include scored `pendingItems` and `topValueItem` fields while preserving existing lifecycle and roadmap fields.
- **Frontend portfolio types** — added `PortfolioPendingItemValue` and `PortfolioValueTier` for the new assessment response fields.

### Testing

- **`scripts/Invoke-ModuleSmokeTest.ps1`** — added value scorer smoke coverage and assertion that ready repo assessment includes scored pending items and selects the highest-value item.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — expanded portfolio assessment contract checks for `pendingItems` and `topValueItem`.

---

## 2026-03-18 — Production Hardening Audit

### Security

- **`NotificationHub.ps1`** — `Register-NotificationWebhook` now validates the webhook URL scheme before registration. Only `http://` and `https://` URLs are accepted; `file://`, `ftp://`, and other schemes throw immediately, preventing SSRF-class abuse.
- **`NotificationHub.ps1`** — `Register-NotificationWebhook` now validates that every supplied event name is in the declared `$script:SupportedEvents` list before writing to disk. Unknown event names throw with a descriptive message.
- **`Start-RepoManagementApiHost.ps1`** — `Read-HttpRequest` now caps `Content-Length` to 10 MB. Requests advertising a body larger than this are rejected (returning `null`) to prevent memory exhaustion from large or malicious payloads.
- **`Start-RepoManagementApiHost.ps1`** — `Get-JsonObjectFromText` now explicitly checks `$end -lt 0` in addition to `$end -le $start`, preventing an out-of-range substring on output that contains `{` but no `}`.

### Reliability

- **`Execution.Ledger.ps1`** — duplicate-task guard in `Invoke-AssignLane` now normalizes task text with `.Trim().ToLowerInvariant()` before comparison, preventing the same task from running in two lanes when its text differs only in case or leading/trailing whitespace.
- **`Execution.Ledger.ps1`** — `Read-ExecutionLedger` now emits a `Write-Warning` before returning the empty fallback when the ledger file cannot be parsed, making corruption visible to operators rather than silently resetting state.
- **`MaturityDrift.Monitor.ps1`** — `Get-MaturityDrift` now uses `[double]::TryParse()` with `InvariantCulture` instead of a bare `[double]` cast when extracting the current score from audit entries. Malformed or non-numeric score values no longer throw; they default to `0`.
- **`NotificationHub.ps1`** — `Send-NotificationEvent` now guards against `null` or non-array `events` properties on webhook objects using an explicit array type check before filtering, preventing a potential null-reference during dispatch.
- **`NotificationHub.ps1`** — The previously silent `catch {}` blocks when persisting webhook registration and metadata updates now emit `Write-Warning` so operators are informed that the in-memory state could not be flushed to disk.

### Performance / Robustness

- **`Roadmap.Linter.ps1`** — `Invoke-LintRoadmapContent` now enforces a 5 000-line and 512 KB budget on roadmap content before running per-line rules. Content that exceeds either limit is silently trimmed to the budget and a new `LINT-SIZE` (warning) finding is added to inform the operator. This prevents runaway processing on pathological or accidentally concatenated roadmap files.
- **`Roadmap.Parser.ps1`** — `Invoke-ParseRoadmapContent` now enforces the same 5 000-line limit before iterating content. Lines beyond the limit are silently ignored, keeping parse time bounded for large inputs.

### Maintenance

- **`backend/config/settings2.json`** — Removed. This file was byte-for-byte identical to `settings.json` and was not referenced by any code or script. It was a source of potential configuration drift.

### Testing

- **`scripts/Invoke-ModuleSmokeTest.ps1`** — Added three new smoke steps that directly exercise the new hardening:
  - _Notification hub URL validation guard_ — verifies that `Register-NotificationWebhook` throws for `file://` URLs.
  - _Notification hub unknown event type guard_ — verifies that `Register-NotificationWebhook` throws for unrecognized event names.
  - _Execution ledger case-insensitive duplicate task guard_ — assigns one repo with task text `"Implement feature X"` then confirms the second repo is rejected when using the same text in a different case (`"Implement Feature X"`).
  - _Roadmap linter oversized content truncation guard_ — lints a 6 000-line roadmap and confirms the `LINT-SIZE` warning finding is present.

---

## 2026-03-16 — Release 1.1: Standardization, Guardrails, and Continuous Improvement

### Added

- **`Roadmap.Linter.ps1`** — new backend module with exported function `Invoke-LintRoadmapContent`. Runs 7 policy checks against raw ROADMAP.md content:
  - LINT-001 (error): Release headings must match `## Release X.Y — Title` format.
  - LINT-002 (error): Checkbox items must use `- [ ]` or `- [x]` format (detects malformed checkboxes).
  - LINT-003 (warning): Product Intent section must be present.
  - LINT-004 (warning): Completed-work section (Recently Completed or similar) must be present.
  - LINT-005 (warning): Each release section must contain at least one checklist item.
  - LINT-006 (info): Vague checklist item text detected (improve, fix, refactor, todo, misc, etc.).
  - LINT-007 (info): Version gaps detected across release headings.
- **`MaturityDrift.Monitor.ps1`** — new backend module with three exported functions:
  - `Set-MaturityBaseline` — stores per-repo target maturity level in `output/maturity-baselines.json`. Upserts existing entries.
  - `Get-MaturityDrift` — compares current audit results against baselines; emits `driftSeverity` (`warning` = 1 level below, `critical` = 2+ levels below) per drifted repo.
  - `Confirm-MaturityDriftAcknowledged` — stamps `lastAcknowledgedAt` on a baseline entry to silence alerts.
- **`DocStandardization.Previewer.ps1`** — new backend module (`backend/modules/docstandardization/`) with:
  - `Invoke-PreviewReadmeStandardization` — analyzes README.md against standard expectations (title, required sections: Installation, Usage, Contributing, License; minimum length). Returns `previewState`: `standardization-preview-ready`, `standardization-blocked`, or `already-standard`, with proposed content and per-action severity list.
  - `Invoke-ApplyReadmeStandardization` — backs up original README, writes proposed content, appends JSONL history entry.
- **`NotificationHub.ps1`** — new common module with:
  - `Register-NotificationWebhook` — registers a webhook URL subscribed to named events (`scan.completed`, `repair.applied`, `execution.failed`, `drift.detected`). Stored in `output/notification-webhooks.json`.
  - `Get-NotificationWebhooks` — returns all registered webhooks.
  - `Remove-NotificationWebhook` — removes a webhook by id.
  - `Send-NotificationEvent` — fires HTTP POST to all webhooks subscribed to the event; failures are caught and reported without crashing callers.
- **`GET /api/roadmap/lint`** — returns lint result for a named repo (requires `repoName` query parameter).
- **`POST /api/roadmap/lint/scan`** — runs lint checks across all repos in the roadmap index; returns per-repo results.
- **`POST /api/readme/standardize/preview`** — builds a full README standardization preview for a named repo.
- **`POST /api/readme/standardize/apply`** — applies an operator-approved README standardization (backs up original, writes proposed content, logs to history).
- **`GET /api/readme/standardize/history`** — returns README standardization history (preview and apply events) with `limit` query parameter.
- **`GET /api/roadmap/drift`** — returns contract drift alerts for all repos with active maturity baselines.
- **`POST /api/roadmap/drift/baseline`** — sets or updates the target maturity level baseline for a named repo.
- **`POST /api/roadmap/drift/acknowledge`** — acknowledges drift for a repo, stamping `lastAcknowledgedAt`.
- **`GET /api/notifications/webhooks`** — lists all registered notification webhooks.
- **`POST /api/notifications/webhooks`** — registers a new notification webhook.
- **`POST /api/notifications/webhooks/remove`** — removes a webhook by id.
- **`POST /api/roadmap/completion-preview`** — after task execution, generates a proposed roadmap update with completed items marked (`- [ ]` → `- [x]`). Returns `previewId`, `currentContent`, `proposedContent`, and `markedCount`.
- **`RoadmapLintModal` component** — per-repo lint findings modal showing pass/fail status, error/warning/info counts, and expandable findings with recommended actions.
- **`ReadmeStandardizationModal` component** — three-tab modal (Standardization Plan / Diff Preview / History) with editable proposed content textarea and explicit two-step apply workflow.
- **Saved operator filters** in `WorkQueueView` — filter presets persisted to `localStorage`; operators can name and save current readiness/maturity/search combinations and load them with one click.
- **"Lint" button in `WorkQueueView`** — appears for repos with a roadmap; opens `RoadmapLintModal`.
- **"Standardize" button in `WorkQueueView`** — opens `ReadmeStandardizationModal` for any repo.
- **`onLintRoadmap` and `onStandardizeReadme` props on `WorkQueueView`** — wired up in `Dashboard.tsx`.
- **`OperationType` extended** with `'roadmap-lint-scan'`, `'readme-standardize-preview'`, `'readme-standardize-apply'`.
- **New frontend types** in `frontend/types.ts`: `RoadmapLintFinding`, `RoadmapLintResult`, `ReadmeStandardizationPreviewState`, `ReadmeStandardizationAction`, `ReadmeStandardizationPreview`, `ReadmeStandardizationHistoryItem`, `MaturityDriftAlert`, `MaturityDriftResult`, `NotificationWebhook`, `RoadmapCompletionPreview`.
- **New API client functions** in `frontend/services/apiClient.ts`: `getRoadmapLint()`, `triggerRoadmapLintScan()`, `previewReadmeStandardization()`, `applyReadmeStandardization()`, `getReadmeStandardizationHistory()`, `getMaturityDrift()`, `setMaturityBaseline()`, `acknowledgeMaturityDrift()`, `getNotificationWebhooks()`, `registerNotificationWebhook()`, `removeNotificationWebhook()`, `previewRoadmapCompletion()`.
- **Module smoke test** — new steps cover loading all four new modules, linting well-formed and malformed roadmaps, setting maturity baselines and detecting drift, previewing README standardization for missing and partial READMEs, and the full notification webhook lifecycle.
- **API smoke test** — new Release 1.1 steps cover `GET /api/roadmap/lint` and `POST /api/roadmap/lint/scan`, `POST /api/readme/standardize/preview` and `GET /api/readme/standardize/history`, `GET /api/roadmap/drift`, `GET/POST /api/notifications/webhooks`, and `POST /api/roadmap/completion-preview`, with contract field validation where applicable.

### Changed

- ROADMAP.md: Release 1.1 milestones marked complete; "Immediate Next Focus" updated to next release.

## 2026-03-16 — Release 0.9: Roadmap Repair Preview & Standardization Workflow

### Added

- **`Roadmap.Repairer.ps1`** — new backend module with two exported functions:
  - `Invoke-PlanRoadmapRepair` — maps a normalized, audited `RoadmapContract` (from `Invoke-AuditRoadmapContract`) to a list of concrete repair actions. Returns a repair plan with `previewState`: `repair-preview-ready`, `repair-blocked`, or `rewrite-not-recommended`. Blocks repair when roadmap is missing or unparseable; recommends against rewrite when roadmap is already complete or at L3/L4.
  - `Invoke-GenerateRepairPreview` — applies the repair plan to generate a proposed normalized roadmap markdown string. Preserves all checked items (`- [x]`), restructures pending work into release-scoped sections with goal statements, acceptance criteria, and out-of-scope boundaries. Returns `previewId`, current content, proposed content, repair action list, and item counts.
- **`POST /api/roadmap/repair/preview`** — builds a full repair preview for a named repository. Reads the roadmap, runs the audit, plans the repair, and generates proposed normalized content. Returns the preview object including `previewState`, `repairActions`, `currentContent`, `proposedContent`, `originalMaturityLevel`, and `auditFindings`.
- **`POST /api/roadmap/repair/apply`** — applies an operator-approved repair preview to the actual roadmap file. Requires `repoName`, `previewId`, and `proposedContent`. Backs up the original file, writes the proposed content, invalidates roadmap and audit caches, and persists the apply event to repair history.
- **`GET /api/roadmap/repair/history`** — returns rewrite history metadata (preview and apply events) for all repos, with `limit` query parameter.
- **Repair history persistence** (`output/roadmap-repair-history/repair-history.jsonl`) — JSONL append-only log of repair events with `previewId`, `repoName`, `roadmapPath`, `previewState`, `originalMaturityLevel`, `event` (`preview` or `apply`), and `timestamp`.
- **Roadmap backup on apply** — original roadmap file is backed up to `output/roadmap-repair-history/backups/` before any write-back.
- **Operations-log traces** for roadmap repair — `[TRACE]` entries for read, plan, preview, write, and apply events; cache invalidation after a successful apply.
- **`RoadmapRepairPreviewState` type** — `'repair-preview-ready' | 'repair-blocked' | 'rewrite-not-recommended'` in `frontend/types.ts`.
- **`RoadmapRepairAction` type** — per-action repair step with `actionId`, `description`, `affectsSection`, and `severity`.
- **`RoadmapRepairPreview` type** — full preview shape with `previewId`, `previewState`, `blockReason`, `repoName`, `roadmapPath`, `originalMaturityLevel`, `originalMaturityScore`, `currentContent`, `proposedContent`, `repairActions`, `auditFindings`, `completedItemCount`, `pendingItemCount`, and `generatedAt`.
- **`RoadmapRepairHistoryItem` type** — history record shape with `previewId`, `repoName`, `roadmapPath`, `previewState`, `originalMaturityLevel`, `event`, `timestamp`, and `appliedAt`.
- **`previewRoadmapRepair()`, `applyRoadmapRepair()`, `getRoadmapRepairHistory()`** in `frontend/services/apiClient.ts`.
- **`RoadmapRepairModal` component** — three-tab modal (Repair Plan / Diff Preview / History) opened from the Work Queue. Shows current maturity badge, repair action list with severity, side-by-side current vs proposed diff preview with syntax highlighting, an editable proposed content textarea, and an explicit two-step apply workflow (Apply button → Confirm Apply). Backs up and logs the apply event.
- **"Repair" button in `WorkQueueView`** — appears for repos at roadmap maturity L0–L2; opens `RoadmapRepairModal`.
- **`onRepairRoadmap` prop on `WorkQueueView`** — wired up in `Dashboard.tsx`.
- **`OperationType` extended** with `'roadmap-repair-preview'` and `'roadmap-repair-apply'`.
- **Module smoke test** (`Invoke-ModuleSmokeTest.ps1`) — new steps cover loading `Roadmap.Repairer.ps1`, planning repair for missing/complete/informal roadmaps, verifying `previewState` assignments, generating a preview with content validation, and confirming that completed items are preserved in proposed output.
- **API smoke test** (`Invoke-ApiHostSmokeTest.ps1`) — new "Roadmap repair routes (Release 0.9)" step covers `POST /api/roadmap/repair/preview` and `GET /api/roadmap/repair/history`, with contract field validation on the preview response.

### Changed

- ROADMAP.md: Release 0.9 milestones marked complete; "Immediate Next Focus" updated to Release 1.0.

## 2026-03-16 — Release 0.8: Roadmap Contract Audit & Maturity Scoring

### Added

- **`Roadmap.Auditor.ps1`** — new backend module with two exported functions:
  - `Invoke-NormalizeRoadmapContract` — maps a parsed roadmap result (from `Invoke-ParseRoadmapContent`) plus raw content and repo metadata into the stable `RoadmapContract` internal model defined by `roadmap-contract.schema.json`. Detects `hasProductIntent`, `hasReleaseSections`, `hasAcceptanceCriteria`, `hasOutOfScope`, and `releaseCount` from raw markdown.
  - `Invoke-AuditRoadmapContract` — applies the weighted rule pack from `roadmap-audit-rules.json` to a normalized contract, computing a 0–100 maturity score, assigning maturity level (L0-Absent through L4-Orchestration-Ready), and emitting per-rule findings with severity, message, recommended action, and score impact.
- **`GET /api/roadmap/audit`** — returns per-repo normalized contract audit results with TTL cache (300 s). Each entry includes `roadmapState`, `maturityLevel`, `maturityScore`, `pendingCount`, `completedCount`, structural flags, and `auditFindings`.
- **`POST /api/roadmap/audit/scan`** — triggers a fresh roadmap contract audit across all configured local roots; reads raw content, parses, normalizes, and scores each repo.
- **Roadmap audit cache** (`roadmap-audit-cache.json`) — TTL-backed memory + disk cache for roadmap contract audit results, following the same pattern as the doc-audit cache.
- **Operations-log traces** for roadmap audit — `[TRACE]` entries for parse, normalize, score, and audit-rule failures; `[WARN]` logged when audit rules file is missing or a per-repo failure occurs.
- **`RoadmapMaturityLevel` type** — `'L0-Absent' | 'L1-Informal' | 'L2-Structured' | 'L3-Contract-Ready' | 'L4-Orchestration-Ready'` in `frontend/types.ts`.
- **`RoadmapMaturityFilter` type** — `RoadmapMaturityLevel | 'all'` for UI filter state.
- **`RoadmapAuditFinding` type** — per-rule finding shape with `ruleId`, `severity`, `message`, `recommendedAction`, and `scoreImpact`.
- **`RoadmapAuditEntry` type** — normalized contract with audit score, matching `roadmap-contract.schema.json`.
- **`RoadmapAuditIndex` type** — response shape for `/api/roadmap/audit` and `/api/roadmap/audit/scan`.
- **`getRoadmapAudit()` and `triggerRoadmapAuditScan()`** in `frontend/services/apiClient.ts`.
- **`RoadmapAuditModal` component** — per-repo contract audit detail panel showing maturity level badge, 0–100 score bar, structural flags checklist, and expandable per-rule findings with recommended actions.
- **Roadmap maturity mini-badge in `WorkQueueView`** — each repo row now shows a compact L0–L4 maturity badge (from roadmap contract audit) alongside the dispatch readiness badge.
- **Maturity-level filter in `WorkQueueView`** — new filter row lets operators narrow the work queue to repos at a specific roadmap maturity level (L0–L4).
- **"Audit" button in `WorkQueueView`** — opens `RoadmapAuditModal` for any repo with audit data.
- **`onViewRoadmapAudit` prop on `WorkQueueView`** — wired up in `Dashboard.tsx`.
- **`roadmapAuditIndex` prop on `WorkQueueView`** — roadmap audit data passed in from Dashboard.
- **`OperationType` extended** with `'roadmap-audit-scan'`.
- **Module smoke test** (`Invoke-ModuleSmokeTest.ps1`) — new steps cover loading `Roadmap.Auditor.ps1`, normalizing missing and pending roadmaps, scoring with the rule pack, verifying score range and maturity level assignment, and validating that a well-formed roadmap has no critical findings.
- **API smoke test** (`Invoke-ApiHostSmokeTest.ps1`) — new "Roadmap audit routes (Release 0.8)" step covers `GET /api/roadmap/audit` and `POST /api/roadmap/audit/scan`, with contract field validation on returned entries.

### Changed

- ROADMAP.md: Release 0.8 milestones marked complete; "Immediate Next Focus" updated to Release 0.9.

## 2026-03-16 — Release 0.6: Copilot Task Packaging & Preview Workflow

### Added

- **`Build-CopilotTaskPacket` function** in the API host — constructs a normalized `CopilotTaskPacket` from local roadmap content, doc audit findings, and parsed neighboring context (previous item, section, follow-up candidates).
- **`POST /api/copilot-task/preview`** — new backend route that builds and returns a full `CopilotTaskPacket` for a named repository. Reads the local roadmap file, parses section order, merges in doc audit findings from the cache, generates acceptance criteria, guardrails, and a structured Copilot-ready prompt. Returns a stable `runId` for tracking.
- **`GET /api/copilot-task/history`** — new backend route returning enriched task history with `repoName`, `roadmapItem`, `startedAt`, `completedAt`, and `status` fields per entry.
- **`CopilotTaskPacket` type** — normalized model in `frontend/types.ts` containing: `repoContext`, `selectedRoadmapItem` (with `previousItem`/`nextItem` neighbors), `followUpCandidates`, `docFindings`, `acceptanceCriteria`, `guardrails`, `generatedPrompt`, stable `runId`, and history paths.
- **`CopilotTaskHistoryItem` type** — enriched history shape with `repoName` and `roadmapItem` fields.
- **`CopilotTaskPacketContext`, `CopilotTaskPacketRoadmapItem`, `CopilotTaskPacketGuardrail` types** in `frontend/types.ts`.
- **`previewCopilotTaskPacket(repoName, roadmapPath?)`** in `frontend/services/apiClient.ts`.
- **`getCopilotTaskHistory(limit?)`** in `frontend/services/apiClient.ts`.
- **`CopilotTaskPreviewModal` component** — three-tab modal (Task Packet / Generated Prompt / History) opened from the Work Queue. Shows repo context, selected roadmap item with neighbors, doc findings, acceptance criteria, guardrails, and the full generated prompt with a copy-to-clipboard button.
- **"Preview Task" button in `WorkQueueView`** — appears for `ready`-state repos; opens `CopilotTaskPreviewModal` for the selected repo.
- **`onPreviewTask` prop on `WorkQueueView`** — wired up in `Dashboard.tsx`.
- **`OperationType` extended** with `copilot-task-preview`.
- **Module smoke test** (`Invoke-ModuleSmokeTest.ps1`) — new step validates section-order neighboring context extraction from the roadmap parser.
- **API smoke test** (`Invoke-ApiHostSmokeTest.ps1`) — new "Copilot task packet routes" step covers `POST /api/copilot-task/preview` (with and without `repoName`) and `GET /api/copilot-task/history`, with packet field validation when the route succeeds.

### Changed

- ROADMAP.md: Release 0.6 milestones marked complete; "Immediate Next Focus" updated to Release 0.7.

## 2026-03-16 — Release 0.5: Documentation Audit & Dispatch Readiness

### Added

- **`backend/config/doc-standards.json`** — machine-readable documentation standards defining required root files (README.md, LICENSE, CONTRIBUTING.md, CHANGELOG.md), README minimum length (300 chars), and recommended README sections (Installation, Usage, Contributing).
- **`backend/modules/docaudit/DocAudit.Scanner.ps1`** — new module with `Invoke-AuditRepoDocumentation` and `Invoke-AuditRepoScan` functions. Scans repos against doc standards, checks README quality, and computes a `DispatchReadiness` state per repo.
- **`DispatchReadiness` type** — six states: `ready`, `needs-doc-standardization`, `missing-roadmap`, `roadmap-complete`, `parse-error`, `blocked`.
- **`GET /api/docs-audit`** — returns per-repo dispatch readiness audit results with TTL cache (300 s).
- **`POST /api/docs-audit/scan`** — triggers a fresh documentation audit scan across all configured local roots.
- **`WorkQueueView` component** — new "Work Queue" primary tab in the dashboard. Shows all repos ranked by readiness priority, with readiness badges, per-finding severity labels (`critical`/`warning`/`info`), expandable findings panels with recommended actions, and filter buttons for each readiness state.
- **Dispatch readiness badge in Repository Grid** — each repo row now displays a `DispatchReadiness` badge when docs-audit data is available.
- **Readiness filter in Repository Grid** — new "Readiness" dropdown filters the grid by dispatch readiness state.
- **`DocAuditEntry`, `DocAuditIndex`, `DocFinding` types** in `frontend/types.ts`.
- **`getDocsAudit()` and `triggerDocsAuditScan()`** in `frontend/services/apiClient.ts`.
- **CI: doc-standards.json integrity check** — new CI step validates `doc-standards.json` structure on every PR/push.
- **Smoke tests for doc audit scanner** — `Invoke-ModuleSmokeTest.ps1` covers `ready`, `blocked`, `needs-doc-standardization`, `missing-roadmap` classifications.
- **API smoke tests for docs-audit routes** — `Invoke-ApiHostSmokeTest.ps1` covers `GET /api/docs-audit` and `POST /api/docs-audit/scan`.

### Changed

- Dashboard adds a **tab bar** (`Repository Grid` | `Work Queue`) at the top of the main panel; Work Queue tab shows a badge with the count of ready-for-dispatch repos.
- `reposWithRoadmap` enrichment in `Dashboard.tsx` now also merges `dispatchReadiness` from the docs-audit index into each repo record.
- `OperationType` extended with `docs-audit-scan`.
- ROADMAP.md: Release 0.5 milestones marked complete; "Immediate Next Focus" updated to Release 0.6.

## 2026-03-07

- Reorganized docs into architecture/planning/reference/operations/archive.
- Added `.github` governance scaffolding (templates, CODEOWNERS, CI).
- Added repository policy files (`CONTRIBUTING`, `SECURITY`, `SUPPORT`, `CODE_OF_CONDUCT`).
