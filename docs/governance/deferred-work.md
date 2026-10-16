# Deferred Work

> **What this file is.** On 2026-10-16 Ben set one objective through
> 2026-11-15: a thirty-day proof of value. One active release (ROADMAP.md
> Release 4.1) proves the delivery loop on repositories other than this one,
> and nonessential feature work is frozen unless a change is needed to complete
> that loop. Every requirement the freeze took out of `ROADMAP.md` is kept here,
> moved verbatim or as near verbatim as the move allowed. Nothing in this file
> is rejected, and nothing in it is deleted.
>
> **Deferred work does not resume on 2026-11-15 by default.** Its priority after
> the window depends on the delivery evidence: the weekly delivery report, the
> decision ledger and the merged pull requests.
>
> For the active roadmap, see [`ROADMAP.md`](../../ROADMAP.md). For work already
> shipped, see [`docs/history/completed-releases.md`](../history/completed-releases.md).

## How to read this file

- Each item carries **why it was deferred** (one line) and **when to reconsider
  it**: the evidence that would justify bringing it back. Both are in the index
  below, one row per item.
- Checkbox and `(state: ...)` text is as it stood in `ROADMAP.md` on 2026-10-16.
  A `[ ]` here is a preserved requirement, not a commitment. No agent takes work
  from this file.
- An item that stayed in `ROADMAP.md` is replaced here by a one-line pointer, so
  the block it came from still reads in order.
- Links inside moved blocks keep their repository-root paths, as the
  completed-release archive does, so the text stays verbatim.
- **Re-admitting an item** moves it back into `ROADMAP.md`, under Must work now
  or Must improve next, in a PR that cites the evidence that met its condition
  and carries its `check:`. Its text here becomes a one-line pointer.

## Index

### Former Current focus items

| Item | Why deferred | Reconsider when |
| --- | --- | --- |
| Accept/reject ledger (`Test-DecisionLedger.ps1`) | Superseded by the Must work now decision ledger, which also captures operator minutes. The prediction, index SHA and `modelVersion` fields are what was not carried over. | The delivery ledger holds enough decisions to revisit the D-013 scorer weights; then add those three fields. |
| 3.7 / M5 prep — previews staged | The 3.7 cohort trial is absorbed by Release 4.1, whose proposals come from the live loop on any repository. | Release 4.1 candidates turn out to be chosen for convenience, not by kind; then the cohort's rule-based selection returns. |
| Portfolio brief and conclusion diff | Frozen by name in the 2026-10-16 decision. It reports on the product's model, not on delivered improvements. | The weekly delivery report exists and a reader cannot act on it without the "what changed since the last run" narrative. |
| One manifest walk | Internal refactor. No drift between the three walkers has been observed. | A repository's kind, technology profile and repo type disagree on one checkout. |
| Lane 0.19 — operator queue in the console | Console polish. The queue file does its job. | An operator-queue row is missed because the console did not show it. |
| 3.8 / D-001 — dependency notion | Frozen by name. The parser and selection are built (Lane 0.18 H-13a/b, archived), no target roadmap declares dependencies, and only the schema change remains. | A target repository declares dependencies, or a dispatch picks an item whose prerequisite was unmet. |
| 4.0 A — counts reconcile on every scan | Release 4.0 is frozen by name. Count consistency is console trust work, not loop work. | A count disagreement leads to a wrong dispatch or readiness decision during the proof. |
| D-022 (1) — one lifecycle the operator sees | Console vocabulary, frozen with the v2 console direction. | The operator misreads a repository's state in a way that costs a decision. |
| D-022 (5) — proposals with the operator upstream | Batch review is a sophisticated workflow with no demonstrated demand yet. | Reviewing proposals one at a time is the largest share of operator minutes in the weekly report. |

### Release 2.9 — Operator Field Proof + Mobile Completion

| Item | Why deferred | Reconsider when |
| --- | --- | --- |
| Deploy the 2.7 Phase D freeze prevention | The agent half is done. What remains is the elevated install, which is OQ-4 in the operator queue. | `Test-LiveServiceCurrency.ps1` reports a route the loop needs missing from the running service. |
| One real copilot entry through the runner | Moved to `ROADMAP.md` §7 as "Copilot dispatch reaches a live task". The live run is OQ-6. | Not applicable; the item is live in `ROADMAP.md`. |
| 2.3 Phase 2 trend accrual | Frozen by name. Calendar-gated, and it holds nothing. | The weekly delivery report needs a 90-day window. |
| [non-blocker] `Dashboard.tsx` refactor | A refactor with no loop dependency. | A loop surface change is blocked by the size of `Dashboard.tsx`. |

### Release 3.7 — Portfolio Value Proof

| Item | Why deferred | Reconsider when |
| --- | --- | --- |
| Execute at least five improvements | Absorbed by Release 4.1's acceptance criteria: five merged PRs on other repositories, with operator minutes. | The 3.7 cohort becomes the proof's candidate set. |
| Adjust and decide | Absorbed by the review of the delivery evidence after 2026-11-15. | Same as above. |

### Release 3.9 — Adaptive Routing

| Item | Why deferred | Reconsider when |
| --- | --- | --- |
| Classify a task before choosing anything to run it | Frozen by name. Routing on evidence needs runs, and there has been no agent run outside the smoke tests since 2026-09-01. | The run ledger holds enough closed runs across at least two providers to compare them. |
| `NO_AGENT` deterministic tier | Same freeze. | A dispatched task turns out to have been answerable without an agent. |
| A cost estimator that can eventually enforce | Same freeze. Operator time limits throughput, not provider spend. | Provider spend or quota, not operator time, stops a loop run. |
| A performance store keyed by what actually varies | Same freeze. There is no run history to store. | Same as the task classifier. |
| Evidence overrides the cold-start prior | Same freeze. Depends on the performance store. | The performance store exists and holds history. |
| Report the verified-task rate | Same freeze. The weekly delivery report covers what the proof needs. | Release 3.9 is re-admitted. |

### Release 4.0 — Rule-Driven Lane Assignment

| Item | Why deferred | Reconsider when |
| --- | --- | --- |
| A: counts reconcile on every scan | Frozen by name (see the Current focus row above). | See above. |
| A: [non-blocker] two more rankings on the old value scale | Console consistency. Neither surface feeds a dispatch. | Either surface's order is used for a dispatch decision. |
| B: step types | Phases B–E are frozen by name. The loop dispatches one step kind at a time and needs no taxonomy yet. | Next actions beyond roadmap rewrites (`ROADMAP.md` §7) produce step kinds that must go to different agents. |
| B: agent registry | Same freeze. One profile per provider is enough. | Two agents with different allowed work share one provider. |
| B: lanes are declared | Same freeze. This is v2 lane structure. | The v2 console is re-admitted. |
| B: units per step and a budget ledger | Same freeze. Operator time is the constraint, not provider budget. | A provider limit stops a loop run. |
| B: repository locks and an attempts counter | Same freeze. The single local slot prevents concurrent runs. | Two runs touch one repository at once. |
| B: run-close fields | Moved to `ROADMAP.md` §7. The weekly report's failure counts and agent time read them. | Not applicable; the item is live in `ROADMAP.md`. |
| B: four per-lane metrics | Same freeze. They exist for the v2 lane cards. | The v2 console is re-admitted. |
| B: vendor balance feed | Same freeze. Spend is not the constraint. | A provider limit stops a loop run. |
| B: every agent launches through the 3.8 adapter contract | Same freeze. Claude already runs through its adapter, and the Copilot path is `ROADMAP.md` §7. | A second agent must be launched by a route other than the runner. |
| C: rules as data, pure assigner, fixture per rule, dry run | Same freeze. The proof dispatches supervised, one item at a time. | Choosing what to dispatch, not reviewing it, is the largest share of operator minutes per merged improvement. |
| D: shadow mode, automation toggle | Same freeze. Both depend on phase C. | Phase C is re-admitted. |
| D: the api-host smoke ends by a deadline | Same freeze. CI hygiene, not loop work. | A hung smoke costs a CI run. |
| E: all eight v2 console milestones | The v2 console is frozen by name. | The proof shows the loop delivers. Then the console is rebuilt on what the evidence shows the operator needs. |

