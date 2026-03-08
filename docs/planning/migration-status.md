# Migration Status

## Completed in this step

- Created backend migration scaffolding:
  - `backend/modules/docreview/`
  - `backend/modules/reconcile/`
  - `backend/modules/common/`
  - `backend/adapters/`
- Copied source doc-review modules into this repo.
- Copied reconciliation script and tests into this repo.
- Added baseline runner:
  - `scripts/Invoke-MigrationBaseline.ps1`
- Added module smoke test runner:
  - `scripts/Invoke-ModuleSmokeTest.ps1`
- Patched copied reconciliation `preflight-check.ps1` to support local module path.
- Added shared structured logging helper:
  - `backend/modules/common/Logging.ps1`
- Added reconciliation module split scaffolding:
  - `backend/modules/reconcile/Reconcile.Scanner.ps1`
  - `backend/modules/reconcile/Reconcile.Matcher.ps1`
  - `backend/modules/reconcile/Reconcile.Reporter.ps1`
  - `backend/modules/reconcile/Invoke-Reconciliation.Modular.ps1`
- Added adapter contract layer:
  - `backend/adapters/Adapter.Common.ps1`
  - `backend/adapters/Status.Adapter.ps1`
  - `backend/adapters/Reconcile.Adapter.ps1`
  - `backend/adapters/DocReview.Adapter.ps1`
  - `backend/adapters/README.md`
- Added minimal local API host and route smoke test:
  - `backend/api-host/Start-RepoManagementApiHost.ps1`
  - `backend/api-host/README.md`
  - `scripts/Invoke-ApiHostSmokeTest.ps1`
- Added adapter smoke runner:
  - `scripts/Invoke-AdapterSmokeTest.ps1`
- Updated doc-review inventory script to support explicit parameters (`OutDir`, `RootPath`, `MaxDepth`).
- Improved baseline runner fallback handling for Stage 1 output path drift.
- Captured baseline evidence under:
  - `evidence/baseline/20260307_213547`
- Executed smoke tests successfully (module smoke + adapter smoke + API host smoke).
- Added in-memory metrics hooks and `/metrics` endpoint.
- Added dependency health route:
  - `GET /health/dependencies`
- Added artifact listing route:
  - `GET /api/report/artifacts`
- Added legacy deprecation route behavior:
  - `POST /api/update` -> `410 Gone`
  - `POST /api/sync` -> `410 Gone`
- Added error categorization support (`validation`, `dependency`, `timeout`, `internal`) in adapter responses.
- Added retry/backoff wrapper for GitHub inventory retrieval in reconciliation flow.
- Added schema validation guard before reconciliation artifact write.
- Added scheduled task template script:
  - `scripts/Register-ScheduledTasks.Template.ps1`
- Added retention cleanup script:
  - `scripts/Invoke-RetentionCleanup.ps1`
- Added regression smoke script:
  - `scripts/Invoke-RegressionSmokeTest.ps1`
- Updated API host smoke test to validate dependencies, artifacts, and metrics endpoints.

## Readiness Summary

- Milestone 1: Completed.
- Milestone 2: Completed.
- Milestone 3: Completed at API contract and operator workflow layer.
- Milestone 4: Completed.
- Milestone 5: Completed.

## Next actions (optional hardening)

1. Run scheduled task template in elevated PowerShell if automatic daily runs are desired:

```powershell
.\scripts\Register-ScheduledTasks.Template.ps1 -WorkspaceRoot 'G:\Development\GitHubRepoManagement' -TaskPrefix 'RepoMgmt'
```

2. Set retention policy cadence (for example weekly) with:

```powershell
.\scripts\Invoke-RetentionCleanup.ps1 -WorkspaceRoot 'G:\Development\GitHubRepoManagement' -RetentionDays 30
```
