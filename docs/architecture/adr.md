# Architecture Decision Records

## ADR-001: Backend Direction is PowerShell/.NET-First

- Status: Accepted
- Date: 2026-03-07

Context:

- Existing tooling is split across Node backend + PowerShell scripts.
- Operational environment is Windows-first with strong PowerShell/.NET preference.

Decision:

- Keep orchestration and core operations in PowerShell modules hosted behind a .NET-friendly API boundary.

Alternatives considered:

- Keep Node backend as canonical core.
- Full immediate .NET rewrite of all script logic.

Rationale:

- aligns with operator runtime and existing automation,
- lowers migration risk by reusing script logic before deeper rewrite.

Consequences:

- requires adapter layer during transition,
- improves long-term maintainability for Windows operations.

## ADR-002: Preserve Artifact-First Contracts

- Status: Accepted
- Date: 2026-03-07

Context:

- Current tools already generate JSON/CSV/HTML/Markdown outputs consumed by operators.

Decision:

- Treat machine-readable artifacts as stable contracts, not side effects.

Alternatives considered:

- rely only on in-memory API responses.
- reduce outputs to UI-only views.

Rationale:

- supports auditability, offline review, and integration with other scripts.

Consequences:

- schema versioning must be defined and tested,
- output retention policies become required.

## ADR-003: Dual GitHub Adapter Strategy (`gh` and API)

- Status: Accepted
- Date: 2026-03-07

Context:

- One repo relies on `gh` CLI; another uses Octokit/GitHub API.

Decision:

- implement a common GitHub inventory interface with two adapters.

Alternatives considered:

- force all usage through `gh` only.
- force all usage through API only.

Rationale:

- increases resilience and portability across auth/scope scenarios,
- allows gradual migration without breaking existing workflows.

Consequences:

- adapter selection logic and fallback rules must be explicit,
- tests need to cover both adapters.

## ADR-004: Phased Migration with Compatibility Shims

- Status: Accepted
- Date: 2026-03-07

Context:

- replacing all entrypoints at once would increase outage/regression risk.

Decision:

- migrate in phases, keeping compatibility routes and wrapper scripts until parity is proven.

Alternatives considered:

- big-bang cutover.
- indefinite multi-tool coexistence.

Rationale:

- controls operational risk while preserving momentum.

Consequences:

- temporary duplication is expected during transition,
- deprecation timeline must be managed.

## ADR-005: Observability Baseline is a Release Gate

- Status: Accepted
- Date: 2026-03-07

Context:

- source tools have inconsistent logging and minimal health/metric standardization.

Decision:

- require structured logging, core metrics, and health endpoints before full cutover.

Alternatives considered:

- postpone observability until after migration.

Rationale:

- faster incident triage and safer operations during consolidation.

Consequences:

- initial implementation effort increases,
- reliability and diagnosability improve significantly.
