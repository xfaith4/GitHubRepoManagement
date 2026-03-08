# Unified Roadmap

Readiness assessment date: 2026-03-07

## Consolidated Feature Program

This roadmap tracks the merged target for:

- inventory and local git operations,
- reconciliation and duplicate detection,
- documentation review planning,
- unified operator UX and observability.

Cross-reference:

- [Architecture](../architecture/architecture.md)
- [Migration Plan](migration.md)
- [Features](../reference/features.md)
- [Contracts](../reference/contracts.md)
- [Migration Status](migration-status.md)

## Milestone Plan

## Milestone 1: Platform Baseline (Must)

- [x] Extract and modularize shared scanner/git metadata utilities.
- [x] Preserve reconciliation JSON/CSV/HTML export behavior in new module layout.
- [x] Preserve doc inventory/queue/batch script behavior in new module layout.
- [x] Define canonical API contract for status/reconcile/doc-review/report endpoints.

Dependencies:

- none (foundation).

## Milestone 2: Unified API and Compatibility Layer (Must)

- [x] Implement unified API host with route handlers per domain.
- [x] Add compatibility adapters for existing dashboard endpoints.
- [x] Standardize error envelope and correlation ID propagation.
- [x] Implement log + metric emission hooks across all operations.

Dependencies:

- Milestone 1.

## Milestone 3: UI Consolidation (Must)

- [x] Integrate Reconciliation and Doc Review domains into dashboard navigation contracts.
- [x] Add run history/artifact panel and domain-level health state indicators via `/api/report/artifacts` and health routes.
- [x] Normalize table patterns (filters, grouping, pagination strategy) at API contract level.
- [x] Align empty/error/loading states and operator guidance text through unified response envelopes.

Dependencies:

- Milestone 2.

## Milestone 4: Reliability and Observability Hardening (Should)

- [x] Add health endpoints and dependency health checks.
- [x] Add metrics endpoint and dashboards for run trends/failures.
- [x] Add retry/backoff policy wrappers for remote calls.
- [x] Add schema validation before artifact write.

Dependencies:

- Milestone 2.

## Milestone 5: Operationalization (Should)

- [x] Add scheduled task templates for periodic scans and report generation.
- [x] Add retention policies for logs and output artifacts.
- [x] Finalize cutover and deprecation notices for legacy entrypoints.

Dependencies:

- Milestones 3 and 4.

## Prioritized Backlog (MoSCoW)

### Must

- [x] Canonical data contracts for `RepoItem`, `ComparisonItem`, `DocManifestRepo`, `QueueItem`, `BatchPlanItem`.
- [x] Unified config model and secret handling policy.
- [x] Regression coverage for duplicate detection and doc queue scoring.
- [x] UI support for local-only degraded operation when GitHub dependency is unavailable.

### Should

- Dual GitHub adapter abstraction (`gh` and API) with fallback logic.
- Incremental scan mode to reduce full-traversal cost.
- Artifact browser enhancements (direct links, retention metadata, size summaries).

### Could

- Operator-defined saved views and filters.
- Comparative run analytics (diff between two reconciliation runs).
- Optional notification hooks for failed scheduled runs.

## Technical Debt and Refactor Candidates

- [x] Split monolithic reconciliation script into domain modules.
- [x] Remove dashboard backend placeholder endpoints by completing or eliminating them.
- [x] Eliminate duplicate scan logic between dashboard and reconciliation code paths.
- [x] Replace ad-hoc console logging with shared structured logger.
- [x] Normalize output path conventions across all domains.

## Observability and Reliability Tasks

- [x] Implement required structured log fields on every operation.
- [x] Emit metric counters/histograms/gauges described in architecture.
- [x] Add liveness/readiness/dependency health checks.
- [x] Introduce error categorization (`validation`, `dependency`, `timeout`, `internal`).
- [x] Add post-retry validation checks and partial-result annotations.

## Completion Criteria

- [x] One dashboard and one API endpoint set for all core workflows.
- [x] Script parity retained for key outputs during transition.
- [x] Observability baseline enforced by tests/checks.
- [x] Legacy standalone paths deprecated with documented replacement commands.

## Evidence

- API host smoke test: `scripts/Invoke-ApiHostSmokeTest.ps1` (health, dependencies, status, reconcile, docreview, artifacts, metrics).
- Adapter smoke test: `scripts/Invoke-AdapterSmokeTest.ps1`.
- Module smoke test: `scripts/Invoke-ModuleSmokeTest.ps1`.
- New operational scripts:
  - `scripts/Register-ScheduledTasks.Template.ps1`
  - `scripts/Invoke-RetentionCleanup.ps1`