### Cross-cutting lanes

| Item | Why deferred | Reconsider when |
| --- | --- | --- |
| Lane 0.2 — read check-run detail | Needs the D-003 grant (OQ-5), and the rollup proxy is enough for one PR at a time. | Outcome recording cannot tell a pending check from a failed one on a product PR. |
| Lane 0.9 — stale browser-persisted GitHub owner | Scan noise, not on the loop's path. | A discovery or readiness result is traced to the stale owner. |
| Lane 0.7 — record whether a repo externalizes its history | Frozen by name (awareness metadata). | A consumer reads `completedCount` as progress. |
| Lane 0.8 — [non-blocker] scheduled and operator dispatch writers | Self-governance (test-coverage symmetry). | A divergence between the two writers is observed. |
| Lane 0.8 — P2 empty catch blocks (built) | Frozen by name (0.8 ratchets). It is held at baseline. | A failure is traced to a swallowed exception. |
| Lane 0.8 — E2 type the API client | Same freeze. | A contract drift between host and client reaches the operator. |
| Lane 0.8 — P3 plaintext-password params | Same freeze. It needs a design review. | A credential surface changes for the loop. |
| Lane 0.8 — capability record for every shipped change | Self-governance. | A shipped change lands with its roadmap item unmoved during the proof. |
| Lane 0.10 — scan-snapshot retention | Frozen by name. Disk hygiene. | Snapshot volume slows a scan or fills the disk. |
| Lane 0.12 — [non-blocker] two clones of one remote | Counting accuracy, and it needs a product judgement. | A readiness count includes a duplicate checkout. |
| Lane 0.12 — classify nested repositories | Counting accuracy. | A readiness count includes a nested working tree. |
| Lane 0.13 — `estimatedSessionWorkUnits` | Frozen by name (console). | The ranking's effort tiebreak decides which repository the proof works on. |
| Lane 0.14 — button token set | Frozen by name (console polish). | The v2 console is re-admitted. |
| Lane 0.14 — opacity ladder against WCAG AA | Same freeze. | The v2 console is re-admitted, or an operator misreads an `unmeasured` value. |
| Lane 0.14 — breakpoints above 768px | Same freeze. | The v2 console is re-admitted. |
| Lane 0.14 — stable `settings.json` writes | Noise in this repository's tree, not a target's. | The rewritten file is committed by mistake. |
| Lane 0.14 — dialog dismiss contract in 17 modals | Same freeze. | The v2 console is re-admitted. |
| Lane 0.16 — [non-blocker] detect versions | No demand. | An upgrade-planning question reaches the product. |
| Lane 0.17 — [non-blocker] api-host smoke vs a live runner | Environmental. Lane 0.8 recorded runner-heartbeat isolation on 2026-09-13; re-check before working it. | The smoke goes red on a clean tree while a runner is live. |
| Lane 0.19 — [non-blocker] verification queue in the console | Same as the Current focus Lane 0.19 row. | Same as that row. |
| Lane 0.21 — a finished scan reaches the page | Load speed is frozen by name. | Waiting on the console shows up in the operator-minutes breakdown. |
| Lane 0.21 — "Auto-scan off" means no scan on load | Same freeze. | Same as above. |
| Lane 0.21 — hidden tabs cost nothing at startup | Same freeze. | Same as above. |
| Lane 0.21 — every wire timestamp is ISO 8601 UTC | Same freeze. | A misread timestamp changes a decision. |
| Lane 0.21 — the first screen is honest and short | Same freeze. | Same as the first Lane 0.21 row. |
| Lane 0.22 — one snapshot, one denominator, honest zeros | Most 0.22 label and count items are frozen. | A count disagreement leads to a wrong dispatch or readiness decision. |
| Lane 0.22 — a control does what its label says | Same freeze. | A mislabelled control costs the operator a step in the loop. |
| Lane 0.22 — lanes close on evidence | Same freeze. Complete still releases a lane, so the loop is not blocked. | A lane stays occupied after its PR merged during the proof. |
| Lane 0.22 — Cancel reaches the runner | Same freeze. | A cancelled run produces an orphan PR. |
| Lane 0.22 — lane tile shows phase, clock and work order | Same freeze (console). | The v2 console is re-admitted. |
| Lane 0.22 — labels match what they count | Same freeze. | Same as the snapshot row. |
| Lane 0.22 — Insights reports a gap as a gap | Same freeze. | Same as the snapshot row. |
| Lane 0.22 — repository detail agrees with itself | Same freeze. | Same as the snapshot row. |
| Lane 0.22 — nothing unfinished in production | Same freeze. | The v2 console is re-admitted. |

---

## Former Current focus items (moved from ROADMAP.md, 2026-10-16)

In their original order. Two items stayed in `ROADMAP.md` and are pointers here.

- Lane 0.22 — one dispatch-eligibility rule: stays in `ROADMAP.md` (Must work now).
- D-012 — the permission envelope binds: stays in `ROADMAP.md` (§7, Must improve next).
- [ ] **Accept/reject ledger (steering extension 1, Rung 1).** Every next action
      and top value item is a prediction; every response to one — accept,
      reject, edit — is a label. Capture each with the prediction it answers and
      the index SHA and `modelVersion` it was drawn under, so the leverage
      panel's "not captured" figure becomes a computed one and the scorer's
      weights (D-013) have evidence to be revisited against. _(state: planned)_
      `check: pwsh ./tests/Test-DecisionLedger.ps1 -FailOnError`
- [ ] **3.7 / M5 prep — previews staged, not applied.** For each `strengthen`
      repository in the cohort, generate the preview its next action produces and
      stage it under the gitignored `output/trials/release-3.7/previews/`. The
      tracked record in `evidence/trials/release-3.7/` holds only the action, route,
      preview hash and state, never repository text, because this repository is
      public. An AI-routed preview is staged as a confirmation request naming the
      provider and the file; the agent sends nothing. The operator approves from
      the queue, and each response lands in the ledger above. _(state: planned)_
      `check: pwsh ./tests/Test-TrialPreviews.ps1 -Cohort evidence/trials/release-3.7/cohort.json -RequireAll`
- [ ] **Portfolio brief and conclusion diff (steering extension 5, Rung 1).**
      Diff two conclusion payloads by index SHA and render the movement as prose
      with the evidence chain under every claim — one exported file a reader who
      has never seen the product can act on. Deterministic; any narration is
      constrained to the evidence lines and marked as narration.
      _(state: planned)_
      `check: pwsh ./tests/Test-PortfolioBrief.ps1 -FailOnError`
- [ ] **One manifest walk (steering extension 4).** Repo type, the technology
      profile and kind signals are three walkers over the same files. One scan
      produces all three views, so they cannot drift and a checkout is read once.
      _(state: planned)_
      `check: pwsh ./tests/Test-ManifestWalk.ps1 -FailOnError`
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
- [ ] **4.0 A — counts reconcile on every scan.** Per snapshot, status counts
      sum to the total and scanned, in-scope, assessed and ledger counts each
      carry one stated definition; the product runs the same assertion after
      every scan and shows a header badge naming the mismatch when it fails.
      _(state: planned)_
      `check: pwsh ./tests/Test-CountsReconcile.ps1 -FailOnError`
