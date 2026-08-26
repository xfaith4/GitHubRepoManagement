# Execution-contract readiness alignment — 2026-08-25

## Outcome

The Release 2.9 foundations-first engineering slice is implemented and
UI-connected. Interactive dispatch, scheduled packaging, portfolio lifecycle,
and the repair-needed UI now consult one explainable execution-contract verdict.
The roadmap milestones remain open until the canonical module and API-host
smoke commands both exit 0 in their supported Windows environment.

## Decision

`Test-RoadmapExecutionContract` is the authority. A sufficient contract names:

- bounded scope: a release goal, pending work, and an out-of-scope boundary;
- observable acceptance criteria;
- an exact runnable command, script, or API request; and
- a sizing signal appropriate to the dispatch target.

L3/L4 maturity is the default sizing signal, not universal admission. A lower
maturity roadmap may qualify when dispatch is bounded to one selected task or
an explicitly scoped phase has a positive estimate within its declared cap.

Canonical route names are `pendingCount` and `nextPendingItem`.
`pendingItemCount` and `nextPendingItemText` remain compatibility aliases and
are normalized from the canonical values by the frontend client.

An insufficient contract returns named failed checks and the existing
preview-first roadmap repair. Repair output now adds a repository-appropriate
validation command, so an L1/L2 repo has a path toward sufficiency instead of a
maturity-only refusal.

## Proof completed

- Red first: the module fixture without runnable verification returns
  `execution-contract-verification-missing`.
- Green after repair: the same bounded L2 fixture with `npm test` returns
  `execution-contract-sufficient`.
- Sizing remains enforced: an L2 phase estimated above its cap returns
  `execution-contract-sizing-missing`.
- Live isolated API proof on port 7095 returned HTTP 200 for
  `POST /api/roadmap/dispatch/check`, all four checks passed,
  `dispatchReady` equaled `executionContract.sufficient`, and the release packet
  carried the same `execution-contract-sufficient` verdict.
- `npm run typecheck` exited 0.
- `npm run lint` exited 0 with the existing 161-warning baseline and no errors.
- `npm run test:unit -- --run` exited 0: 27 files and 274 tests passed.
- PowerShell parse checks passed for all changed scripts under pwsh and Windows
  PowerShell 5.1.
- The live Release 2.9 context parsed with four acceptance criteria, six
  out-of-scope entries, eight validation-plan lines, and a sufficient verdict.

## Canonical-suite status

`scripts/Invoke-ModuleSmokeTest.ps1` passes the new red/green verdict,
validation-plan parser, L1 repair, portfolio lifecycle, packaging, stale-base,
and default-branch invariant sections. Its WSL run later stops in the existing
bounded-sweep timing fixture because zero marker intervals are observed. The
Windows PowerShell 5.1 run passes the new gate and stops earlier in an existing
Unicode roadmap-auditor fixture. Neither failure is in an execution-contract
consumer.

`scripts/Invoke-ApiHostSmokeTest.ps1` reaches background-scan start/cancel under
WSL after making the worker launch omit Windows-only `-WindowStyle`. The harness
then loses its host connection before the changed roadmap route. A separate
isolated host run exercised that route successfully as described above.

CI or a supported Windows pwsh run remains the arbiter before these roadmap
checkboxes advance to complete. No operator-verification claim is made.

`scripts/Invoke-LintGate.ps1` was also attempted under WSL. Its repository-wide
PSScriptAnalyzer sweep remained active with sustained CPU but produced no
result after 15 minutes, so the run was stopped and is not counted as a pass.
