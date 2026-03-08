# Consolidated Features

Indexed by domain: Inventory, Docs Review, Reconciliation, UI/Operations.

## Inventory Domain

## Feature: Local Repository Discovery and Git Status

Description and user value:
- Discovers repositories under configured roots and surfaces branch/status/freshness for quick operational triage.

Inputs/outputs and data sources:
- Inputs: local root paths, max depth, ignore rules.
- Data sources: filesystem + `git` CLI.
- Outputs: `RepoItem` list with branch, dirty counts, ahead/behind, commit metadata.

Commands/scripts/services involved:
- Current: `backend/server.js` `/api/status`, `repo_reconciliation_dashboard.ps1` local inventory routines.
- Target: `inventory-service.scan` endpoint + reusable module.

Configuration knobs and defaults:
- `LocalRoots`, `scanDepth`, `IgnoreDirNames`, `IgnorePathRegex`, stale threshold.

Error cases and expected handling:
- inaccessible path: continue scan, log warning with path.
- git command failure: mark repo item with partial metadata and continue.

Metrics/logging emitted:
- `repo_scan_runs_total`, `repo_scan_duration_ms`, `repo_items_discovered`.
- structured log operations: `status.scan`, `inventory.walk`.

Known limitations and TODOs:
- local scan logic currently duplicated across two repos.
- TODO: unify scanner depth/ignore semantics to one module.

## Feature: Repo Actions (Pull/Fetch)

Description and user value:
- Executes batch repo sync operations from UI (selected or all repos).

Inputs/outputs and data sources:
- Inputs: repo name list, operation type.
- Outputs: per-repo success/failure results with stderr/stdout snippets.

Commands/scripts/services involved:
- Current: `/api/update` -> `git pull`, `/api/sync` -> `git fetch --all --prune`.

Configuration knobs and defaults:
- selected repositories (optional), workspace path.

Error cases and expected handling:
- one repo fails: operation continues for remaining repos.
- network/remote failures: classify dependency error, no silent drop.

Metrics/logging emitted:
- `operation_failures_total{operation="pull|fetch"}`
- per-repo operation logs with correlation ID.

Known limitations and TODOs:
- no server-side real-time progress stream currently implemented.
- TODO: add SSE/WebSocket or polling-based progress contract.

## Docs Review Domain

## Feature: Stage 1 Documentation Inventory

Description and user value:
- Builds repo-level markdown manifest with quality hints and priority scoring.

Inputs/outputs and data sources:
- Inputs: `RootPath`, `OutDir`, `MaxDepth`.
- Outputs: `doc-review-manifest.json`, `doc-review-summary.csv`, `doc-review-report.md`.

Commands/scripts/services involved:
- `scripts/Invoke-DocReviewInventory.ps1`.

Configuration knobs and defaults:
- root scan path, markdown depth, exclusion behavior.

Error cases and expected handling:
- missing root path: hard fail.
- per-file scan issues: skip file and continue scan where safe.

Metrics/logging emitted:
- `doc_inventory_runs_total`, `doc_inventory_repo_count` (gauge), phase timing histograms.

Known limitations and TODOs:
- script-level console logging only.
- TODO: emit structured run metadata JSON for each stage execution.

## Feature: Stage 2a Queue Planning

Description and user value:
- Produces prioritized cross-repo review queue and AI prompt packets.

Inputs/outputs and data sources:
- Inputs: Stage1 manifest, overrides, batch sizing.
- Outputs: `doc-review-queue.json`, `doc-review-queue.csv`, `doc-review-playbook.md`, packet markdown files.

Commands/scripts/services involved:
- `scripts/Build-DocReviewQueue.ps1`.

Configuration knobs and defaults:
- `MaxFilesPerBatch`, `IncludeLowPriority`, `RepoOverridesPath`.

Error cases and expected handling:
- missing/invalid manifest: hard fail with path details.
- malformed overrides: warn and continue without override entries.

Metrics/logging emitted:
- `doc_queue_items_total`, `doc_queue_generation_duration_ms`.

Known limitations and TODOs:
- packet volume can grow large in broad staging roots.
- TODO: add queue filters and retention cleanup workflow.

## Feature: Stage 2b Batch Plan for Single Repo

Description and user value:
- Generates actionable review batches with prompts/checklists and execution index.

Inputs/outputs and data sources:
- Inputs: manifest, target repo name, optional batch rules.
- Outputs: `index.md`, `batch-manifest.json`, `batch-*-(prompt|checklist).md`.

Commands/scripts/services involved:
- `scripts/Invoke-DocReviewBatchPlan.ps1`.

Configuration knobs and defaults:
- `TargetRepo`, `BatchRulesPath`, `RepoOverridesPath`.

Error cases and expected handling:
- target repo not found in manifest: hard fail with available repo list.
- no batchable files: explicit failure reason.

Metrics/logging emitted:
- `doc_batch_count_total`, `doc_batch_plan_duration_ms`.

Known limitations and TODOs:
- execution status lifecycle remains mostly manual in generated index.
- TODO: persist batch execution status via API/state file.

## Feature: Stage 3a Queue Prompt Automation

Description and user value:
- Converts queue packets into deterministic Copilot workitems so operators can execute prompts in paged batches rather than manual copy/paste.

Inputs/outputs and data sources:
- Inputs: `doc-review-queue.json`, `doc-review-state.json`, queue page controls.
- Outputs: `workitems/<QueueId>/workitem.md`, `workitem.json`, `prompt.txt`, and `copilot-workitems.json` manifest.