- [ ] **D-022 (1) — one lifecycle the operator sees.** Needs plan → Plan needs
      approval → Ready for agents → Agent working → In review → Healthy /
      Archived, with flags beside it (Uncommitted changes, CI failing, Behind
      remote, Docs gap). The three steering conclusions stay the model's output;
      the consistency table maps every operator state to the conclusion it
      agrees with. L-levels and hold codes become detail. Amends steering in the
      same PR. Stands under D-024: these are the states the lane cards and
      Portfolio render. _(state: planned)_
      `check: pwsh ./tests/Test-OperatorLifecycle.ps1 -FailOnError`
- [ ] **D-022 (5) — proposals with the operator upstream.** The operator picks N
      repositories and triggers "Generate proposals" with a cost preview and the
      egress confirmation; the review queue shows a side-by-side diff with
      keyboard approve, reject and skip, and each response lands in the ledger.
      Nothing is generated in the background. _(state: planned)_
      `check: pwsh ./tests/Test-ProposalBatch.ps1 -FailOnError`

---

## Former execution order (moved from ROADMAP.md §4, 2026-10-16)

Superseded by the Release 4.1 dependency table in `ROADMAP.md` §4. Kept because
it records the sequencing decisions behind Releases 3.7, 3.8 and 4.0.

### Execution Order and Dependencies

Release numbers identify scope — they do not dictate sequence. Work through
open items in the order below, and update this section whenever a lane
closes or a new dependency appears.

**Trial sequencing — approved 2026-09-05.** Select the ten by kind now; fix
and validate the remaining Lane 0.15 truth defects before measured execution.
Release 3.6 field proof (OQ-1) and operator approvals remain required. Lane
0.18 acceptance evidence is required for each counted improvement, but an
independent operator check can supply it; completing all of Lane 0.18 is not
a prerequisite. **Dependency ordering is no longer blocked:** D-001 was
answered 2026-09-06 — a managed roadmap may optionally declare dependencies,
within one repository, acyclic, keyed on stable item ids, gating dispatch
eligibility. The cohort is unblocked too; see the D-006 note under Release 3.7.

1. **Release 3.7 — Portfolio Value Proof** is the next engineering
   release (execution contract in §6). The model fixes the first cohort pass
   exposed — kind detection (M4a and its follow-through), limiting foundation
   by kind applicability (M4b), next action by the kind of gap (M4c) — and the
   lifecycle/conclusion consistency contract were verified 2026-09-14 and
   archived. What remains, in order: the accept/reject ledger, so responses
   to previews are captured from the first one; M5 prep, staging the
   previews; the portfolio brief; measured execution; the rollout decision.
   3.7 needs Ben for the approvals, not for the engineering. Every release
   from 1.x through 3.6 is engineering-closed; new work is still proposed as a
   release with its own contract, never appended to a closed one.
2. **Release 2.9 — the active release.** Its engineering half closed
   2026-08-26 (archived); what remains is the operator half, batched and
   waiting on Ben's presence at the machine.
3. **Release 3.6 field proof** — OQ-1 in the operator queue: eyes on the
   `Today` landing, the outcome card and the Insights leverage panel.
   Engineering closed 2026-09-14; the proof ratchets the archived record and
   holds nothing.
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
| 3.7 accept/reject ledger                  | nothing                                                | none               |
| 3.7 M5 previews staged                    | the ledger; OQ-12 (live index carries kind signals)    | soft — sequencing  |
| 3.7 portfolio brief                       | nothing — two conclusion payloads already exist        | none               |
| 3.7 measured execution + rollout decision | operator approvals (queue item OQ-3)                   | **operator queue** |
| One manifest walk                         | nothing                                                | none               |
| 3.8 D-001 dependency notion               | nothing                                                | none               |
| 3.8 provider-aware scheduler              | 3.7 rollout decision; D-003 grant (OQ-5)               | soft — sequencing  |
| Lane 0.19 verify tab                      | nothing                                                | none               |
| 4.0 A — counts reconcile                  | Lane 0.22 one-snapshot item (slice 4.0-2)              | soft — sequencing  |
| 4.0 B/C — data model and assigner         | 4.0 A; 3.8 WorkPacket and adapters (built)             | soft — sequencing  |
| 4.0 E — the v2 console                    | D-024 (decided 2026-09-24); phases A–D                 | soft — sequencing  |
| Lane 0.5 tab disclosure                   | product decision — `open-decisions.md`                 | hard — design      |
| 2.9 trend accrual                         | calendar time                                          | time-gated         |

---

## Deferred releases (moved from ROADMAP.md §5 and §6, 2026-10-16)

### Release 2.9 — Operator Field Proof + Mobile Completion

#### Former §5 snapshot — 2.9 Operator Field Proof + Mobile Completion

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

#### Former §6 release contract

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
- One real **copilot** entry through the runner: moved to `ROADMAP.md` §7 on
  2026-10-16 as "Copilot dispatch reaches a live task"; the live run is OQ-6.
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

**All three addressed before measurement, 2026-09-14.** M4a resolves kind from
manifests, entry points and the README purpose line; M4b chooses the limiting
foundation only among the domains that apply to the kind; M4c routes each kind
of planning gap to its own preview. All are verified and archived in
`docs/history/completed-releases.md`. They landed before any improvement was
executed, so no measurement straddles a model change, and every conclusion
carries `modelVersion` and the index SHA it was drawn under.

**Still open:**

- [ ] **Execute at least five improvements** through preview → approve →
      execute → validate, recording operator minutes, agent first-pass
      result, and whether the repository is materially stronger afterwards —
      appropriate-as-is or archive counts as a conclusion outcome, not automatically
      as one of the five improvements. Each counted improvement needs an
      independently checked acceptance criterion and before/after evidence;
      merge evidence alone is insufficient. _(state: planned)_
      `check: pwsh ./tests/Test-TrialExecution.ps1 -Cohort evidence/trials/release-3.7/cohort.json -MinCountedImprovements 5`
- [ ] **Adjust and decide** — every false positive or bad recommendation the
      executed improvements expose is either fixed as a rule change carrying
      `observedOn` or recorded with its reason, and the go/no-go for the full
      rollout is recorded with the leverage numbers behind it. The check asserts
      that record, never a distribution over the cohort (steering §6).
      _(state: planned)_
      `check: pwsh ./tests/Test-TrialDecision.ps1 -Cohort evidence/trials/release-3.7/cohort.json -FailOnError`

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

**Dependencies:** Lane 0.15 truth validation; Release 3.6 field proof (OQ-1);
the operator's approvals and measured effort. **D-006 no longer blocks the
cohort** (decided 2026-09-06): external management is owner intent and may not
be inferred, so a category with no natural member is recorded as unrepresented
rather than filled by a substitute. The trial proceeds with nine named
repositories and records the tenth category as having no cohort member.

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

### Release 4.0 — Rule-Driven Lane Assignment

**Status:** planned — defined 2026-09-24 from Ben's "build it from the engine
outward" plan for the Repo Console v2 mockup. The mockup is mostly a view of
four things the product does not have: one ranking, typed steps, agent
profiles and a rule-driven assigner. Built screen-first, the Lanes tab would
have nothing real to show, so the phases below run engine-first and the screen
is last. Ben's plan numbered the phases 2.2–2.6; those numbers belong to closed
releases, so they are phases A–E of one release here, in the same order.

