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

**Last updated:** 2026-09-13

Releases 0.4 through 2.6, 2.8 and 3.0 are **engineering-complete and archived**,
as is every completed milestone from the releases and lanes still open below.
Their full text lives in
[`docs/history/completed-releases.md`](docs/history/completed-releases.md).

**This file carries open work only.** Every checkbox in it is something still
to do — if an item is `[x]` here it is a mistake, not a record (rule restored
by the 2026-08-11 archive pass, recorded in `CHANGELOG.md`).

**Current focus (next agent actions), in order.** Every item here is agent-closable;
the operator queue is a separate file. Take the first `[ ]` and open a PR.

- [ ] **3.7 / M4a follow-through — kind under steering contract 6.** `unknown`
      carries the hint list that failed to match, so a rule can be added as data.
      The hint derivation (README wording patterns, the app-framework dependency
      list, firmware file names) moves out of `Portfolio.KindSignals.ps1` into
      `backend/config/kind-signals.json`, every rule carrying `observedOn`. Kind
      is emitted as a ranked list with the hints each rested on, and a
      manifest-vs-README disagreement is its own observation with
      `canonicalEffect: none` (steering extension 2). `modelVersion` bumps.
      _(state: built)_
      `check: pwsh ./tests/Test-KindDetection.ps1 -FailOnError`
- [ ] **Lifecycle/conclusion consistency contract (steering extension 3, Rung 1).**
      `lifecycleState` and `conclusion` are two verdicts over the same signals;
      they never disagree without saying why. A contract test enumerates the
      allowed pairs and the explanation each exception must carry; a
      contradiction with no explanation fails it. Runs before M4b because a
      contradiction it finds changes how applicability is written.
      _(state: built)_
      `check: pwsh ./tests/Test-FoundationConclusions.ps1 -Cohort evidence/trials/release-3.7/cohort.json -Assert lifecycle-consistency -FailOnError`
- [ ] **3.7 / M4b — limiting foundation by kind applicability.** The limiting
      foundation is chosen only among the domains that apply to the repository's
      kind; a domain `foundation-domains.json` marks not-applicable for that kind
      renders its configured reason instead of a status. Seven of nine trial
      repositories sharing `planning`-weak + `structure`-weak is the observation
      that raised this, not the target: the check asserts properties, never a
      distribution. _(state: built)_
      `check: pwsh ./tests/Test-FoundationConclusions.ps1 -Cohort evidence/trials/release-3.7/cohort.json -Assert applicability -FailOnError`
- [ ] **Accept/reject ledger (steering extension 1, Rung 1).** Every next action
      and top value item is a prediction; every response to one — accept,
      reject, edit — is a label. Capture each with the prediction it answers and
      the index SHA and `modelVersion` it was drawn under, so the leverage
      panel's "not captured" figure becomes a computed one and the scorer's
      weights (D-013) have evidence to be revisited against. _(state: planned)_
      `check: pwsh ./tests/Test-DecisionLedger.ps1 -FailOnError`
- [ ] **3.7 / M4c — next-action routing by limiting foundation.** Every
      actionable repository is told `POST /api/roadmap/repair/preview`. A
      configured map routes each limiting foundation to its own previewable
      action, so `structure` and `documentation` gaps reach their own previews.
      The check asserts that each limiting foundation routes to a distinct
      configured action with a route — never a ratio of repositories.
      _(state: planned)_
      `check: pwsh ./tests/Test-FoundationConclusions.ps1 -Cohort evidence/trials/release-3.7/cohort.json -Assert action-routing -FailOnError`
- [ ] **3.7 / M5 prep — previews staged, not applied.** For each of the eight
      `strengthen` repositories, generate the preview the product recommends and
      write it to `evidence/trials/release-3.7/previews/<repo>.md`. The operator
      approves from the queue; the agent's job ends at a reviewable preview.
      _(state: planned)_
      `check: pwsh ./tests/Test-TrialPreviews.ps1 -Cohort evidence/trials/release-3.7/cohort.json -RequireAll`
- [ ] **One manifest walk (steering extension 4).** Repo type, the technology
      profile and kind signals are three walkers over the same files. One scan
      produces all three views, so they cannot drift and a checkout is read once.
      _(state: planned)_
      `check: pwsh ./tests/Test-ManifestWalk.ps1 -FailOnError`
- [ ] **Portfolio brief and conclusion diff (steering extension 5, Rung 1).**
      Diff two conclusion payloads by index SHA and render the movement as prose
      with the evidence chain under every claim — one exported file a reader who
      has never seen the product can act on. Deterministic; any narration is
      constrained to the evidence lines and marked as narration.
      _(state: planned)_
      `check: pwsh ./tests/Test-PortfolioBrief.ps1 -FailOnError`
- [ ] **Lane 0.19 — surface the operator queue in the console.**
      `operatorOnlyItemCount` is produced and read nowhere. Render
      `docs/governance/operator-queue.md` as a Verify tab so parked work is
      visible somewhere other than this file. _(state: planned)_
      `check: pwsh ./tests/Test-ApiHostSmoke.ps1 -Route /api/operator-queue`
- [ ] **3.8 / D-001 — dependency notion.** Optional, single-repo, acyclic,
      keyed on stable item ids, gating dispatch eligibility. Schema + parser +
      cycle check. Does not wait on the trial: it changes what the contract
      *can express*, not what runs. _(state: planned)_
      `check: pwsh ./tests/Test-RoadmapDependencies.ps1 -FailOnError`

**Forward arc.** Releases 3.0-3.5 describe the finished product: dispatch that
runs, the loop closing legibly and without a hand-off, numbers an operator can
act on, an 80+ repo portfolio that feels immediate, unattended operation.
Release 3.6 extends it to "every repository ends with an explainable
conclusion"; Release 3.7 makes the product prove, on ten real repositories,
that it returns more time than it takes. Release 3.8 makes the execution layer
provider-aware, so that proof is not capped by one agent's subscription.

---

## 1. What This Document Is

> Read [`docs/governance/steering.md`](docs/governance/steering.md) first. It
> says what the product is for, what it must never do, and what "proved" means;
> this file says only what to build next.

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

Open work is one of four kinds — unbuilt engineering, human verification,
product decisions, calendar-gated accrual — and this file tracks only the
first; the others and their ledgers are named in
[`docs/governance/kinds-of-work.md`](docs/governance/kinds-of-work.md).

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

Every milestone carries exactly one state and exactly one `check:` — the command
that decides it. A milestone with no runnable check is not a milestone; it is a
question, and it goes to `docs/governance/open-decisions.md` instead.

| State      | Meaning                                                                   | Closed by |
| ---------- | ------------------------------------------------------------------------- | --------- |
| `planned`  | Contract written (goal, boundary, `check:`); no code on any branch        | agent     |
| `built`    | Code on a branch; `check:` not yet green in CI                            | agent     |
| `verified` | `check:` exits 0 in CI on the PR head; evidence linked from the PR        | agent     |

`verified` is the terminal state for this file. It is the only state that earns `[x]`,
and `[x]` means the item leaves this file for the archive in the same PR.

**Field proof is not a state.** "Seen working on the live portal", "ran under SYSTEM",
"confirmed on the phone" are recorded as ratchets in
[`docs/governance/operator-queue.md`](docs/governance/operator-queue.md) via
`scripts/Add-OperatorVerification.ps1`. A ratchet may be recorded any time after
`verified`, may be recorded never, and never blocks a later milestone. The
promotion boundary — merge to the protected default branch on an operator-approved
verified head SHA — is unchanged and lives in §8; it gates *merge*, not *the next item*.

