# Release 3.6 milestone 1 — the conclusion model — 2026-08-26

**Window:** 2026-08-26, one working session, after Release 2.9's foundations-first
items closed (PR #187, `cfd3941`).
**Source of truth:** the local canonical suite (`scripts/Invoke-TestSuite.ps1
-SkipApiHost`) on Windows, cited by gate below; CI Smoke on the PR is the
arbiter for the api-host smoke step, which this machine cannot reach (see
"Not claimed").
**Verified:** 2026-08-26, from the gate output — nothing here is operator-verified.

## Outcome

Every indexed repository can now be asked for one explainable conclusion —
`strengthen`, `appropriate-as-is`, or `insufficiently-understood` — with a
reason, per-domain evidence, and (for `strengthen`) a preview-first next
action the console can run. The domains, statuses, repository kinds and
per-kind applicability are data in `backend/config/foundation-domains.json`.

## What shipped

| Piece | Where | Note |
| --- | --- | --- |
| Conclusion module | `backend/modules/portfolio/Portfolio.Conclusion.ps1` | Composes from the cached index only; param-less; StrictMode-safe accessor |
| Domain data | `backend/config/foundation-domains.json` (`schemaVersion: "v1"`) | Five domains, five statuses (incl. `not-scored`), seven kinds, two detection rules |
| Collection route | `GET /api/portfolio/conclusions` (`?conclusion=` filter) | Counts by conclusion and kind, per-domain coverage, contract block, read budget |
| Per-repo route | `GET /api/portfolio/conclusions/{repoId}` | Same four-way id match as `/api/operations/repos/{repoId}`; 404 is JSON |
| Deadline tier | `backend/api-host/RequestDeadline.ps1` | Both paths on the extended tier — a cold index rebuild must not FailFast the host |
| Config gate | `Invoke-TestSuite.ps1` "foundation-domains.json integrity (Release 3.6)" | Versioned, complete, unscored domain cannot claim a score |

## Decisions recorded

- `not-scored` is a fifth domain status. The intentional-engineering domain
  is defined, not scored (the roadmap's own wording); reporting it as
  `not-applicable` would have been a lie about why.
- `appropriate-as-is` must cite positive evidence. The validator refuses a
  conclusion whose only support is "no findings".
- Kinds the index cannot evidence are `unknown`, and every scored domain
  applies. Detection covers `archived` (lifecycle state, or the operator's
  `archived-ignore` curation). `minimal`, `externally-managed`, `library`,
  `service` and `script-collection` exist as data with their applicability
  reasons and await a kind signal — a JSON-only refinement, proven by the
  module smoke flipping a conclusion with a new detection rule and no code.
- A missing roadmap reads "no plan recorded" and offers the roadmap repair
  preview — the smallest credible plan — never a bare `L0-Absent`.

## Proof

- Module smoke (`[PASS]`, 89.5s): "Foundation conclusions — Release 3.6 M1":
  5 domains, 7 kinds; validator red on a blank reason, a `strengthen` with no
  route, and a bare `L0-Absent`; 9 fixtures all concluded
  (strengthen=3 appropriate-as-is=4 insufficiently-understood=2); coverage and
  `byConclusion` reconcile to the item count; JSON round trip holds; a
  JSON-only kind rule flipped a conclusion.
- Module smoke tripwires that fired first, then passed: the derived
  deadline-tier check ("runs a full-portfolio scan [Get-OperationsReposPayload]
  but is not on the extended deadline tier") and the read-budget wiring list.
- `foundation-domains.json integrity (Release 3.6)` (`[PASS]`): 5 domains
  (4 scored), 7 kinds, 2 detection rules.
- PowerShell lint (`[PASS]`): 0 Error-severity; 566 findings against a
  baseline of 571 after three ratchet findings from the new code were fixed
  (unused parameter, `OutputType`, a `New-` verb without ShouldProcess).
- Roadmap structure lint 0 errors; capability record gate `[PASS]`.
- Frontend typecheck, lint (161-warning baseline), 274 unit tests, build: all
  `[PASS]` — untouched by this milestone, confirmed unaffected.

## Not claimed

- The api-host smoke step (100% of the live index concludes; the fixture's
  `strengthen` next action answers JSON 200; detail/404/filter; route census)
  was not run locally: on this machine the smoke dies earlier, at the
  differential-reuse proof, because the installed SYSTEM service shares
  `output/`. CI Smoke on the PR is its venue.
- The API contract gate fails locally (seven `/api/portfolio/snapshot` tests
  answer 500). Bisected: identical with every change of this milestone
  stashed, and CI passed the gate on all four merges today — environmental,
  recorded in memory, not fixed here.
- No UI consumes the route yet (that is the outcome card, milestone 2). No
  trend series yet (milestone 5). Nothing is operator-verified.