**Goal:** lanes are filled by a pure, rule-driven assigner that reads one
ranking, typed steps, agent profiles, locks and a budget, and explains every
choice by rule id — first in shadow beside the operator's hand dispatches,
then, once the two agree, with automation switched on under stated guardrails.

**Where it sits.** D-024 (Ben, 2026-09-24) supersedes D-022: lanes stay as the
main thing the operator works with — lane cards with trends and per-lane
usage — and Dashboard is the only place to take action. The destinations are
Dashboard (Now + Lanes), Queue (read-only), Insights (read-only), Portfolio,
Runs and Settings. The 2026-09-18 lane rulings under Lane 0.22 (lanes close on
evidence, Cancel reaches the runner, tiles show the phase) become lane-card
behaviour. Phase A leads Current focus ahead of the D-022 items that survive.

#### Product outcomes

- Today and the board rank the portfolio the same way, so the operator never
  sees one repository as #1 and #8 at once.
- Every lane assignment names the rules that made it, including why a lane was
  left empty, and the same inputs always give the same answer.
- A lane card shows what its agent has spent, in the vendor's own unit, and
  its trend, because every run that closes records when, with what verdict,
  under which vendor, at what usage.
- Automation, when it is switched on, stops at the budget cap, holds dirty
  trees and new-contract authoring for the operator, and demotes an item after
  three consecutive failures — and it cannot be switched on until the shadow
  log shows the assigner and the operator agree.

#### Engineering milestones

**Phase A — reconcile what already exists (current UI, no new screen).** The
assigner dispatches whatever the queue hands it, including bad data, so the
queue is made honest first. Three of Ben's five items are already open under
Lane 0.22 and are not repeated: roadmap-line extraction is "Only actionable
roadmap lines become work"; the scan-status contradiction and the count
denominators are "One snapshot, one denominator, honest zeros"; "Blocking a
lane" placement is "Labels match what they count". Checked against the code
2026-09-30: only the counts gate depends on one of them (the one-snapshot
item). The ranking reads the operations index, not the extracted work lines,
and the hold card changes grouping, not placement, so both shipped first as
slice 4.0-1. One ranking and one hold card per repository were verified
2026-09-30 and archived (`docs/history/completed-releases.md`, Release 4.0).
What is new and still open:

- [ ] **Counts reconcile on every scan, and the header says when they do not.**
      A gate asserts, per snapshot, that status counts sum to the total and
      that scanned, in-scope, assessed and ledger counts each carry one stated
      definition. The product runs the same assertion after every scan and
      shows a header badge naming the mismatch when it fails, instead of two
      tabs quietly disagreeing. _(state: planned)_
      `check: pwsh ./tests/Test-CountsReconcile.ps1 -FailOnError`
- [ ] **[non-blocker] Two more rankings on the old value scale.** Found by the
      one-ranking sweep (2026-09-30), outside Today and the board: the
      Dashboard's top-entries card (`Dashboard.tsx`) and the trend seed's top
      candidates (`apiClient.ts`) sort by `topValueItem.valueScore`, which the
      2026-09-01 correction retired. Read `ranking.rank` in both, and widen the
      gate from the two views' imports to every surface that orders
      repositories. _(state: planned)_
      `check: pwsh ./tests/Test-OneRanking.ps1 -FailOnError -AllSurfaces`

**Phase B — the data model** (on 2.1's SQLite layer and 3.8's WorkPacket).

- [ ] **Step types.** A closed taxonomy — `roadmap.author`, `doc.standardize`,
      `task.*` and their siblings — and a mapping from every existing next
      action to one type: "Preview the smallest credible plan"
      (`roadmap-repair-preview`) is `roadmap.author`, a structure repair is
      `doc.standardize`, a checklist item is `task.*`. A WorkPacket carries its
      `stepType`; a next action with no mapping fails the gate by name.
      _(state: planned)_
      `check: pwsh ./tests/Test-StepTypes.ps1 -FailOnError`
- [ ] **Agent registry.** `backend/config/agents.json` (`schemaVersion` v1):
      id, provider, allowed step types, concurrency. An agent is a profile over
      a 3.8 provider adapter, not a new adapter; `GET /api/providers` reports
      each agent beside its provider. _(state: planned)_
      `check: pwsh ./tests/Test-AgentRegistry.ps1 -FailOnError`
- [ ] **Lanes are declared, and a lane is a stage.** The mockup's lanes are
      "Stage 1 — Documentation refinement · Agent A · copilot" and "Stage 2 —
      Phase achievement · Agent B · anthropic", with "stage 1 gates stage 2".
      A lane declaration (id, stage name, the step types the stage takes, the
      bound agent) lives beside the agent registry; the gating between stages
      is a `policy.json` rule, never a lane property, so the assigner can
      explain it by id. _(state: planned)_
      `check: pwsh ./tests/Test-LaneDeclarations.ps1 -FailOnError`
- [ ] **Units per step and a budget ledger.** Each step type declares its
      units; each run appends `units_consumed` to a ledger in the shape of
      [`ROADMAP_BUDGET_MODEL.md`](standards/roadmap/ROADMAP_BUDGET_MODEL.md),
      and remaining budget is derived from that ledger, never stored.
      _(state: planned)_
      `check: pwsh ./tests/Test-StepBudgetLedger.ps1 -FailOnError`
- [ ] **Repository locks and an attempts counter** written to the execution
      events ledger (`Execution.Events.ps1`): a lock names the run that holds
      it and is released by its terminal event; attempts count per item hash
      and survive a restart. _(state: planned)_
      `check: pwsh ./tests/Test-RepoLocks.ps1 -FailOnError`
- A run that closes records `completedAt`, the verdict, the vendor and usage:
  moved to `ROADMAP.md` §7 (Must improve next) on 2026-10-16.
- [ ] **Four per-lane metrics over a 7-day and a 30-day window.** From the
      run-close fields, one route computes per lane: occupied (share of runner
      hours), tasks entered (with per-day rate), median agent time (with the
      closed count it rests on), and completed (with its rate and the failed
      or demoted count), each with its delta against the prior window and its
      per-day series for the sparkline. A metric with no closed run in the
      window reads "unmeasured", never 0. _(state: planned)_
      `check: pwsh ./tests/Test-LaneMetrics.ps1 -FailOnError`
- [ ] **Each vendor's balance feed confirms balance left and reset time.**
      Copilot is counted in premium requests; Anthropic and OpenAI in dollars.
      The feed records, in the vendor's own unit against the 3.8 capacity
      window: the source it read (GitHub billing API, Anthropic Admin API cost
      report, OpenAI Costs API), used, limit, left, the reset instant, the
      per-day series, tokens where the vendor reports them and "tokens not
      reported" where it does not. The lane share of the month is attributed
      from run-close usage and shown beside "other use on account"; the
      month-end projection is shown as its arithmetic (used ÷ elapsed days ×
      days in month), never as a forecast. Nothing is converted into a shared
      unit — a converted number is a guess wearing a unit. A vendor with no
      feed reads "unconfirmed", never 0. _(state: planned)_
      `check: pwsh ./tests/Test-VendorBalanceFeed.ps1 -FailOnError`
- [ ] **Every agent launches through the 3.8 adapter contract.** Ben's plan
      left "how the second agent runs" open because
      `Start-RoadmapCopilotTask.ps1` only starts Copilot. Release 3.8 answered
      it: the WorkPacket contract and the Claude and Codex adapters are built.
      What remains is the wiring — a dispatch resolves the agent's adapter from
      the registry, and no route calls the Copilot script as the only entry.
      _(state: planned)_
      `check: pwsh ./tests/Test-AgentLaunchPath.ps1 -FailOnError`

