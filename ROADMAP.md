# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 2.9 — Operator Field Proof + Mobile Completion**
> **Next active release:** **Release 3.6 — Every Repository Gets an Outcome** (`planned`, defined 2026-08-23 under the product lens in §2) — it starts when Release 2.9's three foundations-first engineering items close; 2.9's operator half keeps riding Ben's next session
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
to do — if an item is `[x]` here it is a mistake, not a record. The 2026-08-11
archive pass that restored that rule is recorded in `CHANGELOG.md`.

What remains falls into four kinds of work, and they are **not**
interchangeable — mixing them is what previously made the roadmap read as
"everything is done" while real gaps sat unlabelled:

1. **Genuinely unbuilt engineering** — Release 2.9's three foundations-first
   items (resequenced 2026-08-23), Release 3.6's milestones once those close,
   and the recorded cross-cutting items. This is the only kind an autonomous
   agent can close on its own.
2. **Elevated / hardware / human verification** — needs SYSTEM rights, a
   physical Android phone, or an operator sitting at an authenticated
   Claude Code session. No autonomous test can produce these.
3. **Product / design decisions** — waiting on a judgement, not on time or
   engineering (progressive disclosure; the `Checks: Read` grant).
4. **Calendar-gated accrual** — the 7/90-day trend windows fill only as
   time passes with capture running.

