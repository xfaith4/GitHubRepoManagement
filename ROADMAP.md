# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 2.9 — Operator Field Proof + Mobile Completion**
> **Next active release:** **Release 3.6 — Every Repository Gets an Outcome** is in **`validation`** — engineering complete 2026-08-27, all six milestones `smoke-tested` and every acceptance criterion gated; only operator verification remains, batched with 2.9. The next release is **Release 3.7 — Portfolio Value Proof**: cohort preparation may proceed; Lane 0.15 truth validation **landed 2026-09-05** (#228), so measured execution now waits only on live Release 3.6 verification, the D-006 cohort decision and the cohort freeze — all operator work, no engineering. Ten real repositories decide the 80+ rollout
> **Work ordering:** dependency-driven, not insertion order — see
> [Execution Order and Dependencies](#execution-order-and-dependencies)
> **Canonical product direction:** [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
> **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
> **Dated change log:** [`CHANGELOG.md`](CHANGELOG.md)

---

## Current Status (Agent Context)

**Last updated:** 2026-09-06

Releases 0.4 through 2.6, 2.8 and 3.0 are **engineering-complete and archived**,
as is every completed milestone from the releases and lanes still open below.
Their full text lives in
[`docs/history/completed-releases.md`](docs/history/completed-releases.md).

**This file carries open work only.** Every checkbox in it is something still
to do — if an item is `[x]` here it is a mistake, not a record (rule restored
by the 2026-08-11 archive pass, recorded in `CHANGELOG.md`).

What remains falls into four kinds of work that are **not** interchangeable —
mixing them once made the roadmap read "everything is done" over real gaps:

1. **Genuinely unbuilt engineering** — Release 3.7's four milestones, Release
   3.8's six (defined 2026-09-06, sequenced after 3.7) and the recorded
   cross-cutting items. This is the only kind an autonomous agent can close on
   its own.
2. **Elevated / hardware / human verification** — SYSTEM rights, a physical
   Android phone, or an operator at an authenticated session; no autonomous
   test can produce these.
3. **Product / design decisions** — waiting on a judgement, not on time or
   engineering. These have one durable home:
   [`docs/governance/open-decisions.md`](docs/governance/open-decisions.md).
   **Nine of the ten are now answered** (2026-09-06 closed D-001 through D-005,
   D-007 and D-008); only D-006's owner-intent labels remain open, and its
   ruling already released the work it was blocking. A decision raised only in
   conversation gets made by default, by whichever agent next touches the code.
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

**What changed 2026-09-05 (record, not an action).** Lane 0.15's truth defects
are fixed and validated (#228): every portfolio timestamp now carries a UTC ISO
8601 basis before any `DateTime` coercion, a value with no determinable basis
reports unavailable instead of inventing one, and `Blocked` is named and given a
denominator wherever it is shown. A raw-wire gate inspects JSON tokens before
`ConvertFrom-Json` can parse the evidence away. Lane 0.17's array-collapse sweep
landed with it (#229): 56 sites, not the estimated ~30, plus an AST lint gate
holding a zero baseline. Together these clear the **engineering** half of Release
3.7's entry gate; everything still open on that gate is operator work, below.
This is emphatically **not** live operator verification, which no agent may
claim. Evidence: [`evidence/verified/trial-truth-readiness-2026-09-05.md`](evidence/verified/trial-truth-readiness-2026-09-05.md).

**What changed 2026-09-06 (record, not an action).** The execution model gained
a written spec and the decision backlog was cleared.
[`docs/governance/Agent-Execution-Governance.md`](docs/governance/Agent-Execution-Governance.md)
is now the design authority for how work reaches a coding agent: a
**provider-neutral task contract** with a **provider-aware scheduler** across
Codex, Claude Code and GitHub Copilot, per-provider capacity in each provider's
own unit, and a promotion boundary where the operator approves a **verified head
SHA**. It is defined as **Release 3.8** (§6) and it supersedes the 2026-07-07
decisions in `docs/execution-orchestrator-design.md`, whose P0 is the only part
ever built — notably reversing that document's "merge automatically when green".
Seven open decisions were answered the same day and one was re-ruled: roadmaps
may declare dependencies (D-001), nested repositories are not portfolio entries
by default (D-002), the PAT gets `Checks: Read` (D-003), RoadmapOrchestrator
does **not** become a third dispatch target (D-004), the archive signal ships as
awareness metadata (D-005), the lane patience defaults stand (D-007), and
**dispatch authority narrows to the Dispatch Board** (D-008, reversing the
default shipped hours earlier under D-010). D-006 stays open but no longer
blocks: an unrepresented trial category is recorded as such, never filled by a
substitute. Nothing in `backend/` or `scripts/` changed — this was a contract
and planning pass.

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
- [ ] **Release 3.8 — Provider-Aware Execution** is defined and sequenced
      **after** 3.7, not started before it: the trial measures the loop as it
      exists, and 3.8 changes what runs inside it. Two dependencies can be
      satisfied in parallel — D-001's dependency notion and D-003's
      `Checks: Read` grant.
- [ ] **Grant the PAT `Checks: Read`** — decided 2026-09-06 (D-003), so this is
      now an operator action rather than an open question. It rides the same
      operator batch. The TLS certificate
      closed 2026-08-29: regenerated around the stored password and live as
      `https://127.0.0.1:7071`. Operator note: plain `http://` bookmarks stop
      working, and the login password is unrecoverable by design — reset with
      `scripts\Set-PortalLogin.ps1` if forgotten.

**Forward arc.** Releases 3.0-3.5 describe the finished product: dispatch that
runs, the loop closing legibly and without a hand-off, numbers an operator can
act on, an 80+ repo portfolio that feels immediate, unattended operation.
Release 3.6 extends it to "every repository ends with an explainable
conclusion"; Release 3.7 makes the product prove, on ten real repositories,
that it returns more time than it takes. Release 3.8 makes the execution layer
provider-aware, so that proof is not capped by one agent's subscription.

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
| **3.8**   | **Provider-Aware Execution**                                             | **`planned`** 2026-09-06 — Codex/Claude/Copilot behind one provider-neutral task contract  |

> **Note on `.5` numbering.** Reserve it for course corrections like 1.7.5;
> default new work to integer minor releases.

### Execution Order and Dependencies

Release numbers identify scope — they do not dictate sequence. Work through
open items in the order below, and update this section whenever a lane
closes or a new dependency appears.

**Trial sequencing — approved 2026-09-05.** Select the ten by kind now; fix
and validate the remaining Lane 0.15 truth defects before measured execution.
Live Release 3.6 verification and operator approvals remain required. Lane
0.18 acceptance evidence is required for each counted improvement, but an
independent operator check can supply it; completing all of Lane 0.18 is not
a prerequisite. **Dependency ordering is no longer blocked:** D-001 was
answered 2026-09-06 — a managed roadmap may optionally declare dependencies,
within one repository, acyclic, keyed on stable item ids, gating dispatch
eligibility. The cohort is unblocked too; see the D-006 note under Release 3.7.

1. **Release 3.7 — Portfolio Value Proof** is the next engineering
   release (execution contract in §6). Its four milestones follow the
   trial-facing consistency fixes: Release 3.6 finished 2026-08-27 with
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

**Where Release 3.8 sits — after the trial, not before it.** The value trial
measures the delivery loop as it exists; Release 3.8 changes what runs inside
that loop. Defining it now (2026-09-06, from the
[execution-governance spec](docs/governance/Agent-Execution-Governance.md)) is
deliberate: the trial's false positives and bad recommendations then land
against a named target instead of an unwritten one. Two of its dependencies are
already satisfiable in parallel — D-001's dependency notion and D-003's
`Checks: Read` grant — and both are listed in the map below.

**Dependency map (open work only):**

| Open item                                            | Depends on                                    | Type                                          |
| ---------------------------------------------------- | --------------------------------------------- | --------------------------------------------- |
| Release 3.6 operator verification                    | Eyes on the live portal (batch with 2.9)      | hard - human; engineering is done             |
| Release 3.7 measured value trial                     | Lane 0.15 truth; live 3.6 proof; approvals    | hard — evidence integrity + operator          |
| Release 3.8 provider-aware execution                 | Release 3.7 baseline; D-001; D-003 grant      | soft — sequencing; one operator grant         |
| Lane 0.2 `Checks: Read` grant (D-003: grant it)      | An operator action outside this repository    | hard — external                               |
| Lane 0.5 tab disclosure                              | A product decision, not engineering time      | hard — design                                 |
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
      authenticated host. **Engineering closed 2026-08-28; only the elevated
      run and eyes-on remain.** The portal bound `127.0.0.1` because the
      Release 2.2 guard refuses a non-loopback bind while API auth is off, and
      auth had never been configured (`settings.json` carried no `auth` block);
      the installer's own default of `0.0.0.0` would have been refused. The
      listener is a raw `TcpListener`, so a LAN bind needs **no urlacl and no
      elevation** — only the Machine-scope variables, firewall rule and service
      reconfigure do. What shipped:
      [`Enable-SharedLanAccess.ps1`](scripts/Enable-SharedLanAccess.ps1) does
      the sequence in the order that never leaves the API open (key → toggle →
      firewall on Private only → rebind → verify), supports `-WhatIf`
      unelevated, prints the key once, and **fails loudly if an anonymous
      request is not refused after the rebind**. Proved on this machine
      against `192.168.50.200:7099`: guard refuses with auth off, binds with
      auth on, anonymous `401`, keyed `200 application/json`.
      **Adjacent leak found and fixed in flight:** enabling auth with the
      toggle alone made the host write a 64-character plaintext API key into
      `backend/config/settings.json` — a file listed in `.gitignore` but still
      **tracked**, so the ignore entry does nothing and one `git add -A`
      publishes it. Demonstrated, then fixed: a generated key now goes to
      `output/auth/api-key` (genuinely ignored), and a key found in
      `settings.json` is honored but warned about by name. Gates: two new
      `Invoke-AuthSmokeTest.ps1` sections — "Non-loopback bind WITH auth binds
      and still enforces the key" (the positive case nothing covered: Part 1
      proved the gate on loopback, Part 2 proved refusal off it, so
      bind-plus-auth was untested) and "Auth enabled without a key stores it
      outside version control" — both confirmed red against `HEAD` first, the
      second reporting the 64-character key it found in the tracked file.
      _(state: smoke-tested → needs one elevated run + `operator-verified`)_
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

**Status:** planned — defined 2026-08-23; sequencing approved 2026-09-05.
Follows Release 3.6. Measured execution is held until the truth checks, live
operator verification and ten-category cohort are ready. Its job is to make
the product earn its next release against the real portfolio, not itself.

Preparation and per-repository evidence: [trial record](evidence/trials/release-3.7/README.md)
and `evidence/trials/release-3.7/cohort.json`. Nine candidates are named; the
tenth category is recorded as unrepresented under D-006's 2026-09-06 ruling
rather than filled by a substitute. No improvements are counted yet.

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
      chosen. Nine provisional candidates and an explicit unfilled external-management
      slot are recorded in `evidence/trials/release-3.7/cohort.json`. **D-006's
      ruling (2026-09-06) releases the selection:** external management is owner
      intent and may not be inferred from age, activity, remote ownership or
      documentation maturity, so a category with **no natural member is recorded
      as unrepresented** rather than filled by a substitute. An empty category
      is a valid trial outcome. Selection completes with nine named
      repositories and the tenth category recorded as having no cohort member.
      _(state: scaffolded)_
- [ ] **Run the conclusion model over the ten**, recording per repository:
      what it is, whether it still matters, its state, what limits its value,
      the highest-value next action, and whether the product can execute or
      facilitate it. _(state: planned)_
- [ ] **Execute at least five improvements** through preview → approve →
      execute → validate, recording operator minutes, agent first-pass
      result, and whether the repository is materially stronger afterwards —
      appropriate-as-is or archive counts as a conclusion outcome, not automatically
      as one of the five improvements. Each counted improvement needs an
      independently checked acceptance criterion and before/after evidence;
      merge evidence alone is insufficient. _(state: planned)_
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

**Dependencies:** Lane 0.15 truth validation; live Release 3.6 verification;
the operator's approvals and measured effort. **D-006 no longer blocks the
cohort** (decided 2026-09-06): external management is owner intent and may not
be inferred, so a category with no natural member is recorded as unrepresented
rather than filled by a substitute. The trial proceeds with nine named
repositories and records the tenth category as having no cohort member.

---

### Release 3.8 — Provider-Aware Execution

**Status:** planned — defined 2026-09-06. The design authority is
[`docs/governance/Agent-Execution-Governance.md`](docs/governance/Agent-Execution-Governance.md);
this block carries only milestones and gates. It supersedes the 2026-07-07
decisions in [`docs/execution-orchestrator-design.md`](docs/execution-orchestrator-design.md),
whose P0 is the only part ever built. Follows Release 3.7 — the value trial
measures the loop that exists, and this release changes what runs inside it.

**Goal:** the work contract becomes provider-neutral and the scheduler becomes
provider-aware. A task carries objective, scope, acceptance criteria,
verification and a permission envelope, and says nothing about which agent runs
it; the orchestrator chooses between Codex, Claude Code and GitHub Copilot on
eligibility and remaining subscription capacity, records why, and returns work
to the queue — never fails it — when a provider is exhausted.

#### Product outcomes

- Roadmap work keeps moving when one provider hits a limit, because
  `CAPACITY_WAIT` is a normal operating state rather than a failed run.
- No subscription is unexpectedly exhausted by ordinary roadmap work: each
  provider keeps a configured reserve only remediation may consume.
- The operator approves a **verified head SHA**, not a pull request number, and
  execution below that line needs no per-step attendance.

#### Engineering milestones

- [ ] **Give a task a provider-neutral contract and a structured result.** A
      `WorkPacket` (objective, scope paths, acceptance criteria, verification
      commands, permission envelope) persisted outside the commit-eligible tree,
      which each adapter renders into its own prompt.
      [`Roadmap.Dispatcher.ps1`](backend/modules/roadmap/Roadmap.Dispatcher.ps1)
      builds prose today and nothing reads a result back. A run producing no
      structured `ExecutionResult` fails by name instead of reaching
      `awaiting-review`. _(state: planned)_
- [ ] **Persist capacity per provider, in the provider's own unit.** Named
      windows with `remainingRatio`, `resetAt` and a confidence rank; reserves
      and ranking weights live in `backend/config/`, not in code.
      [`BudgetLedger.ps1`](backend/modules/agent-runs/BudgetLedger.ps1) keeps the
      portfolio work-unit quota and gains no token conversion it cannot source.
      A limit re-queues the task with workspace, branch, attempt and session
      intact. _(state: planned)_
- [ ] **Route between providers, and add the Codex adapter.** One registry
      replaces the `claude`/`copilot` pair hardcoded in
      [`Automation.RoadmapQueue.ps1`](backend/modules/automation/Automation.RoadmapQueue.ps1),
      [`Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1) and
      `frontend/types.ts`, and reconciles the third vocabulary
      (`operator-runner`) the approval route writes. Eligibility then ranking,
      selection reason recorded, presence counts derived from the registry
      rather than naming providers. _(state: planned)_
- [ ] **Move push and PR opening to Repo Manager; bind approval to the verified
      SHA.** The agent exits at `IMPLEMENTATION_COMPLETE`; Repo Manager pushes,
      opens the pull request and monitors CI on a cadence without holding an
      execution slot — which also closes Lane 0.17's open "nothing refreshes the
      board" non-blocker. A head change after verification invalidates
      `READY_FOR_OPERATOR`. Merge stays an explicit operator action.
      _(state: planned)_
- [ ] **Remediate from evidence, and hand off between providers.** Attempt and
      remediation counts survive a restart; a CI failure builds a
      `RemediationPacket`, resumes the original session where capacity allows,
      and otherwise transfers a `HandoffPacket` of durable evidence to another
      eligible provider. No provider depends on another's conversation.
      _(state: planned)_
- [ ] **Normalize execution events onto the Dispatch Board.** Provider output
      converts to the canonical `execution.*` vocabulary, reconciled with
      [`roadmap-events.md`](standards/roadmap/roadmap-events.md) so exactly one
      is canonical. New states arrive as a mapped dimension in
      [`status-vocabulary.md`](docs/reference/status-vocabulary.md), keeping the
      Release 3.5 rule that no two dimensions share a word. Per D-008 this is
      the one surface that dispatches. _(state: planned)_

#### Acceptance criteria

- A task contract carries no provider-specific execution assumption unless the
  task genuinely requires a provider-specific capability.
- A provider at a hard limit is not dispatched; exhaustion re-queues the task
  rather than failing it, and the task resumes after the window resets.
- Capacity is persisted per provider in its native unit with no invented token
  conversion, and survives a restart along with attempt count, session id,
  cooldown and verified SHA.
- Provider selection records its reason; a run records the provider, session id
  and usage it actually consumed.
- Operator approval names a verified head SHA, and a head change after
  verification invalidates readiness.

#### Out of scope

- Concurrency above one local execution slot, raised only after capacity
  accounting, session persistence, CI reconciliation and restart recovery are
  proven.
- Automatic merge. The promotion boundary stays an explicit operator action.

**Validation plan:** module smoke covers the pure decision tables — eligibility,
ranking, capacity arithmetic, handoff construction — offline, in the shape
`Resolve-LaneObservation` already uses; api-host smoke covers the routes; every
new gate is proven red against a violating fixture before it is trusted.

**Risks:** an adapter that quietly widens the packet's scope or permission
envelope (the contract forbids it and a gate asserts it); equating provider
token telemetry with remaining subscription allowance; reserves set so high that
ordinary work starves.

**Dependencies:** D-001 for the dependency clause of eligibility; D-003's
`Checks: Read` grant for check-run-level CI evidence; Release 3.7's trial for
the measured baseline this release changes.

---

## 7. Cross-Cutting Engineering Work

Continuous, not release-scoped. **This section carries open work only.**
Completed cross-cutting items are in
[the archive](docs/history/completed-releases.md#cross-cutting-engineering-work-completed-items)
(2026-08-07) and [the 2026-08-08 batch](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).

### Lane 0.2 — Credential freshness

- [ ] **Grant the PAT `Checks: Read` — decided 2026-09-06 (D-003).**
      _(state: planned — an operator action outside this repository)_ The token
      403s on check-runs and GraphQL `statusCheckRollup`. The open question was
      grant-or-decline-permanently, and the answer is **grant**: detailed CI
      state is becoming a first-class input to orchestration, remediation and
      merge readiness rather than the optional `gh pr checks --watch` detail it
      was when this was raised. The scope stays read-only and within least
      privilege. Batch it with the Release 2.9 operator session.
- [ ] **Read check-run detail where it exists; keep `mergeStateStatus` as the
      documented fallback.** _(state: planned)_
      [`MergeReadiness.ps1`](backend/modules/agent-runs/MergeReadiness.ps1)
      reads `mergeable_state` from the Pulls API, which is why a `BLOCKED`
      rollup cannot tell a required check still running from one that failed —
      the ambiguity the merge loop works around by polling. With the grant in
      place, prefer per-check conclusions and keep the proxy for a token
      without the scope. Release 3.8's CI-failure evidence collection is the
      consumer that wants the finer signal. Gate: a fixture with one pending
      and one failed required check reports different blockers, and a token
      lacking `Checks: Read` still evaluates through the proxy rather than
      erroring.
- [x] **Regenerate the portal TLS certificate (recovery is dead).** _(state:
      done 2026-08-29 — the portal serves HTTPS; verified live:
      `tlsState: enabled`, `CN=localhost`, valid to 2031-08-29, and plain
      `http://` no longer answers)_ The "one elevated step remains" note below
      resolved itself: shawl's restart policy recycled the service during the
      test-suite work and the new host loaded the repaired certificate — the
      elevated restart was never run by hand. Unplanned, and worth recording:
      the service's own restart policy is an unelevated path to picking up
      config changes, at the cost of not choosing the moment.
      Machine-scoped `REPO_MGMT_TLS_PFX_PASSWORD` (17 chars) does not open
      `backend\config\tls\portal.pfx`, so the portal serves plain HTTP on
      loopback while `REPO_MGMT_TLS_PFX` points at the pfx. Re-confirmed
      2026-08-29 against the live service, which logs the degraded state on
      every start: `the certificate could not be loaded ("The specified
      network password is not correct")`. The pfx on disk dates from
      2026-07-07; the password was rotated after it and the certificate was
      never regenerated to match, which is the whole defect.

      **Recovery of the old password is not an option** and is not needed: the
      pre-#53 shawl logs that recorded it have rotated away (a 2026-08-10 sweep
      of the shawl log dir, `evidence/` and `output/` found zero `-PfxPassword`
      matches, which also closes the old plaintext-leak concern).

      **The remedy is cheaper than this item previously recorded.** The earlier
      plan generated a NEW password and reconfigured the service, which needs
      an elevated session twice over (a Machine-scope env write plus a service
      restart). Instead, regenerate the certificate **around the password
      already stored in `REPO_MGMT_TLS_PFX_PASSWORD`** — `New-RepoManagement‑
      TlsCertificate.ps1` writes the pfx with .NET directly (no PKI module, no
      certificate store, no elevation) and accepts `-PfxPassword`. Nothing then
      has to change in the environment or in `settings.json`, so **only the
      service restart needs admin**, and the blast radius is one file.

      All steps are **done** (2026-08-29); only 5 (client trust) is optional
      and still open — accept the browser warning, or import
      `backend\config\tls\portal.cer`:

      1. ~~Read the existing Machine-scope `REPO_MGMT_TLS_PFX_PASSWORD`; abort
         if absent rather than inventing a new secret.~~ Present, 17 chars.
      2. ~~`New-RepoManagementTlsCertificate.ps1 -Force -PfxPassword <existing>`
         with SANs covering `localhost`, the hostname, `127.0.0.1` and the
         current LAN IPv4.~~ Issued `CN=localhost`, SAN
         `DNS=localhost, DNS=THESHIRE, IP=127.0.0.1, IP=192.168.50.200`,
         thumbprint `3ECA086B0D5C…`, valid to 2031-08-29. The old pfx
         (2026-07-07) is kept out of the repo as evidence; `*.pfx` and
         `backend/config/tls/` are both gitignored, so no key is committed.
      3. ~~Prove the pfx opens with the stored password before touching the
         service, and prove the old one did not.~~ Both, with the **same**
         password: old → `The specified network password is not correct`;
         new → loads, `CN=localhost`, `notAfter=2031-08-29`. Nothing in the
         environment or in `settings.json` changed, and no elevation was used.
      4. ~~Restart `RepoMgmtPortal` (elevated).~~ Attempted unelevated and
         refused as expected; then shawl's restart policy recycled the service
         on its own and the new host loaded the certificate. Confirmed live:
         `tlsState: enabled`, `encryptedInTransit: true`, 72 repos over
         `https://127.0.0.1:7071`, plain `http://` refused.
      5. Trust the exported `.cer` on this machine (`-TrustLocally`, also
         elevated) or accept the browser warning; import it on the phone for
         the LAN portal.

      **Consequence, stated because it breaks working URLs:** once the
      certificate loads, the host wraps every connection in an SslStream, so
      the portal becomes `https://127.0.0.1:7071` and plain `http://` stops
      answering. Bookmarks, the Vite dev proxy and any script calling the
      loopback API must move to `https://`.

- [x] **The HTTPS flip's fallout, swept rather than awaited.** _(state:
      shipped 2026-08-29)_ Enabling TLS makes the portal stop answering plain
      `http://`, so everything holding an `http` assumption about a live portal
      broke or would have. Found by sweeping for `7071`/`http://` consumers,
      not by waiting for each to fail:
      [`Enable-SharedLanAccess.ps1`](scripts/Enable-SharedLanAccess.ps1) probed
      `http` only (its verification would burn 90s and blame the service) and
      printed "TLS is NOT enabled" unconditionally — it now probes both
      schemes, tolerates the self-signed certificate, carries the answering
      scheme into the phone URL it prints, and states the transport it actually
      saw; the Vite dev proxy needed `secure: false` for a self-signed https
      target; the frontend smoke's probe needed `-SkipCertificateCheck`;
      [`ApiReference.tsx`](frontend/components/ApiReference.tsx) had a
      hardcoded `http://192.168.50.200:7071` fallback — one operator's LAN
      address compiled into every build, wrong host for anyone else and wrong
      scheme for everyone — replaced with an honest "unavailable outside a
      browser"; and [`Invoke-DailyEvidence.ps1`](scripts/Invoke-DailyEvidence.ps1)
      was the fourth host-starting gate inheriting `REPO_MGMT_TLS_PFX`, now
      cleared in its job and added to the inherited-env gate.

- [x] **Surface `tlsState: degraded` to signed-in operators, not only at the
      login screen.** _(state: shipped 2026-08-29 — found while diagnosing the
      item above)_ The host has reported TLS state on every transport payload
      since Release 3.x, and the frontend renders it in exactly one place:
      [`Login.tsx:115`](frontend/components/Login.tsx#L115). An operator who is
      already signed in — which is every operator, most of the time — is never
      told that the portal claiming TLS is serving plain HTTP. That is how this
      certificate stayed broken from 2026-08-10 to 2026-08-29 with the warning
      printed on every single service start. **Done means the degraded state is
      visible on an authenticated surface** (the page header carries
      `RunnerHealthIndicator` and `AgentActivityIndicator` already and is the
      obvious home), and a test proves it renders for `degraded` and stays
      silent for `enabled`. Shipped as
      [`TransportSecurityIndicator`](frontend/components/TransportSecurityIndicator.tsx)
      in the page header, fed from the `authStatus` the header already holds —
      no new request. It warns on two states and no others: `degraded` (config
      claims TLS, the connection has none) and unencrypted on a **non-loopback**
      bind (the shared-LAN path without a certificate). A plain-HTTP loopback
      bind is the documented default and renders nothing, because a permanent
      chip nobody needs is how the ones that matter stop being read. Eight tests
      cover both directions, including that an unreported bind is not treated as
      exposed.

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
      payload. **Decided 2026-09-06 (D-005): yes, as awareness metadata, not an
      enforcement requirement.** The contract may state that history is
      externalized and where it lives; it never requires a repository to
      externalize history and prescribes no archive format. The purpose is
      semantic accuracy for portfolio reporting, progress calculation and future
      automation. The `spec/roadmap-contract` mirror moves with the schema, so
      the sync gate is part of this item, not a follow-up.
- Sanction the external-archive pattern in the standard — done (`ROADMAP_TEMPLATE.md` §6 "External archive option"); [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

### Lane 0.8 — Verification gate integrity (CI audit 2026-08-10)

**Re-homed from Release 3.1 on its closure (2026-08-15):**

- [x] **Give the portal settings file the override its queue already has, so a
      gate stops writing the file the operator is reading.** _(state: shipped
      2026-08-29 — reproduced live, then closed)_
      `Invoke-ApiHostSmokeTest.ps1` repoints the git-tracked
      [`backend/config/settings.json`](backend/config/settings.json) at its own
      fixture workspace for the duration of the gate. It restores the file
      afterwards, byte-exact, and that restore works — but for the ~10 minutes
      the gate runs, the **live portal reads the same file**. Observed
      2026-08-29 during a routine suite run: the console emptied mid-session
      because the status cache is keyed by scan root
      (`f:\development\20_staging|depth:3|nonGit:False`), and while the fixture
      path was installed that key had no entry to serve. The operator sees a
      portfolio that has apparently vanished, with nothing on screen connecting
      it to a test run.

      This is the reading-side twin of the 2026-08-19 queue incident, and it
      has the same shape of fix. Release 2.9 gave the queue `Get-RoadmapQueue‑
      Path` plus `REPO_MGMT_QUEUE_PATH` so redirecting it is one decision
      instead of four edits that can disagree; settings never got an
      equivalent, so the only way for a gate to point the host at different
      settings is to **overwrite the operator's copy**.

      Note the smoke does not write the file directly — it `POST`s
      `/api/settings` and the **host** writes it. So the override has to be
      honoured by the host on both the read and the write path, or the fixture
      POST lands on the tracked file regardless.

      Precise steps:

      1. Add `Get-PortalSettingsPath -WorkspaceRoot` beside the queue resolver's
         pattern, honouring `REPO_MGMT_SETTINGS_PATH` and falling back to
         `backend\config\settings.json`. Home it where both the api-host and
         `backend/adapters` can dot-source it without a circular load.
      2. Route all **seven** current construction sites through it: six in
         [`Start-RepoManagementApiHost.ps1`](backend/api-host/Start-RepoManagementApiHost.ps1)
         (settings read, secret-strip, setup-status probe, setup config write,
         `GET /api/settings`, `POST /api/settings`) and one in
         [`Adapters.ps1`](backend/adapters/Adapters.ps1) (the scope policy).
      3. Point the api-host smoke at a temp copy via the override, and **delete
         the backup/restore machinery it needed** — a restore that never has to
         run is the proof the mutation is gone. Keep one assertion that the
         tracked file's bytes are unchanged across the whole gate.
      4. Extend the module-smoke queue-path gate to refuse inline settings-path
         construction under `backend/`, with the same operator-path-only rule
         under `scripts/` (the smokes legitimately build settings paths inside
         their own fixture workspaces).
      5. Prove it non-vacuously: the detector must fail a planted violating
         fixture first, and the gate must name the file when the old inline
         line is re-injected.

      **Done means** a full api-host smoke run leaves `git status` clean for
      `backend/config/settings.json` at every point during the run, not merely
      at the end.

      **Shipped, with two things the plan did not foresee.** First, there were
      **three** gates writing the tracked file, not one:
      `Invoke-AuthSmokeTest.ps1` did the same backup-and-restore, and
      `Invoke-DailyEvidence.ps1` kept a net for both. All three now redirect or
      declare intent, and the two host smokes assert the tracked bytes are
      byte-identical across the run instead of restoring them. Second, the
      auth smoke's "must not persist a secret into settings" assertions had to
      follow the host's file rather than the tracked one — left pointing at the
      tracked file they would pass because the host can no longer write it,
      which is a vacuous green, not a proof.

      The gate itself was **wrong on its first two attempts and the injection
      test is what said so.** Attempt one anchored on
      `'backend\config\settings.json'`, but `Adapters.ps1` resolves from
      `backend\` and writes `'config\settings.json'` — re-injecting that exact
      inline build left the gate green, meaning it would never have caught the
      call site it was written for. Attempt two matched its own detector
      fixtures. Final form: match any `Join-Path` ending in a
      `config\settings.json`, skip the resolver and this smoke's own source,
      exempt `Install-RepoManagementService.ps1` (acting on the operator's real
      file is its job), and allow a `$...Tracked...` variable so the
      untouched-assertions can still name the file. Verified both ways —
      green clean, and red naming `Adapters.ps1` with the bypass re-injected.

- [ ] **The portal watchdog is restarting a healthy service every 3 minutes —
      its probe URL was frozen at registration time.** _(state: diagnosed
      2026-08-29; the fix is ONE elevated re-registration, waiting on the
      operator)_ Found live the evening the portal flipped to HTTPS: shawl's
      log shows `Received stop event` every ~3 minutes (59 restarts in one
      window), each an SCM stop ordered by `RepoMgmtPortalWatchdog` — a SYSTEM
      scheduled task invisible to unelevated queries (`schtasks` answers
      _Access is denied_, not _not found_, which is itself the tell).
      [`Watch-PortalHealth.ps1`](scripts/service/Watch-PortalHealth.ps1) on
      disk handles HTTPS correctly — defaults to `https`, skips the
      self-signed certificate on both pwsh and 5.1, and documents this exact
      failure — but the REGISTERED task carries the `-BaseUrl` baked into its
      argument string when it was installed, before TLS. The plain-http probe
      dies in the TLS handshake, the watchdog declares the host frozen, and
      restarts a healthy service, forever. The handshake-failure flood in
      `apihost.log` is that probe.

      The lesson the HTTPS fallout sweep missed, stated for the next flip of
      any kind: **grep finds stale assumptions in files; it cannot find frozen
      copies of arguments in the task registry.** Registered tasks, service
      ImagePaths, and shortcuts all hold snapshots of defaults that later
      change — a config-flip sweep must enumerate REGISTRATIONS, not just
      sources. The runner task from this same release has the identical
      exposure (its argument string is also frozen; benign today).

      Fix, elevated: `pwsh -File .\scripts\service\Install-PortalWatchdog.ps1`
      — the installer already unregisters and re-registers with current
      defaults. Done means shawl's log shows no stop events for an hour and
      the watchdog's next cycles leave the service pid unchanged.

- [ ] **[non-blocker]** **Isolate the runner heartbeat the way the queue,
      settings and TLS config now are.** _(state: planned — found 2026-08-29
      while verifying the port and settings fixes)_ The api-host smoke asserts
      the **no-operator-runner** path of the presence route
      (`The smoke host has no operator runner; reporting one present would be
      the false-green this route exists to prevent`). The route reads the real
      heartbeat at `output\roadmap-task-runner.heartbeat.json`, so a live
      scheduled runner makes it correctly report a runner and the assertion
      fails. The operator must therefore **stop their runner to run the test
      suite** — the same "a gate cannot coexist with the operator's live state"
      shape as the three fixes above, and the last one left. CI never sees it
      because a runner is never installed there. An override on the heartbeat
      path, set by the smoke exactly as `REPO_MGMT_QUEUE_PATH` and
      `REPO_MGMT_SETTINGS_PATH` now are, removes the constraint. Deliberately
      **not** bundled into this PR: it changes what the presence route reads,
      which deserves its own change and its own proof.

- [x] **The api-host smoke defaulted to the port the portal service listens
      on, and the host it starts evicts whatever holds that port.** _(state:
      shipped 2026-08-29 — found while verifying the settings override above)_
      `Invoke-ApiHostSmokeTest.ps1` declared `-Port 7071` and
      `-BaseUrl http://127.0.0.1:7071` as its DEFAULTS. 7071 is the installed
      portal service's port, and `Start-RepoManagementApiHost.ps1` deliberately
      terminates whatever already holds the port it is told to bind, so that a
      restart-in-place is not blocked by its own stale process. Pointed at the
      operator's port, that mechanism attacks the operator's service:

      ```text
      Port 7071 is already in use by pwsh (PID 35160). Terminating it before startup.
      ```

      The portal survived only because an unelevated smoke cannot kill a
      LocalSystem service — luck, not design; run from an elevated shell it
      would have taken the portal down mid-session.
      [`Invoke-TestSuite.ps1`](scripts/Invoke-TestSuite.ps1) always passed
      `7171` explicitly, so the suite was never exposed and the default sat
      unnoticed behind it; only a direct invocation reached it.

      Two changes, because the default alone is not a guarantee: the default is
      now **7171**, and the smoke **refuses to start** when anything already
      holds its target port, naming the PID and process rather than evicting
      it. An explicit `-Port 7071` is now a refusal, not a kill. Verified both:
      `-Port 7071` against the live service refuses by name and leaves PID
      35160 listening; the default run proceeds untouched.

- [x] **The API contract gate could not pass on a machine running our own
      shared-LAN configuration.**
      [`Enable-SharedLanAccess.ps1`](scripts/Enable-SharedLanAccess.ps1) writes
      `REPO_MGMT_API_KEY` and `REPO_MGMT_REQUIRE_API_KEY` at **Machine** scope —
      correctly; that is the Release 2.9 feature doing its job. But a
      machine-scope variable reaches every shell forever, so the host
      [`Invoke-ApiContractTest.ps1`](scripts/Invoke-ApiContractTest.ps1) starts
      inherited it, enforced auth, and answered `401` to tests that send no
      credentials by design. Measured on this machine: **32 of 37 failed, every
      one a `401`, not one a contract violation** — and the gate reported them
      as 32 broken contracts, pointing at the routes instead of at the
      environment. The same defect class as the task runner's inherited
      `GITHUB_TOKEN`: a variable no one passed silently changing what a process
      does. The gate now clears the inherited value for **its own process only**
      and says so, leaving the operator's LAN auth intact at User and Machine
      scope; auth enforcement stays the Auth smoke's gate, which sets the
      variables itself. Verified both ways: 32 failures before, 37/37 after,
      with a real machine-scope key inherited. _(state: shipped 2026-08-29)_
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

- [ ] **Classify a repository nested inside another as `nested`, not as its own
      portfolio entry.** _(state: planned)_ Decided 2026-09-06 (D-002): the
      portfolio represents managed projects, not merely every `.git` boundary
      present on disk. `custom_SereneHarmonySite` is a working tree inside
      `SereneHarmony_Site_Starter`, which is also one, and the scan counts both
      — correctly, as the 70-versus-72 explanation in Lane 0.15 established.
      Give `Get-RepoScopeClassification`
      ([`Portfolio.Scope.ps1`](backend/modules/portfolio/Portfolio.Scope.ps1))
      a `nested` verdict beside `vendored` and `archived`, so a nested
      repository is reported and never silently lost, with an explicit opt-in
      promoting one to independently managed when it genuinely has its own
      lifecycle. **The portfolio total falls by one when this lands** — record
      that in the Release 3.7 trial evidence so it is not later read as scan
      drift. Gate: a fixture with a repository inside a repository classifies
      the inner one `nested` and drops it from the managed count, and the
      opt-in promotes it back.

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

- [x] **Surface the staleness verdict where the operator ranks work.** The
      `Today` landing — the default view, and the one the Release 2.9 operator
      session reads first — now leads with a banner naming the index age and
      every reason it cannot be trusted, above the orientation paragraph and
      before any row. `GET /api/operations/repos` carries `basis` from the
      same verdict (the assessment-cache fallback says it has no index behind
      it at all, which is a stronger reason to speak, not a reason to stay
      quiet), `normalizeConclusionBasis` treats **only an explicit `false` as
      fresh**, and `TodayView` shows the banner when the prop is absent — so
      the failure mode of every layer is to warn, never to reassure. Covered
      by three component tests including one that the banner stays out of the
      way when the index is current, so the gate cannot pass by always
      warning. _(state: smoke-tested)_

- [x] **Put the scan the banner asks for inside the banner.** The staleness
      banner told the operator to _"run a portfolio scan before acting"_ while
      offering no control that does so — found by the operator on 2026-08-30,
      searching the screen for a button that did not exist. `POST
      /api/portfolio/scan` and its client wrapper `startPortfolioScan()` had
      shipped with Release 3.2's background scan, but nothing in the UI ever
      called them: the chip could observe and cancel a scan, never start one,
      and the only rescan affordances lived on the Repository Grid tab under
      different names ("Rescan all", Refresh). The banner now carries a **Run
      portfolio scan** button wired to that route; progress shows in the
      existing header chip, and the Dashboard watches for the terminal state
      and re-pulls `/api/operations/repos` so the banner clears — or restates
      its reasons — from the rebuilt index instead of freezing on the
      pre-scan verdict. An already-running scan and a refused start are each
      said, never pretended. Covered by five component tests, including that
      a still-stale refresh re-offers the button and that the guidance
      renders without a dead control when no handler is wired.
      _(state: smoke-tested)_

- [x] **Remove the staleness banner from the Today landing (operator
      decision, 2026-08-30).** With a scan completed three minutes earlier,
      the landing still opened with the amber warning — showing the fallback
      _"was not established"_ reason, which explains nothing an operator can
      act on — and the operator's verdict was that a first screen that
      appears to have a problem costs more confidence than the freshness
      warning earns. The banner is gone from `TodayView` (a component comment
      marks the removal as deliberate, so it is not "restored" as a
      regression); a component test now pins that **no** staleness banner
      renders on this view, stale or absent basis alike. The verdict itself
      is unchanged and still rides every payload as `basis`
      (`/api/operations/repos`, `/api/portfolio/conclusions`,
      `/api/portfolio/tech-inventory`) and the Dependencies inventory panel;
      the **Run portfolio scan** control survives as a quiet neutral button
      in the Today filter row, with the same started / already-running /
      refused reporting and re-arm on refresh. This decision also supersedes
      the former non-blocker _"render the same verdict on the outcome card
      and Insights"_ — no more warning banners; the basis stays a payload
      fact for surfaces to consult, not an alarm to lead with.
      _(state: smoke-tested)_

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

### Lane 0.14 — Console UI audit follow-ups (operator audit 2026-08-29)

An operator audit of the live console found the product contradicting itself
before it found anything visual: `Blocked` reads 1, 17 and 58 on three surfaces
because six components use one word for different quantities; "how many
repositories" has six denominators; and seven timestamps in one sitting span
three clock bases. Those are Lane 0.15 (below). This lane is the part that is
**component-wide styling debt** — real, counted, and deliberately not blocking
anything.

Four single-location fixes from the same audit already shipped and are not
repeated here: the global `:focus-visible` ring, the muted-foreground token
lift to `#858fa3` (4.51:1 on the worst surface, from 3.03:1), the ARIA tablist
on the seven views, and `Escape`-to-close plus a focus trap on the two dialogs
that had neither.

- [x] **Put Help where the question gets asked, and give the console's words a
      definition.** Two findings, one fix. **(a) Reach** — `Help` and
      `API Docs` were buttons in the Repository Grid's action bar, so the
      guide and the endpoint reference were reachable from one of seven tabs.
      An operator on Today, Work Queue or Operations had no route to either.
      They now sit in the page header beside `Settings`, which moved there for
      exactly this reason in an earlier release, and they are **one dialog**:
      the API reference is a tab inside Help
      ([`ApiReference.tsx`](frontend/components/ApiReference.tsx), converted
      from a modal to a panel) rather than a second button answering an
      adjacent question. **(b) Vocabulary** — the console had no glossary.
      Badge meanings lived in a legend inside the grid, readiness meanings in a
      hover `title`, and maturity levels in a modal reachable only from a repo
      that already had a roadmap; `docs/reference/status-vocabulary.md` settled
      the model but in a file the operator never opens. A `Definitions` tab now
      renders [`lib/glossary.ts`](frontend/lib/glossary.ts): every term states
      what it means **and what computed it**, with a `caveat` wherever a
      displayed value can be mistaken for a measurement it is not —
      `PRs` reads 0 in Local mode because nothing populates it, `Clean` in
      GitHub mode means unmeasured, `unknown` drift is not stale, and
      `no-checklist` is a sound document, never a damaged one. The two
      `Blocked` meanings are documented as two entries, which is Lane 0.15's
      finding explained rather than resolved — the surfaces still share the
      word. Drift is gated in both directions: the readiness and maturity
      groups are `Record`s over their unions, so a new union member is a
      **compile** error, and `glossary.test.ts` reads the vocabulary doc and
      fails naming any documented value with no entry (proven by injecting
      one). The doc itself was missing `no-checklist` from the readiness row;
      added. Help also adopted `useDialogDismiss`, taking the dialog contract
      to 3 of 20. _(state: shipped 2026-08-29 — 390 frontend tests green,
      UI ratchet re-baselined down 649→643 tinyText and 5→4 outlineNone)_

- [ ] **Collapse the ad-hoc button palette into a semantic token set.** The
      audit counted **21 distinct button background colors** on one tab. They
      are ad hoc, so no checker can currently tell a legitimate new one from an
      accidental one — which is why the UI ratchet
      ([`tools/Measure-UiRatchet.mjs`](tools/Measure-UiRatchet.mjs)) counts
      unrestored `outline-none` but **not** button colors. That rule is a
      consequence of this item, not a substitute for it. The Nocturne token
      sheet ([`frontend/styles.css`](frontend/styles.css)) now supplies the
      semantic set this item asked for — one accent plus three status hues —
      so what remains is the enforcement, not the palette.
      **Done means CI rejects a raw hex or a bare Tailwind color utility in a
      button background** — at which point the second ratchet rule ships with
      it. _(state: planned)_

- [x] **Raise the type floor from 12px to 13px.** **Superseded — not done, and
      no longer wanted.** The item assumed the console's ≤12px text was
      accidental debt. The Nocturne migration ([`MIGRATION.md`](MIGRATION.md)
      §4) makes it deliberate: the ladder is 10px eyebrows, 11px meta, 12–13px
      body, because "the density is the point — an operator sees the whole
      state without scrolling." Raising the floor would now break the design
      the console is being migrated to, so the `tinyText` ratchet rule that
      policed it was retired in the same change
      ([`tools/Measure-UiRatchet.mjs`](tools/Measure-UiRatchet.mjs)) — it had
      also only ever matched integer px, so the ladder's 11.5px and 12.5px
      steps passed it unseen. The accessibility question underneath it did NOT
      go away and is now the open one: the §2 opacity ladder's bottom three
      rungs measure 4.55:1, 3.91:1 and 3.58:1 on `--color-bg`, which is
      large-text-only, and the design uses them at 10–11.5px — including for
      `unmeasured`. That is tracked as its own item below rather than as a type
      floor. _(state: superseded 2026-09-01 — density is a design decision, not
      debt)_

- [ ] **Resolve the Nocturne opacity ladder against WCAG AA.** The migration's
      text hierarchy is opacity over `--color-text`
      ([`frontend/styles.css`](frontend/styles.css)), and the top four rungs
      clear AA comfortably (14.54:1, 9.21:1, 7.62:1, 5.19:1 on `--color-bg`).
      The bottom three do not: 50% is 4.55:1, 45% is 3.91:1, 42% is 3.58:1 —
      all below the 4.5:1 body-text floor, and all used at 10–11.5px where the
      large-text exemption does not apply. 42% is where `unmeasured` renders,
      which MIGRATION.md §5.1 makes load-bearing, so this cannot be fixed by
      dropping the value. **Done means every rung used for body text clears
      4.5:1 on both grounds, or the ones that cannot are moved off body text**,
      with the measurement recorded. _(state: planned)_

- [ ] **Add breakpoints above 768px.** The console declares **two responsive
      breakpoints, both under 768px**, so every viewport from a laptop to a
      wide desktop renders one fixed desktop layout — the 310 interactive
      controls the audit counted on a single tab are laid out for none of them
      specifically. Define the wide tiers and prove them at 1280px and 1920px.
      _(state: planned)_

- [ ] **Write `settings.json` with a stable key order, and not at all when
      nothing changed.** A running portal rewrites
      [`backend/config/settings.json`](backend/config/settings.json) with the
      keys reordered and **no value altered** — verified by comparing the two
      revisions with keys sorted. The file is tracked, so the working tree
      reads dirty in every session for a change nobody made, and eventually
      someone stages it without diffing. This is the same class as the rest of
      the audit: the system generating noise that trains its operator to
      ignore signals. Serialize with a fixed key order and skip the write when
      the content is unchanged. _(state: planned)_

- [ ] **Adopt the dialog dismiss contract in the remaining 17 modals.**
      [`useDialogDismiss`](frontend/hooks/useDialogDismiss.ts) now carries
      `Escape`-to-close, a focus trap and focus restoration, proven by seven
      tests, and is wired into `SettingsModal`,
      `RepositoryImprovementWorkflowModal` and `HelpModal`. **Twenty modal components ship in
      this console and exactly one handled `Escape` before this lane**
      (`AgentRunSheet`, with its own inline implementation to be replaced by
      the hook). Each remaining dialog is a two-line change: call the hook,
      attach the ref to the panel. _(state: planned)_

---

### Lane 0.15 — The console contradicts itself (operator audit 2026-08-29)

**2026-09-05 implementation:** trial-facing fixes are connected in the working
branch. Validation and live deployment boundaries are recorded in
`evidence/verified/trial-truth-readiness-2026-09-05.md`; open checkboxes remain
until the required proof is complete. The paragraphs below retain the original
audit observations; their old line numbers are historical pointers.

The audit's headline, and the reason it outranks every visual finding: once an
operator catches the console disagreeing with itself on a number, they stop
trusting all of it. Each item below was **confirmed in code**, not inferred
from the screenshot.

- [ ] **Give the six `Blocked` counts six names.** `Blocked` reads **1, 17 and
      58** on three surfaces simultaneously, and all three are correct — they
      count different things: queue items in `blocked` execution state
      ([`ExecutionQueuePanel.tsx:27`](frontend/components/ExecutionQueuePanel.tsx#L27)),
      repos blocked from dispatch for missing docs or a roadmap parse error
      ([`PortfolioMissionSection.tsx:36`](frontend/components/PortfolioMissionSection.tsx#L36)),
      merge blockers on a single PR
      ([`OperationsWorkspaceView.tsx:2179`](frontend/components/OperationsWorkspaceView.tsx#L2179)),
      plus a per-repo badge and a filter value in `RepoGrid`. Reconciling the
      numbers is the wrong fix — they are different quantities wearing one
      word. Name each, and state the denominator on the surface that shows it.
      _(state: ui-connected — `evidence/verified/trial-truth-readiness-2026-09-05.md`)_

- [ ] **Stop the app switching data source without being asked.**
      [`App.tsx:240`](frontend/App.tsx#L240) calls `setViewMode('github')` on a
      successful GitHub fetch, and that fetch is reachable from inside the
      Settings dialog via `onConnectGitHub` — so connecting a credential
      silently changes which source the operator is _looking at_, and `Cancel`
      cannot revert it because `viewMode` was never modal state. Connecting a
      credential and choosing a view are different acts; the source toggle
      already exists for the second. _(state: ui-connected — `evidence/verified/trial-truth-readiness-2026-09-05.md`)_

- [x] **Never render "not computed" as a number.** In GitHub mode
      `Dirty Repositories` showed **0**, which reads as "clean" and means "no
      working tree exists here". Confirmed at the source, not just the
      consumer: `Get-GitHubReposViaApi`
      ([`Start-RepoManagementApiHost.ps1`](backend/api-host/Start-RepoManagementApiHost.ps1))
      hardcodes `status = 'clean'` and `uncommittedChanges = 0` for every
      remote repository, so the Dashboard filter could only ever return 0.
      A count is now `number | null`, where `null` means **not measurable from
      this source**; [`SummaryCard.tsx`](frontend/components/SummaryCard.tsx)
      renders it as an em dash with the reason beneath it and a
      `data-unavailable` marker, and the Dashboard passes `null` for dirty
      whenever the source is GitHub. The sibling tiles were checked rather
      than assumed: `Commits This Week` and `Stale Repositories` ARE genuinely
      computed in GitHub mode (commit counts from the API, staleness from
      `pushed_at` via `Resolve-RepoStaleness`), so they keep their numbers.
      Gated by three `PortfolioSummarySection` tests including a row-wide
      tripwire — proven red first by forcing the old always-render path, where
      2 of 7 failed. _(state: smoke-tested)_

- [ ] **Show the Today rank basis instead of hiding it in a tooltip.** The
      audit read a value-49 repo above a value-80 one as a sort bug; it is not.
      `todayRanking` ranks conclusion, then curation, then whether a row offers
      an action, and only then value
      ([`todayRanking.ts:120-145`](frontend/lib/todayRanking.ts#L120-L145)), so
      that order is correct and deliberate. The defect is that the `rankBasis`
      audit trail the module already builds for exactly this question renders
      **only as a `title=` tooltip**
      ([`TodayView.tsx:187`](frontend/components/TodayView.tsx#L187)) — invisible,
      hover-only, unreachable by keyboard. Do not change the comparator.
      _(state: ui-connected — `evidence/verified/trial-truth-readiness-2026-09-05.md`)_

- [ ] **Fix the dead-end automation instruction.**
      [`automationStatus.ts:100`](frontend/lib/automationStatus.ts#L100) tells
      the operator _"Enable it in Settings to keep favorites assessed
      automatically."_ The Settings dialog holds seven fields and none of them
      is that toggle — nor packaging, auto-scan, lane concurrency, or the
      scoring thresholds that drive every number in the product. Either build
      the control or stop naming it. _(state: ui-connected — `evidence/verified/trial-truth-readiness-2026-09-05.md`)_

**Already fixed (2026-08-29) — the snapshot route answered 500 on every
operator machine.** `Get-StatusFromCache` returns
`{ hit, source, ageSeconds, cachedAt, response }` on every path: the payload is
an API envelope under `response`, and the four other callers unwrap it that
way. The snapshot route instead read `.entries` and `.scannedAt`, which is
**`Get-RoadmapFromCache`'s** shape, so StrictMode threw the moment a status
cache existed. All seven `/api/portfolio/snapshot` contract tests failed at
their FIRST assertion (`StatusCode | Should -Be 200`), so every rule after it —
including the timezone-basis and denominator invariants — never executed at
all. CI passed because a fresh clone has no cache, `hit` is false, and the
branch never ran: the gate was real but had **never once evaluated this path**.
Fixed by unwrapping `response.data.repos` and taking the UTC `cachedAt` as the
status basis. A regression test now writes a cache fixture so the branch runs
on a fresh clone too, and asserts the fixture's own repo count so a key
mismatch fails loudly instead of silently skipping — verified by re-injecting
the bug and watching the guard alone go red.

**Re-audit against a working snapshot (2026-08-29).** Run once the unifier
actually returned 200, to test the prediction that these contradictions were
consumers stamping their own values because `Build-PortfolioSnapshot` 500'd.
The prediction was half right, and the half that was wrong matters more.

**Collapsed, as predicted — the denominators.** They now form one stated chain
rather than six free-floating numbers: `repoCount` **72** (`status-scan`),
`inScopeRepoCount` **58** with `denominator: 72` declared on the metric,
`staleRepoCount` and `dirtyRepoCount` both carrying `denominator: 58`. The 57
is `blockedCount` — 57 of the 58 in-scope. So 72 → 58 → 57 is coherent and
self-describing.

**Did NOT collapse — Blocked.** Two live surfaces still report different
numbers, and both are right: `/api/execution/metrics` says `blocked=17`
(ledger **execution state**, alongside `idle=30 ready=20 complete=4`), while
`/api/portfolio/assessment` says `blockedCount=57` (repos **blocked from
dispatch**). The fallback theory is therefore dead for this one: these are two
definitions sharing one word, and reconciling them is hand work, not a
consequence of the fix.

**Did NOT collapse — the clock bases.** Three remain, and the fix did not
touch two of them: the snapshot emits UTC `Z`, `/api/execution/metrics` emits
a local offset `-04:00`, and **`/api/portfolio/assessment` and
`/api/operations/repos` emit `createdAt` as locale text with no basis at all**
(`01/12/2026 05:25:34`, on the wire, unparsed). The "four hours fast" reading
is explained by the first two: `...T08:56:29Z` and `...T04:56:29-04:00` are
the SAME instant, so any surface rendering the UTC one as if it were local
runs exactly four hours ahead.

**A new discrepancy the guard surfaced — resolved 2026-09-04.** An independent
filesystem walk found **70** working trees under the configured root at depth
3 while the status cache reported **72**. The scan was right and the walk was
wrong; both reasons are recorded on the closed item below.

The re-audit's two live `Blocked` definitions are covered by the first naming
item above; they are not a second implementation task.

- [ ] **Give `/api/portfolio/assessment` and `/api/operations/repos` a
      timezone basis.** Both serialize `createdAt` as locale text
      (`01/12/2026 05:25:34`) with no `Z` and no offset — the only two
      surfaces with no basis at all. This is what the existing contract
      assertion was written to catch and cannot, because it skips any value
      `ConvertFrom-Json` has already promoted to `[datetime]`. Fix the
      serializer and the assertion together. _(state: ui-connected — `evidence/verified/trial-truth-readiness-2026-09-05.md`)_

- [x] **Explain the 70-vs-72 repository gap — the scan was right.** _(state:
      operator-verified 2026-09-04; re-runnable, see below)_ The audit's
      independent walk was the thing miscounting, for two compounding reasons.
      It **stopped at the first `.git`**, so it could not see a repository
      nested inside another one (`SereneHarmony_Site_Starter` contains
      `custom_SereneHarmonySite`, and both are working trees), and it walked
      to **depth 3** while the scan walks one level deeper, the same
      `MaxDepth + 1` convention `Invoke-RoadmapScan` uses so a repo at the
      deepest level is not invisible. A descending walk reproduces the product
      exactly: depth 3 finds 71, depth 4 finds 72, depth 5 finds 72. One more
      shape a naive walk misses: a linked worktree stores `.git` as a **file**,
      not a directory, so a directory-only test skips it. No product change;
      the number on the landing surface was correct all along. Whether a
      repository nested inside another should be its own portfolio row is a
      product question, recorded as D-002 in
      [`docs/governance/open-decisions.md`](docs/governance/open-decisions.md).

- [ ] **Verify the remaining clock and denominator presentation on the live console.**
      The snapshot 500 and 70-versus-72 discrepancy are resolved above. The
      re-audit established the coherent 72 scanned → 58 in-scope → 57 dispatch
      blocked chain; different quantities must retain their own denominators.
      Do not repeat the obsolete hypothesis that the snapshot has never run.
      Verify the newly named execution/dispatch/PR blockers, stable selected
      source, visible rank basis and local rendering of explicitly based UTC
      timestamps after deployment. Automated proof is in
      `evidence/verified/trial-truth-readiness-2026-09-05.md`.
      _(state: ui-connected)_

- [ ] **Close the timestamp-basis test's own blind spot.** The contract test
      _"every timestamp field in key payloads carries an explicit timezone
      basis"_ guards its check with `-and $value -is [string]`, and
      PowerShell's `ConvertFrom-Json` silently promotes an ISO-8601 string to
      `[datetime]`. Every timestamp that parses as a date is therefore skipped
      by the very test that exists to check timestamps. Assert against the raw
      response body instead, as the new cache-fixture test does.
      _(state: ui-connected — `evidence/verified/trial-truth-readiness-2026-09-05.md`)_

---

### Lane 0.16 — The Dependencies tab answered a different question than it asked (operator feedback 2026-08-30)

The tab led with _"What does this repository depend on?"_ and answered with
roadmap cross-references — for a portfolio, in the plural, and usually with
nothing at all. To an operator, dependencies are what the repositories run
on: Node, Next.js, PostgreSQL, SQLite, Docker. The product had no answer to
that question anywhere.

- [x] **Make the Dependencies tab answer with technologies.**
      `Get-RepoTechnologyProfile`
      ([`Portfolio.Assessment.ps1`](backend/modules/portfolio/Portfolio.Assessment.ps1))
      detects languages, frameworks, data stores, and infrastructure from
      each repository's manifests — named files, dependency names in
      `package.json` (root and one level down, for monorepos), Python
      manifest contents, and compose service images — **during the index
      build**, because a scan belongs to the background worker, never to a
      request. Every index row now carries `technologies`, each detection
      with the manifest evidence that produced it. `GET
      /api/portfolio/tech-inventory` aggregates from the written index only
      (read-budget class `portfolio-index`, on the route census and the
      budget-wiring gate), carrying the index staleness verdict as `basis` —
      and because the detector lives under `backend/modules/portfolio`, the
      logic fingerprint moved on its own, so every pre-upgrade index honestly
      reads stale-by-logic until the next scan. The tab now leads with a
      `TechInventoryPanel` grouped by category with per-technology repo
      counts and expandable evidence, renames the old section to _"Cross-repo
      roadmap references"_, and the tab question becomes _"What does the
      portfolio run on?"_. A pre-detection index renders as **"predates
      technology detection — rescan"**, never as a portfolio with no
      technology in it. Gated by the module-smoke section "Technology
      inventory" (which caught a StrictMode empty-pipeline bug on its first
      red run) plus 6 `TechInventoryPanel` component tests; full module smoke
      and the 409-repo-free census pass locally.
      _(state: smoke-tested)_

- [x] **Amber means a problem, never a statement about the data (operator
      principle, 2026-08-30).** Stated while removing the Today staleness
      banner and extended here: _"Anytime we show an amber text box, it
      better represent an actual problem"_ — a validity note styled as a
      warning reads as an error in the manager itself. The inventory panel's
      amber basis banner is gone; freshness is quiet footer metadata (when
      the index was generated, plus _"a portfolio scan refreshes this"_ when
      stale), with a component comment and test pinning that no amber basis
      banner returns. Fetch-failure notices (the `stale` async-panel state)
      keep their amber: a refresh that failed is an actual problem. Pinned by
      the reworked `TechInventoryPanel` basis test.
      _(state: smoke-tested)_

- [ ] **[non-blocker]** Detect versions, not just presence — the inventory
      says _which_ repos run Node, not which Node; a version column would
      turn the panel into an upgrade-planning surface. Needs a per-manifest
      version parse and a staleness policy for engines fields.
      _(state: planned)_

---

### Lane 0.17 — The dispatch console could not dispatch (operator evaluation 2026-08-30)

An operator evaluation of the Copilot Execution Lanes tab found the page's
one verb broken end to end: **Dispatch** opened a preview modal instead of
assigning a lane, the modal had no dispatch action of its own, the packet
build failed for a repo the queue itself called Ready, and the failure
surfaced as the browser's bare _"Failed to fetch"_ because the host wrote
the 500 to the wrong stream under TLS. Around the broken verb, the surface
over-promised: five state tiles that count but cannot filter, a three-tab
layout where "Top Candidates" duplicates rows 1–3 of "Ready Queue", and a
tab name ("Copilot Execution Lanes") that claims execution monitoring the
ledger does not do — states are manual bookkeeping derived from audit data,
not observed agent activity.

- [x] **Deliver route errors over the stream the request arrived on.** The
      accept-loop catch in
      [`Start-RepoManagementApiHost.ps1`](backend/api-host/Start-RepoManagementApiHost.ps1)
      wrote its 500 to the raw `$client.GetStream()`; under TLS the request
      rode an `SslStream`, so plaintext bytes corrupted the session and every
      uncaught route error reached the browser as _"Failed to fetch"_ with
      the real message lost. _(state: smoke-tested 2026-08-30 — the catch now
      prefers `$req.Stream`, then `$activeStream`, and reuses the request's
      correlation id; per-request variables reset at loop start so a stale
      `$req` from a previous connection can never answer. `POST
      /api/copilot-task/preview` gained a route-level catch, pinned by a new
      api-host smoke step: an unknown repo must return structured JSON whose
      `operation` is `copilot-task.preview` — shown red first against the
      pre-fix host, which answered from `api.request`. The preview modal's
      roadmap-scan hint now renders only for roadmap errors (a network
      failure gets a connectivity hint), pinned by two component tests. The
      TLS half specifically — plaintext-on-SslStream — is asserted by code
      path, not by an automated TLS fixture; the operation-name gate is the
      tripwire that keeps route errors out of the accept-loop catch.)_
- [x] **Carry the known roadmap path through dispatch, and never write item
      text into `roadmapPath`.** The ledger entry carries `roadmapPath`, but
      [`ExecutionQueuePanel.tsx`](frontend/components/ExecutionQueuePanel.tsx)
      dropped it when opening the preview, so the packet build re-resolved
      from caches and threw when they were cold; and
      [`Execution.Ledger.ps1`](backend/modules/execution/Execution.Ledger.ps1)
      fell back to `$doc.nextPendingRoadmapItem` — the roadmap item _text_ —
      when no roadmap-audit entry existed, which is why a queue row could
      show raw markdown as its "path". _(state: smoke-tested 2026-08-30 —
      `entry.roadmapPath` travels with the dispatch callback (component test:
      a pathless entry passes `undefined`, never `''`); the ledger fallback
      is now empty, pinned by a module-smoke fixture (`smoke-repo-noaudit`)
      proven red against the pre-fix module first.)_
- [x] **Give the preview modal its dispatch.** From this tab the flow
      dead-ended: preview opened, and the only actions were Copy and Close —
      `assignExecutionLane` was unreachable. _(state: smoke-tested 2026-08-30
      — [`CopilotTaskPreviewModal.tsx`](frontend/components/CopilotTaskPreviewModal.tsx)
      offers "Dispatch to Lane" when its caller provides the action;
      `Dashboard.tsx` wires it to `assignExecutionLane` and bumps a refresh
      token so the board reloads its ledger on success; a backend refusal
      (lanes full, not dispatchable) renders inline, and a preview-only
      caller gets no dispatch button. Five component tests cover the action,
      the refusal, the absence, and both error hints.)_
- [x] **One filtered queue instead of three overlapping lists; the state
      tiles become the filters.** The five state tiles were static; the page
      said 27 Ready while showing three; "Top Candidates" was rows 1–3 of the
      next tab; blocked repos hid in an "Other repos" appendix. _(state:
      smoke-tested 2026-08-30 —
      [`ExecutionQueuePanel.tsx`](frontend/components/ExecutionQueuePanel.tsx)
      pins the two lanes on top, renders one ranked ledger list filtered by
      state-tile toggle buttons (counts stay portfolio-wide; the active tile
      clicked again clears the filter; Total shows everything), and keeps
      History as the only remaining tab. Seven component tests, including
      the every-ready-repo-renders pin. The new tiles are `text-sm`; the
      UI-ratchet baseline moved DOWN six tiny-text nodes and was locked in.)_
- [x] **Rename the tab to what the page does.** "Copilot Execution Lanes"
      claimed monitoring; the page is a dispatch board — ready work ranked,
      two lanes of work in progress, a paper trail. _(state: smoke-tested
      2026-08-30 — renamed to **Dispatch Board** (short "Dispatch") in
      [`viewMeta.ts`](frontend/viewMeta.ts) with question "What is
      dispatched, and what should go next?"; the panel header, the
      improvement-workflow modal copy, `viewMeta.test.ts` (old label
      asserted gone) and [`frontend-smoke.cjs`](scripts/frontend-smoke.cjs)
      all follow. The `execution-queue` view key is unchanged, so no route
      or persisted state breaks.)_
- [x] **Follow-up (operator, 2026-08-31): dispatching a sparse repo crashed
      the whole portal.** The Lane 0.17 fixes made packets buildable for
      repos with no value assessment — and exposed a latent serializer bug:
      a PowerShell `if`-EXPRESSION enumerates its result, so an empty `@()`
      collapses to `$null` and `valueContext.rationale` reached the browser
      as JSON `null`; the modal's `.length` read then threw, and because the
      modal renders outside the per-view boundary the app-level card took
      the entire portal down. _(state: smoke-tested 2026-08-31 — reproduced
      by rendering the modal against the live captured packets; three-layer
      fix: the backend wraps the whole if-expression in `@(...)` (micro-proof:
      the old shape serializes `null`, the new `[]`);
      [`copilotTaskPacket.ts`](frontend/lib/copilotTaskPacket.ts) normalizes
      every UI-iterated array at the API-client choke point so a stale
      service cannot crash the page (3 lib tests with the field-observed
      payload + a modal render test); and `Dashboard.tsx` wraps the modal in
      its own `ErrorBoundary` so any future preview crash degrades to a
      labeled card instead of the whole portal. Requires a service restart
      to take effect on the live host.)_
- [x] **[non-blocker]** Sweep the `$x = if (...) { @(...) } else { @() }`
      pattern portfolio-wide: the estimate of ~30 sites across
      [`Start-RepoManagementApiHost.ps1`](backend/api-host/Start-RepoManagementApiHost.ps1)
      and `backend/modules/` was low — an AST sweep found **56** across 12
      files, each assigning an if-expression that silently turns an empty
      array into `$null` (and `@($x)` then makes a one-element `[null]`).
      Only the payload-literal site crashed a surface; the local-variable
      sites are now wrapped too, and the pattern has the lint gate the audit
      asked for. _(state: smoke-tested 2026-09-05 — all 56 wrapped; `tools/Assert-NoArrayCollapsingIfExpression.ps1` is AST-based, not textual, proves itself against a collapsing fixture before sweeping, spares the wrapped and scalar forms, and holds a zero baseline in `scripts/array-collapse-baseline.json`; wired into the module smoke)_
- [x] **The "Running" state was bookkeeping — an operator clicked Dispatch and
      had not clicked Complete.** Every occupied lane rendered identically
      whether its agent was three minutes into a draft PR or had died an hour
      earlier, because `Invoke-AssignLane` minted a throwaway GUID that
      resolved to nothing. Two halves closed it: the board now **really
      dispatches** (operator decision, 2026-09-06), and the lane carries the
      dispatch run id that joins it to the run ledgers.
      _(state: smoke-tested 2026-09-06 — `backend/modules/execution/Execution.LaneObservation.ps1` is pure (`Resolve-LaneObservation` takes already-read records and a clock, so the whole decision table runs offline) and reports two orthogonal facts: `verdict` (unlinked | queued | working | awaiting-review | finished | failed) and `stalled`, each non-terminal verdict carrying its own patience (queued 15m, working 90m, awaiting-review 24h) because one threshold is wrong in both directions. `Execution.Ledger.ps1` stores `dispatchRunId`/`agentRunId`/`dispatchSource` through a shape-tolerant setter (a pre-Lane-0.17 PSCustomObject entry throws on assignment to a property it lacks) and releases them on complete/cancel so a finished run never follows the repo into its next lane; `Get-ExecutionQueueSummary` derives the observation on read and never persists it. `CopilotTaskPreviewModal.tsx` dispatches the previewed prompt through `POST /api/roadmap/dispatch/execute` and binds the returned run id via `POST /api/execution/assign`, in that order — occupying the lane first would rebuild the very defect — behind Release 3.1's runner-presence gate with the `Queue anyway` override. A dispatch that succeeds while the lane refuses reports success and names the lane problem, because the work is queued either way. Lane closure stays the operator's (operator decision, 2026-09-06): the verdict highlights Complete or Cancel and never presses them. Covered by 8 module-smoke assertions (decision table + an on-disk join proving lane -> run summary -> agent run -> PR #7, proven red by reverting the assign to drop the id) and 8 component tests (4 proven red against the pre-change card); `sources` is asserted to serialize as `[]`, never JSON `null`.)_
- [ ] **[non-blocker]** The api-host smoke fails on any machine where the
      operator is actually running a runner. `Invoke-ApiHostSmokeTest.ps1:3754`
      asserts `GET /api/roadmap/runner` reports **no** runner present, but the
      route reads `output/roadmap-task-runner.heartbeat.json` from the real
      workspace — so a live `Invoke-RoadmapTaskRunner.ps1` (the normal state
      when work is being driven) makes the gate fail on an untouched tree.
      Confirmed 2026-09-06: `origin/main` (f7452d4) fails at the same line with
      the same message as a feature branch, with the operator's runner alive on
      PID 8892. The isolation the smoke already applies to settings and the
      queue ("queue isolated to `output/smoke/api-host/…`") is the shape of the
      fix — the presence check needs the same fixture treatment, not a real
      heartbeat read. Until then the gate is red for an environmental reason
      and cannot distinguish a regression from a working runner.
      _(state: planned)_
- [ ] **[non-blocker]** The board reads observed state; nothing refreshes it on
      a cadence. `Invoke-AgentRunAutoClose` advances open runs only when
      someone loads Agent Runs, so a lane can sit on a `lastObservedAt` that is
      hours old and be reported — correctly — as stuck for want of a poll
      rather than want of progress. The verdict is honest either way (it says
      when it last observed), but a board that refreshed its own runs would
      distinguish "the agent stopped" from "nobody looked". Release 3.8's
      fourth milestone owns the cadence — Repo Manager monitors CI without
      holding an execution slot — so close this item there rather than building
      a second poller. _(state: planned)_
- [ ] **Restrict dispatch authority to the Dispatch Board.** _(state: planned)_
      Decided 2026-09-06 (D-008), and it **reverses the default shipped the
      same day** under D-010. `CopilotTaskPreviewModal` opens from the Dispatch
      Board, the Work Queue and Operations, and
      [`Dashboard.tsx`](frontend/components/Dashboard.tsx) passes its dispatch
      callback unconditionally — so all three now queue real agent work and
      spend quota, where before they only wrote a ledger row. Previewing a task
      must not implicitly grant authority to consume agent budget. Work Queue
      and Operations keep the full preview — readiness, estimated resource
      requirement, intended provider — and navigate the operator to that task
      on the board instead of invoking the dispatch endpoint themselves. This
      also gives Release 3.8's capacity governor, provider selection and budget
      impact one consistent surface to appear on before work begins. Gate:
      component tests prove the dispatch action is present from the board and
      absent from the two preview-only surfaces.
- [ ] **[non-blocker]** Archive this lane's eight closed items to
      [`docs/history/completed-releases.md`](docs/history/completed-releases.md).
      The roadmap's own rule is that this file carries open work only and an
      `[x]` here is a mistake rather than a record; the lane has held eight
      since 2026-08-30. Left in place deliberately on 2026-09-06 so the
      execution-model pass stayed reviewable — a verbatim move of ~110 lines
      does not belong in the same diff as a new release contract. It is the
      larger half of `R010-FILE-LENGTH`, which has warned since the file passed
      2,000 lines. _(state: planned)_

---

### Lane 0.18 — Execution depth: four mechanisms RoadmapOrchestrator already solved (evaluated 2026-09-04)

**Trial boundary (approved 2026-09-05):** independently verify acceptance
criteria for each Release 3.7 improvement. The operator may perform and record
that check through the existing workflow; this lane's new automated gate,
carryover, cumulative sequence cap and dependency selector are not blanket
prerequisites for the trial. Preserve existing merge gates.

`RoadmapOrchestrator` (`xfaith4/RoadmapOrchestrator`, local at
`F:\Development\20_Staging\AI Projects\RoadmapOrchestrator`) reaches the same
end as this console from the opposite side. This product decides **what**
deserves an agent across a portfolio and dispatches one item; that one takes a
single target and drives a dependency-ordered roadmap to completion in a closed
loop, gating every phase against the real repository. Its `README.md` states
the split worth borrowing: phase selection is deterministic and lives in
PowerShell, while execution and self-assessment are delegated to the model.
Both products already refuse an agent's self-report —
[`Roadmap.WriteBack.ps1`](backend/modules/roadmap/Roadmap.WriteBack.ps1)
demands merge evidence, the orchestrator demands an independent gate — so these
items extend a conviction this repo already holds rather than importing a
foreign one.

**Each item adds a step that does not exist today; none changes what a current
surface already does.** Every acceptance line below names the unchanged
behaviour explicitly, because that is the cheap half to get wrong.

**Do not build on its `maintain_existing_app` pipeline.** `Get-Pipeline`
(`orchestrator\Invoke-RoadmapOrchestrator.ps1`) names eleven agents,
`agents\agent-library.json` defines eight, and `RepoContextBuilder`,
`ReviewGate` and `PRPublisher` exist only as prose in `agents\agents-full.md`.
`Invoke-Agent` returns failure for an unknown agent, so that pipeline halts on
its first step. None of the items below depend on it.

**The third-dispatch-target option is withdrawn — D-004, decided 2026-09-06.**
GitHub Repo Manager is the orchestration authority, and a second closed-loop
orchestrator beneath it would duplicate ownership of task selection, execution
state, budgeting, remediation and completion. Mechanisms still come across —
that is exactly what the items below are. If the tool is integrated later it
participates through Release 3.8's provider-adapter contract, which is bounded
by construction: an adapter translates packets and events, and makes no
roadmap, merge or portfolio-priority decisions. **Three of the four items below
are re-scoped into Release 3.8** rather than built standalone; each says how.

- [ ] **Carry an amendment forward between dispatches.** Every dispatch starts
      cold: what the last agent learned, or deliberately left undone, dies
      unless it reaches the pull-request body, so the next prompt for the same
      repository re-asks settled questions. Port the carryover channel from
      `.orchestration\STATE_SCHEMA.md` — a `carryover[]` replaced wholesale
      each run and injected into the next run's context by
      `Invoke-PhasePipeline`. **Translate, do not copy:** there it lives in a
      state file written by the very agent being judged, a weaker trust model
      than this repo's append-only ledgers, so carryover belongs beside the run
      that produced it in the agent-run ledger and is read by the dispatch
      prompt builder. Acceptance: a second dispatch to the same repository
      carries the prior run's unresolved note into its prompt; a repository
      with no prior run produces exactly the prompt it produces today.
      **Re-scoped 2026-09-06:** this is the `HandoffPacket`'s `priorResult` and
      `remainingScope` in Release 3.8 — build it there, once, rather than as a
      separate carryover channel that a cross-provider handoff would then have
      to duplicate. _(state: planned)_
- [ ] **Check the acceptance criteria before a pull request is called ready.**
      Dispatch prompts already carry acceptance criteria and nothing verifies
      them; merge evidence answers "did this land", not "did it do what the
      item asked". Port `Test-PhaseGate`
      (`orchestrator\Invoke-RoadmapOrchestrator.ps1`): a separate read-only
      pass that re-checks the named deliverables against the repository, with
      an unparseable verdict treated as rejection rather than a pass. Its
      refusal shape and read-only tool set transfer directly; its inputs do
      not, so run it against the agent's branch and record the verdict in the
      agent-run ledger. Acceptance: an item whose criteria are unmet reports
      the failing criterion by name, and every existing merge gate keeps its
      current strictness. **Re-scoped 2026-09-06:** this check is what gives
      Release 3.8's `LOCAL_VERIFYING` state its meaning — without it
      `IMPLEMENTATION_COMPLETE` asserts only that an agent stopped. Build it as
      that gate. _(state: planned)_
- [ ] **Cap cumulative spend across a dispatch sequence.**
      [`BudgetLedger.ps1`](backend/modules/agent-runs/BudgetLedger.ps1)
      evaluates one dispatch against a work-unit quota. The orchestrator's run
      loop caps per agent, per gate and per roadmap, halts on the cap, and
      persists banked cost **before** halting so the figure is never lost.
      Port the cumulative cap and the persist-before-halt ordering; translate
      the unit, since this product counts work units and captured token cost
      rather than one headless price. Acceptance: a sequence that reaches the
      cap stops with its spend recorded, and a single dispatch inside quota
      behaves as it does today. **Re-scoped 2026-09-06:** the cumulative cap
      becomes Release 3.8's per-provider reserve, which is the same
      persist-before-halt ordering applied to the unit each provider actually
      exposes; the work-unit quota stays the portfolio budget beside it. The
      two measure different things and neither replaces the other.
      _(state: planned)_
- [ ] **Order work inside one repository's roadmap, and detect dead ends.**
      [`Roadmap.DependencyTracker.ps1`](backend/modules/roadmap/Roadmap.DependencyTracker.ps1)
      finds references _between_ repositories; nothing orders items _within_ a
      roadmap, so an operator re-picks after every merge. Port `Get-NextPhase`
      (`orchestrator\Invoke-RoadmapOrchestrator.ps1`): the first item whose
      `depends_on` are all complete, plus its Phase 3 dead-end rule, where
      incomplete-but-ineligible halts as blocked instead of reporting the
      roadmap complete. **This is the one piece that transfers as code** — a
      pure function over item ids and a completed set, liftable almost
      verbatim into a module and covered by module smoke. It needs a
      `depends_on` notion in this product's roadmap contract first, which is a
      spec decision in `standards/roadmap` and `spec/roadmap-contract`, not a
      code change. Acceptance: selection is deterministic for a given completed
      set; a cycle or an unresolved id halts as blocked; a roadmap with no
      dependency declarations ranks exactly as it does today.
      **Unblocked 2026-09-06 (D-001):** dependencies are permitted, optional,
      within one repository, acyclic, keyed on stable item ids, and they gate
      dispatch eligibility. Less new notation than it looks —
      [`ROADMAP_TEMPLATE.md`](standards/roadmap/ROADMAP_TEMPLATE.md) already
      recommends `[[M3]]` ids and an inline `(depends: M3)` tag that nothing
      reads; the schema and parser have to catch up with the authoring
      convention. _(state: planned)_

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
- **A provider limit is state, not an execution failure** (added 2026-09-06
  from the [execution-governance spec](docs/governance/Agent-Execution-Governance.md)).
  Reaching a subscription limit returns the task to the queue with its
  workspace, branch, attempt count and session identifier intact. It must never
  mark the roadmap item failed, and `CAPACITY_WAIT` is a normal operating state.
  Ordinary roadmap work may not consume a provider's configured reserve.
- **Operator approval applies to a verified head SHA, not a pull request
  number.** Any change to the pull request head after verification invalidates
  readiness and requires re-approval. Agent execution may be autonomous;
  promotion to the protected default branch is not.

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
