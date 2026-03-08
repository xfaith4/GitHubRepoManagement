# Product Roadmap

Updated: 2026-03-08

This roadmap tracks forward work for the current standalone GitHub Repo Management platform.

Cross-reference:

- [Architecture](../architecture/architecture.md)
- [Platform Status](platform-status.md)
- [Features](../reference/features.md)
- [Contracts](../reference/contracts.md)

## Current Baseline

- Unified API host and adapter layer is operational.
- Reconciliation, duplicate detection, and doc-review pipelines are operational.
- Structured logging, metrics, health/dependency checks, and retention tooling are in place.
- Canonical governance and repository structure are established.

## Near-Term Priorities (Must)

- Add dual GitHub inventory adapter support (`gh` + direct API fallback).
- Add incremental scan mode for large root paths.
- Add stricter API contract tests for all routes and error categories.
- Add CI checks for link validation and documentation integrity.
- Automate queue-to-workitem Copilot prompt preparation with paged dispatch outputs.

## Mid-Term Priorities (Should)

- Expand artifact browser metadata (retention, size, run correlation).
- Add comparative reconciliation run analytics.
- Add notification hooks for scheduled-run failures.

## Long-Term Priorities (Could)

- Saved operator filters/views.
- Optional lightweight UI host for route orchestration and artifact browsing.
- Policy-as-code checks for repository standards enforcement.

## Technical Debt

- Reduce remaining duplication between status scan and reconciliation scan execution paths.
- Add stronger schema validation for doc-review queue/batch outputs.
- Normalize historical evidence layout and lifecycle conventions.

## Definition of Done for New Features

- Route/module behavior documented in docs.
- Contract updates reflected in `docs/reference/contracts.md`.
- Smoke or regression test coverage added or updated.
- Structured logs and metric hooks included.


