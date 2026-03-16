# Changelog

All notable changes to this project are documented here.

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
