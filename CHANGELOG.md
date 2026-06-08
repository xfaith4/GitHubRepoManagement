# Changelog

All notable changes to this project are documented here.

## 2026-06-07 — Release 1.8: Prompt Refinement Panel

### Changes

- **`Start-RepoManagementApiHost.ps1`** — added `POST /api/operations/prompt/refine` route that builds a refined dispatch prompt by calling `Build-CopilotTaskPacket` (which gained a new `ForcedItemText` parameter for operator item override) and appending custom operator instructions. Refinement records are persisted per-repo to `output/roadmap-task-history/prompt-refinements/`. Added `GET /api/operations/prompt/history` route to retrieve per-repo refinement history.
- **`OperationsWorkspaceView.tsx`** — added inline Prompt Refinement panel to the Operations workspace repo detail pane. The panel lets the operator add custom instructions, build a refined prompt via `POST /api/operations/prompt/refine`, edit the result in an editable textarea, copy it, and browse refinement history in a History tab.
- **`frontend/types.ts`** — added `OperationsPromptRefineResult`, `OperationsPromptHistoryItem` types; extended `CopilotTaskPacketValueContext.selectedBy` to include `'operator-selected'`.
- **`frontend/services/apiClient.ts`** — added `refineOperationsPrompt()` and `getOperationsPromptHistory()` client functions.
- **`ApiDocsModal.tsx`** — documented `POST /api/operations/prompt/refine` and `GET /api/operations/prompt/history` in the API reference.
- **`ROADMAP.md`** — marked Release 1.8 prompt-refinement milestones complete.

### Testing

- **`npm run build`** — passed.
- **PowerShell parser diagnostics** — `Start-RepoManagementApiHost.ps1` passed with no parse errors.



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