**Phase C — the assigner** (the deterministic side of the two-brains design).

- [ ] **Rules as data.** `backend/config/policy.json`: an ordered list of rules
      with ids, each a predicate over queue item, agent, lane, lock and budget
      fields, with a plain-language `because`. The operator's own thumb on the
      scale is a rule like any other: a favourite ranked above higher-value
      work carries the rule id, and the row says so. _(state: planned)_
      `check: pwsh ./tests/Test-LanePolicy.ps1 -FailOnError`
- [ ] **A pure assignment function.** `Get-LaneAssignment -Queue -Agents
      -Locks -Budget -Policy` returns what goes in each lane and the rule ids
      behind each choice, including why a lane is left empty. It uses no
      randomness, no model call and no clock, so the same inputs always give
      the same result — the canonical-verdict requirement applied to dispatch.
      _(state: planned)_
      `check: pwsh ./tests/Test-LaneAssignment.ps1 -FailOnError`
- [ ] **A fixture per rule, including the mockup's scenario.** Every rule id
      has a fixture that fails when the rule is removed; one fixture is the
      mockup's case — every ready item at stage 1 and Agent B not allowed
      `doc.*` steps — and asserts lane 2 is empty with the rule that says so.
      _(state: planned)_
      `check: pwsh ./tests/Test-LaneAssignment.ps1 -FailOnError -RequireFixturePerRule`
- [ ] **Dry run.** `GET /api/lanes/dry-run` is the same function over the next
      hour's queue with nothing dispatched; its payload is the assignment plus
      rule ids, and the route writes no ledger. _(state: planned)_
      `check: pwsh ./tests/Test-LaneDryRun.ps1 -FailOnError`

**Phase D — shadow mode, then switching on.**

- [ ] **Shadow mode.** The assigner writes "would assign X to lane N because
      rules …" to the events ledger while dispatch stays by hand. Each hand
      dispatch that differs from the shadow choice is logged with both choices
      and their rule ids, and a disagreement report over any window is one
      route, so the review is a read, not a recollection. _(state: planned)_
      `check: pwsh ./tests/Test-AssignerShadow.ps1 -FailOnError`
- [ ] **The api-host smoke ends by a deadline.** Unattended lanes turn a hang
      into spent budget with nobody watching. The smoke has per-request
      timeouts (180 s, 900 s for scans) and no run-level one; it gains a
      whole-run deadline that kills the host tree and fails by name, with the
      route it was on. _(state: planned)_
      `check: pwsh ./tests/Test-SmokeDeadline.ps1 -FailOnError`
- [ ] **The Automation toggle, with its guardrails.** "Automation off /
      Enable" is a Settings control that can only be enabled once the shadow
      log holds a disagreement report; enabled, the assigner dispatches and:
      stops at the budget cap, always holds dirty trees and new-contract
      authoring for the operator, and demotes an item after three consecutive
      failures. Each guardrail is a rule id in `policy.json`, so the log names
      it when it fires. _(state: planned)_
      `check: pwsh ./tests/Test-AutomationGuardrails.ps1 -FailOnError`

**Phase E — the v2 console** (D-024).

- [ ] **Dashboard: Now plus lane cards.** Now is one status line ("1 agent
      working" / "Nothing running", with which lane and why the other is
      gated), the scan summary ("59 in scope · index 6.4s ago"), the runner
      pill, Refresh and "Rescan · minutes". Each lane card shows its stage,
      name and agent; its slot ("Working · lock held" or "Empty · 41m ·
      gated" with the reason and the next eligible item); the repository, step
      type and elapsed time; "Then:" naming the step that follows; the four
      metrics with their sparklines and the window switch; usage for the month
      in the vendor's unit (requests or spend, per task, tokens or
      "unmeasured"); and a "Completed · next step" table of recent runs with
      the awaiting counts. The slot's bar fills by phases reached and is
      labelled as phases: the mockup draws a percentage, and the 2026-09-18
      ruling that no tile invents a figure stands. Below the lanes, the AI
      usage section renders each vendor's balance card and the daily or
      cumulative series against its limit. Dashboard is the only place an
      action can be taken. The Dispatch Board and Today's queue retire once
      Dashboard does everything they do, not before. _(state: planned)_
      `check: npx vitest run frontend/components/LaneCards.test.tsx`
- [ ] **"Needs you" is one row per repository, and every row names its
      rule.** The hold list reads "the only decisions in the console live
      here": each row is the repository, why it is held in plain words with
      the rule behind it ("discarding is destructive, always held";
      "auto-merge on green will neither merge nor fail"; "authoring a contract
      is always approval-gated"; "self-demoted after 3 failures, no retry
      scheduled"), and one action (Inspect tree, Set override, Preview step,
      Requeue). A hold with no rule id does not render as a hold.
      _(state: planned)_
      `check: npx vitest run frontend/components/NeedsYou.test.tsx`
- [ ] **Six destinations.** Dashboard (Now + Lanes), Queue (read-only),
      Insights (read-only), Portfolio, Runs, Settings. No other tab, and no
      control outside Dashboard mutates anything. The v2 mockup draws only
      Dashboard, Queue, Insights and Settings; Portfolio and Runs are D-024's
      names and have no design yet, so they open as the existing Grid and
      agent-run list until their own design pass. _(state: planned)_
      `check: npx vitest run frontend/components/AppNavigation.test.tsx`
- [ ] **Queue and Insights open the v2 read-only views, not v1.** Their
      routes render the new views, with no action control on either; the v1
      panels are unreachable from navigation once these land.
      _(state: planned)_
      `check: npx vitest run frontend/components/QueueView.test.tsx frontend/components/InsightsView.test.tsx`
- [ ] **The idle state shows the last activity.** When nothing is running,
      Now shows the last run — repository, step type, lane, agent, time
      worked, when — with its outcome pipeline (Run completed → PR opened →
      Checks passed → Approved → Merged, each step done, current or to do),
      the PR chip ("PR #412 · Approved — awaiting merge") and the actions it
      allows: Open PR, and Merge bound to the verified head SHA (§8). Each
      empty lane shows the next action the assigner would take. Never a blank
      tile. _(state: planned)_
      `check: npx vitest run frontend/components/LaneIdleState.test.tsx`
- [ ] **Data sources map to the new cards.** `frontend/lib/todayRanking.ts`
      feeds the ranking, `frontend/components/ExecutionQueuePanel.tsx` feeds
      Queue, `frontend/lib/portfolioTrendView.ts` feeds the lane trends; each
      card names its source and a card with no mapped source does not render.
      _(state: planned)_
      `check: npx vitest run frontend/lib/dashboardSources.test.ts`
- [ ] **Remedy buttons edit the policy or the agent profile**, re-run the dry
      run, and show the resulting assignment beside the current one before
      anything is applied. _(state: planned)_
      `check: npx vitest run frontend/components/LaneRemedy.test.tsx`
- [ ] **First-pass success per agent.** The leverage panel's portfolio-wide
      `agentFirstPassSuccess` gains a per-agent slice from the 3.9 performance
      store, so an agent card reads a number, not "unmeasured".
      _(state: planned)_
      `check: pwsh ./tests/Test-AgentFirstPass.ps1 -FailOnError`

#### Acceptance criteria

- Today and the Dispatch Board show the same order for the same snapshot.
- `Get-LaneAssignment` over a fixture returns the same result on every run and
  names a rule id for every filled and every empty lane.