**Milestone format.** One bullet, action-first, with the check on its own line:

- [ ] Resolve repository kind for `library`, `firmware`, `application`, `experiment`
      from the index, not just `archived`. _(state: planned)_
      `check: pwsh ./tests/Test-KindDetection.ps1 -FailOnError`

**Checkbox rule.** `[x]` = `verified`. An item whose code is merged but whose field
proof is unrecorded is `[x]` here and open in the operator queue — two ledgers, no
overlap. The old rule ("stays `[ ]` and names the resource it waits on") is retired
2026-09-13: it made the operator the terminal state of every item and taught agents
to end each session by asking for verification.

**Archive rule** unchanged: once `[x]`, the item moves verbatim to
`docs/history/completed-releases.md` in the same PR.

**Operator-work rule.** Nothing in this file may name an action only the operator can
take. If a milestone needs SYSTEM rights, a device, an authenticated session, a grant
outside the repository, or eyes on a browser, the agent-closable half stays here with
its own `check:` and the human half is appended to the operator queue. The validator
(`R021`) rejects the file otherwise.

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

**Dependency map (agent-closable work only; operator rows live in
[`operator-queue.md`](docs/governance/operator-queue.md)):**

| Open item                                 | Depends on                                             | Type               |
| ----------------------------------------- | ------------------------------------------------------ | ------------------ |
| 3.7 M4a/b/c model fixes                   | nothing — ship as `foundation-conclusions v2`          | none               |
| 3.7 M5 previews staged                    | M4a (kind must resolve before previews are meaningful) | soft — sequencing  |
| 3.7 measured execution + rollout decision | operator approvals (queue item OQ-3)                   | **operator queue** |
| 3.8 D-001 dependency notion               | nothing                                                | none               |
| 3.8 provider-aware scheduler              | 3.7 rollout decision; D-003 grant (OQ-5)               | soft — sequencing  |
| Lane 0.19 verify tab                      | nothing                                                | none               |
| Lane 0.5 tab disclosure                   | product decision — `open-decisions.md`                 | hard — design      |
| 2.9 trend accrual                         | calendar time                                          | time-gated         |

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
      `check: pwsh ./scripts/Test-LiveServiceCurrency.ps1`

**Field proof — one authenticated operator session covers all three:**