**Priority reset — 2026-08-11** (mobile deferred until a PC workflow ran to
completion) was satisfied and lifted 2026-08-19; its narrative is
[archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

**Product lens — 2026-08-23.** Every remaining roadmap-worthy idea is ranked
on operational efficiency and actionable improvement, under one principle:
**the product does not prescribe what a repository should become; it
identifies and strengthens the foundations that allow each repository to
succeed at what it is intended to be.** Full statement in §2 and the
[thesis doc](docs/product/portfolio-execution-console.md#foundation-domains);
it resequenced Release 2.9 and defined Release 3.6 the same day.

**Current focus (next agent actions), in order:**

- [ ] **Release 2.9 — foundations first (resequenced 2026-08-23).** The
      three engineering items that make findings explainable now lead the
      release's milestones: the two readiness gates that disagree about the
      same repo, the two routes that name one concept two ways, and the L1/L2
      repair path for the 26 of 34 roadmap repos below L3. Close these before
      anything in 3.6.
- [ ] **Release 3.6 — Every Repository Gets an Outcome** is defined in §6 as
      the next engineering release (`planned`). Start it when 2.9's three
      items close — not earlier, to manufacture momentum.
- [ ] **Batch the remaining operator-session work (2.9).** An elevated shell
      covers the watchdog _and_ the service installer; one authenticated shell
      covers the `gh agent-task` run and the re-homed live-portal proofs.
      Doing them separately wastes the scarcest resource here. The phone
      session is its own item and rides the same visit when the device is on
      the LAN.
- [ ] **Lane 0.2's two items need an operator action outside this repository**
      — the PAT's `Checks: Read` grant (optional; the `mergeStateStatus` proxy
      is the working contract) and the portal TLS certificate password, whose
      recovery path is exhausted and needs a regeneration in an elevated
      session.

**Forward arc.** Releases 3.0-3.5 describe the finished product: dispatch that
runs (3.0), the loop closing end to end and legibly (3.1), the delivery loop
closing without a hand-off (3.4), numbers an operator can act on (3.5), an 80+
repo portfolio that feels immediate (3.2), unattended operation (3.3).
Release 3.6 extends the arc from "the loop runs" to "every repository ends
with an explainable conclusion, and a next action only where one is
warranted."

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
improved.

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
3. **One batched operator session** — an elevated shell covers the watchdog,
   the service installer and 2.7's freeze-prevention deploy; one authenticated
   shell covers the `gh agent-task` run and the re-homed 3.1/3.5 live-portal
   proofs. Batching is the whole point: the operator, not the code, is the
   scarce resource.
4. **Trend accrual** closes itself as calendar time passes, provided capture
   keeps running.
5. **Mobile completion (2.9)** — un-deferred 2026-08-19 when its resume
   condition was met; both engineering items shipped the same day (archived),
   and the physical-Android proof rides the operator batch above.

**Dependency map (open work only):**

| Open item                                            | Depends on                                    | Type                                          |
| ---------------------------------------------------- | --------------------------------------------- | --------------------------------------------- |
| Release 2.9 foundations-first items (active)         | —                                             | none — engineering; resequenced 2026-08-23    |
| Release 3.6 Every Repository Gets an Outcome         | Release 2.9's three foundations-first items   | soft — substance, not sequence; engineering   |
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

Release 2.9 became the active release 2026-08-19, when Release 3.3 closed and
left no unblocked engineering release behind it. Its two halves have opposite
shapes: **the operator half waits on Ben and cannot be advanced by an agent**
(SYSTEM rights, a physical device, a browser with human eyes, an interactive
credential prompt — listed, batched, and ready), and **the engineering half is
now the three foundations-first items** resequenced 2026-08-23 (the two mobile
engineering items shipped 2026-08-19 and are archived; the physical-device
proof rides the operator batch).

The full execution contract lives in one place,
[Release 2.9 below](#release-29--operator-field-proof--mobile-completion), per
`ROADMAP_TEMPLATE.md`. This heading exists so the validator can resolve the
active-release pointer; it deliberately restates nothing.

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
external resource into `operator-verified` with durable evidence, and finish the
two mobile surfaces left incomplete under Release 2.5. No new capability — this
closes the honesty gap between "the suite is green" and "this works in the
field."

**Prerequisites:** each field-proof milestone names the one external resource
it waits on; none block each other, and several share a session. Batch them:
the operator, not the code, is the scarce resource.

**Resequenced 2026-08-23 under the product lens (§2).** Three items that had
sat under _Known issues_ lead the engineering milestones below: they are what
makes a finding explainable — the visible and enforced readiness models must
agree, one concept must carry one name, and a repo below L3 must leave the
console with a reachable next action or a stated conclusion. They are the
preconditions, in substance, for Release 3.6.

#### Product outcomes

- No milestone is marked complete on an automated suite alone when what it
  claims needs hardware, elevation, credentials, or a human.
- `evidence/` carries a durable record for each proof, so the next agent reads
  the evidence instead of re-litigating whether something works.

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
      make the other consult it. What exists:
      [`Automation.RoadmapPackaging.ps1`](backend/modules/automation/Automation.RoadmapPackaging.ps1)
      (maturity gate) and
      [`DocAudit.Scanner.ps1`](backend/modules/docaudit/DocAudit.Scanner.ps1)
      (readiness gate). _(state: scaffolded - both gates exist and are
      individually correct)_
- [ ] **Two routes name the same concepts differently.** `/api/roadmap/audit`
      emits `pendingCount`/`nextPendingItem`; `/api/portfolio/assessment` emits
      `pendingItemCount`/`nextPendingItemText` for the same ideas. Both are
      correct in isolation; together they cost a reviewer a false defect on
      2026-08-20. Align the names, or document the mapping where both are
      consumed. What exists:
      [`Portfolio.Assessment.ps1`](backend/modules/portfolio/Portfolio.Assessment.ps1)
      and [`DocAudit.Scanner.ps1`](backend/modules/docaudit/DocAudit.Scanner.ps1).
      _(state: scaffolded - both payloads ship; only the naming differs)_
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
      _(state: planned - repair workflows exist; their reachability at L1/L2
      is unverified)_

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

- [ ] Deploy the Release 2.7 Phase D freeze prevention to the live service. All
      three engineering parts ship; only the install remains.
      **Measured 2026-08-20:** the running service is missing **4 of 52**
      declared GET routes (`/api/maintenance/ledgers`, `/api/maintenance/backups`,
      `/api/portfolio/scan/status`, `/api/portfolio/snapshot`) - it predates
      Release 3.5. One elevated command upgrades it
      (`Install-RepoManagementService.ps1 -Action Repair`), and
      [`Test-LiveServiceCurrency.ps1`](scripts/Test-LiveServiceCurrency.ps1)
      proves whether it landed rather than trusting a health check, which
      answered 200 the entire time the service was weeks behind. What exists:
      [`Install-RepoManagementService.ps1`](scripts/Install-RepoManagementService.ps1),
      [`Install-PortalWatchdog.ps1`](scripts/service/Install-PortalWatchdog.ps1)
      and [`Watch-PortalHealth.ps1`](scripts/service/Watch-PortalHealth.ps1),
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
- The visible and the enforced readiness models agree for every repo, one
  concept carries one name across `/api/roadmap/audit` and
  `/api/portfolio/assessment`, and an L1/L2 fixture repo reaches a
  preview-first repair or a stated conclusion — each proven by a gate shown
  red first.

#### Out of scope

- New product capability; remote (non-LAN) mobile access; native apps.

**Validation plan:** the two halves are verified differently, deliberately.
The engineering half (the foundations-first items; the shipped mobile items
before them) lands under the module smoke and api-host smoke with a gate
shown red first, `npm run test:unit` at an emulated 390px viewport where a
surface is touched, and `npm run typecheck` / `npm run lint` / the
PSScriptAnalyzer ratchet at baseline; CI is the arbiter. The operator half is
verified by the operator — on the device, at the elevated prompt, with eyes on
the surface — and recorded in `evidence/operator-verification-log.jsonl` with
the surface id and what was observed. No agent may mark an operator item
verified.

**Risks:** the physical-device proof must run against the LAN-bound host, not
loopback, or it proves nothing about the setup it is meant to prove; and an
operator item marked verified from a green suite rather than from eyes on the
surface would reintroduce exactly the honesty gap this release exists to
close.

**Dependencies:** the operator's presence at the machine (elevated session,
authenticated `gh`, browser), a Galaxy S24 Ultra on the same LAN
([`lan-mobile-setup.md`](docs/reference/lan-mobile-setup.md)), and Lane 0.2's
certificate regeneration for the TLS-dependent portal proofs. The mobile
engineering half depends on none of these.

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

- [ ] **Conclusion model (backend).** One per-repo conclusion object —
      `conclusion` (strengthen | appropriate-as-is | insufficiently-understood),
      `reason`, per-domain `{domain, status: present|weak|missing|not-applicable,
      evidence, nextAction?}`, `basis` — derived from signals that already
      exist (README contract, doc findings, roadmap audit and maturity,
      structure audit, the scope classifier) and served by
      `GET /api/portfolio/conclusions` and per repo. Domains and their
      per-kind applicability live in `backend/config/foundation-domains.json`
      (`schemaVersion: "v1"`), so refining a domain is a data change. The
      _intentional engineering_ domain ships `not-scored` until its evidence
      is defined. What exists:
      [`Portfolio.Assessment.ps1`](backend/modules/portfolio/Portfolio.Assessment.ps1),
      [`DocAudit.Scanner.ps1`](backend/modules/docaudit/DocAudit.Scanner.ps1),
      [`Portfolio.Scope.ps1`](backend/modules/portfolio/Portfolio.Scope.ps1).
      _(state: planned)_
- [ ] **Outcome card (UI).** Per repository: the conclusion, why, each
      domain's status and evidence, and the next action wired to the existing
      preview-first repair and packaging flows; repos without a roadmap show
      a conclusion, not `L0-Absent`; _appropriate as-is_ renders and filters
      like any other outcome. What exists:
      [`RepoEvaluationModal.tsx`](frontend/components/RepoEvaluationModal.tsx),
      [`InsightsView.tsx`](frontend/components/InsightsView.tsx).
      _(state: planned)_
- [ ] **First interaction.** A portfolio-level orientation (what this
      evaluates, what it uncovers, how findings strengthen a portfolio) and
      tab labels that pose the question each view answers, with the Release
      2.6 per-view subtitle as the second line. What exists:
      [`DashboardViewTabs.tsx`](frontend/components/DashboardViewTabs.tsx).
      _(state: planned)_
- [ ] **Flexible standards.** Per-kind applicability in
      `foundation-domains.json` (library, service, script collection,
      archived, minimal, externally managed) so a domain can be
      `not-applicable` with a stated reason; `L0-Absent` reads as "no plan
      recorded" with the smallest credible plan offered, and the 2.9 L1/L2
      repair path is the default next action at L1/L2. _(state: planned)_
- [ ] **Measure.** `GET /api/portfolio/trend` gains a foundation-coverage
      series (per domain: present / weak / missing / not-applicable counts),
      captured by
      [`Invoke-DailyEvidence.ps1`](scripts/Invoke-DailyEvidence.ps1) and
      rendered in Insights as foundations gained over the window.
      _(state: planned)_

#### Acceptance criteria

- 100% of indexed repositories carry a conclusion with a non-empty reason;
  zero repositories present `L0-Absent` or "not applicable" as their only
  state — asserted over the live index and a fixture set that includes a
  no-roadmap repo, an archived repo, a vendored repo, and a minimal utility.
- Every `strengthen` conclusion names a next action whose route exists and
  returns `application/json` with HTTP 200 for the fixture repo.
- Every `appropriate-as-is` conclusion cites its evidence (classifier result,
  archive marker, explicit repo declaration) — never an absence of findings.
- Adding a domain or a per-kind applicability rule is a JSON-only change,
  covered by the config-integrity gate and a module-smoke fixture.
- The first screen states what the product evaluates; every tab label poses
  its question (unit test).
- `GET /api/portfolio/trend` reports foundation coverage for the window, and
  Insights renders it.

#### Out of scope

- New detectors beyond composing existing signals; prescribing a target
  architecture for any repository; auto-applying repairs; mobile surfaces.

**Validation plan:** module smoke — the conclusion model over the fixture
set, with the detector shown red first against a fixture whose reason is
blank; api-host smoke — the conclusions and trend routes return JSON (the
SPA fallback makes status alone meaningless); `npm run test:unit` — outcome
card and orientation copy; the config-integrity gate for
`foundation-domains.json`; CI Smoke is the arbiter.

**Risks:** domains hardening into a taxonomy (mitigated by data-defined
domains and the explicit refinement rule); _appropriate as-is_ becoming a
dumping ground (every such conclusion must cite evidence); scoring the
intentional-engineering domain before it is defined (it ships `not-scored`).

**Dependencies:** Release 2.9's three foundations-first items; the existing
assessment, audit, classifier, and trend modules. No external resource.

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
