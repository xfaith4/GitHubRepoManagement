# Backend Modules

## Current State

- `modules/docreview/`
  - `Invoke-DocReviewInventory.ps1`
  - `Build-DocReviewQueue.ps1`
  - `Invoke-DocReviewBatchPlan.ps1`
  - `repo-overrides.json`
- `modules/reconcile/`
  - `Invoke-Reconciliation.ps1` (copied from `repo_reconciliation_dashboard.ps1`)
  - `Invoke-Reconciliation.Modular.ps1`
  - `Reconcile.Scanner.ps1`
  - `Reconcile.Matcher.ps1`
  - `Reconcile.Reporter.ps1`
  - `repo_reconciliation.Tests.ps1`
  - `preflight-check.ps1`
- `modules/common/`
  - `Logging.ps1`
  - `Metrics.ps1`
  - `Retry.ps1`
  - `Validation.ps1`
- `adapters/`
  - `Status.Adapter.ps1`
  - `Reconcile.Adapter.ps1`
  - `DocReview.Adapter.ps1`
  - `Adapter.Common.ps1`
- `api-host/`
  - `Start-RepoManagementApiHost.ps1`

## Execution

Use root scripts:

```powershell
# Capture baseline artifacts for parity checks
.\scripts\Invoke-MigrationBaseline.ps1 -GitHubOwner '<owner>'

# Validate copied modules and run preflight checks
.\scripts\Invoke-ModuleSmokeTest.ps1
```

## Next Refactor Steps

1. Add direct GitHub API adapter fallback alongside `gh`.
2. Expand API contract tests for error categories and deprecation routes.
3. Add trend workbook/dashboard outputs over metrics snapshots.