- No value on Dashboard renders 0 for something not measured; a lane metric
  with no closed run, a vendor with no feed and a tokens figure Copilot does
  not report each read "unmeasured" or "unconfirmed" with the reason.
- Shadow mode has logged at least one disagreement with both choices and the
  rules behind them before the Automation toggle can be enabled.
- With automation on, a fixture at the budget cap, a dirty tree and a third
  consecutive failure each produce the named guardrail rule in the log and no
  dispatch.

#### Out of scope

- Ranking on evidence rather than rules — that is Release 3.9's router.
- More than one execution slot per provider until 3.8's capacity accounting is
  proven.

**Validation plan:** the assigner, the policy and the budget ledger are pure
decision tables gated offline against fixtures in the module-smoke shape; no
fixture spends provider quota.

**Risks:** the scan shows about 49 repositories at L0 and about 9 with
prose-only roadmaps, so once "docs before roadmap" is a rule nearly the whole
portfolio sits at the doc stage, and an agent limited to `roadmap.*` idles as
lane 2 does in the mockup — set the allowlists with that in mind, or let one
agent take `doc.*` until the portfolio moves past it; an assigner trusted on
a shadow log too short to have disagreed; a lane card that shows usage before
run-close fields are recorded, so the number is a sample of 4 runs in 51.

**Dependencies:** Lane 0.22's one-snapshot item for phase A's counts gate
(the ranking and the hold card depended on none, checked 2026-09-30); 3.8's
WorkPacket and adapters (built) for phase B; 3.9's performance store for the
per-agent first-pass number; D-024 (decided) for phase E.

#### Delivery plan (strengthened 2026-09-30)

The phases say what gets built; this says how it ships. Four rules hold for
every slice:

1. **One slice, one PR, one visible change.** Each slice ends with something
   the operator can see, or with a gate that makes the next slice safe. At most
   two slices wait in review (AGENTS.md); a third is built on its branch with
   no PR.
2. **Derived, never stored.** Every new figure (rank, metric, balance,
   assignment) is computed on read from ledgers that already exist or that the
   slice adds. Rollback is a revert: no migration, no backfill, no ledger to
   repair.
3. **Backend first, and the UI tolerates an older host.** This machine serves
   `frontend/dist` the moment it is built, while backend changes wait for the
   elevated service restart. Every slice's UI therefore renders an absent field
   honestly ("—", "unavailable", "unmeasured"). The deploy order is: merge,
   elevated restart, `npm run build`, then the slice's field check.
4. **Its own check in CI verifies a slice**, never the field check. The field
   check is an operator-queue ratchet and holds no later slice.

| Slice | Milestones | What the operator sees | Deploy | Rollback |
| --- | --- | --- | --- | --- |
| 4.0-1 | A: one ranking; one hold card | Today's #n is the board's #n; one card per repository | restart + build (OQ-14) | revert; nothing stored |
| 4.0-2 | Lane 0.22 one snapshot; A: counts reconcile | a header badge naming a count mismatch, and none when counts agree | restart + build | revert |
| 4.0-3 | B: step types, agent registry, lane declarations | Settings lists each agent beside its provider | restart | no reader yet; revert |
| 4.0-4 | B: run-close fields; locks and attempts | Runs show completed time, verdict, vendor, usage | restart + runner restart | additive; absent reads "unmeasured" |
| 4.0-5 | B: units and budget ledger; per-lane metrics | lane metrics over 7 and 30 days, "unmeasured" until closes accrue | restart + build | revert |
| 4.0-6 | B: vendor balance feed; launch path | a balance card per vendor, "unconfirmed" without a feed | restart; each read grant is an operator-queue row | no feed reads "unconfirmed" |
| 4.0-7 | C: rules as data, pure assigner, fixture per rule, dry run | `GET /api/lanes/dry-run` says what would go where, and why | restart | the route writes nothing |
| 4.0-8 | D: shadow mode; smoke deadline | a disagreement report over any window | restart | shadow writes events only |
| 4.0-9 | D: automation toggle | a Settings toggle, disabled with its reason until a report exists | restart + build | off is the default |
| 4.0-10+ | E: the v2 console, one milestone per PR | Dashboard (Now + Lanes) beside v1 until parity | build | v1 stays reachable until parity |

**Phase exits.** A phase closes when its milestones are verified and the
product itself answers its exit question:

- **A:** does Today's order equal the board's on the live snapshot? (OQ-14)
- **B:** does every run closed since 4.0-4 carry all four close fields? A
  query over the run ledger finds zero misses.
- **C:** does the dry run name a rule for every filled and every empty lane on
  the live queue?
- **D:** has the shadow log recorded at least one disagreement, with both
  choices and their rules? Automation stays off until the operator has read
  it.
- **E:** can the operator do everything v1 did from Dashboard? Only then do
  Today's queue and the Dispatch Board retire.

**Owner review.** Slices 4.0-3 (config), 4.0-7 (`policy.json`) and 4.0-9
(automation) change config or governance, so they always need owner review
(AGENTS.md, config rule 4), whatever the posture.

---

## Deferred cross-cutting lanes (moved from ROADMAP.md §7, 2026-10-16)

