# Release 2.9 foundations-first items — closed 2026-08-26

**Window:** 2026-08-25 (PR #184 opened) to 2026-08-26 (PR #186 merged).
**Source of truth:** GitHub Actions CI Smoke runs on `xfaith4/GitHubRepoManagement`
(`windows-latest`, `scripts/Invoke-TestSuite.ps1`), cited by run id below.
**Verified:** 2026-08-26, from the run records — not from a local suite run.

## Outcome

The three foundations-first engineering items of Release 2.9 (resequenced
2026-08-23) are closed. Their only remaining condition — recorded in
[`execution-contract-readiness-2026-08-25.md`](execution-contract-readiness-2026-08-25.md)
as "the canonical module and API-host smoke commands both exit 0 in their
supported Windows environment" — was met by CI Smoke on `windows-latest`,
which is the arbiter named in the release's validation plan.

## What closed, and the gate that proves each

| Item | Shipped in | Gate shown red first |
| --- | --- | --- |
| Two gates disagree about the same repo | PR #184 (`ba8ffc7`): `Roadmap.ExecutionContract.ps1` is the authority; `Automation.RoadmapPackaging.ps1`, `Portfolio.Assessment.ps1`, and the dispatch-check route consume it | Module smoke "Execution-contract authority": the violating fixture returns `execution-contract-verification-missing` before the sufficient fixture returns `execution-contract-sufficient`; api-host smoke `/api/roadmap/dispatch/check -> ready=True verdict=execution-contract-sufficient` |
| Two routes name the same concepts differently | PR #184: canonical `pendingCount` / `nextPendingItem` flow through backend, index, and `apiClient.ts`; `pendingItemCount` / `nextPendingItemText` remain compatibility aliases | api-host smoke asserts the canonical fields and aliases on `/api/portfolio/assessment` and `/api/roadmap/audit` |
| 26 of 34 roadmap repos below L3 cannot be dispatched | PR #184: `Roadmap.Repairer.ps1` adds a repository-appropriate validation command; the bounded-L2 path qualifies without maturity; `RoadmapDispatchModal.tsx` names the verdict and the repair | Module smoke: L1 preview reachable, bounded-L2 red/green; `RoadmapDispatchModal.test.tsx` renders the named verdict and repair |

## Proof

- PR #184 first failed CI (run 32947175000): the api-host smoke's own L3
  packaging fixture carried a prose-only validation plan and was refused by the
  new gate as `execution-contract-verification-missing` — the gate rejecting
  the suite's fixture is itself evidence the enforced model changed.
- Commit `0d4941e` gave the fixture a runnable command; CI Smoke run
  32949331713 passed all 18 gates on the PR head (module smoke 78.8s,
  api-host smoke green, PowerShell lint at baseline).
- Squash-merged as `ba8ffc7`; the `main` push run 32949908469 passed.
- Subsequent PRs #185 (`a757c27`) and #186 (`9917e15`) each passed CI Smoke
  on top of it (runs 32964731487 and 33018708702).

## Effect on the roadmap

- The three items move verbatim to
  [`docs/history/completed-releases.md`](../../docs/history/completed-releases.md)
  under the Release 2.9 archive heading, per the archive rule.
- Release 2.9 stays `active` for its operator half (elevated session,
  authenticated `gh`, the phone on the LAN).
- Release 3.6 — Every Repository Gets an Outcome — has its stated precondition
  met and may start. It stays `planned` in the index because ROADMAP-011
  allows one `active` release, and 2.9 holds that slot.

## Not claimed

Nothing here is `operator-verified`; every proof above is an automated gate.
The operator items of Release 2.9 are untouched.
