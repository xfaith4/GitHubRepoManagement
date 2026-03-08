# Migration Plan

## Migration-Phase Checklist (Immediate)

1. Freeze source baselines and tag each source repo at migration start.
2. Extract shared scan/reconcile/doc-review modules into target backend folders without changing behavior.
3. Introduce unified API contract with adapters that call existing scripts/services.
4. Migrate UI calls incrementally behind feature flags and preserve local-only mode.
5. Validate parity (automated + manual), then perform cutover with rollback artifacts prepared.

## Scope

Included repositories:
- `G:\Development\20_Staging\GitHubRepoManagerDashboard`
- `G:\Development\Doc_Review_Inventory`
- `G:\Development\Repo_reconciliation-dashboard`

Merged:
- local inventory + git status operations,
- reconciliation and duplicate detection,
- documentation review inventory/queue/batch planning,
- reporting/export surface and operator UI.

Deprecated (post-migration):
- standalone, user-facing execution entrypoints spread across all three repos.
- duplicate scanner implementations with inconsistent output contracts.

## Pre-Migration Checklist

- Backup/branching
  - Create migration branch in target repo.
  - Tag source repos with `pre-consolidation-*` tags.
- CI/test baseline
  - Capture current Pester results from reconciliation repo.
  - Capture UI smoke baseline from dashboard repo.
- Artifact baseline
  - Save known-good outputs:
    - `doc-review-manifest.json`
    - `doc-review-queue.json`
    - `repo-reconciliation_<timestamp>.json`
    - dashboard `/api/status` payload sample.

## Source-to-Target Mapping

| Source Repo | Source Path | Target Path | Action |
| --- | --- | --- | --- |
| Dashboard | `backend/server.js` | `backend/api-host/` | Refactor route logic into modular handlers |
| Dashboard | `services/apiClient.ts` | `frontend/services/` | Update to unified contracts |
| Dashboard | `components/*` | `frontend/components/` | Keep, adapt for new domains |
| Doc Review | `scripts/Invoke-DocReviewInventory.ps1` | `backend/modules/docreview/Invoke-DocReviewInventory.ps1` | Keep logic, wrap with API/job runner |
| Doc Review | `scripts/Build-DocReviewQueue.ps1` | `backend/modules/docreview/Build-DocReviewQueue.ps1` | Keep logic, normalize output paths |
| Doc Review | `scripts/Invoke-DocReviewBatchPlan.ps1` | `backend/modules/docreview/Invoke-DocReviewBatchPlan.ps1` | Keep logic, add API wrapper |
| Reconcile | `src/repo_reconciliation_dashboard.ps1` | `backend/modules/reconcile/` | Split into scanner/matcher/reporter modules |
| Reconcile | `tests/*.ps1` | `tests/powershell/reconcile/` | Preserve and extend |
| Reconcile | `docs/PREFLIGHT_GUIDE.md` etc. | `docs/` | Fold operational guidance into unified docs |

### Shared Utility Extraction

Extract common utilities:
- path normalization and ignore filtering,
- git command wrappers and error handling,
- output writer helpers (JSON/CSV/HTML/MD),
- logging + correlation helpers.

## Proposed Renames

- `repo_reconciliation_dashboard.ps1` -> `Invoke-Reconciliation.ps1` (entrypoint)
- `Invoke-DocReviewInventory.ps1` -> `Invoke-DocInventory.ps1` (alias allowed)
- `Build-DocReviewQueue.ps1` -> `Invoke-DocQueuePlan.ps1`
- `Invoke-DocReviewBatchPlan.ps1` -> `Invoke-DocBatchPlan.ps1`

Keep backward-compatible shim scripts during transition.

## Migration Phases

### Phase 0: Baseline Capture

Entry criteria:
- all three source repos readable and executable in current environment.

Tasks:
- run baseline operations and save outputs,
- capture known defects/gaps and operator pain points.

Exit criteria:
- baseline artifact set committed under migration evidence folder.

### Phase 1: Backend Module Consolidation (No UI Contract Change)

Entry criteria:
- baseline complete.

Tasks:
- copy/refactor scripts into target module structure,
- preserve CLI/script entrypoints,
- introduce shared logging + config loader.

Partial usability strategy:
- operators can continue using existing scripts directly.

Exit criteria:
- module entrypoints run from target repo with equivalent outputs.

### Phase 2: Unified API Layer with Adapters

Entry criteria:
- modules consolidated.

Tasks:
- add API routes that proxy to module functions,
- map existing dashboard routes to adapter calls,
- add consistent error envelope and correlation ID.

Partial usability strategy:
- legacy route compatibility maintained.

Exit criteria:
- UI can run against unified API in compatibility mode.

### Phase 3: UI Integration and Workflow Expansion

Entry criteria:
- API compatibility stable.

Tasks:
- add reconciliation and doc-review pages/tabs,
- expose artifact downloads and run history,
- implement consistent empty/error/loading states.

Partial usability strategy:
- feature flags per tab/operation.

Exit criteria:
- operators can execute all core workflows from single UI.

### Phase 4: Hardening, Cutover, and Cleanup

Entry criteria:
- parity test pass and manual sign-off.

Tasks:
- enable strict observability baselines,
- remove deprecated adapters/shims,
- archive standalone entrypoints and update docs.

Exit criteria:
- consolidated repo is canonical operational path.

## Code Integration Strategy

- Branching:
  - `migration/module-extract`
  - `migration/api-unification`
  - `migration/ui-integration`
  - `migration/hardening-cutover`

- PR sequencing:
  - small, reviewable PRs by layer (module -> API -> UI -> docs/tests).

- Temporary shims/adapters:
  - maintain old route names while UI migrates.
  - provide script wrappers calling new module paths.

- Deprecation notices:
  - mark legacy scripts with replacement commands and target removal milestone.

## Compatibility and Data Migration

Behavioral parity requirements:
- status and reconciliation counts remain consistent for same inputs.
- existing JSON top-level reconciliation schema preserved (or versioned with documented transition).
- doc-review manifests and queue outputs remain consumable by existing workflow.

Data migration:
- mostly file/path migration and output root normalization.
- no database migration required currently.

TODO:
- verify whether any existing external automation consumes specific filenames in `output/` and requires alias files.

## Validation and Acceptance

Automated:
- run Pester reconcile suite after module split.
- add contract tests for API response envelopes.
- add regression tests for duplicate classification and doc queue scoring.

Manual sign-off:
- local scan + reconcile + export from UI,
- doc inventory + queue + batch plan via UI/API,
- failure mode checks (missing `gh`, invalid path, GitHub auth failure).

Acceptance checkpoints:
- parity check report approved.
- observability fields present in logs.
- rollback script tested once.

## Cutover Plan

1. Enable consolidated API/UI as primary path for one operator session.
2. Compare outputs with legacy tools for selected roots and owner.
3. Switch scheduled tasks/jobs to consolidated entrypoints.
4. Keep legacy scripts read-only for fallback during stabilization window.
5. Finalize documentation and deprecate legacy flows.

## Rollback Strategy

- Keep source repos and baseline tags unchanged.
- Retain legacy startup scripts and original script entrypoints.
- Provide rollback script to restore prior scheduled tasks and launch paths.
- Trigger rollback if parity failures exceed agreed threshold or critical workflow blocks.

## Post-Cutover Cleanup

- remove compatibility route aliases after sunset window,
- archive duplicate code paths,
- enforce one canonical output root and schema version strategy.

## Decision Log

- Uses ADRs in [ADR.md](../architecture/adr.md): runtime direction, adapter strategy, observability baseline, and phased migration model.

