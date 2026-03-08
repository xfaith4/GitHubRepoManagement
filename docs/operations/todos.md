# TODOs and Source Completion Checklist

This file tracks unresolved details and exactly where to extract missing information from source repos.

## Migration-Phase Checklist (Immediate)

1. Capture and commit baseline outputs from all three source tools.
2. Confirm canonical API route and schema names before module extraction PRs.
3. Implement compatibility adapters and run parity checks for status + reconcile + doc-review outputs.
4. Add structured logging and correlation IDs across all migrated operations.
5. Execute cutover rehearsal and validate rollback procedure.

## README.md TODOs

- TODO: confirm final backend host run/build commands once canonical project structure is committed.
  - Source files to inspect:
    - `G:\Development\20_Staging\GitHubRepoManagerDashboard\backend\package.json` (scripts section)
    - `G:\Development\20_Staging\GitHubRepoManagerDashboard\start-live.bat` (all lines)
    - `G:\Development\20_Staging\GitHubRepoManagerDashboard\start.bat` (all lines)
- TODO: verify final runtime baselines (PowerShell/.NET) from target implementation artifacts.
  - Source files to inspect:
    - `G:\Development\Repo_reconciliation-dashboard\README.md` (Dependencies section)
    - `G:\Development\GitHubRepoManagement\backend\*` (once created)

## docs/architecture/architecture.md TODOs

- TODO: finalize API host route map and contract versioning.
  - Source files to inspect:
    - `G:\Development\20_Staging\GitHubRepoManagerDashboard\backend\server.js:136-416`
    - `G:\Development\20_Staging\GitHubRepoManagerDashboard\services\apiClient.ts` (API call functions)
- TODO: resolve log streaming design (SSE endpoint mismatch).
  - Source files to inspect:
    - `G:\Development\20_Staging\GitHubRepoManagerDashboard\components\LogPanel.tsx:13-14`
    - `G:\Development\20_Staging\GitHubRepoManagerDashboard\hooks\useSse.ts:86-101`
    - `G:\Development\20_Staging\GitHubRepoManagerDashboard\backend\server.js` (verify absent `/api/streams/*` route)
- TODO: define output retention/cleanup policy.
  - Source files to inspect:
    - `G:\Development\Doc_Review_Inventory\output\` (folder growth patterns)
    - `G:\Development\Repo_reconciliation-dashboard\output\` and `logs\` (artifact/log growth)

## docs/planning/migration.md TODOs

- TODO: validate rename strategy against any external automation that depends on current script names.
  - Source files to inspect:
    - `G:\Development\Repo_reconciliation-dashboard\tools\run-test.bat` (all lines)
    - any scheduled-task/export scripts outside repo (operator environment)
- TODO: confirm compatibility alias requirements for existing output filenames.
  - Source files to inspect:
    - `G:\Development\Repo_reconciliation-dashboard\src\repo_reconciliation_dashboard.ps1:930-946`
    - `G:\Development\Doc_Review_Inventory\scripts\Invoke-DocReviewInventory.ps1:503-527`
    - `G:\Development\Doc_Review_Inventory\scripts\Build-DocReviewQueue.ps1:866-889`

## docs/planning/roadmap.md TODOs

- TODO: estimate milestone effort based on real runtime and repo counts.
  - Source files to inspect:
    - `G:\Development\Repo_reconciliation-dashboard\logs\*.log` (duration data)
    - `G:\Development\Doc_Review_Inventory\output\inventory\doc-review-summary.csv` (repo volume)
- TODO: prioritize backlog by actual operator frequency.
  - Source files to inspect:
    - `G:\Development\Repo_reconciliation-dashboard\logs\DIAGNOSTIC_REPORT.md`
    - operator run history/scripts in local environment.

## docs/reference/features.md TODOs

- TODO: confirm final field-level schema for unified `RepoItem` and `ComparisonItem` objects.
  - Source files to inspect:
    - `G:\Development\20_Staging\GitHubRepoManagerDashboard\types.ts` (all interfaces)
    - `G:\Development\Repo_reconciliation-dashboard\src\repo_reconciliation_dashboard.ps1:612-746`
- TODO: verify doc-review queue scoring thresholds before freezing API outputs.
  - Source files to inspect:
    - `G:\Development\Doc_Review_Inventory\scripts\Build-DocReviewQueue.ps1:126-758`

## docs/architecture/adr.md TODOs

- TODO: add implementation ADRs once canonical backend scaffold is created.
  - Source files to inspect:
    - `G:\Development\GitHubRepoManagement\backend\` (future files)
- TODO: add explicit security/auth ADR after PAT handling flow is finalized.
  - Source files to inspect:
    - `G:\Development\20_Staging\GitHubRepoManagerDashboard\backend\server.js:416-823`
    - `G:\Development\20_Staging\GitHubRepoManagerDashboard\components\DataSourceModal.tsx` (token handling UX)

## docs/operations/todos.md TODOs

- TODO: replace placeholder references to future `backend/` files once generated.
- TODO: convert suggested line ranges into exact validated ranges after initial module extraction commits.

## Exact Source Areas Already Used (for validation/refinement)

- `G:\Development\20_Staging\GitHubRepoManagerDashboard\backend\server.js`
  - `136-310` local status scan logic
  - `311-378` update/sync operations
  - `379-415` placeholder export/archive/artifacts routes
  - `416-823` GitHub insights route and helpers
  - `825-980` metrics enrichment mapping
- `G:\Development\Doc_Review_Inventory\scripts\Invoke-DocReviewInventory.ps1`
  - `232-315` priority/doc class logic
  - `316-375` review mode logic
  - `503-527` JSON/CSV output generation
- `G:\Development\Doc_Review_Inventory\scripts\Build-DocReviewQueue.ps1`
  - `126-214` batch typing/order logic
  - `601-758` queue item scoring/shape
  - `866-889` output generation
- `G:\Development\Doc_Review_Inventory\scripts\Invoke-DocReviewBatchPlan.ps1`
  - `105-185` batch assignment logic
  - `186-250` acceptance criteria mapping
  - `329-342` batch manifest output
  - `495` index output location
- `G:\Development\Repo_reconciliation-dashboard\src\repo_reconciliation_dashboard.ps1`
  - `115-154` logging
  - `296-489` local inventory
  - `490-611` GitHub inventory via `gh`
  - `612-689` local-vs-GitHub comparison
  - `690-746` duplicate detection
  - `930-946` report exports

## Missing Information Checklist

- [x] Final backend project scaffold and command surface in consolidation repo.
- [x] Final route and schema versioning policy.
- [x] Final retention policy for logs/artifacts.
- [x] Confirmed external consumers for output filenames.
- [x] Production-ready secret storage policy for PATs.