In their original order. Lanes 0.3–0.6, 0.15, 0.18 and 0.20, and the closed
items of Lane 0.17, held no deferred work and moved to the completed-release
archive instead.

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
- [ ] **The roadmap record moves with every shipped change, not only release-claiming ones.**
      `Test-RoadmapCapabilityRecord.ps1` fires only when a commit subject reads
      `feat(release-N.M):` or `(phaseN)` and its diff touches `backend/` or
      `scripts/`. The Lane 0.21 poll-loop commit (`fix(portfolio): … (Lane
      0.21)`, 2026-09-17) shipped 16 files under that bar and was checked by
      nobody; `frontend/` never counts. AGENTS.md rule 3 ("the roadmap is the
      last file you write") therefore binds by contract, not by gate. Widen
      the predicate: a PR range whose diff touches `backend/`, `scripts/` or
      `frontend/` source (tests, fixtures and the smoke harnesses excluded)
      must advance a milestone in `ROADMAP.md` — a `(state:)` moving past
      `planned`, a `[x]`, or a verbatim move to the archive — whatever the
      commit prefix. Keep the existing rule that adding `planned` items is
      not advancement. Prove it red on a fixture range that ships a frontend
      file with an unmoved roadmap. _(state: planned)_
      `check: pwsh ./tests/Test-RoadmapCapabilityRecordScope.ps1 -FailOnError`
- P4 — BOM/PS5.1 hazard: [archived](docs/history/completed-releases.md#closed-2026-09-14-archived-from-roadmapmd).
- **Deliberately unscheduled (accepted debt, held at baseline):** the naming
  and style tiers (`UseSingularNouns` 90, `UseOutputTypeCorrectly` 136,
  `UseShouldProcessForStateChangingFunctions` 67, five smaller) — churn for
  zero behavior.
- **Separate lane, never batched mechanically:** ESLint `set-state-in-effect`
  (31) — every site needs behavioral review; a "fix" can change rendering.

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

### Lane 0.17 — The dispatch console could not dispatch (operator evaluation 2026-08-30)

The lane's opening prose and its three closed items moved to the
completed-release archive on 2026-10-16. Its one open item:

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

### Lane 0.21 — The portal freezes while it loads (operator evaluation 2026-09-15)

A timed reload: the shell painted in 0.7 s, then the host barely answered for
3 m 33 s. `/api/log/tail` averaged 37 s, `/health/live` peaked at 48 s, and a
reload mid-scan ended in `ERR_TIMED_OUT`. The host accepts one connection at a
time, so any request that holds the thread holds every route. The host log
names the one that did: each `GET /api/portfolio/assessment?scanMode=differential`
ran 60–72 s inline (`prepMs` 50–61 s), and two page loads back to back held it
twice.

**The largest cause was a defect, fixed in the PR that opened this lane.** The
differential decision counted a repository as `local+github` only if the
route's GitHub API list contained it. The assessment and the index also counted
a local repository whose status carries a GitHub `htmlUrl`. `sourceCoverage` is
a fingerprint token, so every repository with a GitHub remote but no API record
never matched and was re-scanned on every load. That was 40 of 59, measured
2026-09-15; on the same data the fix reuses 58, and the 59th has a new commit.
Both sides now use `Get-PortfolioSourceCoverage`.

**The assessment route no longer holds the request thread (verified
2026-09-16, #309, archived).** With nothing changed, a differential load still
ran `prepMs` 28 s inline (22:59 2026-09-14): the route's own GitHub API pass (a
workflow-run call and a Pages lookup per repository) plus scans of changed
roots. That work moved into the background worker, as `GET /api/status` did on
2026-08-11. `Invoke-PortfolioAssessmentScan` holds the former route body, and
only `scripts/Invoke-StatusCacheRefresh.ps1 -RunAssessment` calls it. The route
serves `assessment-cache.json` under the index root, reports `refreshing`, and
keeps one scan in flight. A forced refresh that arrives mid-scan is queued.
`REPO_MGMT_CACHE_ROOT` isolates the scan caches and the worker lock, as
`REPO_MGMT_INDEX_ROOT` does for the index.

**Still open, in order of what the operator waits on:**

- [ ] **A finished scan reaches the page.** The scan ended at 05:17:15 and the
      snapshot regenerated at 05:19:05, but the header still read "Last scan
      01:09 AM · 64.0s scan · 9m ago". When scan status moves to `completed`, the
      page refetches the snapshot, assessment and status. The failed
      background-refresh path retries at that point instead of logging the same
      warning twice. Since the assessment moved to the worker, a host with no
      index answers `GET /api/operations/repos` with 409 until the first scan
      lands. The page shows that as waiting for the first scan and refetches
      when the scan finishes. _(state: planned)_
      `check: npx vitest run frontend/lib/scanCompletionRefresh.test.ts`
- [ ] **"Auto-scan off" means no scan on load.** The page showed Auto-scan off
      and started a background re-scan on load anyway. With auto-scan off it
      serves the cached index and offers the scan; otherwise the re-scan is
      labelled as such. _(state: planned)_
      `check: npx vitest run frontend/lib/startupRefreshPolicy.test.ts`
- [ ] **Hidden tabs cost nothing at startup.** Sixteen calls fire in parallel on
      load. `operations/repos` (548 KB), `automation/packages` (374 KB) and
      `roadmap/index` (56 KB) load when their tab opens. Startup marks each phase
      (auth, bootstrap, snapshot, scan start and end) with `performance.mark`
      and one `console.debug` line, so a slow reload explains itself.
      _(state: planned)_
      `check: npx vitest run frontend/lib/startupPhases.test.ts`
- [ ] **Every wire timestamp is ISO 8601 UTC.** Scan status returned
      `09/15/2026 05:13:42`, culture-formatted with no zone, and
      `repos.index.json` `generatedAt` has the same shape. The snapshot emits
      ISO 8601. PowerShell 7 turns ISO strings into `DateTime` on read, and
      `[string]` then formats them in the machine's culture. Emit
      `.ToUniversalTime().ToString('o')` at every writer, with a tripwire over
      the route payloads. _(state: planned)_
      `check: pwsh ./tests/Test-WireTimestamps.ps1 -FailOnError`
- [ ] **The first screen is honest and short.** Before the snapshot arrives,
      counts show placeholders, not "Sample data source" with zeros. Today's
      "Blocking a lane" shows one card per repository with its reasons as tags:
      the page ran 23,641 px, Portfolio-Forge had four cards, and
      `roadmap-no-checklist` appeared nine times. Below about 900 px, ranking
      rows move "Rank basis" into an expandable row, and header badges move
      into a menu instead of wrapping. Each tab's code loads on demand
      (`import()`), off the 858 KB first bundle. _(state: planned)_
      `check: npx vitest run frontend/components/TodayView.test.tsx`

### Lane 0.22 — The console disagrees with itself (UX assessment 2026-09-15)

An assessor used build `fa18be4` through the UI only, without reading code or
docs. They went cold reload, every tab, Help, Settings, one repo detail, one
trace, Dispatch history and the agent-run list, and did not press Dispatch, Run
Evaluation, Start runner or Save. The verdict: **the main UX problem is trust,
not layout.** The findings below are the defects. The structural
recommendations (four destinations, one vocabulary, Today as an exception inbox,
one Work pipeline) are product decisions and live in D-022.

**What the session saw.**

- **Repository counts:** 0 (summary cards), 59 (Today), 72 (scan banner), 71
  (execution ledger), 1 (Doc Readiness, a smoke fixture), and 0 in the
  Repository Grid, which asked for a workspace path already set.
- **After a reload:** Today read "No repositories are indexed yet" while
  Operations read "Indexed entries: 59". The Operation Log said "Scan complete.
  No repositories found." and then "Operation completed successfully."
- **One work item:** the list said "Queued for the runner"; its own trace said
  "no queue entry exists … nothing will pick this up"; Insights said "Queued 0".
- **One repository:** "Ready" on the Dispatch Board, "Dispatch Readiness:
  blocked" above "Dispatch Blockers (0)" in its detail, and "L0-Absent" on Today.
  The glossary defines L0-Absent as "No roadmap file present", yet its roadmap
  scores 55.
- **Board labels:** repositories Today marks "always held" for uncommitted
  changes, and a curated-out archived repository, read "Ready" on the board.
- **Unnoticed stuck work:** the runner heartbeat was 27.6 h old, shown as
  "99293.3s". A lane had run 1,655 minutes. A run dispatched six days earlier had
  no branch and no PR.
- **Non-tasks in the work queue:** "Ready" candidates included "Code is
  implemented", "Monorepo structure created", "Work one bounded slice at a
  time.", a "(Deferred) … Not needed for v1" line and truncated fragments.
  One item completed and was re-assigned 17 seconds later.

**Checked against the code and data (2026-09-15).**

- **Test data in the live ledger: confirmed.** 175 of 192 agent-run records in
  the live `output/agent-runs` are `dispatch-success-smoke`. The api-host smoke
  writes the real agent-run ledger and the packaging queue, and also work
  packets, run summaries and the `app.db` mirror. It does not write
  `roadmap-writeback.jsonl`. The write-back ledger is
  `output\roadmap-writeback\history.jsonl`, and the smoke only reaches its
  refusals, which write nothing. (2026-09-16: 251 of 257 packaged items are
  `smoke-packaging-repo`.)
- **"One click, no preview": not true.** The board's Dispatch button opens the
  task preview, not a dispatch. Its "Ready" label still ignores holds.

**Keep as they are:** the work-item trace (a stage-by-stage chain with a named
broken link, the best diagnostic in the product); Leverage's "Not captured yet",
which names missing measurements instead of showing zeros; the "Previews first;
nothing is applied" copy and Private Scope; and Help's "Computed from" lines.

**Open, in order.** One dispatch-eligibility rule leads Current focus (test
fixtures never reaching live state was verified on #320's head and archived
2026-09-30). Then:

- Only actionable roadmap lines become work: stays in `ROADMAP.md` (Must work
  now).
- Stuck work is detected, not noticed: stays in `ROADMAP.md` (§7, Must improve
  next).
- [ ] **One snapshot, one denominator, honest zeros.** Every count reads the
      same snapshot: generated-at, discovered, in scope, excluded, scanned and
      failed. A scan that finds 0 repositories is a warning, never "completed
      successfully", and the last good snapshot stays on screen labelled with its
      time. An unmeasured value renders "—" with its reason, never 0. The Grid's
      empty state never asks for a workspace path that is already set.
      _(state: planned)_
      `check: npx vitest run frontend/lib/portfolioSnapshot.test.ts`
- [ ] **A control does what its label says.** A "Preview…" next action opens
      the preview, not the generic Run Evaluation modal. Header popovers close
      on Escape and outside click. A disabled control, including the
      Local/GitHub switch during a scan, says why. The "Runner stalled … Use
      Start runner" banner carries the button. Settings never shows "Checking…"
      or an empty provider list indefinitely. _(state: planned)_
      `check: npx vitest run frontend/components/HeaderPopovers.test.tsx`
- [ ] **Lanes close on evidence, not on a click.** Ben's ruling, 2026-09-18:
      the Dispatch Board's Complete button goes. An operator pressing Complete
      on a `running` lane asserts work the operator did not do; the button
      also always sent `hasRemainingWork: true`, so it never completed
      anything — it released the lane under the wrong name. The board already
      observes the verdict (`Execution.LaneObservation.ps1`: `finished` when
      the PR is merged, `failed` when the run failed or the PR closed
      unmerged) and Lane 0.17 stopped one step short of acting on it. A sweep
      over the lane ledger — the pattern `Invoke-AgentRunAutoClose` already
      uses for agent runs — frees a `finished` lane and returns the repo to
      `ready` if its roadmap still has open items, `complete` if it does not
      (a roadmap fact, never a click); a `failed` lane takes the cancel path
      with its retry count. `POST /api/execution/complete` is removed and the
      `Complete` control with it. Cancel stays. A lane with no run behind it
      (`unlinked`) can only be cancelled; L22-ELIG stops it being occupied at
      all. Done when: a fixture lane whose PR is merged is `ready` after one
      sweep with a `completed` history record naming the sweep, not an
      operator; a `failed` fixture lane follows the cancel transition; the
      complete route answers the SPA fallback (`text/html`), not JSON; the
      board renders no Complete control. _(state: planned)_
      `check: pwsh ./tests/Test-LaneClosesOnEvidence.ps1 -FailOnError`
- [ ] **Cancel reaches the runner.** Cancel on the Dispatch Board only edits
      the lane ledger (`Invoke-CancelTask`): the lane frees, the agent keeps
      working, and its pull request arrives later as an orphan the board can
      no longer attribute. The runner accepts a `cancelled` structured result
      *from the agent* but nothing carries an operator's cancel *to* it. Ben,
      2026-09-18: "that needs to be a trustworthy button." A cancel writes a
      flag under the runner control root (`REPO_MGMT_RUNNER_CONTROL_ROOT`)
      keyed by `dispatchRunId`; `Invoke-RoadmapTaskRunner.ps1` reads it at
      every phase boundary and stops there, the way the portfolio scan's
      cancel is honoured at the worker's next phase; a draft PR the run has
      opened is closed with a comment naming the cancel; the lane's history
      records who cancelled, at which phase, and what the runner did with it.
      Until the runner acknowledges, the tile reads "Cancelling… (honoured at
      the next phase boundary)", never "cancelled". Done when: a fixture run
      cancelled during `working` stops before `pushing` and the summary
      records `cancelled` at that phase; the lane's history carries the
      acknowledgement; a cancel with no live runner still frees the lane and
      says so. _(state: planned)_
      `check: pwsh ./tests/Test-CancelReachesRunner.ps1 -FailOnError`
- [ ] **A lane tile shows the phase, the clock and the work order.** The two
      lane tiles read "Running" and nothing else. Agents report no percentage
      and the product invents no figure (steering contract 2), but the
      execution event stream already names the phases — QUEUED, DISPATCHED,
      WORKING, LOCAL_VERIFYING, PUSHING, PR_OPEN, CI_PENDING,
      CI_PASSED/CI_FAILED, READY_FOR_OPERATOR, MERGING, MERGED,
      POST_MERGE_VERIFYING, COMPLETE (`Execution.Events.ps1`). Each tile shows
      the current phase as "phase n of N — <name>", the time it entered that
      phase, the time since the last observed event, and the `stalled` flag
      the observation already computes; a ring may fill by phases reached and
      is labelled as phases, never `%`. The tile links to the work order it is
      executing — the WorkPacket (`workPacketPath`) and `/api/trace/{id}` via
      the trace modal — so an operator can read what is being done before
      cancelling and queueing other work. Open question for the register: the
      two-lane cap is a Release 1.0 constant; if it stands in for provider
      capacity it is per-installation state and belongs in Settings (steering
      contract 8). Done when: a fixture lane at `ci-pending` renders phase,
      entered-at, elapsed and the trace link; a lane with no events renders
      "no phase observed" and no ring; the string `%` appears nowhere in the
      tile. _(state: planned)_
      `check: npx vitest run frontend/components/ExecutionLaneTile.test.tsx`
- [ ] **Labels match what they count.** "N need you" counts repositories, not
      holds × codes (it read 63 for 59 repositories); that clause shipped with
      4.0 A's one hold card (2026-09-30). "Blocking a lane" appears
      only where work is under way and stopped. L0-Absent is never shown for a
      repository whose roadmap exists; the glossary text and the audit
      disagree. Help's "first pass" names tabs that exist. "Insufficiently
      understood" shows its cause in plain words (the roadmap is prose, not a
      checklist). _(state: planned)_
      `check: npx vitest run frontend/lib/glossary.test.ts`
