You are planning Release 2.1, Phase 2 of ROADMAP.md: migrate execution-ledger
and ops-log reads/writes behind the persistence boundary using parameterized
SQL, keeping JSON exports as debugging artifacts only.

Read only what you need, in this order:
1. ROADMAP.md — section 5 (Active Release Snapshot) and the Release 2.1
   engineering milestones / acceptance criteria.
2. backend/modules/persistence/Persistence.Store.ps1 — the Phase 1 seam
   pattern (capability detection, schema-v1, parameterized helpers, the
   agent-run-event dual-write). Phase 2 must follow this pattern, not
   invent a new one.
3. The current JSON read/write call sites for the execution ledger and ops
   log (locate them; do not assume paths).
4. scripts/Invoke-ModuleSmokeTest.ps1 and scripts/Invoke-ApiHostSmokeTest.ps1
   — the Release 2.1 smoke sections you will extend.

Produce an implementation plan that satisfies these acceptance criteria:
- The execution ledger survives a concurrent assign + complete call without
  data loss.
- The ops log is queryable by time range via
  GET /api/log/tail?since=<ISO>&level=ERROR.
- All existing smoke tests pass against the SQLite backend.
- JSON files remain as debug exports, never as the source of truth for
  migrated paths.

Constraints:
- Parameterized SQL only — no string-interpolated queries.
- Dual-write first, cut reads over second (mirror the agent-run-event seam),
  so a mid-phase failure never strands state.
- Windows winsqlite3.dll and WSL libsqlite3 must both keep working; respect
  the existing graceful-degradation path when no provider exists.

Plan output format:
1. Ordered file-change list with one-line intent per file.
2. Migration sequence (dual-write -> read cutover -> JSON demotion) with the
   verification command after each stage.
3. New smoke assertions to add, named per script.
4. Risks you see that the roadmap's risk section does not already list.

Do not write code in this session. End with the plan only.
