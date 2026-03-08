# Adapter Contracts

PowerShell adapter layer providing stable operation envelopes for future API host routes.

## Shared Response Envelope

All adapters return:

```json
{
  "operation": "string",
  "correlationId": "string",
  "success": true,
  "timestamp": "ISO-8601",
  "data": {},
  "error": null,
  "meta": {}
}
```

## Status Adapter

- File: `backend/adapters/Status.Adapter.ps1`
- Function: `Get-StatusAdapterResult`
- Purpose: local status scan for git repositories.

Inputs:
- `LocalRoots`, `MaxDepth`, `IncludeNonGitFolders`.

Output data fields:
- `repos[]` with `name`, `path`, `branch`, `lastCommitDate`, dirty counts, and `status`.

## Reconcile Adapter

- File: `backend/adapters/Reconcile.Adapter.ps1`
- Function: `Invoke-ReconcileAdapter`
- Purpose: run modular reconciliation and export artifacts.

Inputs:
- `LocalRoots`, `GitHubOwner`, `OwnerType`, `OutDir`, `MaxDepth`.

Output data fields:
- run summary counts and artifact file paths (`JsonPath`, `CsvPath`, `DuplicatesCsvPath`).

## DocReview Adapter

- File: `backend/adapters/DocReview.Adapter.ps1`
- Function: `Invoke-DocReviewAdapter`
- Purpose: run inventory, optional queue, optional per-repo batch planning.

Inputs:
- `RootPath`, `MaxDepth`, `OutDir`, `GenerateQueue`, `GenerateBatchPlan`, `TargetRepo`.

Output data fields:
- inventory artifact paths, queue path, optional workitems root.

## Next Step

Map these adapter functions to HTTP routes in planned API host:
- `GET /api/status`
- `POST /api/reconcile`
- `POST /api/docreview/run`