Commands/scripts/services involved:
- `backend/modules/docreview/Invoke-DocReviewExecution.ps1 -Mode PreparePrompts`.
- `backend/modules/docreview/DocReview.Execution.psm1` (`Publish-DocReviewCopilotWorkItems`).

Configuration knobs and defaults:
- `PageSize` default `25`, `PageNumber` default `1`, `WorkItemRoot` default sibling `output/.../workitems`.

Error cases and expected handling:
- missing packet file: item is skipped for prompt preparation and remains in current state.
- invalid paging params: hard fail with explicit argument error.

Metrics/logging emitted:
- run manifest includes total eligible items, selected page size, and next-page indicator for throttled execution.

Known limitations and TODOs:
- automated prompt execution engine is still operator-driven after workitem generation.
- TODO: wire prompt execution responses back into `Validate`/`Complete` lifecycle states.

## Reconciliation Domain

## Feature: Local vs GitHub Reconciliation

Description and user value:
- compares local inventory to GitHub owner inventory and classifies matches and gaps.

Inputs/outputs and data sources:
- Inputs: local roots, owner, owner type, ignore rules.
- Data sources: filesystem/git + `gh` CLI (or future GitHub API adapter).
- Outputs: comparison list and aggregate counts.

Commands/scripts/services involved:
- `src/repo_reconciliation_dashboard.ps1` (`Compare-LocalAndGitHub`, `Get-GitHubRepoInventory`).

Configuration knobs and defaults:
- `-GitHubOwner`, `-OwnerType`, `-IncludeNonGitFolders`, `-MaxDepth`.

Error cases and expected handling:
- missing `gh`: fail dependency path with clear message, allow local-only mode.
- GitHub query failure: continue with local-only reconciliation when possible.

Metrics/logging emitted:
- `reconcile_runs_total`, `reconcile_mismatch_items`, `operation_failures_total{operation="reconcile"}`.

Known limitations and TODOs:
- GitHub adapter currently CLI-dependent in reconciliation script.
- TODO: implement adapter interface for `gh` and direct API fallback.

## Feature: Duplicate Candidate Detection

Description and user value:
- identifies potential duplicate local repos with confidence class.

Inputs/outputs and data sources:
- Inputs: local items with fingerprints.
- Outputs: duplicate candidate list (`SameOrigin`, `SameName`, `Structural` + confidence/score).

Commands/scripts/services involved:
- `Get-SimilarityScore`, `Get-PotentialLocalDuplicates` in reconciliation script.

Configuration knobs and defaults:
- similarity threshold and scoring weights (script constants).

Error cases and expected handling:
- pairwise comparison errors: log pair context and continue.

Metrics/logging emitted:
- `duplicate_candidates_total`, duplicate confidence breakdown gauges.

Known limitations and TODOs:
- O(n^2) pair comparison for large inventories.
- TODO: evaluate indexing or bucketing pre-pass for scale.

## Feature: Reconciliation Report Export

Description and user value:
- creates machine-readable + human-readable reconciliation artifacts.

Inputs/outputs and data sources:
- Inputs: local items, GitHub items, comparison, duplicates.
- Outputs: timestamped JSON, CSV, duplicate CSV, HTML report.

Commands/scripts/services involved:
- export block in reconciliation script and HTML generator.

Configuration knobs and defaults:
- `OutDir`, `OpenHtmlReport`, `LogPath`.

Error cases and expected handling:
- individual export format failure should not block other formats.

Metrics/logging emitted:
- `report_exports_total{format="json|csv|html|md"}`.

Known limitations and TODOs:
- output folder conventions differ across repos.
- TODO: standardize output root + schema version marker.

## UI Domain

## Feature: Dashboard Summary and Repo Grid

Description and user value:
- presents repository health with filtering/grouping, selection, and link-outs.

Inputs/outputs and data sources:
- Inputs: API status payloads (local or GitHub mode).
- Outputs: interactive grid and summary cards.

Commands/scripts/services involved:
- `App.tsx`, `Dashboard.tsx`, `RepoGrid.tsx`.

Configuration knobs and defaults:
- view mode, group-by option, filter text, selected repo set.

Error cases and expected handling:
- API failures produce top-level error state and retryable refresh path.

Metrics/logging emitted:
- frontend action events (planned), API request timing via backend metrics.

Known limitations and TODOs:
- log panel expects SSE stream not currently backed by API.
- TODO: implement operation stream endpoint or replace with polling job logs.

## Feature: GitHub Insights View

Description and user value:
- fetches extended repo metrics (issues, branches, projects, health score) for prioritized visibility.

Inputs/outputs and data sources:
- Inputs: GitHub username + PAT + options (private/forks/limit/extended).
- Outputs: enriched repo dataset + rate-limit metadata.

Commands/scripts/services involved:
- `/api/github/status`, Octokit calls in `backend/server.js`.

Configuration knobs and defaults:
- include private/forks/archived, repo limit, extended metrics toggle.

Error cases and expected handling:
- auth/scope/rate errors mapped to actionable API messages.

Metrics/logging emitted:
- `github_api_calls_total`, `github_api_failures_total`, rate-limit gauges.

Known limitations and TODOs:
- potential rate pressure when extended metrics enabled for many repos.
- TODO: add bounded concurrency and adaptive throttling.

## Behavioral Reconciliation Notes

Behavior differences to harmonize:
- Dashboard currently mixes mock/live behavior; target should make mode explicit and testable.
- Reconciliation uses `gh`; dashboard uses Octokit. Target supports both via one adapter contract.
- Doc review writes to stage-specific folders; target keeps structure but standardizes root and naming.

Planned behavior changes:
- consistent structured logs across all domains,
- unified health/error semantics,
- unified output schema versioning for downstream consumers.
