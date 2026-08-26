# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 2.9 — Operator Field Proof + Mobile Completion**
> **Next active release:** **Release 3.6 — Every Repository Gets an Outcome** (`planned`, defined 2026-08-23 under the product lens in §2) — it starts when Release 2.9's three foundations-first engineering items close; 2.9's operator half keeps riding Ben's next session — then **Release 3.7 — Portfolio Value Proof**, where ten real repositories decide the 80+ rollout
> **Work ordering:** dependency-driven, not insertion order — see
> [Execution Order and Dependencies](#execution-order-and-dependencies)
> **Canonical product direction:** [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
> **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
> **Dated change log:** [`CHANGELOG.md`](CHANGELOG.md)

---

## Current Status (Agent Context)

**Last updated:** 2026-08-23

Releases 0.4 through 2.6, 2.8 and 3.0 are **engineering-complete and archived**,
as is every completed milestone from the releases and lanes still open below.
Their full text lives in
[`docs/history/completed-releases.md`](docs/history/completed-releases.md).

**This file carries open work only.** Every checkbox in it is something still
to do — if an item is `[x]` here it is a mistake, not a record (rule restored
by the 2026-08-11 archive pass, recorded in `CHANGELOG.md`).

What remains falls into four kinds of work that are **not** interchangeable —
mixing them once made the roadmap read "everything is done" over real gaps:

1. **Genuinely unbuilt engineering** — Release 2.9's three foundations-first
   items (resequenced 2026-08-23), Release 3.6's milestones once those close,
   and the recorded cross-cutting items. This is the only kind an autonomous
   agent can close on its own.
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

- [ ] **Release 2.9 — foundations first (resequenced 2026-08-23).** The
      three items that make findings explainable lead the release's
      milestones: the disagreeing readiness models, the two routes that name
      one concept two ways, and the L1/L2 repair path for the 26 of 34
      roadmap repos below L3. Close these before anything in 3.6.
- [ ] **Release 3.6 — Every Repository Gets an Outcome** is defined in §6 as
      the next engineering release (`planned`). Start it when 2.9's three
      items close — not earlier, to manufacture momentum.
- [ ] **Release 3.7 — Portfolio Value Proof** follows 3.6 (defined,
      `planned`): ten representative repositories, chosen by kind, decide the
      80+ rollout with recorded leverage numbers.
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
| **3.6**   | **Every Repository Gets an Outcome**                                     | **`planned`** 2026-08-23 — product lens (§2); after 2.9's foundations-first items          |
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

1. **Release 2.9 — the active release.** Its engineering half is now the
   three foundations-first items (resequenced 2026-08-23: the disagreeing
   readiness gates, the two-names-one-concept routes, the L1/L2 repair path);
   its operator half is batched and waiting on Ben's presence at the machine.
2. **Release 3.6 — Every Repository Gets an Outcome** is the next engineering
   release (`planned`, defined 2026-08-23; execution contract in §6). It
   starts when 2.9's three foundations-first items close — they are its
   preconditions in substance, not merely in order: a conclusion cannot be
   trusted while the visible and the enforced readiness models disagree.
   Every release from 1.x through 3.5 is closed; new work is still proposed
   as a release with its own contract, never appended to a closed one.
3. **Release 3.7 — Portfolio Value Proof** follows 3.6 (`planned`, contract
   in §6): ten representative repositories, chosen by kind, decide the full
   80+ rollout with recorded leverage numbers. The product earns its next
   release there, not by improving itself further.
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
| Release 2.9 foundations-first items (active)         | —                                             | none — engineering; resequenced 2026-08-23    |
| Release 3.6 Every Repository Gets an Outcome         | Release 2.9's three foundations-first items   | soft — substance, not sequence; engineering   |
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
credential prompt — listed, batched, ready), and **the engineering half is the
three foundations-first items** resequenced 2026-08-23 (the two mobile
engineering items shipped 2026-08-19 and are archived).

The full execution contract lives in one place,
[Release 2.9 below](#release-29--operator-field-proof--mobile-completion); this
heading exists so the validator can resolve the active-release pointer.

**Current focus (resequenced 2026-08-23):** the three foundations-first
engineering items at the top of the release's milestones — the two readiness
gates that disagree about the same repo, the two routes that name one concept
two ways, and the L1/L2 repair path for the 26 of 34 roadmap repos below L3.
The two mobile engineering items shipped 2026-08-19 (archived); the operator
batch rides Ben's next session at the machine.

---

## 6. Open Releases

### Release 2.9 — Operator Field Proof + Mobile Completion

**Status:** ACTIVE — promoted 2026-08-19 when Release 3.3 closed and left no
unblocked engineering release behind it. Mobile completion is **un-deferred**
in the same move: its 2026-08-11 resume condition (a PC workflow that runs to
completion) has been met three times over.

**Goal:** convert every surface that is `smoke-tested` but still waits on an
external resource into `operator-verified` with durable evidence, and close
the three foundations-first items. No new capability — this closes the
honesty gap between "the suite is green" and "this works in the field."

**Prerequisites:** each field-proof milestone names the one external resource
it waits on; none block each other, and several share a session. Batch them:
the operator, not the code, is the scarce resource.

**Resequenced 2026-08-23 under the product lens (§2).** Three items that had
sat under _Known issues_ now lead the engineering milestones: they are what
makes a finding explainable, and the preconditions in substance for Release
3.6.

#### Product outcomes

- No milestone is marked complete on an automated suite alone when what it
  claims needs hardware, elevation, credentials, or a human; `evidence/`
  carries a durable record for each proof, so the next agent reads it instead
  of re-litigating whether something works.

#### Engineering milestones

**Foundations first — resequenced 2026-08-23.** Moved up from _Known issues_
under the product lens (§2); close these before anything in Release 3.6.

- [ ] **Two gates disagree about the same repo.** The console's
      `dispatchReadiness` and the packaging path enforce different standards:
      packaging gates on L3+ maturity, the console on doc findings. On
      2026-08-19 the product packaged and dispatched INcendiary while the
      console reported it not ready. The guardrail "do not auto-dispatch
      without a visible readiness model" is only half true while the visible
      model and the enforced model differ. Decide which is authoritative and
      make the other consult it. **Resolution direction (2026-08-23):** the
      enforced model becomes _sufficiency of the execution contract_ — scope,
      acceptance criteria, a runnable verification, sized to repository kind
      and task scope — and the visible model displays that same judgement;
      L3+ maturity stays the default way roadmap-sourced work meets it, not a
      universal precondition. What exists:
      [`Automation.RoadmapPackaging.ps1`](backend/modules/automation/Automation.RoadmapPackaging.ps1)
      (shared verdict consumer),
      [`DocAudit.Scanner.ps1`](backend/modules/docaudit/DocAudit.Scanner.ps1)
      (documentation signal), and
      [`Roadmap.ExecutionContract.ps1`](backend/modules/roadmap/Roadmap.ExecutionContract.ps1)
      (authority). Focused red/green and live-route proof:
      [`execution-contract-readiness-2026-08-25.md`](evidence/verified/execution-contract-readiness-2026-08-25.md).
      _(state: ui-connected - shared backend and visible verdict ship; canonical
      module/api-host smoke exit 0 remains pending)_
- [ ] **Two routes name the same concepts differently.** `/api/roadmap/audit`
      emits `pendingCount`/`nextPendingItem`; `/api/portfolio/assessment` emits
      `pendingItemCount`/`nextPendingItemText` for the same ideas. Both are
      correct in isolation; together they cost a reviewer a false defect on
      2026-08-20. Align the names, or document the mapping where both are
      consumed. What exists:
      [`Portfolio.Assessment.ps1`](backend/modules/portfolio/Portfolio.Assessment.ps1)
      and [`apiClient.ts`](frontend/services/apiClient.ts). Canonical fields and
      compatibility aliases are gate-covered in
      [`Invoke-ApiHostSmokeTest.ps1`](scripts/Invoke-ApiHostSmokeTest.ps1).
      _(state: ui-connected - canonical names flow through backend, index, and
      frontend normalization; canonical api-host smoke exit 0 remains pending)_
- [ ] **26 of 34 roadmap repos are below L3 and cannot be dispatched.** The
      maturity gate is correct - a weak roadmap yields an ambiguous task - but
      the product's own answer for those repos is step 5 (preview-first
      roadmap/README repair), which is what would raise them. Confirm that
      path is reachable for an L1/L2 repo, since raising maturity is the only
      route from "assessed" to "helped" for most of the portfolio. Under the
      2026-08-23 lens this is the first "every repository gets an outcome"
      item: an L1/L2 repo must leave the console with a reachable
      preview-first repair **or** an explainable appropriate-as-is
      conclusion — never only "not dispatchable".
      [`Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1) proves
      the L1 preview and the bounded-L2 red/green path; the modal renders the
      named verdict and repair in
      [`RoadmapDispatchModal.test.tsx`](frontend/components/RoadmapDispatchModal.test.tsx).
      _(state: ui-connected - preview-first repair is reachable and named at
      L1/L2; canonical module/api-host smoke exit 0 remains pending)_

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

**Status:** planned — defined 2026-08-23 under the product lens (§2); it
starts when Release 2.9's three foundations-first items close.

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
      _(state: planned)_
- [ ] **Outcome card (UI).** Per repository: the conclusion, why, each
      domain's status and evidence, and the next action wired to the existing
      preview-first repair and packaging flows; repos without a roadmap show
      a conclusion, not `L0-Absent`; _appropriate as-is_ renders and filters
      like any other outcome. What exists:
      [`RepoEvaluationModal.tsx`](frontend/components/RepoEvaluationModal.tsx).
      _(state: planned)_
- [ ] **First interaction — the ranked `Today` landing.** The default view is
      a ranked table with _why now_, one primary next action per row, and
      effort (the value score and work-unit estimate already exist, three
      clicks deep) under a one-paragraph orientation; tab labels pose the
      question each view answers, with the Release 2.6 subtitle second.
      Decides the Lane 0.5 question (2026-08-23). What exists:
      [`DashboardViewTabs.tsx`](frontend/components/DashboardViewTabs.tsx),
      [`RepoGrid.tsx`](frontend/components/RepoGrid.tsx), the value scorer.
      _(state: planned)_
- [ ] **Flexible standards.** Per-kind applicability in
      `foundation-domains.json` (library, service, script collection,
      archived, minimal, externally managed) so a domain can be
      `not-applicable` with a stated reason; `L0-Absent` reads as "no plan
      recorded" with the smallest credible plan offered. _(state: planned)_
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
      foundations gained and hours returned over the window. _(state: planned)_
- [ ] **Define the intentional-engineering evidence model — define, not
      score.** Name the evidence per sub-area (test, architecture,
      operational, maintenance, delivery health), how each is read from a
      repository, which are cheap from existing signals (Actions results,
      merge readiness, PR state) and which need a detector; record it in
      `foundation-domains.json` as `not-scored`, so Release 3.7's ten
      repositories decide which evidence earns a detector. _(state: planned)_

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

- The progressive-disclosure question — **decided 2026-08-23**: the ranked `Today` landing with one primary action per row is Release 3.6's first-interaction milestone, and collapsible sections / regrouping the six peers resolve inside it; the three 2026-08-15 review inputs are [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

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
