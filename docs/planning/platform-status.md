# Platform Status

Updated: 2026-03-08

## Operational Status

- Core modules are operational:
  - `backend/modules/reconcile/*`
  - `backend/modules/docreview/*`
  - `backend/modules/common/*`
- Unified API host is operational:
  - `backend/api-host/Start-RepoManagementApiHost.ps1`
- Adapter layer is operational:
  - `backend/adapters/*`
- Configuration model is active:
  - `backend/config/settings.json`

## Available Validation

- `.\scripts\Invoke-ModuleSmokeTest.ps1`
- `.\scripts\Invoke-AdapterSmokeTest.ps1`
- `.\scripts\Invoke-ApiHostSmokeTest.ps1`
- `.\scripts\Invoke-RegressionSmokeTest.ps1`

## Reliability and Operations Baseline

- Health endpoints:
  - `GET /health/live`
  - `GET /health/ready`
  - `GET /health/dependencies`
- Metrics endpoint:
  - `GET /metrics`
- Artifact index endpoint:
  - `GET /api/report/artifacts`
- Retention and scheduling scripts:
  - `.\scripts\Invoke-RetentionCleanup.ps1`
  - `.\scripts\Register-ScheduledTasks.Template.ps1`

## Known Current Constraints

- If `gh` is unavailable, dependency health reports degraded and reconcile runs in local-only mode.
- API host is intentionally minimal and PowerShell-native.
- Full UI host integration remains optional and out-of-scope for core backend operation.

## Recommended Operational Cadence

1. Run smoke suite after changes to adapters, API host, or module contracts.
2. Execute retention cleanup on a schedule (for example weekly).
3. Review roadmap quarterly and promote completed priorities into baseline docs.
