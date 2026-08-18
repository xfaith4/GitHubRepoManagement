# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 3.2 — Portfolio Scale and Responsiveness**
> **Next active release:** **Release 3.3 — Steady-State Operation**
> **Work ordering:** dependency-driven, not insertion order — see
> [Execution Order and Dependencies](#execution-order-and-dependencies)
> **Canonical product direction:** [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
> **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
> **Dated change log:** [`CHANGELOG.md`](CHANGELOG.md)

---

## Current Status (Agent Context)

**Last updated:** 2026-08-15

Releases 0.4 through 2.6, 2.8 and 3.0 are **engineering-complete and archived**,
as is every completed milestone from the releases and lanes still open below.
Their full text lives in
[`docs/history/completed-releases.md`](docs/history/completed-releases.md).

**This file carries open work only.** Every checkbox in it is something still
to do — if an item is `[x]` here it is a mistake, not a record. The 2026-08-11
archive pass that restored that rule is recorded in `CHANGELOG.md`.

What remains falls into four kinds of work, and they are **not**
interchangeable — mixing them is what previously made the roadmap read as
"everything is done" while real gaps sat unlabelled:

1. **Genuinely unbuilt engineering** — Release 3.5's seven trustworthy-surfaces
   milestones, Release 3.2's three remaining scale milestones, and the recorded
   cross-cutting items. This is the only kind an autonomous agent can close on
   its own. (The two mobile surfaces are also unbuilt engineering, but are
   deferred by the priority reset below rather than by any gate.)
2. **Elevated / hardware / human verification** — needs SYSTEM rights, a
   physical Android phone, or an operator sitting at an authenticated
   Claude Code session. No autonomous test can produce these.
3. **Product / design decisions** — waiting on a judgement, not on time or
   engineering (progressive disclosure; the `Checks: Read` grant).
4. **Calendar-gated accrual** — the 7/90-day trend windows fill only as
   time passes with capture running.

**Priority reset — 2026-08-11.** Mobile surfaces are **deferred**; PC
reliability and one workflow that finishes are the priority. The trigger was
not a preference. The live portal reported `state=absent, queuedTotal=6,
strandedCount=6` — six dispatches queued into a room with no runner, none ever
claimed — while the wizard that queued them kept offering an enabled "Approve
and create PR task" button. On the same day, that button was found to have been
incapable of succeeding since Release 3.0 ([PR #119](https://github.com/xfaith4/GitHubRepoManagement/pull/119)).
A second device form factor cannot be the priority while the first one has a
workflow that does not complete and does not say so.

**Current focus (next agent actions), in order:**

- [ ] **Release 3.2 — portfolio scale.** The active release, resumed
      2026-08-17 when 3.5 closed with its trust report
      ([per-finding before/after](docs/reference/trust-report.md)). Its
      performance budget landed 2026-08-11, so the three remaining milestones
      have a declared number to beat: warm reads 2-3s, cold scan 300s.
- [ ] **Batch the remaining operator-session work (2.9).** An elevated shell
      covers the watchdog _and_ the service installer; one authenticated shell
      covers the `claude` run, the `gh agent-task` run, and the full-loop
      proof. Doing them separately wastes the scarcest resource here. The
      phone session is no longer part of this batch — see the deferral below.
- [ ] **Lane 0.2's two items need an operator action outside this repository**
      — the PAT's `Checks: Read` grant (optional; the `mergeStateStatus` proxy
      is the working contract) and the portal TLS certificate password, whose
      recovery path is exhausted and needs a regeneration in an elevated
      session.

**Forward arc.** Releases 3.0-3.5 describe the finished product: dispatch that
runs (3.0), the loop closing end to end and legibly (3.1), the delivery loop
closing without a hand-off (3.4), numbers an operator can act on (3.5), an 80+
repo portfolio that feels immediate (3.2), unattended operation (3.3).

---

## 1. What This Document Is

This is the **active execution roadmap**. Its job is to answer two questions
for any operator or coding agent:

1. What is the current active release?
2. What is the next concrete work item?

Long-form product direction (thesis, principles, north-star workflow, risks,
guardrails) lives in
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
and is summarized below in section 2. The full text of every completed
release (0.4 through 2.6, plus 2.8) lives in
[`docs/history/completed-releases.md`](docs/history/completed-releases.md);
this document references them by version + status only.

---

## 2. Product Direction (summary)

GitHub Repo Management is a **portfolio intelligence and execution console**
that assesses an entire local and GitHub repository collection, standardizes
repo readiness, creates or repairs roadmap contracts, ranks the
highest-value incomplete roadmap work, prepares reviewed agent prompts,
monitors agent execution, and reports whether work is safe to merge.

The **north-star operator workflow** every release should serve is:

> scan portfolio → index repos → classify every repo → show lifecycle state →
> identify blockers → repair README/roadmap/structure → rank highest-value
> next work → refine agent prompt → dispatch → monitor agent run → validate
> Actions → evaluate merge readiness → update roadmap / report progress

For the full thesis, ten core questions, principles, risks, and guardrails,
see
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md).

---

## 3. Implementation-State Vocabulary

Every milestone in this roadmap should carry one of these states. A `[x]`
checkbox alone is not enough — it does not distinguish "backend exists" from
"end-to-end working."

| State               | Meaning                                                                      |
| ------------------- | ---------------------------------------------------------------------------- |
| `planned`           | Proposed; no code yet                                                        |
| `scaffolded`        | Files / route / UI exist but stubbed or returns mock data                    |
| `backend-complete`  | Server-side logic implemented; no UI consumer yet                            |
| `ui-connected`      | Frontend wires through to live backend; manual smoke ok                      |
| `smoke-tested`      | Automated module / api-host smoke covers it                                  |
| `operator-verified` | Confirmed working end-to-end against the live workspace                      |
| `done`              | All four of: backend-complete, ui-connected, smoke-tested, operator-verified |

Render the state inline on each milestone in italics, e.g. `- [x] Add the
route. _(state: smoke-tested)_`.

**Checkbox rule.** `[x]` means _nothing remains for that item in this roadmap_.
An item whose engineering is complete but whose proof is still outstanding stays
`[ ]` and names the resource it waits on.

**Archive rule (2026-08-11).** A completed item does not stay here. Once `[x]`,
it moves to [the archive](docs/history/completed-releases.md) **verbatim** —
evidence prose intact, because that is what stops the next agent re-litigating a
settled decision — and this file keeps at most a one-line pointer. A release
whose remaining work is only an external-resource proof is closed, and that
proof re-homed to Release 2.9, rather than held open.

**Pending-item phrasing rule:** action-first, surface-specific wording a coding
agent can select without rereading surrounding prose: `verb + artifact/route/
module + verification boundary`.

---

## 4. Release Index

| Version   | Title                                                                    | Status                                                                                     |
| --------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| 0.4 - 1.1 | Foundation through Standardization and Guardrails                        | `done` — see [archive](docs/history/completed-releases.md)                                 |
| 1.2       | Enhanced Portfolio Intelligence                                          | `done` — closed 2026-07-05; see archive                                                    |
| 1.3 - 1.7 | Frontend build, repo evaluation, README generation, dispatch, git status | `done` — see archive                                                                       |
| 1.7.5     | Portfolio Mission Alignment, Indexed Scanning, Value-Ranked Planning     | `done` — shipped 2026-05-28; see archive                                                   |
| 1.8 - 2.0 | Operations workspace, AI doc cycles, agent-run monitoring                | `done` — see archive                                                                       |
| 2.1       | Persistent Data Layer                                                    | `done` (engineering) — closed 2026-08-07; operator sign-off tracked in 2.9                 |
| 2.2       | API Auth, Network Security, Onboarding, GitHub App                       | `done` (engineering) — 2026-07-05; optional live App-token exchange tracked in 2.9         |
| 2.3       | Portfolio Analytics, Trend Visualization, Distribution                   | `done` (engineering) — 2026-07-06; 7/90-day accrual is calendar-gated, tracked in 2.9      |
| 2.4       | Agent Integration Protocol and AI Repair Loop                            | `done` — 2026-07-05; live submit-PR proof landed 2026-08-09 (2.7 Phase A, PR #96)          |
| 2.5       | Mobile-Friendly Operator Experience                                      | `done` (engineering) — 2026-07-05; two surfaces + device proof tracked in 2.9              |
| 2.6       | Interface Clarity and Operator Orientation                               | `done` — 2026-07-06; device sign-off tracked in 2.9                                        |
| 2.7       | Guarded Scheduled Automation (Curated-Subset, Preview-First)             | `done` — closed 2026-08-11; see archive. Live service install re-homed to 2.9              |
| 2.8       | Local Claude Code Execution (queue + operator runner)                    | `done` (engineering) — 2026-07-15; real `claude` run tracked in 2.9                        |
| **2.9**   | **Operator Field Proof** (mobile completion deferred)                    | `planned` — external-resource residuals only; the two mobile surfaces are deferred         |
| 3.0       | Operator-Context Execution                                               | `done` (engineering) — 2026-08-09; see archive. Live proof tracked in 2.9                  |
| 3.1       | Closed-Loop Delivery                                                     | `done` 2026-08-15 — manual loop proof recorded; portal + scheduled proofs re-homed to 2.9  |
| **3.2**   | **Portfolio Scale and Responsiveness**                                   | **active** — resumed 2026-08-17 when 3.5 closed; read-path budget done, 3 milestones open  |
| **3.3**   | **Steady-State Operation**                                               | `planned` — unattended for months: retention, restore, honest TLS, decision-grade digests  |
| **3.4**   | **The Delivery Loop Closes**                                             | `done` 2026-08-15 — six milestones + the full-loop proof, driven live and operator-verified |
| 3.5       | Trustworthy Surfaces (UI Quality)                                        | `done` 2026-08-17 — all seven milestones; trust-report per finding; operator sign-off in 2.9 |

> **Note on `.5` numbering.** Reserve it for course corrections like 1.7.5;
> default new work to integer minor releases.

### Execution Order and Dependencies

Release numbers identify scope — they do not dictate sequence. Work through
open items in the order below, and update this section whenever a lane
closes or a new dependency appears.

**Everything that once blocked something else has landed.** Step 0's
unblockers closed 2026-08-08; Release 2.7's two lanes closed 2026-08-09; 3.0's
dispatch runs. No open item is now waiting on another open item — the ordering
below is therefore about **what kind of resource each item needs**, not about
prerequisites.

1. **Release 3.2 — the active release.** Portfolio scale, resumed on 3.5's
   closure: the background-job cold scan, bounded per-repo git work, and grid
   virtualization — each against the budget shipped 2026-08-11.
2. **Release 3.4 — the delivery loop closes.** Engineering complete
   2026-08-15: all twelve steps of the loop are built, each behind its own
   refusal matrix, and the default-branch invariant is a derived tripwire that
   proves itself before sweeping. What remains is driving one real item around
   the circle — batched with the operator session below, alongside 3.1's proof.
3. **Release 3.3 — steady-state operation.** Next after 3.2; independent
   milestones, any order.
5. **One batched operator session** — an elevated shell covers the watchdog,
   the service installer and 2.7's freeze-prevention deploy; one authenticated
   shell covers the `claude` run, the `gh agent-task` run, the 3.1 live-portal
   proofs and the scheduled-trigger loop proof (all re-homed to 2.9 on 3.1's
   closure). Batching is the whole point: the operator, not the code, is the
   scarce resource.
6. **Release 3.3 — pick-up work.** Every milestone is independent; take one
   whenever the active release is blocked.
7. **Trend accrual** closes itself as calendar time passes, provided capture
   keeps running.
8. **Deferred — mobile completion (2.9) and the physical-Android proof.** Not
   cancelled and not obsolete; the responsive foundation from 2.5 still ships.
   They resume once a PC workflow runs end to end without an operator having to
   know which background process must be alive for a button to mean anything.

**Dependency map (open work only):**

| Open item                                            | Depends on                                    | Type                                          |
| ---------------------------------------------------- | --------------------------------------------- | --------------------------------------------- |
| Release 3.2 scale and responsiveness (active)        | —                                             | none — budget declared, three milestones open |
| Release 3.4 full-loop proof (engineering done)       | The same authenticated operator session       | hard — human; batch with 3.1's proof          |
| Release 3.5 trustworthy surfaces (UI quality)        | —                                             | none — root causes identified, engineering    |
| Release 2.9 mobile completion (ergonomics, run list) | A priority decision, already taken            | deferred 2026-08-11 — not blocked, deranked   |
| Release 3.3 steady-state operation                   | —                                             | none — independent milestones, any order      |
| Lane 0.2 `Checks: Read`; TLS certificate password    | An operator action outside this repository    | hard — external                               |
| Lane 0.5 tab disclosure; Lane 0.7 archive signal     | A product decision, not engineering time      | hard — design                                 |
| Release 2.9 freeze-prevention deploy (from 2.7)      | An elevated (SYSTEM) Windows install          | hard — privilege; batch with the two below    |
| Release 2.9 watchdog + service-installer proof       | An elevated (SYSTEM) session                  | hard — privilege                              |
| Release 2.9 physical-Android proof (2.5 + 2.6)       | An Android device on the LAN                  | deferred 2026-08-11 — hardware, and deranked  |
| Release 2.9 real `claude` + `gh agent-task` runs     | An authenticated operator session             | hard — human; one session covers both         |
| Release 2.9 re-homed 3.1 proofs (portal + schedule)  | The same authenticated operator session       | hard — human; batch with the runs above       |
| Release 2.9 GitHub App installation-token exchange   | A registered GitHub App                       | hard — optional; PAT supersedes               |
| Release 2.9 trend accrual (2.3 Ph2)                  | Days of live capture                          | hard, time-gated                              |

---

## 5. Active Release Snapshot

### Active release detail — 3.2 Portfolio Scale and Responsiveness

Release 3.2 resumed as the active release 2026-08-17, when Release 3.5 closed
with its trust report — the ordering settled 2026-08-11 finally arriving at
the release it deferred: latency was a quality of a workflow that works and of
numbers worth waiting for, and both now exist.

The full execution contract lives in one place,
[Release 3.2 below](#release-32--portfolio-scale-and-responsiveness), per
`ROADMAP_TEMPLATE.md`. This heading exists so the validator can resolve the
active-release pointer; it deliberately restates nothing.

**Current focus:** the cold full assessment becomes a visible background job
with progress and a cancel; per-repo git work gets a timeout and a
concurrency cap; the grid virtualizes. The declared numbers to beat shipped
2026-08-11: warm reads 2-3s, cold scan 300s.
---

## 6. Open Releases

### Release 2.9 — Operator Field Proof (mobile deferred)

**Status:** planned

**Goal:** convert every surface that is `smoke-tested` but still waits on an
external resource into `operator-verified` with durable evidence, and finish the
two mobile surfaces left incomplete under Release 2.5. No new capability — this
closes the honesty gap between "the suite is green" and "this works in the
field."

**Prerequisites:** each field-proof milestone names the one external resource
it waits on; none block each other, and several share a session. Batch them:
the operator, not the code, is the scarce resource.

#### Product outcomes

- No milestone is marked complete on an automated suite alone when what it
  claims needs hardware, elevation, credentials, or a human.
- `evidence/` carries a durable record for each proof, so the next agent reads
  the evidence instead of re-litigating whether something works.

#### Engineering milestones

**Mobile completion — deferred 2026-08-11**, not cancelled. Both items have no
technical gate; they were deranked because the PC workflow they would be a
second front-end for does not yet run to completion, and a second form factor
multiplies an unreliable workflow rather than adding reach. Resume when Release
3.1 closes; the Release 2.5 responsive foundation stays shipped, so nothing
regresses meanwhile.

- [ ] _(deferred)_ Touch ergonomics beyond the Release 2.5 Phase 1 surfaces:
      ~44px targets and a tap equivalent for every hover-only affordance across
      the Phases 2-3 surfaces. _(state: scaffolded)_
- [ ] _(deferred)_ The tap-through mobile agent-run list from the agent-activity
      indicator. _(state: planned — only the view is missing)_
- [ ] _(deferred)_ Verify the four Release 2.5 workflows and the Release 2.6
      clarity affordances on a **physical Android phone**, per
      [`lan-mobile-setup.md`](docs/reference/lan-mobile-setup.md). _(state: both
      smoke-tested at an emulated 390px viewport → need real hardware)_

**Field proof — one elevated (SYSTEM) session covers all three:**

- [ ] Deploy the Release 2.7 Phase D freeze prevention to the live service. All
      three engineering parts ship; only the install remains. _(state:
      smoke-tested → needs an elevated Windows install)_
- [ ] Run the elevated
      [`Install-PortalWatchdog.ps1`](scripts/service/Install-PortalWatchdog.ps1)
      and confirm a real freeze-and-recover, with the
      `output/logs/service-watchdog.jsonl` line and the `execution.failed`
      webhook to prove it. _(state: smoke-tested → needs `operator-verified`)_
- [ ] Operator-verify the reworked
      [`Install-RepoManagementService.ps1`](scripts/Install-RepoManagementService.ps1):
      install / repair / `icacls` / scheduled task, secrets from machine env
      vars, tracked `settings.json` secret-free. _(state: smoke-tested)_

**Field proof — one authenticated operator session covers all three:**

- [ ] One real `claude` run through
      [`Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1):
      claim → branch → run → verify → commit → `awaiting-review`. Closes the
      Release 2.8 residual. _(state: smoke-tested dry-run E2E)_
- [ ] One real **copilot** entry through the runner — `gh agent-task create`
      reaches a live task, URL in the run summary. Closes the Release 3.0
      residual. _(state: smoke-tested. Requires `gh auth login` and **no**
      `GH_TOKEN`/`GITHUB_TOKEN` set; gh ignores stored OAuth when one is.)_
- [ ] **Release 3.1's scheduled-trigger loop proof** — the manual half is
      operator-verified 2026-08-15
      ([evidence](evidence/verified/full-loop-proof-2026-08-15.md)); this
      session records a scheduled packaging run approved through to the same
      outcome. _(re-homed from 3.1 on closure, 2026-08-15)_
- [ ] Operator-verify the Release 3.1 empty-room gate against the live portal
      (the refusal, the disabled approve controls, the stranded badge).
      _(state: smoke-tested; re-homed from 3.1 on closure)_
- [ ] Operator-verify Release 3.1 engine attribution on the live portal (the
      `engine` block above the findings, `providerId` null for rule engines).
      _(state: smoke-tested; re-homed from 3.1 on closure)_
- [ ] Operator-verify Release 3.5 on the live portal — the before/after
      screenshots of every tab the trust report describes, the scope toggle,
      the runner pill, and the async panels under a real slow backend.
      _(state: smoke-tested; re-homed from 3.5 on closure 2026-08-17)_

**Field proof — credential / calendar:**

- [ ] Operator-verify Release 2.1 against the live workspace and record the
      sign-off, closing the release formally. _(state: smoke-tested against live
      data — `output/app.db`, the real 68-repo scan)_
- [ ] Operator-verify the auth + shared-LAN path so automation runs on a bound,
      authenticated host. _(state: planned — carried over from 2.7 Phase D)_
- [ ] (Optional) Prove live GitHub App installation-token exchange + refresh,
      closing the Release 2.2 residual. _(state: planned — the PAT supersedes)_
- [ ] Let the Release 2.3 Phase 2 trend windows accrue: `GET /api/portfolio/trend`
      reports a real 7-day, then 90-day, window. _(state: smoke-tested — only
      calendar time is missing. Keep
      [`Invoke-DailyEvidence.ps1`](scripts/Invoke-DailyEvidence.ps1) running.)_

#### Acceptance criteria

- Every milestone above carries an entry in
  `evidence/operator-verification-log.jsonl`, appended via
  [`Add-OperatorVerification.ps1`](scripts/Add-OperatorVerification.ps1) — an
  unrecorded proof is indistinguishable from one that never happened.
- A deliberately frozen portal is detected and recovered by the installed
  watchdog without intervention, with the ledger line to prove it.
- All four mobile workflows complete on a physical Android phone; the app
  installs to the home screen; every hover-only affordance taps at 390px.
- One real `claude` run reaches `awaiting-review` with a commit on a
  `roadmap/<runId>` branch and nothing pushed, and Release 2.1 is formally
  closed with a recorded sign-off.

#### Out of scope

- New product capability; remote (non-LAN) mobile access; native apps.

---

### Release 3.2 — Portfolio Scale and Responsiveness

**Status:** planned — was active from 2026-08-11, demoted the same day behind
Release 3.1. Nothing here was found wrong; the ordering was. A portfolio that
renders faster while queueing work nobody executes is not more reliable, and
the reliability gap was the one an operator was actually hitting. Resume as the
active release when 3.1 closes. 1 of 4 milestones shipped (the read-path
performance budget).

**Goal:** make an 80+ repo portfolio feel immediate. Reads serve from the
persistent index; a cold full assessment becomes a visible background job
instead of a synchronous request that can outlive its own deadline.

**Prerequisites:** met. Lane 0.4 settled the deadline question 2026-08-09 — an
extended 900-second tier rather than an exemption — so this release starts from
a bounded scan budget it has to beat rather than from an open question. The
performance milestone landed first deliberately: without a declared target,
the remaining three milestones would have no way to prove they helped.

#### Product outcomes

- No portal action can trip the freeze guard that exists to protect it.
- Portfolio reads are served from `app.db` and refreshed incrementally, so
  repeated views cost nothing.
- Scan progress is visible while it runs, rather than a spinner that may or may
  not still be alive.

#### Engineering milestones

**The read-path performance budget shipped 2026-08-11
([PR #117](https://github.com/xfaith4/GitHubRepoManagement/pull/117)) and is
archived.** It landed first deliberately: without a declared target, the three
milestones below would have no way to prove they helped. The numbers they have
to beat are now stated and enforced — warm reads at 2-3s, a cold scan at 300s
(against the 900s deadline), measured figure served beside its budget.

- [ ] Serve portfolio assessment from the persistent index with incremental
      refresh; make a cold full scan an explicit background job with progress
      and a cancel. _(state: planned — a cold scan currently exceeds both the
      smoke's client timeout and the 180s request deadline on the real
      75-repo workspace)_
- [ ] Bound per-repo git work with a timeout and a concurrency cap so one
      pathological repo cannot stall a sweep. _(state: planned — seven
      sequential unbounded `git` calls per repo, ~525 process launches on the
      real 75-repo workspace; one hung call stalls the sweep until the
      deadline guard kills the host)_
- [ ] Virtualize the repo grid so row count stops driving render cost.
      _(state: planned)_ Pairs with the `Dashboard.tsx` non-blocker below —
      both are render cost on the same screen.
- [ ] **[non-blocker]** `Dashboard.tsx` is **1,752 lines** (2,519 → 2,308 after
      the Phase D extractions → 1,752 on 2026-08-10, when the ~600-line Insights
      block became [`InsightsView.tsx`](frontend/components/InsightsView.tsx)).
      What remains is ~1,000 lines of hooks and handlers above the return — a
      different shape of problem from the JSX blocks already extracted.
      **Gained a driver 2026-08-17:** Release 3.5 deferred the Operations
      panels' full stale-keeps-last-good rendering to this refactor rather
      than threading it through the current component shape. _(state: planned — inherited from
      Release 2.7 Phase D when that release closed 2026-08-11; worth doing, not
      worth blocking on.)_

#### Acceptance criteria

- A cold full-portfolio assessment completes without tripping the request
  deadline, and its progress is observable while it runs.
- Repeated portfolio reads after a warm index are served without a rescan.
- The performance budget is stated in the repo and checked by smoke.

#### Out of scope

- Distributed or multi-machine scanning.
- Replacing SQLite.

**Validation plan (restored in full when 3.2 is active again):** `npm test`,
exit 0, plus a per-milestone gate — a hung `git` call abandoned at its
timeout, scan progress observable and a cancel honored mid-scan, and the
read-path budget assertions still green. A scale change that regresses a warm
read has traded the wrong thing.

**Risks:** a scale change must keep the progress heartbeat publishing from
**inside** the loop it describes, or a healthy scan reads as frozen and the
watchdog restarts it mid-flight (Lane 0.9, three P0 outages); a concurrency
cap must not reorder or drop repositories — output identical to sequential is
an assertion, not a hope; a background job must not leave an orphaned
operation marker when it outlives its request.

**Dependencies:** the persistent index (`Save-PortfolioIndexArtifacts`, 1.7.5),
the operation heartbeat, the request-deadline tier classifier, and the
read-path budget ([`PerformanceBudget.ps1`](backend/api-host/PerformanceBudget.ps1))
that gives the remaining milestones a number to beat.
**Known issues:**

- [ ] `FailFast` as deadline policy means one slow request destroys every
      in-flight request. Recorded as a Lane 0.9 non-blocker; the blast radius is
      a design question this release touches but does not by itself settle.
- [ ] `/health/live` is unanswerable while a scan runs, because the host is
      single-threaded. The background-job milestone is the first real
      opportunity to fix that rather than tolerate it — see the open Lane 0.9
      item, which this release should close or explicitly hand back.

---

### Release 3.3 — Steady-State Operation

**Status:** planned

**Goal:** run unattended for months without an operator babysitting it — bounded
storage, honest transport, a restore path, and reports that state their own data
window.

**Prerequisites:** none; each milestone is independent.

#### Product outcomes

- Append-only evidence stays append-only without growing without bound.
- What the portal claims about its own transport and credentials matches what
  it is actually doing.
- A lost or corrupted `app.db` is recoverable from evidence already on disk.
- Every export and digest states its data window, units, headline finding, and
  recommended next action.

#### Engineering milestones

- [ ] Add retention and compaction for the JSONL ledgers and `app.db`, with the
      policy stated in config and the pruned range logged. _(state: planned —
      `service-watchdog.jsonl` reached 6.9 MB from one-minute probes)_
- [ ] Add a documented backup and restore path for `app.db`, including a schema
      migration story. _(state: planned)_
- [ ] Make the portal's self-reported transport match reality, closing behind
      Lane 0.2's certificate recovery. _(state: planned — the host degrades to
      plain HTTP on a certificate it cannot open, while config still claims
      TLS)_
- [ ] Bring every export and digest up to the decision-grade contract: data
      window, units, headline finding, recommended next action.
      _(state: planned — the digest payload ships; the framing does not)_

#### Acceptance criteria

- Ledger growth is bounded by a stated policy, and pruning is itself logged.
- A restore from backup produces a working portal with its history intact.
- The transport the portal reports is the transport it serves.
- Every export names its window, units, headline, and next action.

#### Out of scope

- Multi-tenant or hosted operation.
- Log shipping to an external observability platform.

---

---

## 7. Cross-Cutting Engineering Work

Continuous, not release-scoped. **This section carries open work only.**
Completed cross-cutting items are in
[the archive](docs/history/completed-releases.md#cross-cutting-engineering-work-completed-items)
(2026-08-07) and [the 2026-08-08 batch](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).

### Lane 0.2 — Credential freshness

- [ ] **Decide the PAT `Checks: Read` grant — it is optional, not required.**
      _(state: planned — non-blocker; scope audit 2026-08-10)_ The token 403s on
      check-runs and GraphQL `statusCheckRollup`, but **nothing in the product
      depends on it**: merge readiness reads `mergeable_state` from the Pulls
      API and the merge loop's `mergeStateStatus` proxy works without it (six
      PRs merged 2026-08-10 on the proxy alone, through required-check branch
      protection). Granting it only adds `gh pr checks --watch` detail. Under a
      minimal-permissions policy it is legitimate to **decline permanently**; if
      declined, close this as "decided: proxy is the contract".
- [ ] **Regenerate the portal TLS certificate (recovery is dead).** _(state:
      planned — non-blocker; recovery path exhausted 2026-08-10)_
      Machine-scoped `REPO_MGMT_TLS_PFX_PASSWORD` (17 chars) does not open
      `backend\config\tls\portal.pfx`, so the portal serves plain HTTP on
      loopback while `REPO_MGMT_TLS_PFX` points at the pfx. **Recovery is no
      longer an option:** the pre-#53 shawl logs that recorded the plaintext
      password have rotated away — a 2026-08-10 sweep of the shawl log dir,
      `evidence/`, and `output/` found zero `-PfxPassword` matches (which
      also closes the old plaintext-leak concern). Remaining remedy is one
      **elevated** session (the service is LocalSystem, so the env var must
      be Machine-scope and the restart needs admin):
      `scripts\New-RepoManagementTlsCertificate.ps1 -Force` (prints the new
      password once), then `scripts\Install-RepoManagementService.ps1
      -Action Reconfigure` with it. Note: enabling TLS flips the portal to
      `https://127.0.0.1:7071` — plain `http://` URLs stop working.

### Lanes 0.3, 0.4 and 0.6 — closed entirely

All three shipped and closed 2026-08-09; detail moved to
[the archive](docs/history/completed-releases.md#closed-2026-08-11-archived-from-roadmapmd)
on 2026-08-11. Kept as named headings because surviving lanes and the
completed-release history reference them by name: **0.3** layout follow-ups,
**0.4** smoke coverage gaps (the extended deadline tier Release 3.2 inherits),
**0.6** the silent workspace-path failure.

### Lane 0.9 — Portal restart loop: the watchdog was killing healthy scans (P0, 2026-08-10)

**The incident closed 2026-08-10 across four passes and is archived.** Two
guards with different budgets meant every full scan was force-restarted; the
fix made **progress, not liveness or CPU**, the contract. Three of the four
passes taught one lesson: **fixing the named instance instead of the pattern is
this repo's most expensive recurring mistake** — every tripwire here now
derives its scope from a classifier or the AST, never a maintained list.

- [x] **Insights has no way to run the assessment it tells you to run.**
      **Closed 2026-08-14** under Release 3.1's "enabled means available".
      Portfolio Analytics said "Refresh the portfolio assessment to seed the
      Release 2.3 trend view" and Documentation Health said it was "unavailable
      until a portfolio assessment succeeds", but the tab offered no control
      that ran one — Documentation Health had no button at all, and Analytics
      had one named `Retry` that re-fetched the trend, so the instruction and
      the control disagreed while the label admitted neither. Both panels now
      carry a **Run portfolio assessment** action, and the trend button is
      renamed **Retry trend fetch** so the two are told apart.
      _(state: smoke-tested — asserted by `InsightsView.test.tsx` on the
      handler each control actually calls, not on its presence.)_
- [ ] **Make `/health/live` independently responsive during long operations.**
      _(state: planned — architectural, deliberately out of the incident fix)_
      The heartbeat makes the watchdog correct, but the underlying cause
      remains: a single-threaded host cannot answer liveness while working, so
      the portal is genuinely unresponsive to the operator for the duration of
      a scan. Options to weigh: a dedicated listener thread/runspace for
      `/health/*`, moving scans to a background runspace with a job handle the
      UI polls, or a small always-available status surface. This is a design
      decision, not a patch.
- [ ] **Clear and harden the stale browser-persisted GitHub owner.** _(state:
      planned — recorded 2026-08-10, not bundled into the watchdog fix)_ Every
      scan queries GitHub for owner `Benjamin-Fuhr_genesys`, which 404s/422s
      and adds failing round-trips to an already-long scan. It is **not** in
      `settings.json` (correctly `xfaith4`) or any env var — the browser sends
      it in the request body, and has since **2026-07-07** (116 occurrences in
      the host log). Clear the persisted client value and stop a client-supplied
      owner from silently overriding validated configuration.
- [x] **Replace the bare `Failed to fetch` screen with an actionable retry
      state.** **Closed 2026-08-14** under Release 3.1's "enabled means
      available". `Dashboard.tsx`'s `error && repos.length === 0` branch
      rendered the raw exception string and nothing else — no retry, no
      explanation. (The Lane 0.5 error boundary catches render throws, not
      rejected fetches.) [`fetchFailure.ts`](frontend/lib/fetchFailure.ts)
      classifies the message into backend-unreachable / auth-required /
      not-configured / backend-error, and the screen renders a headline, the
      next step, the verbatim original message, a retry, and a route into
      Settings — the modal is rendered inside the branch, since it returns
      early and the control would otherwise open nothing.
      _(state: smoke-tested — the classifier is unit-tested on the two states
      that need opposite actions, and a tripwire fails if the one-line raw-error
      return comes back.)_

### Lane 0.5 — Portal UX follow-ups (empty-state audit 2026-08-08)

Three of four closed 2026-08-10 and are archived: the missing error boundary,
bulk-scope confirmation on mutating actions, and the tab-inversion defect.

- [ ] **[non-blocker]** The wider progressive-disclosure question is still
      open, and is now a smaller one. With Insights no longer competing for the
      same vertical space as the tab strip, the remaining candidates are a
      triage-first default view with drill-down, collapsible advanced sections,
      or regrouping the six peers into three. _(state: planned — design
      -dependent; deliberately not decided while fixing the defect underneath
      it, since the density judgement changes once the layout is honest.)_

      **Three inputs arrived 2026-08-15** from the adversarial UI review, all
      arguing the same decision from different angles and all routed here rather
      than scheduled as engineering: a ranked `Today` landing view (the value
      score and work-unit estimate already exist and are three clicks deep), a
      sortable table instead of ~120px cards for a 76-repo triage screen, and a
      single primary action per row instead of nine equal-weight buttons. Release
      3.5 supplies the trustworthy numbers any of them would render; the choice
      of surface stays here. See
      [the triage](docs/reference/2026-08-15-ui-review-triage.md).

### Lane 0.7 — Roadmap-standard fidelity: split-history awareness (2026-08-08)

Does the standard this product applies to 80+ repos account for a roadmap that
archives completed work to a separate file — the shape this repo uses? Partly.
Nothing penalizes a split repo, but nothing tells one apart from a repo that
deleted its history. The 2026-08-08 survey found **zero** managed repos using
the split layout, so the live risk is the **repair path**, not scoring: repair
would push all 32 roadmap-bearing repos toward in-file history. The intent is
**awareness, not enforcement**. (A separate finding — 28 of 32 use no release
sections at all — is a far larger conformance gap and the reason so many sit at
L2.)

- [ ] **Record whether a repo externalizes its completion history.**
      _(state: planned)_ The contract carries `completedCount` as a required
      field, and a split roadmap reports ~0 forever. No rule reads it today,
      so nothing breaks — but nothing distinguishes "history archived to
      `docs/history/`" from "history deleted", and any future consumer that
      treats `completedCount` as progress would read a well-kept split repo as
      inert. Add an explicit signal (e.g. `historyLocation` / `archiveRef`)
      to [`roadmap-contract.schema.json`](standards/roadmap/roadmap-contract.schema.json),
      set from a pointer link in the roadmap, and surface it in the audit
      payload.
- [x] **Sanction the external-archive pattern in the standard.** _(state:
      planned — documentation)_ `ROADMAP_TEMPLATE.md` Section 6 anticipates
      release sections being "archived or removed" but assumes the surviving
      history stays **in** the roadmap; no part of the standard, schema, or
      the 12 audit rules mentions an external archive file. Document it as a
      supported option with a required pointer convention, so a split repo is
      self-describing rather than merely unpenalized.

### Lane 0.8 — Verification gate integrity (CI audit 2026-08-10)

**Re-homed from Release 3.1 on its closure (2026-08-15):**

- [ ] **[non-blocker]** **No `.gitattributes`, with `core.autocrlf=true`.**
      Byte-level comparisons between tracked copies are non-deterministic
      locally while passing in CI's fresh checkout (surfaced 2026-08-13: 245
      CRLF vs 245 LF, same characters, reported as drift). The sync gate now
      normalises before comparing, but it was the only gate audited; the
      general fix is a `.gitattributes` declaring `text eol=lf`, and the risk
      until then is a gate that reports drift that is not there, or hides
      drift that is. _(state: planned)_
- [ ] **[non-blocker]** The scheduled and operator dispatch paths reach the
      queue through different writers with only one end-to-end test. The
      behavioural divergence was closed in 3.1 (three roads, all gated, scope
      derived); what remains is the coverage asymmetry itself.
      _(state: planned)_

**The gate work closed 2026-08-10 (PRs #102–#107) and is archived.** A merge
had been gated on almost nothing; now `ci-smoke.yml` **invokes
`Invoke-TestSuite.ps1` itself** so CI and local are one list by construction,
both linters fail the build, and `main` requires the `smoke` check with
`enforce_admins` on. Full text:
[the archive](docs/history/completed-releases.md#closed-2026-08-11-archived-from-roadmapmd).

What remains is the debt the ratchets hold, and it is deliberately not a sweep.

**Warning-debt reduction plan (decided 2026-08-10).** The baselines are
controlled debt, not a cleanup backlog — **no blanket lint sweep.** Work lands
as small, behaviorally coherent batches, each ending with `-UpdateBaseline` /
a lowered `--max-warnings` so the ratchet locks the gain. Priority order:

- [x] **P1 — PSSA correctness micro-batch (12 findings, low risk).**
      `PossibleIncorrectComparisonWithNull` 1, `AvoidAssignmentToAutomatic
      Variable` 3, `UseDeclaredVarsMoreThanAssignments` 6,
      `AvoidOverwritingBuiltInCmdlets` 1, `AvoidUsingInvokeExpression` 1.
      Mechanical, each a latent-bug class, one PR. _(done 2026-08-15: all 12
      fixed — `$Event`→`-RepairEvent`/`-EventName`, `$args`→`$refusalArgs`,
      `Write-Log`→`Write-ReconcileLog`, `Invoke-Expression` replaced by an
      exe+args contract on `Resolve-VerifyCommand` with a smoke assertion,
      null flipped left, six dead assignments discarded. Evidence: lint gate
      PASS at 575/587 then baseline rewritten with the five rules removed —
      each now gates at zero; module smoke and api-host smoke exit 0.)_
- [ ] **E1 — ESLint `exhaustive-deps` review (8 findings).** Behavioral, not
      mechanical: each missing dep is either a real staleness bug or a
      deliberate omission that earns a comment. Small enough for one PR.
- [ ] **P2 — empty catch blocks (79), classify then fix.** Guardrail-aligned
      ("never swallow silently"): each site becomes either an annotated
      deliberate best-effort (narrowed catch + comment) or a surfaced
      failure. Batch by module; multiple PRs.
- [ ] **E2 — type the API client (`no-explicit-any`, 123, bulk in
      `apiClient.ts`).** Per endpoint-group batches; the value is contract
      drift caught at typecheck, not style. Lower the ratchet after each.
- [ ] **P3 — plaintext-password params (9).** Design review per surface
      (SecureString vs env-var flow), coupled to the Lane 0.2 TLS work —
      **not** mechanical remediation.
- [ ] **P4 — BOM/PS5.1 hazard (60).** Measure first: which BOM-less files
      contain non-ASCII AND can run under Windows PowerShell 5.1; add BOMs to
      that subset only.
- **Deliberately unscheduled (accepted debt, held at baseline):** the naming
  and style tiers (`UseSingularNouns` 90, `UseOutputTypeCorrectly` 136,
  `UseShouldProcessForStateChangingFunctions` 67, and five smaller rules) —
  renames are call-site churn for zero behavior.
- **Separate lane, never batched mechanically:** ESLint
  `set-state-in-effect` (31) — every site needs individual behavioral review
  because a "fix" can change real render behavior.

---

## 8. Risks and Guardrails

The full list lives in
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md).
Headline guardrails for the active release and near-term roadmap:

- Do not auto-dispatch tasks without a visible readiness model.
- Do not silently mark roadmap items complete based only on code churn.
- Prefer preview-first workflows before write-back or autonomous mutation.
- Preserve genuine completion history when rewriting roadmaps.
- Enforce L3+ roadmap maturity before any dispatch.
- Do not treat an AI-improved README or ROADMAP as accepted until the
  operator reviews the side-by-side diff and explicitly applies it.
- Do not show merge readiness unless the app can identify the PR, latest
  Actions result, validation evidence, and unresolved blockers.
- Do not let dashboard badges become decorative; every badge must drill
  into the source data or explanation that produced it.
- Do not merge automatically; merge must remain an explicit operator action
  after readiness passes.
- **Do not leave a control enabled that cannot succeed.** A disabled control
  names its unmet precondition; an enabled one is a promise.
- **Do not mark an item `[x]` while it still names an outstanding proof.**
  Split it: archive the shipped half, keep the unproven half open.
- **A pull request that ships a capability updates the milestone that claims it,
  in the same pull request.** Recorded 2026-08-15 after
  [PR #134](https://github.com/xfaith4/GitHubRepoManagement/pull/134) shipped a
  tested 306-line module and left all six of its release's milestones reading
  `planned` — the next agent to read the roadmap was one step from rebuilding it.
  Enforced by `Test-RoadmapCapabilityRecord.ps1`, which fails a commit whose
  message claims a release and whose diff touches `backend/` or `scripts/`
  without touching `ROADMAP.md`. A stated rule drifts; a derived one does not.

---

## 9. Roadmap Contract Standard for Managed Repos

The full Roadmap Contract Standard is documented in
[`docs/reference/roadmap-contracts.md`](docs/reference/roadmap-contracts.md)
and shipped as a package under
[`standards/roadmap/`](standards/roadmap/) (template, schema, audit rules,
maturity model, repair prompt), with the publishable copy under
[`spec/roadmap-contract/`](spec/roadmap-contract/). Managed repos should
converge toward the release-oriented format described there.

---

## 10. Definition of Done for Release Execution

A release should not be marked complete unless:

- all checklist items for that release are truly implemented or explicitly
  blocked
- UI elements are connected to real behavior rather than placeholders
- affected docs are updated where workflow or product behavior changed
- logging and error handling are sufficient to diagnose failures
- later releases were not partially started just to create the illusion of
  momentum
- dashboard signals can be traced back to their source data
- preview-first flows have explicit apply/dispatch/submit/merge actions
- validation and smoke coverage exist for new routes or workflows

This roadmap intentionally treats each release as a bounded, agent-usable
execution contract.

---

## 11. Roadmap Structure Validation

Run the validator before handing this file to another coding agent:

```powershell
pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md
```

The check is read-only: release order, missing sections, active-release
pointer/detail mismatches, duplicate headings, archived detail left behind,
oversized future releases, and file-length drift. `-JsonOut` / `-CsvOut` give
machine-readable output; CI runs it with `-FailOnError`, so warnings stay
advisory while structural errors fail the smoke workflow.

**The warnings are load-bearing, not decoration.** `R010-FILE-LENGTH` and
`R013-FUTURE-RELEASE-SIZE` caught this file at 2,020 lines on 2026-08-11 — a
roadmap that could no longer answer "what is the next work item?" without a
long read.

<!-- Release 2.7 Phase A — live submit-PR evidence.
     This note was written, committed, pushed, and opened as a pull request by
     POST /api/roadmap/repair/submit-pr (createPr=true) at 2026-08-09 12:43:32 UTC.
     Its existence in a PR IS the Phase A artifact: it proves the write path
     runs end to end against a real repo, not just the dry-run plan. -->
