# Task Plan

## Goal
Close the last open Release 2.1 (Persistent Data Layer) milestone: persist
agent-run timing/token/cost and quota-burn metrics over time so
time-to-deliver and cost-per-phase trends are queryable, following the same
best-effort mirror seams and JSON-authoritative rollout contract as Phases
1-2.

## Scope

- Schema v2: add a `quota_burn_snapshots` table (one row per dispatch quota
  evaluation) alongside the existing but previously writer-less `agent_runs`
  table; keep DDL idempotent and the migration row versioned.
- Write path: mirror agent-run ledger records (metrics included) into
  `agent_runs` from `New-AgentRunRecord` / `Update-AgentRunRecord`, and
  persist every `Test-AgentDispatchQuota` evaluation as a quota-burn
  snapshot in the dispatch route. All mirrors are best-effort and never
  break the run or dispatch they describe.
- Read path: `GET /api/agent-runs/metrics-history` (SQLite-backed with
  first-read seeding from `output/agent-runs/runs/*.json` and a truthful
  JSON fallback) and `GET /api/agent-runs/quota-burn-history` (SQLite only;
  empty + `source=none` without a provider), both following the
  maturity-history route contract. API docs entries added.
- Validation: module-smoke Phase 3 sections (mirror upserts, metrics
  history shape, ordered quota burn-down), api-host smoke assertions for
  both new route contracts, `npm run build`.

## Phases

| Phase | Status | Notes |
| --- | --- | --- |
| 1. Reconcile milestone against live code | complete | `agent_runs` columns existed from schema v1 but nothing wrote them; quota evaluations were computed per dispatch and only emitted as JSONL events. |
| 2. Schema v2 + write seams | complete | `quota_burn_snapshots` table, `Write-AppDbAgentRun` / `Write-AppDbQuotaBurnSnapshot`, guarded mirrors in AgentRuns.ps1 and the dispatch route. |
| 3. History read helpers + routes | complete | `Get-AppDbAgentRunMetricsHistory` (with first-read JSON seeding) / `Get-AppDbQuotaBurnHistory`, two new GET routes, `{runId}` prefix-matcher exclusion fix, ApiDocsModal entries. |
| 4. Validation and roadmap state update | complete | Targeted persistence proof passed (schema v2, upserts, ttd derivation, seeding, ordered burn-down, disabled-boundary contract); api-host smoke `[PASS]` end to end with both new route contracts live; `npm run build` passed; ROADMAP/CHANGELOG/progress updated truthfully. Full module suite remains blocked by a pre-existing roadmap-repairer failure unrelated to this slice (see Errors). |

## Errors Encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| `scripts/Invoke-ModuleSmokeTest.ps1` aborts at the pre-existing "plan repair for L1 informal roadmap" step (`rewrite-not-recommended` instead of `repair-preview-ready`) before reaching the Release 2.1 sections | 1 | Confirmed pre-existing on HEAD: the failing path only exercises files untouched by this slice (likely stale smoke expectation after commit `2fed134` audit-rule refactor). Ran the Phase 3 persistence assertions as a targeted standalone proof instead (all passed); repairer smoke repair tracked as separate follow-up work. |
