# Changelog

All notable changes to this project are documented here.

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
