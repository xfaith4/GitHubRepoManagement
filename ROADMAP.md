# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 3.2 — Portfolio Scale and Responsiveness**
> **Next active release:** **Release 2.9 — Operator Field Proof and Mobile Completion**
> **Work ordering:** dependency-driven, not insertion order — see
> [Execution Order and Dependencies](#execution-order-and-dependencies)
> **Canonical product direction:** [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
> **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
> **Dated change log:** [`CHANGELOG.md`](CHANGELOG.md)

---

## Current Status (Agent Context)

**Last updated:** 2026-08-11

Releases 0.4 through 2.6, 2.8 and 3.0 are **engineering-complete and archived**,
as is every completed milestone from the releases and lanes still open below.
Their full text lives in
[`docs/history/completed-releases.md`](docs/history/completed-releases.md).

**This file carries open work only.** Every checkbox in it is something still
to do — if an item is `[x]` here it is a mistake, not a record. That rule had
drifted: on 2026-08-11 the file had grown to 2,020 lines, 840 of them completed
detail, and `tools/Test-RoadmapStructure.ps1` was reporting `R010-FILE-LENGTH`
and `R013-FUTURE-RELEASE-SIZE`. The completed detail moved to the archive
**verbatim** — the evidence prose is why later agents stop re-litigating
settled decisions, so it is preserved rather than summarized.

What remains falls into four kinds of work, and they are **not**
interchangeable — mixing them is what previously made the roadmap read as
"everything is done" while real gaps sat unlabelled:

1. **Genuinely unbuilt engineering** — Release 3.2's three remaining scale
   milestones, two mobile surfaces, and the recorded cross-cutting items.
   This is the only kind an autonomous agent can close on its own.
2. **Elevated / hardware / human verification** — needs SYSTEM rights, a
   physical Android phone, or an operator sitting at an authenticated
   Claude Code session. No autonomous test can produce these.
3. **Product / design decisions** — waiting on a judgement, not on time or
   engineering (progressive disclosure; the `Checks: Read` grant).
4. **Calendar-gated accrual** — the 7/90-day trend windows fill only as
   time passes with capture running.

**Current focus (next agent actions), in order:**

- [ ] **Release 3.2 — portfolio scale.** The one release with unblocked
      engineering left, and therefore the default next work. Its performance
      budget landed 2026-08-11, so the remaining three milestones now have a
      declared number to beat instead of an untested claim. Independent of 3.1
      and schedulable in parallel.
- [ ] **Release 3.1 — closed-loop delivery.** Three of four milestones shipped
      2026-08-10; the fourth is a **live full-loop proof** that needs an
      operator session rather than engineering time. Batch it with 2.9's.
- [ ] **Batch the operator-session work (2.9).** Several proofs share one
      setup — an elevated shell covers the watchdog _and_ the service
      installer; one phone session covers 2.5 _and_ 2.6; one authenticated
      shell covers the `claude` run, the `gh agent-task` run, and 3.1's
      full-loop proof. Doing them separately wastes the scarcest resource here.
- [ ] **Lane 0.2's two items need an operator action outside this repository**
      — the PAT's `Checks: Read` grant (optional; the `mergeStateStatus` proxy
      is the working contract) and the portal TLS certificate password, whose
      recovery path is exhausted and needs a regeneration in an elevated
      session.

**Forward arc.** Releases 3.0-3.3 were added 2026-08-08 to describe the
finished product rather than the working one: dispatch that runs (3.0), the
north-star loop closing end to end (3.1), an 80+ repo portfolio that feels
immediate (3.2), and unattended operation (3.3).

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

Render the state inline on each milestone in italics, e.g.:

```markdown
- [x] Add `GET /api/portfolio/assessment` route. _(state: smoke-tested)_
```

**Checkbox rule.** `[x]` means _nothing remains for that item in this
roadmap_. An item whose engineering is complete but whose proof is still
outstanding stays `[ ]` and names the resource it waits on.

**Archive rule (2026-08-11).** A completed item does not stay here. Once `[x]`,
it moves to [the archive](docs/history/completed-releases.md) **verbatim** —
evidence prose intact, because that is what stops the next agent re-litigating
a settled decision — and this file keeps at most a one-line pointer. A release
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
| **2.9**   | **Operator Field Proof and Mobile Completion**                           | `planned` — collects every external-resource residual plus the two unbuilt mobile surfaces |
| 3.0       | Operator-Context Execution                                               | `done` (engineering) — 2026-08-09; see archive. Live proof tracked in 2.9                  |
| **3.1**   | **Closed-Loop Delivery**                                                 | `planned` — rank → dispatch → monitor → Actions → merge readiness → roadmap write-back     |
| **3.2**   | **Portfolio Scale and Responsiveness**                                   | **active** — promoted 2026-08-11; read-path budget done, 3 scale milestones open           |
| **3.3**   | **Steady-State Operation**                                               | `planned` — unattended for months: retention, restore, honest TLS, decision-grade digests  |

> **Note on `.5` numbering.** Release 1.7.5 was a deliberate course-correction
> release between 1.7 and 1.8. Reserve the `.5` pattern for similar course
> corrections; default new work to integer minor releases.

### Execution Order and Dependencies

Release numbers identify scope — they do not dictate sequence. Work through
open items in the order below, and update this section whenever a lane
closes or a new dependency appears.

**Everything that once blocked something else has landed.** Step 0's
unblockers closed 2026-08-08; Release 2.7's two lanes closed 2026-08-09; 3.0's
dispatch runs. No open item is now waiting on another open item — the ordering
below is therefore about **what kind of resource each item needs**, not about
prerequisites.

1. **Release 3.2 — the active release, and the only one an agent can advance
   alone.** Three scale milestones, no external gate.
2. **Release 2.9 mobile completion** — engineering work with no gates; the
   responsive foundation shipped in 2.5.
3. **One batched operator session** — an elevated shell covers the watchdog,
   the service installer and 2.7's freeze-prevention deploy; a phone session
   covers 2.5 _and_ 2.6; one authenticated shell covers the `claude` run, the
   `gh agent-task` run and 3.1's full-loop proof. Batching is the whole point:
   the operator, not the code, is the scarce resource.
4. **Release 3.3 — pick-up work.** Every milestone is independent; take one
   whenever the active release is blocked.
5. **Trend accrual** closes itself as calendar time passes, provided capture
   keeps running.

**Dependency map (open work only):**

| Open item                                            | Depends on                                    | Type                                          |
| ---------------------------------------------------- | --------------------------------------------- | --------------------------------------------- |
| Release 3.2 scale and responsiveness                 | —                                             | none — active; deadline + budget both settled |
| Release 2.9 mobile completion (ergonomics, run list) | —                                             | none — the responsive foundation is shipped   |
| Release 3.3 steady-state operation                   | —                                             | none — independent milestones, any order      |
| Lane 0.2 `Checks: Read`; TLS certificate password    | An operator action outside this repository    | hard — external                               |
| Lane 0.5 tab disclosure; Lane 0.7 archive signal     | A product decision, not engineering time      | hard — design                                 |
| Release 2.9 freeze-prevention deploy (from 2.7)      | An elevated (SYSTEM) Windows install          | hard — privilege; batch with the two below    |
| Release 2.9 watchdog + service-installer proof       | An elevated (SYSTEM) session                  | hard — privilege                              |
| Release 2.9 physical-Android proof (2.5 + 2.6)       | An Android device on the LAN                  | hard — hardware                               |
| Release 2.9 real `claude` + `gh agent-task` runs     | An authenticated operator session             | hard — human; one session covers both         |
| Release 3.1 full-loop proof                          | The same authenticated operator session       | hard — human; batch with the runs above       |
| Release 2.9 GitHub App installation-token exchange   | A registered GitHub App                       | hard — optional; PAT supersedes               |
| Release 2.9 trend accrual (2.3 Ph2)                  | Days of live capture                          | hard, time-gated                              |

---

## 5. Active Release Snapshot

### Active release detail — 3.2 Portfolio Scale and Responsiveness

Release 3.2 was promoted 2026-08-11 when Release 2.7 closed. It is the only
open release whose remaining work an agent can start without an external
resource — 2.9 needs hardware, elevation or a human; 3.1 needs one operator
run; 3.3 is independent pick-up work with no ordering of its own.

The full execution contract for the active release — goal, outcomes,
milestones, acceptance criteria, and out-of-scope — lives in one place,
[Release 3.2 below](#release-32--portfolio-scale-and-responsiveness),
per `ROADMAP_TEMPLATE.md`: the release section is the single source of truth
for its own status. This heading exists so the roadmap validator can resolve
the active-release pointer; it deliberately restates nothing.

**Current focus:** bound per-repo git work with a timeout and a concurrency cap.
Taken next because it is the milestone with the clearest failure mode — seven
sequential unbounded `git` calls per repo, and one that hangs stalls the sweep
until the deadline guard destroys the host — and because it reduces the cold
scan the background-job milestone then has to make observable.

---

## 6. Open Releases

### Release 2.9 — Operator Field Proof and Mobile Completion

**Status:** planned

**Goal:** convert every surface that is `smoke-tested` but still waits on an
external resource into `operator-verified` with durable evidence, and finish the
two mobile surfaces left incomplete under Release 2.5. No new capability — this
closes the honesty gap between "the suite is green" and "this works in the
field."

**Prerequisites:** the mobile milestones have none. Each field-proof milestone
names the one external resource it waits on; none block each other, and several
share a session — one elevated shell covers all three SYSTEM milestones, one
phone session covers both device milestones, one authenticated shell covers both
runner milestones and 3.1's full-loop proof. Batch them: the operator, not the
code, is the scarce resource.

#### Product outcomes

- No milestone is marked complete on an automated suite alone when what it
  claims needs hardware, elevation, credentials, or a human.
- `evidence/` carries a durable record for each proof, so the next agent reads
  the evidence instead of re-litigating whether something works.

#### Engineering milestones

Mobile completion (no gates — build these first):

- [ ] Apply touch ergonomics beyond the Release 2.5 Phase 1 surfaces: ~44px
      minimum touch targets and a tap equivalent for every hover-only
      affordance (tooltips, row actions, rationale popovers) across the
      Phases 2-3 surfaces. _(state: scaffolded — Phase 1 done 2026-07-04;
      the rest was never built)_
- [ ] Add the tap-through mobile agent-run list from the agent-activity
      indicator: status, repo, phase, elapsed time. _(state: planned — the
      indicator ships and `/api/agent-runs` is reachable; only the view is
      missing)_

Field proof — elevated (SYSTEM) session, batch together:

- [ ] **Deploy the Release 2.7 Phase D freeze prevention to the live service.**
      _(state: smoke-tested → needs an elevated Windows install; inherited from
      Release 2.7 when it closed 2026-08-11)_ All three engineering parts ship —
      cache-off regression guards, the per-request work timeout, and scheduled
      `app.db` prune + `VACUUM`. Only the install remains.
- [ ] Run the elevated
      [`Install-PortalWatchdog.ps1`](scripts/service/Install-PortalWatchdog.ps1)
      and confirm a real freeze-and-recover: kill + `Restart-Service
      RepoMgmtPortal`, the action appended to
      `output/logs/service-watchdog.jsonl`, and the `execution.failed` webhook
      fired. _(state: smoke-tested → needs `operator-verified`; decision logic
      and a dry-run against the actual frozen host are already proven)_
- [ ] Operator-verify the reworked
      [`Install-RepoManagementService.ps1`](scripts/Install-RepoManagementService.ps1):
      elevated install / repair / `icacls` / scheduled-task registration, secrets
      from machine env vars, tracked `settings.json` secret-free. _(state:
      smoke-tested → needs `operator-verified`)_

Field proof — physical Android device on the LAN, batch together:

- [ ] Verify the four Release 2.5 workflows on a **physical Android phone**
      (repo health, agent activity, prompt refinement, roadmap dispatch), plus
      real touch input and home-screen install, then confirm the Release 2.6
      clarity affordances on the same device: data-source indicator, per-tab
      subtitles, advanced-filters toggle, orientation overlay. Steps in
      [`lan-mobile-setup.md`](docs/reference/lan-mobile-setup.md). _(state:
      both smoke-tested at an emulated 390px viewport → need
      `operator-verified` on real hardware)_

Field proof — human / credential / calendar:

- [ ] Operator-verify Release 2.1 against the live workspace and record the
      sign-off, closing the release formally. _(state: smoke-tested against
      live data — `output/app.db`, the real 68-repo `F:\Development` scan →
      needs a recorded human sign-off)_
- [ ] Execute one real `claude` run through
      [`Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1)
      in the operator's authenticated session: claim → branch → run →
      verify → commit → `awaiting-review`. Closes the Release 2.8 residual.
      _(state: smoke-tested dry-run E2E → needs `operator-verified`)_
- [ ] Same session: one real **copilot** entry through the runner —
      `gh agent-task create` reaches a live task, URL in the run summary.
      Closes the Release 3.0 residual. _(state: smoke-tested → needs
      `operator-verified`. Requires `gh auth login` and **no**
      `GH_TOKEN`/`GITHUB_TOKEN` set; gh ignores stored OAuth when one is.)_
- [ ] Same session: **Release 3.1's full-loop proof** — one real item travelling
      rank → dispatch → run → PR → merge → write-back, recorded in `evidence/`.
      It needs exactly the session the two runs above need.
- [ ] Operator-verify the auth + shared-LAN path so automation runs on a bound,
      authenticated host. _(state: planned — carried over from 2.7 Phase D)_
- [ ] (Optional) Prove live GitHub App installation-token exchange
      (`Get-GitHubAppInstallationToken`) + auto-refresh, closing the Release 2.2
      residual. _(state: planned — not required; the PAT path supersedes it)_
- [ ] Let the Release 2.3 Phase 2 trend windows accrue: confirm
      `GET /api/portfolio/trend` reports a real 7-day, then 90-day, window.
      _(state: smoke-tested — rollup logic is live and `status=history-backed`;
      only calendar time is missing. Keep
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

### Release 3.1 — Closed-Loop Delivery

**Status:** planned — 3 of 4 milestones shipped 2026-08-10 (the work-item
trace, the completion-edit generator, and the merge-evidence gate). The fourth
is the live full-loop proof, which needs an operator session rather than
engineering time; batch it with Release 2.9's. The status token
stays `planned` because `active` means _the single dispatch target_ and
Release 2.7 still holds it (section 5); it does not mean "no work has
started". **[non-blocker]** 2.7's only open item is an elevated Windows
install, so whether it should still be the active release is a governance
call for the next roadmap pass, not something this release decides.

**Goal:** close the north-star loop end to end, repeatedly, with explicit
operator gates at apply, dispatch, and merge. Today the console can rank work
and prepare a prompt, and it can read merge readiness, but no single work item
has ever travelled the whole chain — so the loop's real failure modes are
unknown.

**Prerequisites:** all but one are met. Release 2.7 Phase A (the live submit-PR
proof) and Release 3.0 (a dispatch that runs) both closed 2026-08-09. Only the
PAT's `Checks: Read` grant (Lane 0.2) is outstanding, and it affects per-check
merge detail rather than the loop — `mergeStateStatus` already answers the
merge-readiness question this release gates on.

#### Product outcomes

- One roadmap item is carried from "ranked highest value" to "merged, with the
  managed repo's roadmap updated" without a human stitching the steps.
- Every stage transition is inspectable after the fact from one trace, rather
  than reconstructed from four ledgers.
- Roadmap write-back is preview-first: the console proposes the completion
  edit and the operator applies it.

#### Engineering milestones

**Three of four shipped 2026-08-10 and are archived:** the per-work-item trace
(`GET /api/trace/{id}`, joining all seven stages from any id the chain minted),
the completion-edit generator behind `POST /api/roadmap/write-back/preview`, and
the merge-evidence gate that refuses nine shapes which are not completion. Full
text and evidence:
[the archive](docs/history/completed-releases.md#closed-2026-08-11-archived-from-roadmapmd).

- [ ] Record a full-loop proof for one real item in `evidence/`, naming each
      stage's artifact. _(state: blocked — needs an operator session, not
      engineering time)_ Every stage is now built and gated, but the proof
      requires one real item to travel the chain: the operator runner must
      execute the dispatched task (`claude` or `gh agent-task`, both of which
      need an authenticated operator session — the same gate Release 2.9 and
      3.0's live round trips wait on), a PR must open and merge, and the
      write-back must apply against real merge evidence. Batch it with 2.9's
      operator session rather than scheduling a separate one.

#### Acceptance criteria

- A single `runId` resolves to every stage artifact through one route.
- A write-back attempt with no merge evidence is refused and says why.
- The loop proof exists in `evidence/` with the PR, the Actions result, and
  the applied roadmap diff.

#### Out of scope

- Automatic merge — merge stays an explicit operator action after readiness
  passes.
- Multi-repo parallel dispatch; one item end to end first.

---

### Release 3.2 — Portfolio Scale and Responsiveness

**Status:** active — promoted 2026-08-11 when Release 2.7 closed. It is the
only open release with unblocked engineering: 2.9 waits on hardware, elevation
and human sessions, 3.1 waits on one operator run, and 3.3 is independent
pick-up work. 1 of 4 milestones shipped (the read-path performance budget).

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
**Bounded per-repo git work shipped 2026-08-11 and is archived** — a per-call
timeout plus a whole-repo budget, so no single repository can stall a sweep. It
costs ~16% on a healthy portfolio (57,660ms → 67,015ms, output identical),
accepted deliberately since three P0 outages here came from that stall class.
[Detail](docs/history/completed-releases.md#closed-2026-08-11-archived-from-roadmapmd).

- [ ] **Re-enable parallel git collection in the sweep.** _(state: built and
      benchmarked, then deliberately withheld 2026-08-11)_ A runspace-pool
      collector was faster standalone (61.9s → 48.0s, output identical) but
      **pathological inside the API host**: ~2 repositories in five minutes
      (~300x slower), so the request hit the 900s deadline and `FailFast` killed
      the process while the stale heartbeat would have restarted a healthy scan.
      **Root cause not established** — worker-runspace module discovery was
      measured and ruled out (81ms vs 19ms). Do not re-enable without an in-host
      reproduction; the stall guarantee does not depend on it.

- [ ] Virtualize the repo grid so row count stops driving render cost.
      _(state: planned)_ Pairs with the `Dashboard.tsx` non-blocker below —
      both are render cost on the same screen.
- [ ] **[non-blocker]** `Dashboard.tsx` is **1,752 lines** (2,519 → 2,308 after
      the Phase D extractions → 1,752 on 2026-08-10, when the ~600-line Insights
      block became [`InsightsView.tsx`](frontend/components/InsightsView.tsx)).
      What remains is ~1,000 lines of hooks and handlers above the return — a
      different shape of problem from the JSX blocks already extracted, and one
      with no user-visible symptom driving it. _(state: planned — inherited from
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

**Validation plan:** run `npm test` (`scripts/Invoke-TestSuite.ps1`, the same
17-gate list `ci-smoke.yml` invokes) and confirm exit 0. Each milestone must
additionally land its own gate rather than a claim: the bounded-git work asserts
that a hung `git` call is abandoned at its timeout instead of stalling the sweep,
the background-job work asserts progress is observable and a cancel is honored
mid-scan, and both must keep the read-path budget assertions green — a scale
change that regresses a warm read has traded the wrong thing.

**Risks and blockers:**

- **Risk — a scale change breaks a scan path that has already caused three P0
  outages.** Lane 0.9 records the pattern: each fix targeted the named instance
  and the same outage returned through a sibling. Every change here must keep
  the progress heartbeat publishing from **inside** the loop it describes, or a
  healthy scan reads as frozen and the watchdog restarts it mid-flight.
- **Risk — parallelizing git work changes scan output, not just its speed.**
  A concurrency cap must not reorder or drop repositories; the sweep's result
  has to be identical to the sequential one, which is an assertion, not a hope.
- **Risk — a background scan job needs a runspace in a single-threaded host.**
  The pattern exists already (`Start-RequestDeadlineWatchdog`), but a job that
  outlives its request must not leave an orphaned operation marker behind —
  `Complete-PortalOperation` has to run on the failure path too.

**Dependencies:** the persistent index written by
`Save-PortfolioIndexArtifacts` (1.7.5), the operation heartbeat
([`OperationHeartbeat.ps1`](backend/api-host/OperationHeartbeat.ps1), Lane 0.9),
the request-deadline tier classifier
([`RequestDeadline.ps1`](backend/api-host/RequestDeadline.ps1), Lane 0.4), and
the read-path budget
([`PerformanceBudget.ps1`](backend/api-host/PerformanceBudget.ps1), shipped
2026-08-11) that gives the remaining milestones a number to beat.

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

## 7. Cross-Cutting Engineering Work

Continuous, not release-scoped. **This section carries open work only.**
Completed cross-cutting items were archived 2026-08-07 — see
[the archive](docs/history/completed-releases.md#cross-cutting-engineering-work-completed-items) —
and again 2026-08-08, when Lane 0.1 closed entirely and Lanes 0.2, 0.4, 0.5,
and 0.6 shed their closed items to
[the 2026-08-08 batch](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).

### Lane 0.2 — Credential freshness

- [ ] **Decide the PAT `Checks: Read` grant — it is optional, not required.**
      _(state: planned — non-blocker; scope audit 2026-08-10)_ The token 403s
      on `repos/{owner}/{repo}/commits/{ref}/check-runs` and on GraphQL
      `statusCheckRollup`. **Nothing in the product depends on it**: the
      merge-readiness feature reads `mergeable_state` from the Pulls API, and
      the merge loop's `mergeStateStatus` proxy works without it — both
      verified in code and in practice (six PRs merged 2026-08-10 on the
      proxy alone, including through required-check branch protection).
      Granting it adds only development-workflow detail: `gh pr checks <n>
      --watch` (live per-check names/durations) and direct check-run reads
      for verifying which check ran on a ref. Read-only, single-repo-scoped,
      low risk — but under a minimal-permissions policy it is legitimate to
      **decline permanently** and keep the proxy; if declined, close this
      item as "decided: proxy is the contract". Metadata, Contents, Pull
      requests, and Actions reads all pass (verified 2026-08-07).
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

Every item in these three lanes shipped, so they carry no open work and their
detail moved to
[the archive](docs/history/completed-releases.md#closed-2026-08-11-archived-from-roadmapmd)
on 2026-08-11. Kept as named headings rather than deleted, because each is
referenced by name from surviving lanes and from the completed-release history:

- **Lane 0.3 — layout follow-ups** (closed 2026-08-09): machine-specific path
  defaults, the documented maturity caps the auditor never applied, `CLAUDE.md`'s
  dangling imports, and the structure linter's own template conformance.
- **Lane 0.4 — smoke coverage gaps** (closed 2026-08-09): the cold-scan request
  deadline (the extended-tier decision Release 3.2 inherits) and the root
  worklog archival convention, now enforced by a tripwire.
- **Lane 0.6 — silent workspace-path failure** (closed 2026-08-09): the
  zero-scope action hint now names the missing root instead of telling the
  operator to scan a workspace they already configured.

### Lane 0.9 — Portal restart loop: the watchdog was killing healthy scans (P0, 2026-08-10)

**The incident closed 2026-08-10 across four passes and is archived.** Two
guards with different budgets: Lane 0.4 raised the in-process request deadline
to 900s for scan routes while the external watchdog kept ~180s, so every full
scan was guaranteed to be force-restarted — 10 times in one stretch. The fix
made **progress, not liveness or CPU**, the contract. Three of the four passes
were the same lesson: the first instrumented one route, the second covered the
routes but not the work inside them, the third found `/api/status` on the wrong
deadline tier. **Fixing the named instance instead of the pattern is this
repo's most expensive recurring mistake** — every tripwire here now derives its
scope from a classifier or the AST rather than a hand-maintained list.

- [ ] **Insights has no way to run the assessment it tells you to run.**
      _(state: planned — surfaced with the 2026-08-10 bug report)_ Portfolio
      Analytics says "Refresh the portfolio assessment to seed the Release 2.3
      trend view" and Documentation Health says it is "unavailable until a
      portfolio assessment succeeds", but the tab offers no control that runs
      one — `Retry` only re-fetches the existing result. Instructions the
      surface cannot carry out are worse than no instructions. Give Insights a
      real "Run assessment" action (or point explicitly at the control that
      does it).
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
- [ ] **Replace the bare `Failed to fetch` screen with an actionable retry
      state.** _(state: planned — recorded 2026-08-10)_ When the backend stops
      answering, `Dashboard.tsx`'s top-level `error && repos.length === 0`
      branch renders the raw exception string and nothing else — no retry, no
      explanation, no indication the server is the problem. (The Lane 0.5 error
      boundary does not cover this: it catches render throws, not rejected
      fetches.) Give it a retry affordance and copy that distinguishes "backend
      unreachable" from "no repositories configured".

### Lane 0.5 — Portal UX follow-ups (empty-state audit 2026-08-08)

Three of four items closed 2026-08-10 and are archived: the missing error
boundary that let one render throw white-screen the whole portal, bulk-scope
confirmation on mutating actions, and the tab-inversion defect underneath the
"six tabs is dense" complaint (Insights was rendering _above_ its own tab bar).

- [ ] **[non-blocker]** The wider progressive-disclosure question is still
      open, and is now a smaller one. With Insights no longer competing for the
      same vertical space as the tab strip, the remaining candidates are a
      triage-first default view with drill-down, collapsible advanced sections,
      or regrouping the six peers into three. _(state: planned — design
      -dependent; deliberately not decided while fixing the defect underneath
      it, since the density judgement changes once the layout is honest.)_

### Lane 0.7 — Roadmap-standard fidelity: split-history awareness (2026-08-08)

Does the standard this product applies to 80+ repos account for a roadmap that
archives completed work to a separate file — the shape this repo uses, and used
again on 2026-08-11? Partly. The gaps are asymmetric: nothing penalizes a split
repo, but nothing can tell one apart from a repo that simply deleted its
history. **The 2026-08-08 survey found zero managed repos using the split
layout** (32 of 89 have a root `ROADMAP.md`; 15 inline-only, 15 with no history,
2 in-file), so this repo is the only instance in the estate — which makes the
**repair path** the live risk, not scoring: repair would push all 32 toward
in-file history, and would do the same to any repo that later adopts the split.
The intent is **awareness, not enforcement** — the split keeps an agent's
context focused, so the standard should recognize and preserve it, never
"correct" it. (A separate finding, that 28 of 32 repos use no release sections
at all, is a far larger conformance gap than history placement and the reason so
many sit at L2. The evaluator-divergence finding closed 2026-08-08.)

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
- [ ] **Sanction the external-archive pattern in the standard.** _(state:
      planned — documentation)_ `ROADMAP_TEMPLATE.md` Section 6 anticipates
      release sections being "archived or removed" but assumes the surviving
      history stays **in** the roadmap; no part of the standard, schema, or
      the 12 audit rules mentions an external archive file. Document it as a
      supported option with a required pointer convention, so a split repo is
      self-describing rather than merely unpenalized.

### Lane 0.8 — Verification gate integrity (CI audit 2026-08-10)

**The gate work closed 2026-08-10 (PRs #102–#107) and is archived.** The audit
found that a merge was gated on almost nothing — the frontend had no gate
anywhere, `ci.yml` was a no-op green check that still counted toward `CLEAN`,
no linter ran, and `main` had no branch protection. All four are fixed:
`ci-smoke.yml` **invokes `Invoke-TestSuite.ps1` itself** so CI and local are one
list by construction, both linters fail the build, and `main` requires the
`smoke` check with `enforce_admins` on. `mergeStateStatus: CLEAN` is
enforcement now, not convention — proven in anger when PR #107 sat `BLOCKED`
until its required check reported `success`. Full text:
[the archive](docs/history/completed-releases.md#closed-2026-08-11-archived-from-roadmapmd).

What remains is the debt the ratchets hold, and it is deliberately not a sweep.

**Warning-debt reduction plan (decided 2026-08-10).** The baselines are
controlled debt, not a cleanup backlog — **no blanket lint sweep.** Work lands
as small, behaviorally coherent batches, each ending with `-UpdateBaseline` /
a lowered `--max-warnings` so the ratchet locks the gain. Priority order:

- [ ] **P1 — PSSA correctness micro-batch (12 findings, low risk).**
      `PossibleIncorrectComparisonWithNull` 1, `AvoidAssignmentToAutomatic
      Variable` 3, `UseDeclaredVarsMoreThanAssignments` 6,
      `AvoidOverwritingBuiltInCmdlets` 1, `AvoidUsingInvokeExpression` 1.
      Mechanical, each a latent-bug class, one PR.
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
- **Deliberately unscheduled (accepted debt, held at baseline):** naming and
  style tiers — `UseSingularNouns` 90 / `UseApprovedVerbs` 18 (renames are
  call-site churn for zero behavior), `UseOutputTypeCorrectly` 136,
  `UseShouldProcessForStateChangingFunctions` 67,
  `AvoidUsingPositionalParameters` 34, `UseUsingScopeModifierInNewRunspaces`
  44, `ReviewUnusedParameter` 26, `ProvideCommentHelp` 18.
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
- **Do not mark an item `[x]` while it still names an outstanding proof.**
  Split it: archive the shipped half, keep the unproven half open.

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

Run the lightweight roadmap validator before handing this file to another
coding agent:

```powershell
pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md
```

The check is read-only. It reports release-order warnings, missing release
sections, active-release pointer/detail mismatches, duplicate headings,
completed-release detail that belongs in the archive, oversized future release
sections, file-length drift, and other obvious execution-roadmap issues. Add
`-JsonOut` / `-CsvOut` for machine-readable output. CI runs the same script
with `-FailOnError`, so warnings stay advisory while structural errors fail the
smoke workflow.

**The warnings are load-bearing, not decoration.** `R010-FILE-LENGTH` and
`R013-FUTURE-RELEASE-SIZE` are what caught this file at 2,020 lines on
2026-08-11, 840 of them completed detail — a roadmap that had stopped being
able to answer "what is the next concrete work item?" without a long read.

<!-- Release 2.7 Phase A — live submit-PR evidence.
     This note was written, committed, pushed, and opened as a pull request by
     POST /api/roadmap/repair/submit-pr (createPr=true) at 2026-08-09 12:43:32 UTC.
     Its existence in a PR IS the Phase A artifact: it proves the write path
     runs end to end against a real repo, not just the dry-run plan. -->
