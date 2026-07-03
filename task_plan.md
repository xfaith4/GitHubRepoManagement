# Task Plan

## Goal
Close the Release 1.2 execution-throughput dashboard slice truthfully:
turn the existing partial `GET /api/execution/metrics` consumer into a real
operator-facing dashboard card with visible zero-state/error handling,
freshness behavior, and validation strong enough to advance the roadmap
state beyond `planned` only if the evidence supports it.

## Scope

- Dashboard frontend only unless validation exposes a real contract bug:
  replace the hidden one-shot metrics strip in `frontend/components/Dashboard.tsx`
  with a dedicated execution-throughput card/panel that remains visible in
  idle states.
- Refresh behavior: load metrics explicitly, surface loading/failure state,
  and refresh after execution-affecting view changes or operator actions so
  the card does not drift after mount.
- Preserve the existing backend route and typed client contract unless
  validation proves they are insufficient.
- Validation and closeout: `npm run build`, targeted smoke confirmation for
  `GET /api/execution/metrics`, and roadmap/planning updates scoped to this
  slice only.

## Phases

| Phase | Status | Notes |
| --- | --- | --- |
| 1. Reconcile roadmap item against live code | complete | Found partial implementation already present: backend route + client + hidden mount-time metrics strip. |
| 2. Update planning artifacts for the active slice | complete | Repointed the working plan at Release 1.2 execution-throughput card completion. |
| 3. Implement durable dashboard card behavior | complete | Replaced the hidden strip with a persistent execution-throughput panel, refresh loop, manual refresh, and post-dispatch refresh wiring. |
| 4. Validation and roadmap state update | complete | `npm run build` passed after Rollup-native recovery; frontend smoke passed with a new execution-throughput assertion; roadmap item advanced to smoke-tested. |

## Errors Encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| `npm run build` failed because Rollup's native Linux package was missing from the workspace root (`@rollup/rollup-linux-x64-gnu`). | 1 | Installed the exact native package with `npm install --no-save --include=optional @rollup/rollup-linux-x64-gnu@4.60.3`; root-cause appears to be `frontend/scripts/ensure-rollup-native.mjs` checking `frontend/node_modules` while this checkout resolves Rollup from the workspace root. |
| `npm run smoke:frontend` failed immediately under WSL because `Invoke-FrontendSmokeTest.ps1` defaulted `WorkspaceRoot` to `G:\Development\GitHubRepoManagement`. | 1 | Re-ran the script with `-WorkspaceRoot "$(pwd)"`, which let the smoke start and pass against the current checkout. |
