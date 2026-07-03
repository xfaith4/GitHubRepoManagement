# Task Plan

## Goal
Ship Release 2.1 Phase 1 (Persistent Data Layer foundation): SQLite
capability detection, `output/app.db` bootstrap with the schema-v1 tables,
thin parameterized-SQL query helpers, and the first persistence migration
seam (agent-run events dual-write) — without breaking the JSON-backed
stores, which remain authoritative during rollout.

## Scope

- New `backend/modules/persistence/Persistence.Store.ps1`: capability
  detection (`Get-SqliteCapability`), zero-dependency native SQLite bridge
  (OS-shipped `winsqlite3.dll` on Windows, `libsqlite3` on WSL/Linux/macOS),
  `Initialize-AppDatabase` (schema v1 + `schema_migrations`, idempotent),
  `Invoke-AppDbQuery` / `Invoke-AppDbNonQuery`, `Write-AppDbAgentRunEvent`.
- Dual-write seam in `Write-AgentRunEvent` (AgentRuns.ps1): best-effort
  mirror after the authoritative JSONL append; non-fatal; `dbMirrored` flag.
- API host: dot-source the module, initialize `output/app.db` at startup
  (non-fatal), add `GET /api/persistence/status`.
- Smoke coverage: Release 2.1 module-smoke sections (capability, bootstrap,
  idempotent re-init, 25 repeated writes, unicode/quote/NULL binding,
  dual-write seam) and an api-host persistence-status step.
- Docs: ApiDocsModal Persistence group, api-host README, ROADMAP milestone
  + phase plan + current focus, CHANGELOG entry.
- Unblocking fixes only where validation was blocked (doc-audit scanner
  strict property access; module-smoke standards version key).

## Phases

| Phase | Status | Notes |
| --- | --- | --- |
| 1. Validate P/Invoke bridge approach | complete | winsqlite3.dll 3.51.1 loads via NativeLibrary + delegates; full round-trip probe passed. |
| 2. Persistence module | complete | Schema v1 (11 tables), WAL, busy timeout, graceful no-provider degradation. |
| 3. Dual-write seam | complete | JSONL stays authoritative; mirror is guarded, idempotent, non-fatal. |
| 4. API host wiring | complete | Startup bootstrap + `GET /api/persistence/status`; verified live on a scratch port. |
| 5. Smoke coverage | complete | Module smoke green end-to-end; api-host persistence step passes. |
| 6. Validation + docs + roadmap closeout | complete | Parser checks, module smoke, api-host harness, npm build, roadmap validator. |

## Errors Encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| `@()` enumeration of a `List[object]` holding PSCustomObjects failed with `Argument types do not match` on pwsh 7.6.3. | 1 | Root-caused to `New-Object`-created lists (PSObject-wrapped instance); switched to `[List[T]]::new()` per codebase convention and returned `.ToArray()`. |
| Module smoke failed pre-existing at doc-audit: `The property 'recommendedSections' cannot be found`. | 1 | Commit `db62f0b` (2026-06-26) moved README section contracts out of doc-standards.json; made the scanner access StrictMode-safe via `Get-DocAuditObjectValue`. Full section-authority wiring deliberately deferred as its own work item (would change dispatch-readiness classification portfolio-wide). |
| Module smoke failed pre-existing at portfolio assessment: `The property 'version' cannot be found`. | 1 | Same commit renamed `version` to `schemaVersion` in repo-structure-standards.json; smoke now accepts either key. |