- [ ] **Insights reports a gap as a gap.** A missing or failed snapshot breaks
      the trend line instead of plotting 0%, and a delta's colour follows its
      direction (a −32.3% badge rendered green). Raw keys
      (`DifferentialChangedCount`, `differential-noop`, `awaiting-first-scan`)
      move behind a "Scan diagnostics" disclosure. Release-number copy ("Release
      2.3 scaffold") leaves the UI. "Failing Actions" agrees with repository
      detail. Team Activity is scoped to the owner or removed. _(state: planned)_
      `check: npx vitest run frontend/lib/portfolioTrendView.test.ts`
- [ ] **Repository detail agrees with itself.** Each panel shows loading,
      unavailable or error, never a stale score beside "not found" (README 95
      next to "README file not found", "blocked" above "Dispatch Blockers (0)").
      Raw errors ("No operations repo record found for repoId …") become operator
      language with a Retry. Three conditions are flags: failing CI, a default
      branch pointing at an agent branch, and two local repositories on one
      remote. _(state: planned)_
      `check: npx vitest run frontend/components/OperationsWorkspaceView.test.tsx`
- [ ] **Nothing unfinished in production, and filters stay visible.** The
      Grid's "Clone PLANNED" and "Archive PLANNED" controls are removed. Active
      filters show as removable chips, and "Clear filters" clears the ones under
      Advanced. A Doc Readiness row carries one primary action plus an overflow
      menu, not eight buttons. The Dependencies tab (a technology inventory, read
      by a developer as package dependencies) is renamed or folded into
      repository detail. _(state: planned)_
      `check: npx vitest run frontend/components/RepoGrid.test.tsx`
- README standardization history is read where it is written: stays in
  `ROADMAP.md` (§7, Must improve next).