- One real `claude` run through the runner — `operator-verified`, proven three times (PRs #140/#142, scheduled 2026-08-18); [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- [ ] One real **copilot** entry through the runner — `gh agent-task create`
      reaches a live task, URL in the run summary. Closes the Release 3.0
      residual. _(state: built. Requires `gh auth login` and **no**
      `GH_TOKEN`/`GITHUB_TOKEN` set; gh ignores stored OAuth when one is.)_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
- Release 3.1's scheduled-trigger loop proof — `operator-verified` 2026-08-18 ([evidence](evidence/verified/scheduled-loop-proof-2026-08-18.md)); [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

**Field proof — credential / calendar:**

- Release 2.1 operator sign-off — `operator-verified` 2026-08-18 against the live `output/app.db`; [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- [ ] Let the Release 2.3 Phase 2 trend windows accrue: `GET /api/portfolio/trend`
      reports a real 7-day, then 90-day, window. _(state: 7-day closed by
      accrual 2026-08-18, `availableDays: 20`, verified live; 90-day filling
      (20/90) — keep
      [`Invoke-DailyEvidence.ps1`](scripts/Invoke-DailyEvidence.ps1) running.)_
      `check: pwsh ./scripts/Invoke-DailyEvidence.ps1`

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
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
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
      `check: pwsh ./scripts/Invoke-ApiHostSmokeTest.ps1`
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
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
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
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
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
      needing nothing, and field-proof surfaces from ledgers already
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
      `check: pwsh ./scripts/Invoke-ApiHostSmokeTest.ps1`
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
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`

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

- [ ] **Two leverage metrics ship uncaptured, by design.** Operator minutes
      per task needs an operator-side timer the product does not have;
      recommendations accepted vs rejected needs an accept/reject ledger the
      packaging approve/reject routes do not write. Both render with their
      reason rather than a zero — Release 3.7's nine repositories decide
      whether either earns a capture.
      `check: pwsh ./scripts/Invoke-ApiHostSmokeTest.ps1`
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
  are found on nine repositories before they are found on eighty.

#### Engineering milestones

**Selection closed 2026-09-13 — recorded as prose, because a `[x]` in this file
is a mistake, not a record.** Nine repositories are selected by rule, one per
category, each with its reason; `externally-managed-project` is recorded as
**unrepresented**, which D-006 ruled a valid trial outcome rather than a gap to
fill with a substitute chosen for conformance. Selection is not owner intent:
the abandoned and externally-managed categories carry `ownerIntentConfirmed:
false`, because assigning a repository to a category is not a claim about what
its owner intended.

Nothing engineering-side had been blocking it. D-006's ruling released the
selection on 2026-09-06 and stated its own default — nine named plus one
unrepresented — but `cohort.json` still carried the 2026-09-05 state, with the
tenth slot reading `operator-input-required`. The artifact asked for a decision
that had already been made, and the milestone sat at `scaffolded` for a week on
nothing.

**The trial record was not in the repository.** `/evidence/**` was ignored
except `evidence/verified/**`, so both files this release links —
`evidence/trials/release-3.7/README.md` and `cohort.json` — existed only on one
machine. The acceptance criteria below require results "recorded per repository
in `evidence/`", and not one of them could have shipped with the PR that earned
it. `.gitignore` now excepts `/evidence/trials/**` on the same grounds the file
already states for curated proof: a selection reason written by hand is
judgement, not regenerable run spill.

**Still open:**

**Conclusions recorded 2026-09-13 — prose, not a `[x]`.** All six fields are in
`cohort.json` per repository (kind and its basis, the conclusion and its reason,
the limiting foundation with evidence, the next action, and whether the product
can perform it), drawn by `foundation-conclusions v1` over the index generated
`2026-09-13T21:07:51Z` with that index's SHA-256 recorded beside each result.
Zero conclusion-contract violations. Eight of nine reach **strengthen**, one is
**appropriate-as-is**, one **insufficiently-understood**. Eight name an action
the product performs itself. **Not operator-verified** — the entry gate still
wants eyes on the live surfaces, so this is what the product concluded, not a
confirmed finding, and no improvement is claimed.

**Three false positives the first pass exposed, for milestone 4 to fix.** This
is the trial working: finding them on nine repositories rather than eighty.

1. **Kind detection resolves only `archived`.** Eight of nine were concluded
   with the basis "no kind signal in the index; every scored domain applies",
   so per-kind applicability never engaged and a library was judged by an
   application's yardstick. Already recorded as a 3.6 out-of-scope gap; what is
   new is that it undercuts a cohort selected **by kind**.
2. **Seven of nine share one limiting pair** — `planning` weak plus `structure`
   weak — across a finished LED firmware project, an API client library and an
   orchestration experiment. A ranking that answers the same for most of the
   portfolio cannot say what to do first.
3. **Every actionable repository gets the same next action**,
   `POST /api/roadmap/repair/preview`. Defensible as a default when planning is
   weakest, but as the universal recommendation it means the model is currently
   a planning detector rather than a portfolio advisor.

Deliberately recorded and not fixed: adjusting the model now, before the
improvements are executed and measured, would change it mid-measurement.

**Still open:**

- [ ] **Execute at least five improvements** through preview → approve →
      execute → validate, recording operator minutes, agent first-pass
      result, and whether the repository is materially stronger afterwards —
      appropriate-as-is or archive counts as a conclusion outcome, not automatically
      as one of the five improvements. Each counted improvement needs an
      independently checked acceptance criterion and before/after evidence;
      merge evidence alone is insufficient. _(state: planned)_
      `check: pwsh ./tests/Test-TrialExecution.ps1 -Cohort evidence/trials/release-3.7/cohort.json -MinCountedImprovements 5`
- [ ] **Adjust and decide** — fix the false positives and bad recommendations
      the nine expose; record the go/no-go for the full rollout and the
      leverage numbers behind it. _(state: planned)_
      `check: pwsh ./tests/Test-FoundationConclusions.ps1 -Cohort evidence/trials/release-3.7/cohort.json -MaxSharedLimitingPair 0.5 -MaxSameAction 0.5`

#### Acceptance criteria

- All ten categories ruled on by the rule, none selected for conformance: nine
  repositories selected with a recorded reason, and `externally-managed-project`
  recorded as unrepresented (D-006 — an empty category is a valid outcome). Each
  selected repository carries a recorded conclusion and reason. Closed
  2026-09-13; a criterion asking for ten repositories could no longer be met by
  a cohort the ruling settled at nine.
- At least five of the nine materially improved through the product's own workflow, with
  operator minutes, outcome quality, and agent first-pass result recorded per
  repository in `evidence/`; a recorded rollout decision with the numbers.

#### Out of scope

- New product capability; finishing every repository; improvements made outside the product's workflow.

**Validation plan:** conclusions, actions, and outcomes recorded in `evidence/`
via [`Add-OperatorVerification.ps1`](scripts/Add-OperatorVerification.ps1) and
the agent-run ledgers; module smoke and api-host smoke stay green; CI is the
arbiter for any product fix the nine expose.

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

**Status:** done — all six engineering milestones and Lane 0.18 items
complete 2026-09-11. The design authority is
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
      `awaiting-review`. _(state: built 2026-09-07 — H38-01 WorkPacket schema v1
      under output/work-packets/; H38-02 dispatch and approval both save one and
      carry workPacketPath; H38-03 ExecutionResult schema v1, a headless run with
      no/invalid result is failed by name; H38-04 Adapter.Claude.ps1 parses
      stream-json, session_id and usage recorded on the run's result.json;
      H38-05 ConvertTo-WorkPacketPrompt renders the packet with criteria
      verbatim, enforcement waits on D-012)_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
- [ ] **Persist capacity per provider, in the provider's own unit.** Named
      windows with `remainingRatio`, `resetAt` and a confidence rank; reserves
      and ranking weights live in `backend/config/`, not in code.
      [`BudgetLedger.ps1`](backend/modules/agent-runs/BudgetLedger.ps1) keeps the
      portfolio work-unit quota and gains no token conversion it cannot source.
      A limit re-queues the task with workspace, branch, attempt and session
      intact. _(state: built 2026-09-07 — H38-07 added
      agent-providers.json (schemaVersion v1) and Get-AgentProviderConfig;
      ranking weights and tieBreak are the decided D-013 values; corrected the
      same day — `providers.<name>.supported` replaces `enabled`, a repository fact
      CI can verify, because whether a provider is installed and funded is
      per-installation state detected at runtime and shown in Settings, never
      committed on every operator's behalf; H38-08
      Execution.ProviderCapacity.ps1 — one record per provider under
      output/provider-capacity/, native units preserved, confidence from the
      spec's six-source ladder, and a merge that refuses to let a worse source
      overwrite a better one; H38-09 Resolve-ProviderCapacityVerdict applies the
      D-011 reserves (15% short, 20% weekly, decided 2026-09-07 and no longer
      provisional; remediation may use the weekly reserve; operator override
      recorded in the reason) — enforcement stays OFF because the per-task cost
      estimate is still a guess, so verdicts are recorded and refuse nobody;
      H38-10 a matched limit signal writes status=queued with capacityWait and
      sets the provider's cooldownUntil — branch, attempt and session survive,
      and the run does not commit; before this a limit fell through to
      verify-commit-push and called an exhausted subscription ready for
      review; H38-11 Test-RunnerClaimAllowed — no claim during cooldown or with
      the one local slot busy, an unknown target refused by name rather than run
      as claude, auto deferred to the router; a running summary counts only
      while the heartbeat pid is live, and startup marks orphans
      failed/orphaned with branch and session kept; H38-12 usage observations
      accumulate as rank-4 evidence without ever moving a window ratio — token
      telemetry is not subscription capacity — and GET /api/providers reports
      the record, the verdict and its reason per provider; H38-13 closed the
      milestone — six module-smoke sections green in one run, capacity and
      cooldown documented in local-task-runner.md, and the delivery-loop
      addendum names where a wait is persisted)_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
- [ ] **Route between providers, and add the Codex adapter.** One registry
      replaces the `claude`/`copilot` pair hardcoded in
      [`Automation.RoadmapQueue.ps1`](backend/modules/automation/Automation.RoadmapQueue.ps1),
      [`Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1) and
      `frontend/types.ts`, and reconciles the third vocabulary
      (`operator-runner`) the approval route writes. Eligibility then ranking,
      selection reason recorded, presence counts derived from the registry
      rather than naming providers. _(state: built 2026-09-08 —
      H38-14 Execution.ProviderRegistry.ps1 is the one token list (claude,
      codex, copilot, auto); the queue module and the runner delegate to it,
      and the two ValidateSet attributes that cannot are gated against it so
      drift fails a smoke rather than rejecting a valid provider unnoticed;
      Invoke-QueuedTask now refuses a known token it has no branch for, so the
      wider vocabulary cannot run Claude Code in codex's place; H38-15
      seven-function adapter contract gated per supported provider, naming
      every missing function at once; Adapter.Copilot.ps1 holds the three moved
      runner functions unchanged, asserted byte-identical, and a cloud dispatch
      now writes an ExecutionResult like every other provider; H38-15b provider
      availability detected per installation (PATH probe, and deliberately no
      authentication — proving an account works would spend its quota) and
      surfaced in GET /setup/prerequisites, which the setup wizard already
      renders, plus GET /api/providers; the operator opt-out lives in an
      untracked installation.local.json that a gate refuses to let become
      tracked; H38-16 Adapter.Codex.ps1 from a synthetic codex exec --json
      transcript, with the thread id and the terminal turn matched exactly
      rather than by pattern — item.id and item.completed both match the loose
      forms and mean something else entirely; the runner runs codex tasks
      through the same branch, launch, parse, verify and commit path, with the
      provider held in a variable at every launch and ledger site so a codex
      run is never recorded, rested or billed as a claude one; H38-17
      Resolve-ProviderSelection is eligibility THEN ranking with the reason
      recorded — every Stage 1 condition is kept per candidate whether it
      passed or failed and the first failure becomes ineligibleBecause, so a
      provider that is never chosen is explainable without reading a log;
      Stage 2 weights eight factors each normalised to [0,1] and a tie names
      the rule that broke it. An unenforced capacity verdict is recorded as
      advisory and does not exclude, because D-011 left the per-task estimate
      provisional and refusing work on a guessed cost would block real
      execution on an unmeasured number. The runner resolves `auto` at CLAIM
      time, not enqueue time, since capacity and cooldowns move in between,
      and writes selectedProvider and selectionReason onto the run summary;
      with no eligible provider the entry stays queued rather than failing.
      dispatch.autoEnabled and defaultTarget are now true/auto (D-013), and
      the config tripwire inverted to guard that rather than disappearing;
      H38-18 dispatch/execute takes a target (default from config, auto
      refused when the config disables it), approval reports the real token,
      backlog is counted per registry token — queuedClaude/queuedCopilot
      unchanged; H38-19 ProviderToken union, queuedByProvider on the presence
      payload, preview names the intended provider; H38-19b Settings shows each
      provider as available, not installed, switched off or not in this build,
      and the opt-out writes per-machine state that is never committed.)_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
- [ ] **Move push and PR opening to Repo Manager; bind approval to the verified
      SHA.** The agent exits at `IMPLEMENTATION_COMPLETE`; Repo Manager pushes,
      opens the pull request and monitors CI on a cadence without holding an
      execution slot — which also closes Lane 0.17's open "nothing refreshes the
      board" non-blocker. A head change after verification invalidates
      `READY_FOR_OPERATOR`. Merge stays an explicit operator action.
      _(state: built 2026-09-08 — H38-21 `Resolve-PostImplementationTransition`
      and `Invoke-RunnerBranchPush` in
      [`scripts/Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1)
      push after a complete, verified result (`autoPush` per provider, default on
      for local providers); awaiting-review survives at off or on push failure,
      and the default branch is refused before git is asked. H38-22
      `Invoke-DeliveryReconciliation` and `POST /api/delivery/reconcile` in
      [`backend/api-host/Start-RepoManagementApiHost.ps1`](backend/api-host/Start-RepoManagementApiHost.ps1)
      open pending PRs with the host's token and refresh CI; the runner calls it
      every fourth poll. H38-23 `Invoke-AgentRunRefresh` in
      [`backend/modules/agent-runs/AgentRuns.ps1`](backend/modules/agent-runs/AgentRuns.ps1)
      records `prHeadSha` and `verifiedHeadSha` only when CI passed on that exact
      head; a moved head clears it and emits `run.head-moved`. H38-24
      `POST /api/agent-runs/{id}/approve` stores `operatorApproval` bound to
      `verifiedHeadSha`, and `Get-MergeReadinessEvaluation` in
      [`backend/modules/agent-runs/MergeReadiness.ps1`](backend/modules/agent-runs/MergeReadiness.ps1)
      refuses `no-verified-head`, `no-operator-approval` and
      `head-moved-since-approval`. H38-25 the merge control in
      [`frontend/components/OperationsWorkspaceView.tsx`](frontend/components/OperationsWorkspaceView.tsx)
      shows and approves the verified SHA and disables on head drift. H38-24b
      risk-based independent review in
      [`backend/modules/execution/Execution.ReviewPolicy.ps1`](backend/modules/execution/Execution.ReviewPolicy.ps1)
      — high risk requires a different provider, medium risk requires one on
      four named triggers, and the reviewer is never the implementer. All six
      are gated in
      [`scripts/Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1)
      and [`OperationsWorkspaceView.test.tsx`](frontend/components/OperationsWorkspaceView.test.tsx))_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
- [ ] **Remediate from evidence, and hand off between providers.** Attempt and
      remediation counts survive a restart; a CI failure builds a
      `RemediationPacket`, resumes the original session where capacity allows,
      and otherwise transfers a `HandoffPacket` of durable evidence to another
      eligible provider. No provider depends on another's conversation.
      _(state: built 2026-09-09 — H38-27 `attempt` and `remediationCount` live on the run summary, written with the claim so a crash cannot lose them, and `Write-RemediationAttempt` in
      [`backend/modules/execution/Execution.WorkPacket.ps1`](backend/modules/execution/Execution.WorkPacket.ps1)
      persists the incremented count before it evaluates the cap; an
      unwritable summary throws rather than returning a verdict. H38-28b
      provider and model are separate fields across registry, capacity and
      routing records, with a pre-packet record's model marked inferred rather
      than observed; every provider declares `unknown` explicitly, because no
      model identifier is determinable without running a CLI (R12); H38-28
      `New-RemediationPacket` carries the CI failures as acceptance criteria
      and the prior session/provider, with the original criteria surviving
      verbatim as a superset; H38-29 `Resolve-RemediationRoute` resumes the
      original session when it exists, the provider supports it and
      remediation capacity allows, and `Resolve-RemediationLaunch` evaluates
      the cap first so a halted attempt never builds an argument vector;
      H38-30 `New-HandoffPacket` carries only durable evidence — a
      `priorResult` holding a transcript is refused by name and by length —
      and a switch excludes the previous provider through the router's new
      `-Exclude` and starts a fresh session; H38-31 the reconcile tick enqueues
      one remediation per failing CI run, idempotent on the Actions run URL,
      cap checked first, target read from `dispatch.defaultTarget` rather than
      any literal — the host enqueues and never executes, so resume-versus-
      handoff stays a claim-time decision made against the capacity that is
      true then)_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
- [ ] **Normalize execution events onto the Dispatch Board.** Provider output
      converts to the canonical `execution.*` vocabulary, reconciled with
      [`roadmap-events.md`](standards/roadmap/roadmap-events.md) so exactly one
      is canonical. New states arrive as a mapped dimension in
      [`status-vocabulary.md`](docs/reference/status-vocabulary.md), keeping the
      Release 3.5 rule that no two dimensions share a word. Per D-008 this is
      the one surface that dispatches. _(state: built 2026-09-11 —
      H38-34 `Execution.Events.ps1` defines the 14-type canonical
      `execution.*` vocabulary; `New-ExecutionEvent` rejects unknown types so a
      producer typo fails immediately; `Test-ExecutionEvent` validates all
      required envelope fields; `Get-DeliveryState` maps run-summary and
      lane-verdict strings to the ALL_CAPS delivery states from the spec,
      returns `$null` for unknown inputs, and is case-insensitive.
      `docs/reference/status-vocabulary.md` now documents the sixth dimension
      with its full state progression; the ALL_CAPS invariant is gated in the
      smoke so no delivery state word can collide with the five existing
      dimensions. `roadmap-events.md` is complementary and non-overlapping:
      `execution.*` events are per-agent-run step events; `roadmap-events.jsonl`
      is phase-level lifecycle history.)_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
- [ ] **Amendments from the execution strategy — the three that are cheap now
      and expensive later.** Absorbed into
      [`Agent-Execution-Governance.md`](docs/governance/Agent-Execution-Governance.md)
      on 2026-09-08. These three are in 3.8 **only** because a packet that has
      not been written yet is their natural home; deferring them means reopening
      work that has already shipped. Everything else the strategy adds is
      Release 3.9. **(a)** Cost, duration and first-pass telemetry join the
      canonical `execution.*` vocabulary as it is defined, not after — adding
      them later is a second vocabulary migration through the reconciliation
      that follows it, and no run executed before then can be costed
      retroactively. **(b)** Provider and model become separate fields before
      the resume path encodes provider-only session assumptions. **(c)**
      Risk-based independent review enters the approval flow while that flow is
      being built, rather than reopening the approve-binds-to-SHA contract and
      its frontend afterwards. _(state: built 2026-09-11 —
      **(a)** H38-35: `New-ExecutionCompletedPayload` adds `startTime`,
      `completionTime`, `durationSeconds`, `cost` (with unit), `firstPassSuccess`,
      `inputTokens`, `outputTokens`, and `attemptCount` to the
      `execution.completed` event payload; duration is computed from timestamps
      when both are present, cost is `$null` when no unit-cost is measurable
      (subscription allowances carry no per-token price), and the payload
      attaches to a full `execution.completed` event via `New-ExecutionEvent`.
      **(b)** Delivered 2026-09-08 as H38-28b. **(c)** Delivered 2026-09-08 as
      H38-24b.)_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`

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

### Release 3.9 — Adaptive Routing

**Status:** planned — defined 2026-09-08. Design authority is
[`Agent-Execution-Governance.md`](docs/governance/Agent-Execution-Governance.md),
which absorbed Ben's _Multi-Provider Agent Execution Strategy_ the same day.
Follows Release 3.8, and cannot precede it: every milestone here consumes
telemetry that 3.8 is what starts recording.

**Goal:** Release 3.8 routes on _capacity_. This release routes on _evidence_.
The router learns which provider actually completes this repository's workload,
at what cost per verified task, and stops paying a frontier tier for work a
cheaper one finishes first time — or stops sending an agent at all where the
answer is deterministic.

#### Product outcomes

- Work the repository can answer itself never reaches a provider, so the
  cheapest routing decision is also the fastest one.
- The operator can see which provider is genuinely better for a kind of task in
  this repository, rather than which one has the better reputation.
- A cold-start preference that the evidence contradicts is overridden by the
  evidence, not defended by the configuration.

#### Engineering milestones

- [ ] **Classify a task before choosing anything to run it.** A task profile —
      type, complexity, risk, context scope, whether verification exists, whether
      the work is deterministic — attached at qualification and carried on the
      WorkPacket. Today `suitability` scores 1.0 when the packet's
      `preferredProvider` matches the candidate and 0.5 otherwise, which echoes a
      preference someone already stated rather than deriving one from the task,
      so the initial routing policy has nothing to attach to. _(state: planned)_
      `check: pwsh ./tests/Test-TaskProfile.ps1 -FailOnError`
- [ ] **`NO_AGENT`: the deterministic tier is a routing outcome, not the absence
      of one.** Branch state, CI status, file existence, repository metrics,
      schema validation, mergeability and configured policy evaluation are
      answered by application logic and recorded as a selection like any other.
      _(state: planned)_
      `check: pwsh ./tests/Test-NoAgentTier.ps1 -FailOnError`
- [ ] **A cost estimator that can eventually enforce.** `effective_cost` =
      metered cost + quota pressure + retry + expected failure, with pricing
      configurable or discovered rather than embedded. Enforcement stays off
      until both the reserves and the per-task consumption estimate are
      non-provisional — D-011 left the estimate a guess, and refusing dispatches
      on a guessed number blocks real work for an unmeasured reason.
      _(state: planned)_
      `check: pwsh ./tests/Test-CostEstimator.ps1 -FailOnError`
- [ ] **A performance store keyed by what actually varies.** Rolling first-pass
      rate, eventual success, cost and duration per success, remediation count,
      human-intervention rate and CI failure rate, broken down by
      `provider × model × taskType × complexity`. The router reads
      `provider × repository` success ratio today, which cannot distinguish a
      provider that is excellent at documentation and poor at one coding
      workload. _(state: planned)_
      `check: pwsh ./tests/Test-PerformanceStore.ps1 -FailOnError`
- [ ] **Evidence overrides the cold-start prior.** Once a task class has enough
      history, the empirical result wins over the configured preference, and the
      routing record says which of the two decided it. _(state: planned)_
      `check: pwsh ./tests/Test-EvidenceOverridesPrior.ps1 -FailOnError`
- [ ] **Report the metric the release exists to move.** Verified tasks ÷ total
      agent cost, with throughput and first-pass rate beside it, on
      `GET /api/providers` and the Dispatch Board. _(state: planned)_
      `check: pwsh ./tests/Test-VerifiedTaskRate.ps1 -FailOnError`

#### Acceptance criteria

- A task carries a classification before any provider is considered, and that
  classification is not derived from a requested provider.
- A deterministic task completes without an agent and records `NO_AGENT` as its
  selection.
- Provider and model are separately represented wherever the provider exposes
  model choice.
- Cost per verified task is computable from stored telemetry for any
  `provider × model × taskType × complexity` slice with history.
- A documented cold-start preference is demonstrably overridden by contrary
  evidence in at least one task class, and the routing record names the
  evidence.

#### Out of scope

- Redundant multi-provider execution of the same task as a default. Two-provider
  work stays deliberate and risk-justified.
- Raising concurrency above one local execution slot, which stays a Release 3.8
  boundary until capacity accounting is proven.

**Validation plan:** the classifier, the cost estimator and the performance
store are pure decision tables, gated offline against fixtures in the shape the
module smoke already uses; no packet spends provider quota to produce a fixture.

**Risks:** a classifier that encodes the same provider preference it was meant
to replace; a performance store confident on too little history — the router
must keep distinguishing "unmeasured" from "measured as bad", as it already does
for capacity; enforcement switched on before consumption is measured.

**Dependencies:** Release 3.8 for the telemetry these milestones read, and in
particular the 3.8 amendment that puts cost and duration into the canonical
event vocabulary as it is defined.

---

## 7. Cross-Cutting Engineering Work

Continuous, not release-scoped. **This section carries open work only.**
Completed cross-cutting items are in
[the archive](docs/history/completed-releases.md#cross-cutting-engineering-work-completed-items)
(2026-08-07) and [the 2026-08-08 batch](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).

### Lane 0.2 — Credential freshness

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
      `check: pwsh ./tests/Test-CheckRunDetail.ps1 -FailOnError`

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

- [ ] **Clear and harden the stale browser-persisted GitHub owner.** _(state:
      planned — recorded 2026-08-10, not bundled into the watchdog fix)_ Every
      scan queries GitHub for owner `Benjamin-Fuhr_genesys`, which 404s/422s
      and adds failing round-trips to an already-long scan. It is **not** in
      `settings.json` (correctly `xfaith4`) or any env var — the browser sends
      it in the request body, and has since **2026-07-07** (116 occurrences in
      the host log). Clear the persisted client value and stop a client-supplied
      owner from silently overriding validated configuration.
      `check: pwsh ./tests/Test-OwnerCacheReset.ps1 -FailOnError`

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
      `check: pwsh ./tests/Test-ExternalizedHistory.ps1 -FailOnError`
- Sanction the external-archive pattern in the standard — done (`ROADMAP_TEMPLATE.md` §6 "External archive option"); [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

### Lane 0.8 — Verification gate integrity (CI audit 2026-08-10)

**Re-homed from Release 3.1 on its closure (2026-08-15):**

**Three items closed 2026-09-13 — recorded as prose, because a `[x]` in this
file is a mistake, not a record.**

_The watchdog restart loop — cause confirmed, fixed by the operator._ The
registered `RepoMgmtPortalWatchdog` task kept the `-BaseUrl` it was installed
with, which predated the 2026-08-29 HTTPS switch, so every one-minute probe went
to `http://` and failed the TLS handshake. After three failures in a row the
watchdog force-killed the host and restarted the service, which reset the count:
**a restart every three minutes, around the clock, from 29 August to 12:29 on
13 September — about 7,000 restarts**, roughly 480 a day, almost none preceded
by a clean shutdown. `apihost.log` holds 122,411 handshake failures, the bulk
of them this probe: four per run, once a minute, 5,665–5,771 a day. The Task
Scheduler log shows the operator updating the task at 12:29, 12:40 and 12:44;
the last plain-http failure is 12:44:58, and the task still runs every minute
without killing the host, so its HTTPS probe now succeeds — fixed, not merely
removed. The lesson above about frozen registration arguments stands, and the
runner task carries the same exposure (benign today). Not related: the API
contract test timeouts, which run against their own host on another port.

_Runner heartbeat isolation._ One override, `REPO_MGMT_RUNNER_CONTROL_ROOT`, now
moves all three runner-state files (heartbeat, hold, stop marker), and every
reader and writer resolves through it: the portal, the runner and
`Stop-RoadmapTaskRunner.ps1`. The problem was worse than recorded here: five
api-host smoke steps did not just read the real heartbeat, they deleted it and
wrote a fake runner over it, so the portal flickered while tests ran and the live
runner rewrote the file underneath them. Proved on the operator's machine with
their runner alive: the api-host smoke passed for the first time, and 290 samples
of the real heartbeat taken during the run all showed the live runner's pid,
never missing and never faked. The smoke's pre-flight warning also never fired —
it read `processId` where the field is `pid` — and now correctly reports a live
runner as left alone.

_TLS handshake hardening, found while attributing the flood._ The host serves one
connection at a time, and the handshake ran on that loop before
`Read-HttpRequest` applied its read timeout, so a client that connected and sent
nothing would have stalled every request behind it — the exact condition the
watchdog kills. The socket now gets the 15-second client timeout before
`AuthenticateAsServer`, and a failed handshake logs `remote=<address>`, so the
next flood names its caller in the log line instead of costing an afternoon.
Takes effect on the next service restart.

**Still open:**

_`.gitattributes` — closed 2026-09-13._ The repository now declares
`* text=auto eol=lf`, PNG and other assets `binary`, and `.bat`/`.cmd` CRLF.
Before it, 386 of 414 tracked files were LF in the index while 22 were CRLF and
4 mixed — whichever editor touched them last decided — and a Windows checkout
under `core.autocrlf=true` held CRLF for all of them, so any byte comparison
drifted locally while passing on CI's LF checkout. The 26 were renormalized in
the same commit: 8,852 lines changed, and a CR-stripped comparison of every
file before and after found zero content differences. The index is now 412 LF
files plus the two PNGs.

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

- E1 — ESLint `exhaustive-deps` review: [archived](docs/history/completed-releases.md#closed-2026-09-13-archived-from-roadmapmd).
- [ ] **P2 — empty catch blocks (79 → 56), classify then fix.** Guardrail-aligned
      ("never swallow silently"): each site becomes either an annotated
      deliberate best-effort (narrowed catch + comment) or a surfaced
      failure. Batch by module; multiple PRs. **Batch 1, the api host, done
      2026-09-13:** all 23 sites were genuine best-effort — log mirrors and
      trims, optional prompt context, per-line JSONL parsing, socket cleanup,
      probes that may be absent or refused — and each now states its reason
      beside a real statement (`$null = $_`). None warranted surfacing: every
      one degrades to the honest answer (blank, null, skipped line) that its
      caller already handles. **Batches 2 and 3, `backend/modules` (20) and
      `scripts`/`tools` (21), done the same day** on the same finding: every
      site best-effort, each now stating its reason. Ratchet locked at 420 (was
      484; empty-catch 79 → 15). The 15 left sit outside the module tree. _(state: built)_
      `check: pwsh ./scripts/Invoke-LintGate.ps1`
- [ ] **E2 — type the API client (`no-explicit-any`, 123, bulk in
      `apiClient.ts`).** Per endpoint-group batches; the value is contract
      drift caught at typecheck, not style. Lower the ratchet after each. _(state: planned)_
      `check: npm --prefix frontend run lint`
- [ ] **P3 — plaintext-password params (9).** Design review per surface
      (SecureString vs env-var flow), coupled to the Lane 0.2 TLS work —
      **not** mechanical remediation. _(state: planned)_
      `check: pwsh ./scripts/Invoke-LintGate.ps1`
- P4 — BOM/PS5.1 hazard: [archived](docs/history/completed-releases.md#closed-2026-09-14-archived-from-roadmapmd).
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

### Lane 0.12 — Two local clones of one repo collapse to one row, arbitrarily (found 2026-08-27)

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
      `check: pwsh ./tests/Test-NestedRepoClassification.ps1 -FailOnError`

### Lane 0.13 — Truthful uncertainty: the product could not tell "unreadable" from "not present" (found 2026-08-27)

- [ ] **`estimatedSessionWorkUnits` is null for every managed repository.**
      _(state: planned)_ Release 3.6's ranked `Today` landing surfaces effort
      per row, and the field is populated only from `activePhasePlan`, which
      **0 of 48** managed roadmaps carry (5 carry an `activeRelease`). The
      effort column is therefore empty portfolio-wide, and `todayRanking`'s
      cheaper-effort tiebreak never fires on real data. Either derive a
      credible estimate from signals that do exist (pending item count, item
      text, repo kind) or render the column as explicitly unmeasured — the
      Release 3.6 leverage panel already sets that precedent with its two
      `available: false` metrics. Decide which, with the nine repositories of
      Release 3.7.
      `check: pwsh ./tests/Test-SessionWorkUnits.ps1 -FailOnError`

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
      `check: npx vitest run frontend/lib/buttonTokens.test.ts`

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
      `check: npx vitest run frontend/lib/contrast.test.ts`

- [ ] **Add breakpoints above 768px.** The console declares **two responsive
      breakpoints, both under 768px**, so every viewport from a laptop to a
      wide desktop renders one fixed desktop layout — the 310 interactive
      controls the audit counted on a single tab are laid out for none of them
      specifically. Define the wide tiers and prove them at 1280px and 1920px.
      _(state: planned)_
      `check: npx vitest run frontend/lib/breakpoints.test.ts`

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
      `check: pwsh ./tests/Test-SettingsWriteOrder.ps1 -FailOnError`

- [ ] **Adopt the dialog dismiss contract in the remaining 17 modals.**
      [`useDialogDismiss`](frontend/hooks/useDialogDismiss.ts) now carries
      `Escape`-to-close, a focus trap and focus restoration, proven by seven
      tests, and is wired into `SettingsModal`,
      `RepositoryImprovementWorkflowModal` and `HelpModal`. **Twenty modal components ship in
      this console and exactly one handled `Escape` before this lane**
      (`AgentRunSheet`, with its own inline implementation to be replaced by
      the hook). Each remaining dialog is a two-line change: call the hook,
      attach the ref to the panel. _(state: planned)_
      `check: pwsh ./tests/Test-DialogDismissAdoption.ps1 -FailOnError`

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
      _(state: built — `evidence/verified/trial-truth-readiness-2026-09-05.md`)_
      `check: npx vitest run frontend`

- [ ] **Stop the app switching data source without being asked.**
      [`App.tsx:240`](frontend/App.tsx#L240) calls `setViewMode('github')` on a
      successful GitHub fetch, and that fetch is reachable from inside the
      Settings dialog via `onConnectGitHub` — so connecting a credential
      silently changes which source the operator is _looking at_, and `Cancel`
      cannot revert it because `viewMode` was never modal state. Connecting a
      credential and choosing a view are different acts; the source toggle
      already exists for the second. _(state: built — `evidence/verified/trial-truth-readiness-2026-09-05.md`)_
      `check: npx vitest run frontend`

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
      _(state: built — `evidence/verified/trial-truth-readiness-2026-09-05.md`)_
      `check: npx vitest run frontend`

- [ ] **Fix the dead-end automation instruction.**
      [`automationStatus.ts:100`](frontend/lib/automationStatus.ts#L100) tells
      the operator _"Enable it in Settings to keep favorites assessed
      automatically."_ The Settings dialog holds seven fields and none of them
      is that toggle — nor packaging, auto-scan, lane concurrency, or the
      scoring thresholds that drive every number in the product. Either build
      the control or stop naming it. _(state: built — `evidence/verified/trial-truth-readiness-2026-09-05.md`)_
      `check: npx vitest run frontend`

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
      serializer and the assertion together. _(state: built — `evidence/verified/trial-truth-readiness-2026-09-05.md`)_
      `check: pwsh ./scripts/Invoke-ApiContractTest.ps1`

- [ ] **Close the timestamp-basis test's own blind spot.** The contract test
      _"every timestamp field in key payloads carries an explicit timezone
      basis"_ guards its check with `-and $value -is [string]`, and
      PowerShell's `ConvertFrom-Json` silently promotes an ISO-8601 string to
      `[datetime]`. Every timestamp that parses as a date is therefore skipped
      by the very test that exists to check timestamps. Assert against the raw
      response body instead, as the new cache-fixture test does.
      _(state: built — `evidence/verified/trial-truth-readiness-2026-09-05.md`)_
      `check: pwsh ./scripts/Invoke-ApiContractTest.ps1`

---

### Lane 0.16 — The Dependencies tab answered a different question than it asked (operator feedback 2026-08-30)

The tab led with _"What does this repository depend on?"_ and answered with
roadmap cross-references — for a portfolio, in the plural, and usually with
nothing at all. To an operator, dependencies are what the repositories run
on: Node, Next.js, PostgreSQL, SQLite, Docker. The product had no answer to
that question anywhere.

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
      a second poller. _(state: built 2026-09-08 — closed by Release 3.8
      H38-22: the runner's poll loop calls POST /api/delivery/reconcile every
      fourth poll, which runs Invoke-AgentRunAutoClose)_
- [ ] **Restrict dispatch authority to the Dispatch Board.** _(state: built 2026-09-09 — H-07: the dispatch callback is passed only when the preview was opened from the `execution-queue` view; Work Queue and Operations previews offer `Open on Dispatch Board` in the same slot and keep the full preview unchanged; the origin is snapshotted at open time rather than read live, so a tab switch cannot change the operator's available actions mid-preview, and a surface added later inherits no dispatch authority by default; gated by four component tests, the decisive one proven red against the unchanged component; the board has no row-focus prop today so switching the view is the whole of the navigation)_
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
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
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
      to duplicate. _(state: built 2026-09-09 — delivered as Release 3.8 H38-30: `HandoffPacket.priorResult` and `remainingScope` carry the prior run's evidence into the next prompt, and a repository with no prior run renders the H38-05 prompt unchanged)_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
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
      that gate. _(state: built 2026-09-11 — H38-36
      `Execution.AcceptanceVerification.ps1` implements the LOCAL_VERIFYING
      read-only pass: `Invoke-LocalAcceptanceVerification` checks each
      acceptance criterion against its verification command via an injected
      `CommandRunner` scriptblock (pure, offline-testable); a passing command
      yields `passed`, a non-zero exit yields `failed`, a missing command yields
      `skipped` (not `failed` — an environment lacking a tool must not block
      valid work), and a `CommandRunner` exception is `skipped` not `failed`.
      `Resolve-LocalVerifyingTransition` is the decision table: `failed` →
      `remediation` (no push), `passed`/`skipped` → `implementation_complete`.
      The gate exercises all six cases including mixed pass+fail (overall
      `failed`) and the empty-criteria list (proceeds without error).)_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
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
      _(state: built 2026-09-09 — delivered as Release 3.8 H38-09/H38-27: per-provider reserves in `agent-providers.json` and a remediation cap persisted before the halt; the work-unit quota in `BudgetLedger.ps1` is unchanged)_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
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
      convention. _(state: built 2026-09-07 — H-13a notation
      parsed into item id/dependsOn and published on the parse result as an
      additive `items` array, so the fifteen consumers of the existing
      string lists are untouched; unknown-id and cycle findings are
      FINDINGS (ROADMAP-013/014), never parse errors, so a roadmap carrying
      either still reads normally everywhere else. The notation was not
      merely unread: `[[M4]]` contains `[M4]`, so the tag extractor claimed
      the inner pair, lowercased the id into allTags and left a stray `[]`
      on the item text that reached the console, the queue and the dispatch
      prompt. Both rules declare an applicabilityCondition and leave the
      DENOMINATOR when a roadmap declares no dependencies — without that,
      adding them moved an unrelated fixture from 64 to 67 and across the
      L2/L3 boundary without a character of it changing. H-13b
      Get-NextEligibleRoadmapItem then gates SELECTION on it: the next item
      is the first ELIGIBLE one in document order, and complete and blocked
      stay distinct verdicts because collapsing them into a null next item
      makes a dead end look like a finished roadmap. A graph with an
      unresolved id or a cycle refuses BY NAME rather than answering from an
      input it cannot trust, and that refusal surfaces through the execution
      contract checks where every other dispatch refusal already does. A
      roadmap with no notation selects exactly what first-pending selected
      before, asserted against this file.)_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`

---

### Lane 0.19 — The queue steered toward work only the operator could do (operator evaluation 2026-09-11)

Two defects, found together while assessing `FowlingScorecard` and reproduced
against its live index entry. They compound: the repository was dispatch-blocked
for a heading, and the work it would have picked once unblocked was work the
operator would have had to perform by hand.

**The ranker could not tell operator-facing from operator-executed.** The impact
dimension in [`value-scoring.json`](backend/config/value-scoring.json) awards its
top score to any item containing "operator", which is right for an outcome and
fatal for a task. `FowlingScorecard`'s top-ranked item scored 71 on
"Record device, network, and operator friction" with the stored rationale
"user-visible or operator-facing outcome" — it ranked first partly because it
named the operator. First-pending selected a live smoke checklist. Both
selectors chose work no agent can run, in a queue whose entire purpose is
dispatching work the operator does not have to do.

**The execution contract demanded a release that pre-release repositories have no
reason to cut.** The four fields the contract actually checks — goal,
acceptance, boundary, and a runnable verification — are exactly the questions an
agent would otherwise stop and ask, and they earn their place. The version
number does not. The parser matched one heading form, so the same four fields
written under "Phase 2.5" produced `activeRelease = null` and failed three of
four checks on content that was present.

- [ ] [non-blocker] Surface the operator-only backlog as a verification queue in
      the console. [`Add-OperatorVerification.ps1`](scripts/Add-OperatorVerification.ps1)
      already records evidence against a verify queue for this repository; the
      portfolio lane now produces `operatorOnlyItemCount` per repo but nothing
      reads it yet, so parked work is correctly out of the dispatch queue and
      not yet visible anywhere else.

---

### Lane 0.20 — The console tells the operator to open a terminal (operator evaluation 2026-09-13)

Found while the operator verified the Release 3.1 empty-room gate. The gate
works: previewing a dispatch with no runner alive refuses, says why, and names
the remedy. The remedy is the problem — it is a command to paste into a shell:

> Runner stalled: nothing would pick this up. Start the operator runner first —
> `pwsh -File "F:\Development\GitHubRepoManagement\scripts\Invoke-RoadmapTaskRunner.ps1"`.

A console that hands its operator a terminal command has made them the
mechanism. Operator intent, 2026-09-13: **the app should start the runner
itself when one is not running**, not ask.

**The constraint that makes this non-trivial, stated once so it is not
rediscovered.** The runner must execute as the OPERATOR, because it launches
their authenticated Claude Code. The portal is a LocalSystem service. A runner
spawned by the service would come up as SYSTEM with no Claude credentials,
claim packets and fail them — strictly worse than refusing, and the same
boundary that made this product enqueue rather than dispatch at all. So "start
it from the service" is not a missing button; it is a cross-identity problem.

**Auto-start is not auto-approve.** The runner only claims what approval has
already queued, so starting it unattended does not let unsanctioned work begin.
That separation must survive this lane.

**Two thirds of this lane was closed the day it was written; recorded here as
prose because a `[x]` in this file is a mistake, not a record.**

The logon-triggered task **already existed** and this lane was wrong to propose
building it: [`Install-RoadmapTaskRunner.ps1`](scripts/service/Install-RoadmapTaskRunner.ps1)
registers `RepoMgmtRoadmapTaskRunner` as `xfaith` / `LogonType=Interactive` /
`RunLevel=Limited`, unelevated, and it was present and enabled on THESHIRE with
a clean exit from 2026-09-11. The logon start was never the gap.

The gap was recovery, and it is now shipped. The operator stopped the runner at
17:59 UTC to verify the empty-room gate; two hours later nothing had restarted
it, because a logon trigger cannot fire again until they log out. So the queue
had nobody to work it and the console's only advice was a command to paste.
`-RepeatMinutes` (default 5) now sets `$trigger.Repetition` on that logon
trigger. It is safe **only** because `-MultipleInstances IgnoreNew` makes a
repeat a no-op while a runner is alive, and the module smoke fails if either
half is removed — a repetition without that policy would start a second runner
against the same queue. Proved live 2026-09-13: runner up at PID 28224,
`GET /api/roadmap/runner` reporting `state: present` with a 3.4s heartbeat.

That the repeating trigger brings a stopped runner straight back is the INTENDED
behaviour, not a problem to solve. Keeping it running is the service's job. This
also retires the cross-identity question entirely: a LocalSystem caller never
reaches into a user session at all.

**The remaining three shipped 2026-09-13; recorded as prose, because a `[x]` in
this file is a mistake, not a record.**

*The action, not the command.* `POST /api/roadmap/runner/start` and
`POST /api/roadmap/runner/stop`
([`Automation.RunnerControl.ps1`](backend/modules/automation/Automation.RunnerControl.ps1))
replace the pasted remedy everywhere it was offered: the header popover, the
Insights pane, and the empty-room refusal text. The gate itself is untouched —
it was operator-verified and refusing to queue into an empty room is still
right; only the remedy it names changed. The command survives in exactly one
place, beside the error, when the console tried to start a runner and could not.
Three frontend assertions were INVERTED to hold that line: they used to require
the command in the detail and the precondition, and now forbid it.

The host never spawns a runner. It is LocalSystem, and a runner it spawned would
hold no Claude credential and fail everything it claimed. It triggers the
operator-owned scheduled task and lets Task Scheduler make the cross-identity
hop. A start therefore reports REQUESTED, never STARTED: an Interactive task
cannot run while the operator is logged out, so only the heartbeat may say a
runner exists, and the console watches for it and says plainly when it never
arrives.

*The kill switch.* `roadmap-task-runner.hold.json` is the durable half the stop
marker could never be — the marker is consumed by the runner honoring it, so on
its own "stop" would have lasted one repeat interval. The runner reads the hold
before anything else and leaves, making each five-minute repeat a two-second
no-op instead of a revival. It fails CLOSED, the only reader here that does: an
unreadable record still holds, because a corrupt byte must not resume work the
operator deliberately halted. Resuming is releasing it, as designed above — one
start path, not two.

Both control files sit under `REPO_MGMT_RUNNER_CONTROL_ROOT`, the fifth
resolver of its kind. The api-host smoke starts its host with the operator's
REAL workspace root, so without it a gate exercising the stop route would have
stopped their live runner and — a hold being durable by design — kept it
stopped. Same shape as the gate that twice emptied the portfolio index, with a
worse recovery, and asserted rather than assumed: the gate fails if a hold ever
appears in the operator's own output directory.

*One pane.* [`RunnerControlPanel.tsx`](frontend/components/RunnerControlPanel.tsx)
leads the Insights tab with runner state, queued total, claimable now, stranded
count, oldest-queued age, the per-provider backlog and the live runner's
identity — the two facts that arrive on one route and had never been rendered
together. It carries the kill switch, because a control to halt work put
anywhere but where the work is visible asks the operator to decide blind. The
header pill and this pane share one hook, so they cannot disagree.

Proved 2026-09-13 against a real host on 127.0.0.1:7099 with the control root
isolated: stop answered 202 and wrote both files, `GET /api/roadmap/runner`
then reported `stoppedByOperator=true`, start answered 202 with
`holdReleased=true` and `taskTriggered=true`, and the operator's live runner
(pid 28224) kept beating throughout. The module smoke proves the behavioural
half against a real detached runner: a held runner exits 0 without claiming, and
does NOT consume the hold.

**The limit to state plainly rather than design around.** "If the service is
running, start the runner" cannot be wholly true. The service is LocalSystem and
outlives any session; the runner needs the operator's session for their
authenticated Claude Code. So the runner is up whenever they are **logged in**,
not whenever the service is up. When they are logged out the queue accumulates
and nothing works it — which is correct behaviour, and the console must say so
rather than let a growing queue read as progress.

**Not doing, decided 2026-09-13.** Creating a scenario where the runner is down,
purely to watch how the app reacts to a job that is the app's own
responsibility, spends time to learn nothing. If a real case arrives where the
runner is not running and the service fails to start it, the error that case
produces is the thing to read — a rehearsed one would not have told us what the
real one will.

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

## 10. Definition of Done

**A milestone is done when its `check:` exits 0 in CI on the PR head.** Nothing
else. Everything below is what a `check:` must cover to be admitted, so that the
sentence above stays true:

- the check exercises real behaviour — a route returning mock data fails it
- the check is in the repository and runs under `-FailOnError` in the smoke workflow
- affected docs changed in the same PR when behaviour changed (`Test-RoadmapCapabilityRecord.ps1`)
- the milestone it closes is marked `[x]` and archived in the same PR
- a signal it adds to a dashboard resolves to source data (`Test-BadgeProvenance.ps1`, or add it)

**A release is done when every milestone in it is `[x]`.** Field proof for the
release is a separate line in the operator queue and does not hold the release.

A check you cannot write is a design decision you have not made. Record it in
`open-decisions.md`, take the next item, and do not ask the operator in chat.

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
