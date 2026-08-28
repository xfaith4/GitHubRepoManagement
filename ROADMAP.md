# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 2.9 — Operator Field Proof + Mobile Completion**
> **Next active release:** **Release 3.6 — Every Repository Gets an Outcome** is in **`validation`** — engineering complete 2026-08-27, all six milestones `smoke-tested` and every acceptance criterion gated; only operator verification remains, batched with 2.9. The next engineering release is **Release 3.7 — Portfolio Value Proof**, where ten real repositories decide the 80+ rollout
> **Work ordering:** dependency-driven, not insertion order — see
> [Execution Order and Dependencies](#execution-order-and-dependencies)
> **Canonical product direction:** [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
> **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
> **Dated change log:** [`CHANGELOG.md`](CHANGELOG.md)

---

## Current Status (Agent Context)

**Last updated:** 2026-08-27

Releases 0.4 through 2.6, 2.8 and 3.0 are **engineering-complete and archived**,
as is every completed milestone from the releases and lanes still open below.
Their full text lives in
[`docs/history/completed-releases.md`](docs/history/completed-releases.md).

**This file carries open work only.** Every checkbox in it is something still
to do — if an item is `[x]` here it is a mistake, not a record (rule restored
by the 2026-08-11 archive pass, recorded in `CHANGELOG.md`).

What remains falls into four kinds of work that are **not** interchangeable —
mixing them once made the roadmap read "everything is done" over real gaps:

1. **Genuinely unbuilt engineering** — Release 3.7's four milestones (Release
   3.6's six closed 2026-08-27) and the recorded cross-cutting items. This is
   the only kind an autonomous agent can close on its own.
2. **Elevated / hardware / human verification** — SYSTEM rights, a physical
   Android phone, or an operator at an authenticated session; no autonomous
   test can produce these.
3. **Product / design decisions** — waiting on a judgement, not on time or
   engineering (progressive disclosure; the `Checks: Read` grant).
4. **Calendar-gated accrual** — the 7/90-day trend windows fill only as
   time passes with capture running.

**Priority reset — 2026-08-11** (mobile deferred until a PC workflow ran to
completion) was satisfied and lifted 2026-08-19 — narrative [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

**Product lens — 2026-08-23.** Every remaining item is ranked on operational
efficiency and actionable improvement, under one principle: **the product does
not prescribe what a repository should become; it identifies and strengthens
the foundations that allow each repository to succeed at what it is intended
to be.** Full statement and admission rule in §2; it resequenced Release 2.9
and defined Releases 3.6 and 3.7.

**Current focus (next agent actions), in order:**

- [ ] **Release 3.7 — Portfolio Value Proof** is the next engineering release
      (§6). Release 3.6 finished its engineering 2026-08-27 — all six
      milestones `smoke-tested`, every acceptance criterion gated — so the
      product now reaches a conclusion for every repository, ranks what to do
      first, and measures its own leverage. 3.7 turns that on ten real
      repositories chosen by kind, and decides the 80+ rollout with recorded
      numbers. It needs Ben for the approvals, not for the engineering.
- [ ] **Operator-verify Release 3.6** — eyes on the live portal for the
      `Today` landing, the outcome card, and the Insights leverage panel. No
      agent may claim it; batch it with the 2.9 operator session below.
- [ ] **Batch the remaining operator-session work (2.9).** An elevated shell
      covers the watchdog _and_ the service installer; one authenticated shell
      covers the `gh agent-task` run and the re-homed live-portal proofs; the
      phone proof rides the same visit when the device is on the LAN.
- [ ] **Lane 0.2's two items need an operator action outside this repository**
      — the PAT's `Checks: Read` grant (optional; the `mergeStateStatus` proxy
      is the working contract) and the portal TLS certificate password, whose
      recovery path is exhausted and needs a regeneration in an elevated
      session.

**Forward arc.** Releases 3.0-3.5 describe the finished product: dispatch that
runs, the loop closing legibly and without a hand-off, numbers an operator can
act on, an 80+ repo portfolio that feels immediate, unattended operation.
Release 3.6 extends it to "every repository ends with an explainable
conclusion"; Release 3.7 makes the product prove, on ten real repositories,
that it returns more time than it takes.

---

## 1. What This Document Is

This is the **active execution roadmap**. Its job is to answer two questions
for any operator or coding agent:

1. What is the current active release?
2. What is the next concrete work item?

Long-form product direction (thesis, principles, north-star workflow, risks,
guardrails) lives in
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
and is summarized below in section 2. Every completed release lives, verbatim,
in [`docs/history/completed-releases.md`](docs/history/completed-releases.md);
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

**Product lens (2026-08-23) — the principle every remaining item is ranked
against.** The product does not prescribe what a repository should become. It
identifies and strengthens the foundations that allow each repository to
succeed at what it is intended to be. Five **foundation domains** are the
starting set — documentation, purpose, planning, structure, and evidence of
intentional engineering — refinable as the product meets new repository types
and operating models, never a fixed scoring taxonomy. Every repository ends
with an **explainable conclusion**: _strengthen_ (with a preview-first next
action), _appropriate as-is_ (healthy, intentionally minimal, externally
managed, archived, or out of scope — and the product says why), or
_insufficiently understood_ (naming what the product would need). Remaining
work is prioritized on operational efficiency and actionable improvement:
purpose obvious from the first interaction, and discovery → remediation as
one workflow that says what was found, why it matters, and what can be
improved. **Admission rule for every item below: one hour spent on this
product must save more than one hour across the portfolio it manages.** An
item that only makes the product better at managing, validating, or
describing itself is maintenance, not roadmap work.

For the full thesis, ten core questions, foundation domains, principles,
risks, and guardrails, see
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
| **2.9**   | **Operator Field Proof + Mobile Completion**                             | **active** — promoted 2026-08-19; mobile UN-DEFERRED (its resume condition was met)        |
| 3.0       | Operator-Context Execution                                               | `done` (engineering) — 2026-08-09; see archive. Live proof tracked in 2.9                  |
| 3.1       | Closed-Loop Delivery                                                     | `done` 2026-08-15 — manual loop proof recorded; portal + scheduled proofs re-homed to 2.9  |
| 3.2       | Portfolio Scale and Responsiveness                                       | `done` 2026-08-19 — budget + bounded sweep + observable/cancellable scan + render bound    |
| 3.3       | Steady-State Operation                                                   | `done` 2026-08-19 — retention, rehearsed restore, honest transport, decision-grade exports |
| **3.4**   | **The Delivery Loop Closes**                                             | `done` 2026-08-15 — six milestones + the full-loop proof, driven live and operator-verified |
| 3.5       | Trustworthy Surfaces (UI Quality)                                        | `done` 2026-08-17 — all seven milestones; trust-report per finding; operator sign-off in 2.9 |
| **3.6**   | **Every Repository Gets an Outcome**                                     | **`validation`** - engineering complete 2026-08-27; operator proof batches with 2.9        |
| **3.7**   | **Portfolio Value Proof**                                                | **`planned`** 2026-08-23 — follows 3.6; ten real repositories decide the 80+ rollout       |

> **Note on `.5` numbering.** Reserve it for course corrections like 1.7.5;
> default new work to integer minor releases.

### Execution Order and Dependencies

Release numbers identify scope — they do not dictate sequence. Work through
open items in the order below, and update this section whenever a lane
closes or a new dependency appears.

**Everything that once blocked something else has landed.** No open item waits
on another open item — the ordering below is about **what kind of resource
each item needs**, not about prerequisites.

1. **Release 3.7 — Portfolio Value Proof** is the next engineering
   release (execution contract in §6). Its four milestones are the only
   genuinely unbuilt engineering left: Release 3.6 finished 2026-08-27 with
   all six milestones `smoke-tested` and every acceptance criterion gated, so
   the product now concludes for every repository, ranks what to do first,
   and measures its own leverage. 3.7 needs Ben for the approvals, not for
   the engineering. Every release from 1.x through 3.6 is engineering-closed;
   new work is still proposed as a release with its own contract, never
   appended to a closed one.
2. **Release 2.9 — the active release.** Its engineering half closed
   2026-08-26 (archived); what remains is the operator half, batched and
   waiting on Ben's presence at the machine.
3. **Operator-verify Release 3.6** — the `Today` landing, the outcome card
   and the Insights leverage panel, seen on the live portal. Engineering is
   closed; only eyes remain, and they batch with the session below.
4. **One batched operator session** — an elevated shell covers the watchdog,
   the service installer and 2.7's freeze-prevention deploy; one authenticated
   shell covers the `gh agent-task` run and the re-homed 3.1/3.5 live-portal
   proofs. Batching is the whole point: the operator, not the code, is the
   scarce resource.
5. **Trend accrual** closes itself as calendar time passes, provided capture
   keeps running.
6. **Mobile completion (2.9)** — un-deferred 2026-08-19 when its resume
   condition was met; both engineering items shipped the same day (archived),
   and the physical-Android proof rides the operator batch above.

**Dependency map (open work only):**

| Open item                                            | Depends on                                    | Type                                          |
| ---------------------------------------------------- | --------------------------------------------- | --------------------------------------------- |
| Release 3.6 operator verification                    | Eyes on the live portal (batch with 2.9)      | hard - human; engineering is done             |
| Release 3.7 Portfolio Value Proof                    | Release 3.6; operator approvals               | soft — sequence; engineering + operator       |
| Lane 0.2 `Checks: Read`; TLS certificate password    | An operator action outside this repository    | hard — external                               |
| Lane 0.5 tab disclosure; Lane 0.7 archive signal     | A product decision, not engineering time      | hard — design                                 |
| Release 2.9 freeze-prevention deploy (from 2.7)      | An elevated (SYSTEM) Windows install          | hard — privilege; batch with the two below    |
| Release 2.9 watchdog + service-installer proof       | An elevated (SYSTEM) session                  | hard — privilege                              |
| Release 2.9 physical-Android proof (2.5 + 2.6)       | The operator's Galaxy S24 Ultra on the LAN    | hard — hardware; the software is ready for it |
| Release 2.9 real `claude` + `gh agent-task` runs     | An authenticated operator session             | hard — human; one session covers both         |
| Release 2.9 re-homed 3.1 proofs (portal + schedule)  | The same authenticated operator session       | hard — human; batch with the runs above       |
| Release 2.9 GitHub App installation-token exchange   | A registered GitHub App                       | hard — optional; PAT supersedes               |
| Release 2.9 trend accrual (2.3 Ph2)                  | Days of live capture                          | hard, time-gated                              |

---

## 5. Active Release Snapshot

### Active release detail — 2.9 Operator Field Proof + Mobile Completion

Release 2.9 became the active release 2026-08-19. Its two halves have opposite
shapes: **the operator half waits on Ben and cannot be advanced by an agent**
(SYSTEM rights, a physical device, eyes on a browser, an interactive
credential prompt — listed, batched, ready), and **the engineering half is
closed** — the three foundations-first items resequenced 2026-08-23 closed
2026-08-26 (archived), as did the two mobile engineering items on 2026-08-19.

The full execution contract lives in one place,
[Release 2.9 below](#release-29--operator-field-proof--mobile-completion); this
heading exists so the validator can resolve the active-release pointer.

**Current focus:** the operator batch — it rides Ben's next session at the
machine. The engineering half is closed: the three foundations-first items
(the two readiness gates that disagreed about the same repo, the two routes
that named one concept two ways, the L1/L2 repair path) closed 2026-08-26
([evidence](evidence/verified/release-2.9-foundations-closed-2026-08-26.md));
the two mobile engineering items shipped 2026-08-19. Engineering attention
moves to Release 3.6.

---

## 6. Open Releases

### Release 2.9 — Operator Field Proof + Mobile Completion

**Status:** ACTIVE — promoted 2026-08-19 when Release 3.3 closed and left no
unblocked engineering release behind it. Mobile completion is **un-deferred**
in the same move: its 2026-08-11 resume condition (a PC workflow that runs to
completion) has been met three times over.

**Goal:** convert every surface that is `smoke-tested` but still waits on an
external resource into `operator-verified` with durable evidence. (The three
foundations-first engineering items closed 2026-08-26.) No new capability —
this closes the honesty gap between "the suite is green" and "this works in
the field."

**Prerequisites:** each field-proof milestone names the one external resource
it waits on; none block each other, and several share a session. Batch them:
the operator, not the code, is the scarce resource.

**Resequenced 2026-08-23 under the product lens (§2), closed 2026-08-26.**
Three items that had sat under _Known issues_ led the engineering milestones
because they are what makes a finding explainable — the preconditions in
substance for Release 3.6. They shipped in PR #184 and closed when CI Smoke
proved the canonical module and api-host smoke green; the three items are
[archived in completed-releases.md](docs/history/completed-releases.md#foundations-first-items--closed-2026-08-26).

#### Product outcomes

- No milestone is marked complete on an automated suite alone when what it
  claims needs hardware, elevation, credentials, or a human; `evidence/`
  carries a durable record for each proof, so the next agent reads it instead
  of re-litigating whether something works.

#### Engineering milestones

**Foundations first — resequenced 2026-08-23, closed 2026-08-26.** The
disagreeing readiness gates, the two-names-one-concept routes, and the L1/L2
repair path all shipped in PR #184 (`ba8ffc7`) and closed `smoke-tested`
when CI Smoke run 32949331713 proved the canonical module and api-host smoke
green; [archived](docs/history/completed-releases.md#foundations-first-items--closed-2026-08-26),
[evidence](evidence/verified/release-2.9-foundations-closed-2026-08-26.md).

**Mobile completion — un-deferred 2026-08-19** once the delivery loop had run
end to end three times (PRs #140, #142, scheduled INcendiary#7). The two
engineering items shipped the same day (archived below); the third needs the
operator's device on the LAN.

- Touch ergonomics (device-keyed ~44px floor + `DefinitionHint`) and the tap-through agent-run list (`AgentRunSheet`) — both `smoke-tested` 2026-08-19; [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- [ ] Verify the four Release 2.5 workflows and the Release 2.6
      clarity affordances on a **physical Android phone**, per
      [`lan-mobile-setup.md`](docs/reference/lan-mobile-setup.md). _(state: both
      smoke-tested at an emulated 390px viewport → need real hardware)_

**Field proof — one elevated (SYSTEM) session covers all three:**

- [ ] Deploy the Release 2.7 Phase D freeze prevention to the live service —
      only the install remains. **Measured 2026-08-20:** the running service
      is missing **4 of 52** declared GET routes (it predates Release 3.5);
      one elevated command upgrades it
      (`Install-RepoManagementService.ps1 -Action Repair`) and
      [`Test-LiveServiceCurrency.ps1`](scripts/Test-LiveServiceCurrency.ps1)
      proves whether it landed rather than trusting a health check. What
      exists:
      [`Install-RepoManagementService.ps1`](scripts/Install-RepoManagementService.ps1),
      [`Install-PortalWatchdog.ps1`](scripts/service/Install-PortalWatchdog.ps1),
      [`Watch-PortalHealth.ps1`](scripts/service/Watch-PortalHealth.ps1),
      covered by the module smoke's installer and watchdog gates. _(state:
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

- One real `claude` run through the runner — `operator-verified`, proven three times (PRs #140/#142, scheduled 2026-08-18); [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- [ ] One real **copilot** entry through the runner — `gh agent-task create`
      reaches a live task, URL in the run summary. Closes the Release 3.0
      residual. _(state: smoke-tested. Requires `gh auth login` and **no**
      `GH_TOKEN`/`GITHUB_TOKEN` set; gh ignores stored OAuth when one is.)_
- Release 3.1's scheduled-trigger loop proof — `operator-verified` 2026-08-18 ([evidence](evidence/verified/scheduled-loop-proof-2026-08-18.md)); [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- [ ] Operator-verify the Release 3.1 empty-room gate against the live portal
      (the refusal, the disabled approve controls, the stranded badge). What
      exists:
      [`Automation.RunnerPresence.ps1`](backend/modules/automation/Automation.RunnerPresence.ps1)
      and [`runnerPresence.ts`](frontend/lib/runnerPresence.ts), both gated.
      Only eyes on the live portal remain.
      _(state: smoke-tested; re-homed from 3.1 on closure)_
- [ ] Operator-verify Release 3.1 engine attribution on the live portal (the
      `engine` block above the findings, `providerId` null for rule engines).
      What exists:
      [`RepositoryImprovement.Workflow.ps1`](backend/modules/docaudit/RepositoryImprovement.Workflow.ps1)
      and [`AiDocImprovement.ps1`](backend/modules/ai/AiDocImprovement.ps1).
      _(state: smoke-tested; re-homed from 3.1 on closure)_
- [ ] Operator-verify Release 3.5 on the live portal — the before/after
      screenshots of every tab the trust report describes, the scope toggle,
      the runner pill, and the async panels under a real slow backend. The
      per-finding record of what shipped is
      [`trust-report.md`](docs/reference/trust-report.md); this item is the
      eyes-on half.
      _(state: smoke-tested; re-homed from 3.5 on closure 2026-08-17)_

**Field proof — credential / calendar:**

- Release 2.1 operator sign-off — `operator-verified` 2026-08-18 against the live `output/app.db`; [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- [ ] Operator-verify the auth + shared-LAN path so automation runs on a bound,
      authenticated host. _(state: planned — carried over from 2.7 Phase D)_
- [ ] (Optional) Prove live GitHub App installation-token exchange + refresh,
      closing the Release 2.2 residual. _(state: planned — the PAT supersedes)_
- [ ] Let the Release 2.3 Phase 2 trend windows accrue: `GET /api/portfolio/trend`
      reports a real 7-day, then 90-day, window. _(state: 7-day closed by
      accrual 2026-08-18, `availableDays: 20`, verified live; 90-day filling
      (20/90) — keep
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
- The visible and enforced readiness models agree for every repo, one concept
  carries one name across `/api/roadmap/audit` and `/api/portfolio/assessment`,
  and an L1/L2 fixture repo reaches a preview-first repair or a stated
  conclusion — each proven by a gate shown red first.

#### Out of scope

- New product capability; remote (non-LAN) mobile access; native apps.

**Validation plan:** the two halves are verified differently, deliberately.
The engineering half lands under the module smoke and api-host smoke with a
gate shown red first, `npm run test:unit` where a surface is touched, and
`npm run typecheck` / `npm run lint` / the PSScriptAnalyzer ratchet at
baseline; CI is the arbiter. The operator half is verified by the operator —
on the device, at the elevated prompt, with eyes on the surface — and recorded
in `evidence/operator-verification-log.jsonl`. No agent may mark an operator
item verified.

**Risks:** the physical-device proof must run against the LAN-bound host, not
loopback; an operator item marked verified from a green suite rather than eyes
on the surface would reintroduce the honesty gap this release exists to close.

**Dependencies:** the operator's presence at the machine (elevated session,
authenticated `gh`, browser), a Galaxy S24 Ultra on the LAN
([`lan-mobile-setup.md`](docs/reference/lan-mobile-setup.md)), and Lane 0.2's
certificate regeneration for the TLS-dependent portal proofs. The engineering
half depends on none of these.

**Known issues:**

- ~~The console cannot answer its own Question 6~~ — **retracted 2026-08-20**, the capability exists; the real defect was the naming drift (now resequenced into the engineering milestones above). [Archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- The three findings-shaped items that used to sit here — the disagreeing
  readiness gates, the two-names-one-concept routes, and the L1/L2 repair
  path — were **resequenced 2026-08-23** to the top of the engineering
  milestones above. They are the release's current focus, not its residue.
- Runner stop marker (`Stop-RoadmapTaskRunner.ps1`) and the smoke's queue isolation (`Get-RoadmapQueuePath` + `REPO_MGMT_QUEUE_PATH`) — both **fixed 2026-08-20**; [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- [ ] **[non-blocker]** `Dashboard.tsx` is ~1,750 lines of hooks and handlers
      above the return; Release 3.5 deferred the Operations panels' full
      stale-keeps-last-good rendering to this refactor. _(inherited 2.7 →
      3.2 → 3.3 → here)_
- The intermittent `L0-Absent` packaging failure — **root-caused and fixed 2026-08-19 (PR #167)**, `Wait-ForPortfolioIndex -RequireAuditedMaturity`; [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

---

### Release 3.6 — Every Repository Gets an Outcome

**Status:** validation — engineering complete 2026-08-27. All six milestones
are `smoke-tested` and every acceptance criterion below is asserted by a
gate; what remains is operator verification (eyes on the live portal), which
no agent may claim. That proof batches with the Release 2.9 operator session.

**Goal:** every repository in the portfolio — including the ~50 with no
roadmap — leaves the console with an explainable conclusion (_strengthen_,
_appropriate as-is_, or _insufficiently understood_) grounded in visible repo
state across the foundation domains, with a reachable preview-first next
action wherever improvement is warranted and a plain statement of why
wherever it is not.

#### Product outcomes

- A newcomer can tell from the first screen what the product evaluates, what
  it uncovers, and how its findings strengthen a portfolio.
- No repository reads as merely `L0-Absent`, "not dispatchable", or "not
  applicable": each carries one conclusion, its domain evidence, and — for
  _strengthen_ — one next action the console can actually run; _appropriate
  as-is_ is a first-class, filterable, evidenced outcome.
- The foundation domains are data the product can refine, not a taxonomy a
  repository is forced to fit, and foundation coverage is measurable over
  time.

#### Engineering milestones

- [ ] **Conclusion model (backend).** One per-repo object — `conclusion`
      (strengthen | appropriate-as-is | insufficiently-understood), `reason`,
      per-domain `{domain, status: present|weak|missing|not-applicable,
      evidence, nextAction?}`, `basis` — composed from signals that already
      exist (README contract, doc findings, roadmap audit and maturity,
      structure audit, scope classifier), served by
      `GET /api/portfolio/conclusions` and per repo. Domains and per-kind
      applicability live in `backend/config/foundation-domains.json`
      (`schemaVersion: "v1"`), so refining a domain is a data change. What
      exists: [`Portfolio.Assessment.ps1`](backend/modules/portfolio/Portfolio.Assessment.ps1),
      [`DocAudit.Scanner.ps1`](backend/modules/docaudit/DocAudit.Scanner.ps1),
      [`Portfolio.Scope.ps1`](backend/modules/portfolio/Portfolio.Scope.ps1).
      _(state: smoke-tested 2026-08-26 —
      [`Portfolio.Conclusion.ps1`](backend/modules/portfolio/Portfolio.Conclusion.ps1)
      composes the conclusion from the cached index only; `not-scored` joins
      the domain statuses for the defined-only domain; `GET
      /api/portfolio/conclusions` (+ `?conclusion=` filter) and
      `/api/portfolio/conclusions/{repoId}` serve it under the Release 3.2
      read budget. Gates: module smoke shows the validator red on a blank
      reason, no route and bare `L0-Absent` before nine fixtures all conclude
      and coverage reconciles; api-host smoke proves 100% of the live index
      concludes, the fixture's `strengthen` next action answers JSON 200, and
      the route census guards the route; the config-integrity gate versions
      the JSON. CI Smoke is the arbiter. No UI consumer yet — that is the
      outcome card.)_
- [ ] **Outcome card (UI).** Per repository: the conclusion, why, each
      domain's status and evidence, and the next action wired to the existing
      preview-first repair and packaging flows; repos without a roadmap show
      a conclusion, not `L0-Absent`; _appropriate as-is_ renders and filters
      like any other outcome. What exists:
      [`RepoEvaluationModal.tsx`](frontend/components/RepoEvaluationModal.tsx).
      _(state: smoke-tested 2026-08-27 —
      [`OutcomeCard.tsx`](frontend/components/OutcomeCard.tsx) renders the
      conclusion, its reason, every domain's status and evidence, and one
      preview-first next action; it leads the evaluation modal, and a repo the
      index does not know says so instead of showing nothing. The action is
      data, so the card runs it only when its route is one of this console's
      preview-first flows — an unrecognised route still renders, disabled,
      with the reason. Backend (2026-08-26): an `outcome` summary on every
      `/api/operations/repos` entry, the full `conclusion` + contract on the
      detail and on `/api/repo/evaluate`, and the packaging flow offered
      preview-first for a healthy repo with pending work — all from
      `foundation-domains.json`. Data layer:
      [`foundationConclusion.ts`](frontend/lib/foundationConclusion.ts).
      Gates: 9 component tests (no repo reads as a bare `L0-Absent`,
      appropriate-as-is renders as a first-class outcome with its evidence, a
      rogue route is refused, a broken contract is shown not hidden), 11 data
      tests, module smoke and api-host smoke on the payloads. Filtering by
      conclusion lands with the ranked `Today` landing below.)_
- [ ] **First interaction — the ranked `Today` landing.** The default view is
      a ranked table with _why now_, one primary next action per row, and
      effort (the value score and work-unit estimate already exist, three
      clicks deep) under a one-paragraph orientation; tab labels pose the
      question each view answers, with the Release 2.6 subtitle second.
      Decides the Lane 0.5 question (2026-08-23). What exists:
      [`DashboardViewTabs.tsx`](frontend/components/DashboardViewTabs.tsx),
      [`RepoGrid.tsx`](frontend/components/RepoGrid.tsx), the value scorer.
      _(state: smoke-tested 2026-08-27 —
      [`TodayView.tsx`](frontend/components/TodayView.tsx) is the default
      landing: an orientation paragraph naming what was assessed and
      concluded, then a ranked table of repository / why now / one next action
      / effort, with every conclusion filterable including appropriate-as-is.
      Ranking is pure and explainable in
      [`todayRanking.ts`](frontend/lib/todayRanking.ts) — conclusion, then
      curation, then whether an action exists, then value, gaps and (only as a
      tiebreak) cheaper effort — and every row carries the basis for its rank.
      `estimatedSessionWorkUnits` reaches a surface for the first time; the
      index always emitted it. Every tab now poses its question with the
      Release 2.6 subtitle second. Gates: 13 ranking tests, 10 view tests, the
      viewMeta contract test (every view has a unique question ending in `?`),
      and the module smoke's Dashboard source-order tripwire. This closes Lane
      0.5.)_
- [ ] **Flexible standards.** Per-kind applicability in
      `foundation-domains.json` (library, service, script collection,
      archived, minimal, externally managed) so a domain can be
      `not-applicable` with a stated reason; `L0-Absent` reads as "no plan
      recorded" with the smallest credible plan offered.
      _(state: smoke-tested 2026-08-27 — the six kinds and their applicability
      reasons are data in `foundation-domains.json`; `archived` is detected
      from `lifecycleState` / `curationState=archived-ignore`, the rest await
      a kind signal and read as `unknown` (every domain applies) rather than
      guessed; a missing roadmap reads "no plan recorded" and offers the
      roadmap repair preview. The module smoke proves a JSON-only detection
      rule flips a conclusion with no code change, and the outcome card
      renders a `not-applicable` domain with its stated reason — asserted by
      an `OutcomeCard` test, which is the rendering half this item was
      waiting on.)_
- [ ] **Measure — coverage and leverage.** `GET /api/portfolio/trend` gains a
      foundation-coverage series (per domain: present / weak / missing /
      not-applicable) captured by
      [`Invoke-DailyEvidence.ps1`](scripts/Invoke-DailyEvidence.ps1), and a
      leverage family derived from ledgers the product already keeps
      (agent-run metrics, execution metrics, queue summaries, the
      operator-verification log): finding → accepted action, action → merged
      improvement, operator minutes per completed task, agent PR first-pass
      success, recommendations accepted vs rejected (the one new capture),
      repositories concluded appropriate-as-is or archived. Insights renders
      foundations gained and hours returned over the window.
      _(state: smoke-tested 2026-08-27 — `GET /api/portfolio/trend` gains a
      `foundationCoverage` series (present as a share of the foundations that
      APPLY; not-applicable and not-scored excluded from both halves, so an
      archived repo neither inflates nor dilutes it) plus a `leverage` block.
      It accrues for real: a `foundation_coverage` table (schema v3, one row
      per domain per scan, 180-day floor, in the backup manifest) written from
      the one site that writes maturity history, and read back with the same
      latest-capture-per-day rule. Leverage derives agent first-pass success,
      estimate accuracy, time to deliver, tasks completed, repositories
      needing nothing, and operator-verified surfaces from ledgers already
      kept; **operator minutes per task and recommendations accepted vs
      rejected ship `available: false` with the reason they are not
      captured** — the roadmap names them and the product does not have them,
      so the gap is on the surface rather than implied to be zero.
      [`LeveragePanel.tsx`](frontend/components/LeveragePanel.tsx) renders
      both halves in Insights and shows an em dash, never a 0, for anything
      unmeasured; `Invoke-DailyEvidence.ps1` records the day's figures in the
      manifest. Gates: module smoke (coverage math, archived exclusion, empty
      portfolio null, series present in BOTH builder blocks and inside the
      frontend palette, leverage contract red on a zeroed fixture first),
      api-host smoke (series shape and range, every metric states a basis, the
      two uncaptured ones named and null), and 15 frontend tests.)_
- [ ] **Define the intentional-engineering evidence model — define, not
      score.** Name the evidence per sub-area (test, architecture,
      operational, maintenance, delivery health), how each is read from a
      repository, which are cheap from existing signals (Actions results,
      merge readiness, PR state) and which need a detector; record it in
      `foundation-domains.json` as `not-scored`, so Release 3.7's ten
      repositories decide which evidence earns a detector. _(state:
      smoke-tested 2026-08-26 — recorded as the `intentional-engineering`
      domain with `scored: false`, `status: not-scored` and six sub-areas
      (test, operational, delivery-health, maintenance: cheap from existing
      signals; architecture, release: need a detector). The config-integrity
      gate refuses a scored status on it; the conclusion reports what it
      observes for the domain, "observed, not judged".)_

#### Acceptance criteria

- 100% of indexed repositories carry a conclusion with a non-empty reason and
  none presents `L0-Absent` or "not applicable" as its only state — asserted
  over the live index and a fixture set (no-roadmap, archived, vendored,
  minimal utility).
- Every `strengthen` conclusion names a next action whose route returns
  `application/json` with HTTP 200 for the fixture repo; every
  `appropriate-as-is` conclusion cites its evidence — never an absence of
  findings.
- Adding a domain or a per-kind applicability rule is a JSON-only change,
  covered by the config-integrity gate and a module-smoke fixture.
- The default landing is the ranked `Today` table — orientation paragraph,
  one primary action per row, effort — and every tab label poses its
  question (unit test).
- `GET /api/portfolio/trend` reports foundation coverage and the leverage
  family for the window, each metric with its basis, and Insights renders
  both.

#### Out of scope

- New detectors beyond composing existing signals; scoring intentional
  engineering (defined only); prescribing a target architecture for any
  repository; auto-applying repairs; mobile surfaces.

**Validation plan:** module smoke — the conclusion model over the fixture
set, detector shown red first against a blank-reason fixture; api-host smoke
— the conclusions and trend routes return JSON (the SPA fallback makes status
alone meaningless); `npm run test:unit` — Today landing and outcome card; the
config-integrity gate for `foundation-domains.json`; CI Smoke is the arbiter.

**Risks:** domains hardening into a taxonomy (data-defined, with an explicit
refinement rule); _appropriate as-is_ becoming a dumping ground (every such
conclusion must cite evidence); scoring intentional engineering before it is
defined (it ships `not-scored`).

**Dependencies:** Release 2.9's three foundations-first items; the existing
assessment, audit, classifier, and trend modules. No external resource.

**Traceability:** PRs #188 (conclusion model), #189 (outcome-card backend),
then #191 (outcome card), #192 (`Today` landing) and #193 (coverage +
leverage), each merged on a green CI Smoke. Gates: the `Foundation
conclusions` and
`Foundation coverage + leverage` module-smoke sections, the
`foundation-domains.json integrity` suite gate, the conclusions and trend
api-host steps, and 47 frontend tests across `foundationConclusion`,
`todayRanking`, `portfolioLeverage`, `OutcomeCard`, `TodayView` and
`LeveragePanel`.

**Known issues:**

- [ ] **Operator verification is outstanding** — every milestone is
      `smoke-tested`, none is `operator-verified`. The `Today` landing, the
      outcome card and the Insights leverage panel need eyes on the live
      portal; batch with the Release 2.9 operator session.
- [ ] **Two leverage metrics ship uncaptured, by design.** Operator minutes
      per task needs an operator-side timer the product does not have;
      recommendations accepted vs rejected needs an accept/reject ledger the
      packaging approve/reject routes do not write. Both render with their
      reason rather than a zero — Release 3.7's ten repositories decide
      whether either earns a capture.
- [ ] **[non-blocker]** Only `archived` has a kind-detection rule. `library`,
      `service`, `script-collection`, `minimal` and `externally-managed`
      exist as data with their applicability reasons but await a signal, so
      they read as `unknown` (every domain applies). Refining that is a
      JSON-only change, proven by the module smoke.
- [ ] **[non-blocker]** The foundation-coverage series starts as a one-point
      scaffold on a fresh database; it becomes history-backed as scans
      accrue, on the same clock as maturity history.

---

### Release 3.7 — Portfolio Value Proof

**Status:** planned — defined 2026-08-23; follows Release 3.6. Its job is to
make the product earn its next release against the real portfolio, not itself.

**Goal:** ten representative repositories — chosen by kind, not for
conformance — each receive a credible conclusion and, where warranted, a next
action; at least five are materially improved through the existing preview →
approve → execute → validate workflow with operator effort and outcome quality
recorded; the result decides the full 80+ rollout.

#### Product outcomes

- "Is this product making the portfolio better, faster?" is answered with
  recorded numbers, not impressions; false positives and bad recommendations
  are found on ten repositories before they are found on eighty.

#### Engineering milestones

- [ ] **Select the ten by rule** — one each: mature active application, weak
      active application, small utility, experiment, abandoned project,
      repository without a roadmap, library, externally managed project,
      nearly finished repository, messy repository — recording why each was
      chosen. _(state: planned)_
- [ ] **Run the conclusion model over the ten**, recording per repository:
      what it is, whether it still matters, its state, what limits its value,
      the highest-value next action, and whether the product can execute or
      facilitate it. _(state: planned)_
- [ ] **Execute at least five improvements** through preview → approve →
      execute → validate, recording operator minutes, agent first-pass
      result, and whether the repository is materially stronger afterwards —
      appropriate-as-is or archive counts as an outcome. _(state: planned)_
- [ ] **Adjust and decide** — fix the false positives and bad recommendations
      the ten expose; record the go/no-go for the full rollout and the
      leverage numbers behind it. _(state: planned)_

#### Acceptance criteria

- Ten repositories selected by the rule, none for conformance, each with a
  recorded conclusion and reason.
- At least five materially improved through the product's own workflow, with
  operator minutes, outcome quality, and agent first-pass result recorded per
  repository in `evidence/`; a recorded rollout decision with the numbers.

#### Out of scope

- New product capability; finishing every repository; improvements made outside the product's workflow.

**Validation plan:** conclusions, actions, and outcomes recorded in `evidence/`
via [`Add-OperatorVerification.ps1`](scripts/Add-OperatorVerification.ps1) and
the agent-run ledgers; module smoke and api-host smoke stay green; CI is the
arbiter for any product fix the ten expose.

**Risks:** choosing repositories that flatter the product (the selection rule
prevents it); counting a repair as an improvement when the repository is not
stronger (outcome quality is recorded, not assumed).

**Dependencies:** Release 3.6; the operator's time for approvals and effort.

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

**The incident closed 2026-08-10 across four passes and is archived** — the
fix made progress, not liveness or CPU, the contract, and taught the rule every
tripwire here now follows: derive scope from a classifier or the AST, never a
maintained list.

- Insights panels that told you to run an assessment but offered no control — **closed 2026-08-14** under Release 3.1; [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- `/health/live` independently responsive during long operations — **closed 2026-08-19** under Release 3.2 M1 (the scan is not the host's job); [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- [ ] **Clear and harden the stale browser-persisted GitHub owner.** _(state:
      planned — recorded 2026-08-10, not bundled into the watchdog fix)_ Every
      scan queries GitHub for owner `Benjamin-Fuhr_genesys`, which 404s/422s
      and adds failing round-trips to an already-long scan. It is **not** in
      `settings.json` (correctly `xfaith4`) or any env var — the browser sends
      it in the request body, and has since **2026-07-07** (116 occurrences in
      the host log). Clear the persisted client value and stop a client-supplied
      owner from silently overriding validated configuration.
- The bare `Failed to fetch` screen replaced by a classified, actionable retry state (`fetchFailure.ts`) — **closed 2026-08-14** under Release 3.1; [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

### Lane 0.5 — Portal UX follow-ups (empty-state audit 2026-08-08)

Three of four closed 2026-08-10 and are archived (error boundary, bulk-scope confirmation, tab inversion).

- The progressive-disclosure question — **decided 2026-08-23, resolved 2026-08-27**: the ranked `Today` landing with one primary action per row is Release 3.6's first-interaction milestone, and it shipped — `Today` is now the default view, the six peers sit behind it, and every tab poses the question it answers. The three 2026-08-15 review inputs are [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd). Nothing remains in this lane.

### Lane 0.7 — Roadmap-standard fidelity: split-history awareness (2026-08-08)

Nothing penalizes a roadmap that archives completed work to a separate file
(this repo's shape), but nothing tells one apart from a repo that deleted its
history; the 2026-08-08 survey found zero managed repos using the split layout,
so the live risk is the repair path pushing 32 repos toward in-file history.
Intent: **awareness, not enforcement.**

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
- Sanction the external-archive pattern in the standard — done (`ROADMAP_TEMPLATE.md` §6 "External archive option"); [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

### Lane 0.8 — Verification gate integrity (CI audit 2026-08-10)

**Re-homed from Release 3.1 on its closure (2026-08-15):**

- [ ] **[non-blocker]** **No `.gitattributes`, with `core.autocrlf=true`.**
      Byte-level comparisons are non-deterministic locally while passing in
      CI's fresh checkout (2026-08-13: 245 CRLF vs 245 LF read as drift); the
      sync gate normalises, but it was the only gate audited. Fix: a
      `.gitattributes` declaring `text eol=lf`. _(state: planned)_
- [ ] **[non-blocker]** The scheduled and operator dispatch paths reach the
      queue through different writers with only one end-to-end test; the
      behavioural divergence closed in 3.1, the coverage asymmetry remains.
      _(state: planned)_

**The gate work closed 2026-08-10 (PRs #102–#107) and is
[archived](docs/history/completed-releases.md#closed-2026-08-11-archived-from-roadmapmd):**
`ci-smoke.yml` invokes `Invoke-TestSuite.ps1` itself, both linters fail the
build, `main` requires `smoke` with `enforce_admins` on. What remains is the
debt the ratchets hold, and it is deliberately not a sweep.

**Warning-debt reduction plan (decided 2026-08-10).** The baselines are
controlled debt — **no blanket lint sweep.** Small, behaviorally coherent
batches, each ending with `-UpdateBaseline` / a lowered `--max-warnings`:

- P1 — PSSA correctness micro-batch — **done 2026-08-15**, all 12 fixed and five rules now gate at zero; [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
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
  `UseShouldProcessForStateChangingFunctions` 67, five smaller) — churn for
  zero behavior.
- **Separate lane, never batched mechanically:** ESLint `set-state-in-effect`
  (31) — every site needs behavioral review; a "fix" can change rendering.

---

### Lane 0.10 — Scan-snapshot retention (found 2026-08-27)

- [ ] **[non-blocker]** Give `output/index/scans/portfolio-scan-*.json` a
      retention rule. `Save-PortfolioIndexArtifacts`
      ([`Portfolio.Assessment.ps1`](backend/modules/portfolio/Portfolio.Assessment.ps1))
      writes one snapshot per scan and nothing reads or prunes them: 762
      files / 103 MB had accumulated since 2026-05-11. The Release 3.3 ledger
      retention ([`Ledger.Retention.ps1`](backend/modules/persistence/Ledger.Retention.ps1))
      is code-declared over six JSONL ledgers and does not name this
      directory. Either add it as a target (age-keyed by file time, since the
      files are whole snapshots, not lines) or cap the directory at N newest
      in the writer. Pruned by hand 2026-08-27 to the last seven days; the
      gate is a module-smoke fixture that writes eight dated snapshots and
      asserts the oldest is gone. _(state: planned)_

### Lane 0.11 — Roadmap identity: repos were being found by folder name (found 2026-08-27)

- [x] **[non-blocker]** Join scanner output to the index by repository path,
      and pick one canonical roadmap file per repository. Found from the portal:
      `CupHandleDetectionv2` reported "Roadmap file exists but could not be
      parsed" *and* "This repo does not have a roadmap" at the same time, with
      a 36 KB `ROADMAP.md` on disk. Three separate defects, all confirmed
      against the live index:
      **(a) identity** — `Invoke-RoadmapScan`
      ([`Start-RepoManagementApiHost.ps1`](backend/api-host/Start-RepoManagementApiHost.ps1))
      keys entries by the `.git`-ancestor *folder* name while the index keys
      repos by their *remote* name, so every repo whose folder differs from its
      GitHub name lost its roadmap, doc audit and maturity together
      (`CupHandleDetectionv2` in `CupHandleDetection`,
      `GenesysCloud-API-Explorer_v3` in `GenesysCloudOpsConsole` — both read as
      `L0-Absent` / `needs-roadmap` / dispatch-blocked).
      **(b) file selection** — discovery accepted any name starting with
      `ROADMAP` at any depth, and `_IndexByRepoName` keeps the *last* write, so
      a nested copy always beat the repository's own file: five repos resolved
      to the wrong one, four of them reported `parse-error` with 0 pending
      items while holding 34, 53 and 25 real items, and
      `2026-06-13_Orchestration` was being planned from
      `archive\roadmaps\ROADMAP.v1.0_original.md`. The doc audit took the
      *first* match, so one repo could be assessed against two different files
      in a single pass.
      **(c) wording** — `ROADMAP-002` said the file "could not be parsed" when
      the parser had read it perfectly and found no `- [ ]` items, sending the
      operator to fix a file that was not broken.
      Fixed by `Select-CanonicalRoadmapFile`
      ([`Roadmap.Parser.ps1`](backend/modules/roadmap/Roadmap.Parser.ps1) —
      markdown only, repository root beats any subdirectory, exact `ROADMAP.md`
      beats a decorated sibling, ordinal tiebreak so enumeration order decides
      nothing), by path-keyed companion maps in
      [`Portfolio.Assessment.ps1`](backend/modules/portfolio/Portfolio.Assessment.ps1)
      with the name join kept as the fallback, and by restating `ROADMAP-002`
      in both rule copies. Gated by the module-smoke section "Roadmap identity";
      all three assertions were confirmed red against `HEAD` first. Still to do:
      the caches under `backend/modules/output/cache/` were built by the old
      logic, so the corrected figures appear only after the next portfolio
      scan. _(state: smoke-tested)_

- [x] **[non-blocker]** Make the prompt-refinement blocker name the condition
      it actually checks. The banner fired on `hasRoadmap` alone while claiming
      refinement "requires a ROADMAP.md with at least one pending item", so one
      sentence covered four different failures and was wrong for two of them --
      a repository with a real roadmap and no checklist items was told it had
      no roadmap, which sends the operator to create a file that already
      exists. `describeRefineBlocker`
      ([`refineReadiness.ts`](frontend/lib/refineReadiness.ts)) now returns a
      distinct sentence and next action for each state (no file / no checklist
      items / all complete / parsed but nothing pending), and the button's
      disabled reason is the same string the banner shows. Covered by six
      assertions in `refineReadiness.test.ts`, one of which pins that a repo
      with a roadmap is never told it has none. _(state: smoke-tested)_

### Lane 0.12 — Two local clones of one repo collapse to one row, arbitrarily (found 2026-08-27)

- [x] **[non-blocker]** Decide which local clone represents a repository when
      more than one exists, and record the loser rather than dropping it.
      `F:\Development\20_Staging\Archive\MusicLibrary` and
      `F:\Development\20_Staging\MusicLibraryProjects\MusicLibrary_v2` are two
      checkouts of the same GitHub repository, so the status scan emits two rows
      both named `MusicLibrary_v2`.
      [`Portfolio.Assessment.ps1`](backend/modules/portfolio/Portfolio.Assessment.ps1)
      dedupes with `$seenLocalKeys.Add($key)` — first wins, keyed on the name —
      so one checkout is discarded and **which one survives depends on
      enumeration order**: the index snapshot kept the active checkout, the
      status cache order keeps the archived one. Found while verifying Lane
      0.11: before the path join, the surviving archived row was displayed with
      the *active* checkout's 52 pending items — a roadmap belonging to a
      directory it is not. The path join fixed the attribution (the archived row
      now reports its own 13), but the active checkout is still absent from the
      portfolio whenever ordering favours the archive, which is the worse of the
      two outcomes and the one the operator would never guess. The status
      response already computes `duplicateIdentities`; the assessment does not
      read it. Options: prefer the non-archived checkout, prefer the one whose
      folder matches the remote name, or emit both and mark the duplicate.
      Whichever is chosen, the discarded checkout should appear in the row's
      evidence rather than vanishing. Gate: a fixture with two local repos
      sharing one remote name asserts the active one survives and the dropped
      path is named.
      Fixed by `Select-CanonicalLocalCheckout`
      ([`Portfolio.Assessment.ps1`](backend/modules/portfolio/Portfolio.Assessment.ps1)),
      which resolves every collision **before** the loop instead of inside it:
      an in-scope checkout beats one the scope policy excluded, a folder name
      matching the repository name beats one that differs, and an ordinal path
      comparison settles the rest — so enumeration order decides nothing. The
      surviving row carries `duplicateCheckouts` (the chosen path, why it was
      chosen, and every displaced checkout with its scope reason), threaded
      through `New-PortfolioIndexPayload` and
      `Convert-PortfolioIndexReposToAssessments` so it survives an index
      round-trip. Measured against the live caches: the active
      `MusicLibraryProjects\MusicLibrary_v2` now survives with its own 52
      pending items and `L2-Structured`, the archived clone is named as
      dropped, and reversing the scan order changes no survivor across all 71
      assessed repositories. Gated by the module-smoke section "Duplicate
      checkouts", confirmed red against `HEAD` first — the reversal assertion
      failed with the archived clone as survivor. _(state: smoke-tested)_

- [ ] **[non-blocker]** Two checkouts with **different folder names** that share
      one remote still produce two portfolio rows.
      `GenesysCloud\Genesys.Core` and `GenesysCloud\Genesys.Core_AuditLogsApp`
      are both clones of `github.com/xfaith4/Genesys.Core`, but the collision
      unit above is the repository _name_, so they never collide and the
      portfolio counts one GitHub repository twice. `Group-RepoByRemoteIdentity`
      ([`Portfolio.Scope.ps1`](backend/modules/portfolio/Portfolio.Scope.ps1))
      already identifies the pair by remote URL plus root-commit SHA and the
      status response carries it as `duplicateIdentities`; the assessment still
      does not read it. Deciding this needs a product judgement rather than
      engineering time — `Genesys.Core_AuditLogsApp` carries its own
      `docs/ROADMAP.md`, so collapsing the pair would discard a real plan.
      _(state: planned)_

### Lane 0.13 — Truthful uncertainty: the product could not tell "unreadable" from "not present" (found 2026-08-27)

- [x] **Stop reporting a sound roadmap as a damaged file.** Measured against
      the live portfolio: **15 of the 48 roadmaps on disk (31%) were reported
      `parse-error`** — among them a **212 KB, 1,496-line** roadmap, a 43 KB
      one and a 35 KB one, every one of them well-formed. The rule was stated
      outright in [`Roadmap.Parser.ps1`](backend/modules/roadmap/Roadmap.Parser.ps1):
      _"parse-error — content is empty, null, or contains no checkbox items."_
      That state propagated to `lifecycleState`, `dispatchReadiness` and the
      operator-facing `recommendedAction` — **"Open the roadmap and fix the
      parse error before this repo can be assessed"** — so the console spent
      the operator's time repairing files that were not broken, which is the
      §2 admission rule running in reverse.
      Fixed by splitting the state: `no-checklist` means the file was read in
      full and records no `- [ ]` items; `parse-error` now means only that
      there was nothing to read. Threaded through the lifecycle, dispatch
      readiness and explanation, the roadmap score (a real plan no longer
      scores as a damaged file), the summary tally,
      [`DocAudit.Scanner.ps1`](backend/modules/docaudit/DocAudit.Scanner.ps1),
      [`Roadmap.Auditor.ps1`](backend/modules/roadmap/Roadmap.Auditor.ps1),
      [`Roadmap.Repairer.ps1`](backend/modules/roadmap/Roadmap.Repairer.ps1),
      the execution ledger, the portfolio report, and the frontend
      (`RepoGrid`, `WorkQueueView`, `OperationsWorkspaceView`, `needsAttention`,
      `refineReadiness`, `portfolioTrendView`, `types.ts`).
      [`Portfolio.Conclusion.ps1`](backend/modules/portfolio/Portfolio.Conclusion.ps1)
      now concludes `insufficiently-understood` **naming what it needs**
      instead of asserting the file is unparseable. Re-parsing all 48 live
      roadmaps with the new parser: **15 move `parse-error` → `no-checklist`
      and zero remain `parse-error` — not one roadmap in the portfolio was
      ever actually damaged.** Gated by the module-smoke section "Truthful
      uncertainty", confirmed red against `HEAD` first, plus 3 new frontend
      tests pinning that the two states never share a sentence. _(state:
      smoke-tested)_

- [x] **Give the served index a staleness contract.** On
      2026-08-27 `output/index/repos.index.json` was generated at 09:46Z and
      reported **58 repositories, all `L0-Absent`, 0 ready-for-work, 58
      blocked**. The roadmap-audit cache written at 16:09Z the same day held
      **10 `L3-Contract-Ready`, 23 `L2`, 15 `L1`**, and re-running the join
      offline over those caches produces **71 assessed repositories, 9 of them
      `L3-Contract-Ready`**. The index simply predated the Lane 0.11 identity
      fix (merged 10:47Z) and nothing re-scanned — but **nothing in the
      product notices, records, or says so**, so every surface Release 3.6
      shipped was rendering a portfolio that was wrong about a third of its
      inputs and short 13 repositories. Before the Release 2.9 operator
      session: every index-backed surface should state how old its data is
      and refuse to present a conclusion drawn from an index older than the
      last correctness-affecting change.
      Shipped as two verdicts, because they fail differently: **stale by
      clock** (generated outside the freshness window) and **stale by logic**
      (produced by different code than is running now — the dangerous one, an
      index minutes old can still be wrong about every row).
      `Get-PortfolioIndexLogicFingerprint` derives the second from a SHA256
      over every `.ps1` under `backend/modules/{portfolio,roadmap,docaudit}` —
      **derived by directory, never a maintained list**, so adding a module
      moves the fingerprint on its own; line endings are normalized so a CRLF
      CI checkout does not read every index as stale.
      `Save-PortfolioIndexArtifacts` stamps `producedBy`, and the verdict is
      attached inside `Get-PortfolioIndexPayload` — the single place every
      consumer already goes through — so no surface can render index data
      without the verdict on the same object. `GET
      /api/portfolio/conclusions` carries it as `basis`, where **absent means
      "not established", never "fresh"**. Verified against the live index: it
      reads `stale: true`, age 14.2 h, reason _"does not record which version
      of the assessment logic produced it"_ — the incident above, caught.
      Gated by the module-smoke section "Index staleness", confirmed red
      against `HEAD` first ("Reading the portfolio index produced no staleness
      verdict — a surface can still render it as fact"); the gate also proves
      the fingerprint moves when a producer is edited **and** when one is
      added, is CRLF-insensitive, and that an unknown current fingerprint
      reads as uncertainty rather than freshness. _(state: smoke-tested)_

- [ ] **Surface the staleness verdict in the UI.** _(state: planned)_ The
      backend contract is complete and `/api/portfolio/conclusions` returns
      `basis`; the `Today` landing, the outcome card and Insights do not yet
      render it. Until they do, an operator can still read a stale conclusion
      as a current one — which is the half of this that the Release 2.9
      operator session actually depends on. Gate: a view rendered from a
      payload whose `basis.indexStale` is true must show it, asserted by a
      component test.

- [ ] **`estimatedSessionWorkUnits` is null for every managed repository.**
      _(state: planned)_ Release 3.6's ranked `Today` landing surfaces effort
      per row, and the field is populated only from `activePhasePlan`, which
      **0 of 48** managed roadmaps carry (5 carry an `activeRelease`). The
      effort column is therefore empty portfolio-wide, and `todayRanking`'s
      cheaper-effort tiebreak never fires on real data. Either derive a
      credible estimate from signals that do exist (pending item count, item
      text, repo kind) or render the column as explicitly unmeasured — the
      Release 3.6 leverage panel already sets that precedent with its two
      `available: false` metrics. Decide which, with the ten repositories of
      Release 3.7.

---

## 8. Risks and Guardrails

Full list in [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md);
headline guardrails for the active release and near-term roadmap:

- Do not auto-dispatch tasks without a visible readiness model.
- Do not silently mark roadmap items complete based only on code churn.
- Prefer preview-first workflows before write-back or autonomous mutation.
- Preserve genuine completion history when rewriting roadmaps.
- Require a sufficient execution contract before any dispatch — scope,
  acceptance criteria, a runnable verification — sized to repository kind and
  task scope; L3+ roadmap maturity is how roadmap-sourced work supplies it,
  not a universal precondition (changed 2026-08-23).
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
  in the same pull request** (recorded 2026-08-15 after
  [PR #134](https://github.com/xfaith4/GitHubRepoManagement/pull/134) left six
  shipped milestones reading `planned`). Enforced by
  `Test-RoadmapCapabilityRecord.ps1`: a stated rule drifts; a derived one does
  not.

---

## 9. Roadmap Contract Standard for Managed Repos

The full standard is documented in
[`docs/reference/roadmap-contracts.md`](docs/reference/roadmap-contracts.md),
shipped under [`standards/roadmap/`](standards/roadmap/) (template, schema,
audit rules, maturity model, repair prompt) with the publishable copy under
[`spec/roadmap-contract/`](spec/roadmap-contract/); managed repos converge
toward it.

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
oversized future releases, file-length drift. CI runs it with `-FailOnError`:
warnings stay advisory, structural errors fail the smoke workflow.

**The warnings are load-bearing, not decoration.** `R010-FILE-LENGTH` and
`R013-FUTURE-RELEASE-SIZE` caught this file at 2,020 lines on 2026-08-11 — a
roadmap that could no longer answer "what is the next work item?" without a
long read.

<!-- Release 2.7 Phase A — live submit-PR evidence.
     This note was written, committed, pushed, and opened as a pull request by
     POST /api/roadmap/repair/submit-pr (createPr=true) at 2026-08-09 12:43:32 UTC.
     Its existence in a PR IS the Phase A artifact: it proves the write path
     runs end to end against a real repo, not just the dry-run plan. -->
