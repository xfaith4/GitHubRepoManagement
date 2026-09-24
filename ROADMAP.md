# GitHub Repo Management — Active Execution Roadmap

> **Revision 2026-09-18 — MVP boundary and governed autonomy.** Promotes
> Release 3.7 to active engineering, moves Release 2.9 to a parallel validation
> track, makes trust defects the MVP critical path, separates verified proposal
> state from integrated delivery, adds Release 3.9 Governed Autonomous Delivery,
> and renumbers Adaptive Routing to Release 4.0. No completed capability is
> reopened; Release 3.8 is reused as the execution substrate.
>
> **Status:** Active
> **Active release:** **Release 3.7 — Portfolio Value Proof**
> **Active field-validation track:** **Release 2.9 — Operator Field Proof + Mobile Completion**. Its engineering is closed; remaining elevated, authenticated, physical-device, and calendar evidence lives in the operator queue and does not block engineering or MVP declaration.
> **Next capability release:** **Release 3.9 — Governed Autonomous Delivery**
> **Future optimization release:** **Release 4.0 — Adaptive Routing**
> **Work ordering:** dependency-driven, not insertion order — see
> [Execution Order and Dependencies](#execution-order-and-dependencies)
> **Canonical product direction:** [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
> **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
> **Dated change log:** [`CHANGELOG.md`](CHANGELOG.md)

---

## Current Status (Agent Context)

**Last updated:** 2026-09-24

Releases 0.4 through 2.6, 2.8, 3.0 and 3.8 are
**engineering-complete**; completed milestones belong in the archive. Release
3.8's detail remains temporarily below only as migration context for Release
3.9 and is non-dispatchable; G39-01 moves it to the completed-release archive.
Their full text lives in
[`docs/history/completed-releases.md`](docs/history/completed-releases.md).

**This file carries open work.** Every checkbox in it is something still to do
— if an item is `[x]` here it is a mistake, not a record (rule restored by the
2026-08-11 archive pass, recorded in `CHANGELOG.md`). Release 3.8's checkbox-
free historical block is the sole temporary exception and G39-01 removes it.


**Current focus (next agent actions), in order.** Every item here is
agent-closable; the operator queue is a separate file. Take the first
dependency-ready `[ ]`, confirm its premise still holds, and open one PR for
that bounded item. Do not begin Release 3.9 implementation before the Release
3.7 rollout decision is recorded. Do not begin D-022 navigation restructuring
before the value-proven MVP boundary is crossed.

### MVP critical path A — make the existing loop trustworthy

- [ ] **Lane 0.22 — test fixtures never reach live state.** 175 of 192 live
      agent-run records are the api-host smoke's `dispatch-success-smoke`. They
      are most of the green "100 agent runs" badge, and a smoke fixture leads
      the packaged work queue. The smoke writes the real agent-run ledger,
      `roadmap-writeback.jsonl` and the packaging queue. Isolate those roots
      as `REPO_MGMT_INDEX_ROOT` did for the index, and keep the records already
      written out of every operational view. _(state: planned)_
      `check: pwsh ./tests/Test-FixtureIsolation.ps1 -FailOnError`
- [ ] **Lane 0.22 — one dispatch-eligibility rule, enforced everywhere.** The
      Dispatch Board read "Ready" for repositories Today holds for uncommitted
      changes, for a curated-out archived repository, for one whose own detail
      reads "blocked", and for folders not in the index. One server-side rule
      answers `{ ok, reasons[] }`. The board lists only eligible items and
      collapses the rest into "N held (why)". Every Dispatch control is
      disabled with its reason when `ok` is false. _(state: planned)_
      `check: pwsh ./tests/Test-DispatchEligibility.ps1 -FailOnError`
- [ ] **D-012 — the permission envelope binds.** For every adapter, a post-run
      diff touching any `forbiddenPaths` entry (`.github/workflows/**`) fails the
      packet by name and the branch is not pushed; provider-native sandboxing is
      a second layer, never the only one. An agent that needs CI changed writes
      the proposal to `.github/workflows-proposed/` and names it as waiting. A
      packet that needs the network declares an allowlist the owner approves;
      `network false` is never loosened silently. _(state: planned)_
      `check: pwsh ./tests/Test-PermissionEnvelope.ps1 -FailOnError`
- [ ] **Lane 0.22 — only actionable roadmap lines become work.** Classify each
      candidate as `actionable | done-statement | deferred | guidance |
    fragment`; rank, queue and dispatch only `actionable`. Record excluded
      lines and reasons. A completed item hash cannot be dispatched again
      inside the configured cooldown unless an operator override is recorded.
      _(state: planned)_
      `check: pwsh ./tests/Test-WorkItemQuality.ps1 -FailOnError`
- [ ] **Lane 0.22 — stuck work is detected, not noticed.** Apply configured
      phase limits to runner heartbeat, lane age, dispatch-without-branch,
      approval-without-queue-entry and scan phase. Surface one diagnosis and
      one remedy per stuck unit; use human-readable durations. _(state: planned)_
      `check: pwsh ./tests/Test-StuckWork.ps1 -FailOnError`
- [ ] **Lane 0.22 — lanes close on integration evidence.** Remove the manual
      Complete route and control. A verified merged PR closes its lane through
      reconciliation; failed or closed-unmerged work takes the cancel/failure
      path; unlinked lanes can only be cancelled. _(state: planned)_
      `check: pwsh ./tests/Test-LaneClosesOnEvidence.ps1 -FailOnError`
- [ ] **Lane 0.22 — cancel reaches the runner.** Persist a cancellation request
      by `dispatchRunId`; observe it at each phase boundary; stop before the
      next mutating phase; close any draft PR with a reason; and record request,
      acknowledgement and terminal phase. The surface reads `Cancelling` until
      acknowledgement. _(state: planned)_
      `check: pwsh ./tests/Test-CancelReachesRunner.ps1 -FailOnError`
- [ ] **Operational MVP proof harness and queued field proof.** Add
      `scripts/Select-OperationalMvpPilot.ps1` and
      `tests/Test-OperationalMvp.ps1`. Select the highest-ranked repository
      that is clean, in scope, dispatch-eligible, low risk, backed by a runnable
      check and not this repository. Drive it through preview, dispatch,
      implementation, exact-head CI and `READY_FOR_PROMOTION`; write one
      operator-queue entry naming the verified SHA and exact remaining merge
      action. After that supervised approval occurs, reconciliation writes
      `evidence/verified/operational-mvp-<date>.md`; the validator requires the
      candidate, WorkPacket, run, PR, checks, approval, merge commit, target-
      branch reachability, roadmap reconciliation, consistent surface states
      and zero fixture contribution. The engineering milestone closes when the
      selector, validator, red fixtures and queued proof packet are green; the
      product boundary crosses only when the real evidence file passes.
      _(state: planned)_
      `check: pwsh ./tests/Test-OperationalMvp.ps1 -FixtureMode -FailOnError`

### MVP critical path B — prove portfolio value on real repositories

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
- [ ] **3.7 / M6 — execute at least five material improvements.** Use only the
      approved previews above. For each repository, record the before evidence,
      accepted action and preview hash, implementation PR, exact acceptance
      criterion, independent result, merge evidence, operator minutes, agent
      first-pass result, and outcome-quality judgement. A merge without an
      independently checked outcome does not count. _(state: planned)_
      `check: pwsh ./tests/Test-TrialExecution.ps1 -Cohort evidence/trials/release-3.7/cohort.json -MinCountedImprovements 5`
- [ ] **3.7 / M7 — adjust and decide.** Every false positive or bad
      recommendation exposed by M6 is either corrected through a versioned
      rule with `observedOn`, or retained with a written reason. Record the
      evidence-backed go/no-go decision for the 80+ repository rollout. This
      decision crosses the value-proven MVP boundary. _(state: planned)_
      `check: pwsh ./tests/Test-TrialDecision.ps1 -Cohort evidence/trials/release-3.7/cohort.json -FailOnError`

### After value-proven MVP — foundation work before guarded autonomy

- [ ] **One manifest walk (steering extension 4).** Repo type, the technology
      profile and kind signals are three walkers over the same files. One scan
      produces all three views, so they cannot drift and a checkout is read once.
      _(state: planned)_
      `check: pwsh ./tests/Test-ManifestWalk.ps1 -FailOnError`
- [ ] **D-001 — dependency notion (Release 3.9 prerequisite).** Optional,
      single-repo, acyclic,
      keyed on stable item ids, gating dispatch eligibility. Schema + parser +
      cycle check. This must close before Release 3.9 can schedule a second work
      unit without operator selection. _(state: planned)_
      `check: pwsh ./tests/Test-RoadmapDependencies.ps1 -FailOnError`
- [ ] **4.0 A — one ranking function for Today and the Dispatch Board.**
      Today ranks through `frontend/lib/todayRanking.ts`; the board ranks the
      queue through `Get-RankedQueue`. One repository read #1 on one and #8 on
      the other, on different scales. One server-side ranking, one scale,
      consumed by both, with the rank's inputs on the payload; the frontend
      holds no ranking arithmetic. _(state: planned)_
      `check: pwsh ./tests/Test-OneRanking.ps1 -FailOnError`
- [ ] **4.0 A — counts reconcile on every scan.** Per snapshot, status counts
      sum to the total and scanned, in-scope, assessed and ledger counts each
      carry one stated definition; the product runs the same assertion after
      every scan and shows a header badge naming the mismatch when it fails.
      _(state: planned)_
      `check: pwsh ./tests/Test-CountsReconcile.ps1 -FailOnError`
- [ ] **4.0 A — one hold card per repository.** "Blocking a lane" showed one
      repository four times, once per hold code; a repository renders one card
      listing its codes, and columns that never carry a value (Effort, assessed
      time) leave the table. _(state: planned)_
      `check: npx vitest run frontend/components/TodayView.test.tsx`
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

### Product maturity boundaries

These boundaries prevent a later capability from moving an earlier finish line.
They are cumulative product claims and are emitted only from merged evidence:

1. **Operational MVP — trustworthy supervised delivery.** All items in MVP
   critical path A are integrated on `main`; one real repository travels from
   an actionable roadmap unit through preview, dispatch, implementation,
   exact-head CI, operator-approved merge and post-merge reconciliation; no
   fixture contributes to the result; and the console shows one consistent
   eligibility and delivery state throughout. Record the proof under
   `evidence/verified/operational-mvp-<date>.md` and gate it with
   `tests/Test-OperationalMvp.ps1`.
2. **Value-proven MVP — Release 3.7.** At least five cohort repositories are
   materially stronger by independently checked criteria, the effort and
   first-pass results are recorded, and M7 contains the evidence-backed rollout
   decision. This is the public MVP boundary. Field-validation items from 2.9
   may remain open if they do not contradict the claimed workflow.
3. **Guarded Autonomy V1 — Release 3.9.** One low-risk phase of at least two
   work units completes under one active mandate without operator dispatch or
   approval between ordinary units; every merge is policy-authorized, verified
   on the intended branch and followed by state refresh; at least one bounded
   remediation and one decision-ready escalation are proven. This is not a
   prerequisite for calling Release 3.7 an MVP.

Do not use percentage-complete estimates for these boundaries. Each is false
until every named condition has merged evidence, then true.

**Forward arc.** Releases 3.0-3.6 established the engineering and conclusion
foundation; Release 3.7 proves that the product returns more time than it takes.
Release 3.8 already made execution provider-aware. Release 3.9 moves authority
from repeated per-PR approval to a bounded, revocable phase mandate and proves
one low-risk multi-PR phase without operator dispatch between units. Release
4.0 then optimizes provider choice from evidence. Optimization may not precede
trustworthy authority and verified integration.

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
> next work → establish execution readiness → activate a bounded mandate →
> dispatch → monitor agent run → validate Actions → evaluate promotion policy →
> merge when authorized → verify integration → reconcile roadmap and continue

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

| State      | Meaning                                                            | Advanced by          |
| ---------- | ------------------------------------------------------------------ | -------------------- |
| `planned`  | Contract written; no implementation exists on a work branch        | planner/orchestrator |
| `built`    | Implementation exists; required exact-head CI is not yet green     | implementation agent |
| `verified` | Required checks ran and passed on the exact applicable PR head SHA | verification service |

A `built` or `verified` milestone's `check:` must be a step CI runs, with every
argument the line passes (validator R024). A check CI does not run can never go
green there, so the state would rest on nobody's word.

These are **proposal states**, not delivery states. `verified` means eligible
for promotion-policy evaluation; it does not mean merged, integrated or
complete. Delivery advances separately through `MERGING → MERGED →
POST_MERGE_VERIFYING → COMPLETE`, and only the orchestrator advances those
states from repository and policy evidence.

`verified` is the last milestone annotation written on a feature branch. It is
the only proposal state that may stage `[x]` and move the milestone text to the
archive in that same PR. On the PR branch, that edit describes the repository
state the PR proposes. On `main`, the merged roadmap and archive describe the
integrated state. If the PR does not merge, `main` remains unchanged and no
completion event may be emitted.

**Field proof is not a state.** "Seen working on the live portal", "ran under SYSTEM",
"confirmed on the phone" are recorded as ratchets in
[`docs/governance/operator-queue.md`](docs/governance/operator-queue.md) via
`scripts/Add-OperatorVerification.ps1`. A ratchet may be recorded any time after
`verified`, may be recorded never, and never blocks a later milestone unless
the claim being made explicitly requires that proof. Promotion is governed by
the active posture in §8: supervised work requires operator approval of the
verified head SHA; guarded work requires a valid mandate plus a replayable
policy decision for that same SHA. Neither path treats green CI as completion.

**Milestone format.** One bullet, action-first, with the check on its own line:

- [ ] Resolve repository kind for `library`, `firmware`, `application`, `experiment`
      from the index, not just `archived`. _(state: planned)_
      `check: pwsh ./tests/Test-KindDetection.ps1 -FailOnError`

**Checkbox rule.** `[x]` on a PR branch means "verified proposal that will be
integrated by this PR"; `[x]` on `main` means "integrated milestone." It never
means that an agent claimed success. An item whose code is merged but whose
separate field proof is unrecorded is integrated in repository history and open
in the operator queue — two ledgers, no overlap.

**Archive rule:** once exact-head verification is green and the PR is otherwise
promotion-eligible, the item moves verbatim to
`docs/history/completed-releases.md` in the same PR. The execution ledger
records whether that proposed archival actually integrated. Reconciliation
treats an archive edit that never merged as no completion at all.

**Operator-work rule.** Nothing in this file may name an action only the operator can
take. If a milestone needs SYSTEM rights, a device, an authenticated session, a grant
outside the repository, or eyes on a browser, the agent-closable half stays here with
its own `check:` and the human half is appended to the operator queue. The validator
(`R021`) rejects the file otherwise.

---

## 4. Release Index

| Version   | Title                                                                    | Status                                                                                                                                               |
| --------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0.4 - 1.1 | Foundation through Standardization and Guardrails                        | `done` — see [archive](docs/history/completed-releases.md)                                                                                           |
| 1.2       | Enhanced Portfolio Intelligence                                          | `done` — closed 2026-07-05; see archive                                                                                                              |
| 1.3 - 1.7 | Frontend build, repo evaluation, README generation, dispatch, git status | `done` — see archive                                                                                                                                 |
| 1.7.5     | Portfolio Mission Alignment, Indexed Scanning, Value-Ranked Planning     | `done` — shipped 2026-05-28; see archive                                                                                                             |
| 1.8 - 2.0 | Operations workspace, AI doc cycles, agent-run monitoring                | `done` — see archive                                                                                                                                 |
| 2.1       | Persistent Data Layer                                                    | `done` (engineering) — closed 2026-08-07; operator sign-off tracked in 2.9                                                                           |
| 2.2       | API Auth, Network Security, Onboarding, GitHub App                       | `done` (engineering) — 2026-07-05; optional live App-token exchange tracked in 2.9                                                                   |
| 2.3       | Portfolio Analytics, Trend Visualization, Distribution                   | `done` (engineering) — 2026-07-06; 7/90-day accrual is calendar-gated, tracked in 2.9                                                                |
| 2.4       | Agent Integration Protocol and AI Repair Loop                            | `done` — 2026-07-05; live submit-PR proof landed 2026-08-09 (2.7 Phase A, PR #96)                                                                    |
| 2.5       | Mobile-Friendly Operator Experience                                      | `done` (engineering) — 2026-07-05; two surfaces + device proof tracked in 2.9                                                                        |
| 2.6       | Interface Clarity and Operator Orientation                               | `done` — 2026-07-06; device sign-off tracked in 2.9                                                                                                  |
| 2.7       | Guarded Scheduled Automation (Curated-Subset, Preview-First)             | `done` — closed 2026-08-11; see archive. Live service install re-homed to 2.9                                                                        |
| 2.8       | Local Claude Code Execution (queue + operator runner)                    | `done` (engineering) — 2026-07-15; real `claude` run tracked in 2.9                                                                                  |
| 2.9       | Operator Field Proof + Mobile Completion                                 | `validation` — engineering closed; operator/device/calendar evidence continues off critical path                                                     |
| 3.0       | Operator-Context Execution                                               | `done` (engineering) — 2026-08-09; see archive. Live proof tracked in 2.9                                                                            |
| 3.1       | Closed-Loop Delivery                                                     | `done` 2026-08-15 — manual loop proof recorded; portal + scheduled proofs re-homed to 2.9                                                            |
| 3.2       | Portfolio Scale and Responsiveness                                       | `done` 2026-08-19 — budget + bounded sweep + observable/cancellable scan + render bound                                                              |
| 3.3       | Steady-State Operation                                                   | `done` 2026-08-19 — retention, rehearsed restore, honest transport, decision-grade exports                                                           |
| **3.4**   | **The Delivery Loop Closes**                                             | `done` 2026-08-15 — six milestones + the full-loop proof, driven live and operator-verified                                                          |
| 3.5       | Trustworthy Surfaces (UI Quality)                                        | `done` 2026-08-17 — all seven milestones; trust-report per finding; operator sign-off in 2.9                                                         |
| 3.6       | Every Repository Gets an Outcome                                         | `done` — closed 2026-09-14 (D-018 PR 2); see archive. Field proof: OQ-1. Its two non-blockers live on as Current focus M4a and the 2.9 trend accrual |
| **3.7**   | **Portfolio Value Proof**                                                | **`planned`** 2026-08-23 — follows 3.6; ten real repositories decide the 80+ rollout       |
| **3.8**   | **Provider-Aware Execution**                                             | **`planned`** 2026-09-06 — Codex/Claude/Copilot behind one provider-neutral task contract  |
| **4.0**   | **Rule-Driven Lane Assignment**                                          | **`planned`** 2026-09-24 — engine outward: a pure assigner, then the v2 console (D-024)    |

> **Note on `.5` numbering.** Reserve it for course corrections like 1.7.5;
> default new work to integer minor releases.

### Execution Order and Dependencies

Release numbers identify scope — they do not dictate sequence. Work through
open items in the order below, and update this section whenever a lane
closes or a new dependency appears.

**Critical-path ruling — 2026-09-18.** The product is feature-rich but does
not yet earn an MVP claim while its primary route blocks the host, fixtures
pollute operational truth, or dispatch eligibility disagrees by surface. The
critical path is therefore evidence-first, not release-number-first:

1. **Trustworthy supervised loop.** Close MVP critical path A in the order
   listed at the top of this file. The first four prevent unsafe or dishonest
   execution; the next four prevent malformed, stuck, manually completed or
   un-cancellable work. Record one merged end-to-end proof and cross the
   Operational MVP boundary.
2. **Release 3.7 — Portfolio Value Proof.** Capture decisions before the first
   preview, stage previews without applying them, produce the portfolio brief,
   execute five independently checked improvements, then record the rollout
   decision. This crosses the Value-proven MVP boundary.
3. **Prepare governed autonomy.** Close one-manifest-walk and D-001. D-001 is
   required before a scheduler may choose a dependent second unit; the manifest
   walk prevents execution readiness from relying on three drifting scans.
4. **Release 3.9 — Governed Autonomous Delivery.** Execute G39-01 through
   G39-09 in order. Later items may be developed on isolated branches only when
   their declared dependencies are already merged; no stacked branch may
   assume an unmerged schema or event vocabulary.
5. **Release 4.0 — Adaptive Routing.** Optimize provider selection only after
   the guarded-autonomy pilot proves that the control plane can safely execute
   what the router selects.

Release 2.9 field proof, Release 3.6 surface verification, physical Android
proof and 90-day trend accrual continue in parallel through the operator queue.
They ratchet claims but do not hold the engineering queue or either MVP
boundary unless they expose a contradiction in a claimed workflow.

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
| 4.0 A — reconcile what exists             | Lane 0.22 actionable-lines and one-snapshot items      | soft — sequencing  |
| 4.0 B/C — data model and assigner         | 4.0 A; 3.8 WorkPacket and adapters (built)             | soft — sequencing  |
| 4.0 E — the v2 console                    | D-024 (decided 2026-09-24); phases A–D                 | soft — sequencing  |
| Lane 0.5 tab disclosure                   | product decision — `open-decisions.md`                 | hard — design      |
| 2.9 trend accrual                         | calendar time                                          | time-gated         |

---

## 5. Active Release Snapshot

### Active release detail — 3.7 Portfolio Value Proof

Release 3.7 is the active engineering release. Its cohort selection,
conclusion capture, kind-aware applicability, gap-specific next actions and
lifecycle/conclusion consistency work are already integrated. Its remaining
work has two gates before measured execution: the operational loop must first
be trustworthy enough that the trial does not measure fixture pollution,
contradictory eligibility or a blocked portal; then every approval must land in
the accept/reject ledger before an approved preview is applied.

The full execution contract lives in
[Release 3.7 below](#release-37--portfolio-value-proof). The top-of-file MVP
critical path is the authoritative work order. Release 2.9 remains a
field-validation track only; its operator tasks never displace the first
dependency-ready engineering item.

**Current focus:** close MVP critical path A, record the Operational MVP proof,
then finish Release 3.7 M5 through M7. Do not start Release 3.9 implementation
or the D-022 information-architecture redesign while this sequence remains
open.

---

## 6. Open Releases

### Release 2.9 — Operator Field Proof + Mobile Completion

**Status:** validation — its engineering is closed. Mobile completion is
un-deferred, but remaining work requires elevation, authentication, a physical
device or elapsed calendar time and therefore lives outside the agent critical
path.

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

### Release 3.7 — Portfolio Value Proof

**Status:** ACTIVE — defined 2026-08-23; critical path revised 2026-09-18.
Follows Release 3.6. Measured execution is held until MVP critical path A, the
decision ledger, staged previews and required operator approvals are ready.
Its job is to make the product earn an MVP claim against the real portfolio,
not against its own test suite.

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

- **M6 — execute at least five improvements** through preview → approve →
  execute → validate, recording operator minutes, agent first-pass
  result, and whether the repository is materially stronger afterwards —
  appropriate-as-is or archive counts as a conclusion outcome, not automatically
  as one of the five improvements. Each counted improvement needs an
  independently checked acceptance criterion and before/after evidence;
  merge evidence alone is insufficient. The dispatchable checkbox and check
  are in Current focus; this paragraph is the release contract, not a
  second work item. Validation is the M6 `check:` in Current focus.
- **M7 — adjust and decide** — every false positive or bad recommendation the
  executed improvements expose is either fixed as a rule change carrying
  `observedOn` or recorded with its reason, and the go/no-go for the full
  rollout is recorded with the leverage numbers behind it. The check asserts
  that record, never a distribution over the cohort (steering §6). The
  dispatchable checkbox and validation command are in Current focus.

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

**Dependencies:** MVP critical path A; the decision ledger and staged previews;
the operator's approvals and measured effort. Release 3.6 field proof (OQ-1)
continues in parallel and blocks only if it contradicts the cohort evidence.
**D-006 no longer blocks the
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
whose P0 is the only part ever built. It was originally specified to follow
Release 3.7 but engineering closed ahead of the measured trial. Statements in
this historical block that keep merge as an explicit operator action describe
the 3.8 boundary; Release 3.9 deliberately supersedes that boundary without
rewriting what 3.8 proved.

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

**Historical record — do not dispatch these bullets.** All were integrated by
2026-09-11. G39-01 moves this block verbatim to
`docs/history/completed-releases.md`; it remains here only so the contract
migration can cite the exact 3.8 boundary it supersedes.

- **Give a task a provider-neutral contract and a structured result.** A
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
- **Persist capacity per provider, in the provider's own unit.** Named
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
- **Route between providers, and add the Codex adapter.** One registry
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
- **Move push and PR opening to Repo Manager; bind approval to the verified
  SHA.** The agent exits at `IMPLEMENTATION_COMPLETE`; Repo Manager pushes,
  opens the pull request and monitors CI on a cadence without holding an
  execution slot — which also closes Lane 0.17's open "nothing refreshes the
  board" non-blocker. A head change after verification invalidates
  `READY_FOR_OPERATOR`. Merge stays an explicit operator action **for the
  3.8 contract**; G39-01 and G39-06 supersede this state and boundary.
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
- **Remediate from evidence, and hand off between providers.** Attempt and
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
- **Normalize execution events onto the Dispatch Board.** Provider output
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
- **Amendments from the execution strategy — the three that are cheap now
  and expensive later.** Absorbed into
  [`Agent-Execution-Governance.md`](docs/governance/Agent-Execution-Governance.md)
  on 2026-09-08. These three are in 3.8 **only** because a packet that has
  not been written yet is their natural home; deferring them means reopening
  work that has already shipped. Everything else the strategy adds is
  Release 4.0. **(a)** Cost, duration and first-pass telemetry join the
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
- Automatic merge was out of scope for Release 3.8. Release 3.9 may add
  mandate-authorized guarded promotion without changing what 3.8 proved.

**Validation plan:** module smoke covers the pure decision tables — eligibility,
ranking, capacity arithmetic, handoff construction — offline, in the shape
`Resolve-LaneObservation` already uses; api-host smoke covers the routes; every
new gate is proven red against a violating fixture before it is trusted.

**Risks:** an adapter that quietly widens the packet's scope or permission
envelope (the contract forbids it and a gate asserts it); equating provider
token telemetry with remaining subscription allowance; reserves set so high that
ordinary work starves.

**Historical dependency note:** 3.8 closed provider routing and recovery
without claiming autonomous dependent-unit scheduling. D-001 therefore remains
open and is reassigned as a hard Release 3.9 prerequisite. D-003's `Checks:
Read` grant remains necessary wherever check-run detail is available; Release
3.7 supplies the measured baseline for later comparison, not a reason to reopen
3.8.

---

### Release 3.9 — Governed Autonomous Delivery

**Status:** planned — introduced 2026-09-18 from Steering contracts 8 and
12-14. Begins only after the Release 3.7 rollout decision, one-manifest-walk
and D-001 are integrated. Execute G39-01 through G39-09 in order; a later item
may not invent a provisional form of an earlier contract.

**Goal:** the owner authorizes a bounded phase once. Repo Manager then selects
each dependency-ready work unit, prepares and dispatches it, verifies the exact
result, remediates ordinary failures, promotes eligible PRs under deterministic
policy, verifies each merge, reconciles the roadmap and continues until the
phase completes or a decision genuinely exceeds the mandate.

This release does not give an agent permission to merge. It gives the
orchestrator a versioned, revocable authority contract and gives deterministic
policy the responsibility to decide whether independently collected evidence
satisfies it.

#### Product outcomes

- Routine roadmap execution no longer waits for repeated approval already
  granted at the phase boundary.
- The owner can see exactly what was authorized, what authority remains, why
  execution advanced, and why it paused.
- A provider session may disappear without losing the mandate, selected unit,
  branch, PR, verification, remediation or reconciliation state.
- No green check, model statement or roadmap checkbox can independently create
  a `COMPLETE` delivery event.

#### Canonical artifacts and ownership

Use these paths unless the repository already contains an exact canonical
equivalent; if it does, migrate that equivalent rather than create a second
authority:

| Concern                     | Canonical artifact                                                             |
| --------------------------- | ------------------------------------------------------------------------------ |
| mandate schema              | `standards/execution/execution-mandate.schema.json`                            |
| readiness schema            | `standards/execution/execution-readiness.schema.json`                          |
| escalation schema           | `standards/execution/execution-escalation.schema.json`                         |
| deterministic policy config | `backend/config/execution-policy.json` (`schemaVersion: v1`)                   |
| mandate decisions           | `backend/modules/execution/Execution.Mandate.ps1`                              |
| readiness decisions         | `backend/modules/execution/Execution.Readiness.ps1`                            |
| scheduling decisions        | `backend/modules/execution/Execution.Scheduler.ps1`                            |
| promotion decisions         | `backend/modules/execution/Execution.PromotionPolicy.ps1`                      |
| escalation decisions        | `backend/modules/execution/Execution.Escalation.ps1`                           |
| mutable local state         | `output/execution-mandates/<mandateId>/`                                       |
| append-only transitions     | `output/execution-mandates/mandate-events.jsonl`                               |
| UI                          | existing Dispatch Board and work-detail surfaces; no new top-level destination |

State under `output/` is operational and gitignored. Schemas, policy defaults,
tests and synthetic fixtures are source-controlled. Never store credentials,
provider transcripts or repository file contents in a mandate or escalation.

#### Engineering milestones

- [ ] **G39-01 — align every operating contract with governed completion.**
      Update `AGENTS.md`, `docs/reference/status-vocabulary.md`, the delivery-
      loop documentation, roadmap template/schema/audit rules and the gates that
      currently equate `[x]` or CI-green with delivery. Preserve the three
      proposal states (`planned`, `built`, `verified`); define delivery as
      `MERGING → MERGED → POST_MERGE_VERIFYING → COMPLETE`. Replace
      `READY_FOR_OPERATOR` as a universal state with `READY_FOR_PROMOTION`;
      render "Ready for operator" only when the active posture is supervised.
      A roadmap archive edit on a PR head is prospective until that PR merges.
      Prove red fixtures for: CI green but unmerged, merged wrong head, merged
      wrong target branch, and an implementation agent attempting to emit
      `COMPLETE`. _(state: planned)_
      `check: pwsh ./tests/Test-GovernedCompletionContract.ps1 -FailOnError`

- [ ] **G39-02 — create the versioned execution-mandate contract and durable
      store.** Implement schema validation, canonical serialization, content
      hashing, optimistic revision checks and append-only lifecycle events. A
      mandate contains, at minimum: `schemaVersion`, `mandateId`, `repositoryId`,
      `targetBranch`, `roadmapPath`, normalized `planFingerprint`, authorized
      phase and work-unit ids, allowed operations, forbidden paths, network
      policy, risk ceiling, required checks, review policy, promotion mode,
      merge method, concurrency limit, work-unit/attempt/remediation/time/cost
      budgets, issuer, issue/expiry timestamps, status, revision and reason.
      Status is exactly `draft | active | paused | revoked | expired |
    completed`; only compare-and-swap on the expected revision may mutate it.
      Create functions to draft, validate, activate, pause, revoke, expire and
      complete; reject an unknown field rather than silently ignore authority.
      _(state: planned)_
      `check: pwsh ./tests/Test-ExecutionMandate.ps1 -FailOnError`

- [ ] **G39-03 — calculate one execution-readiness verdict.** Return one
      object `{ ready, reasons[], evidence[], checkedAt, repositorySnapshot,
    planFingerprint, policyVersion }`; every reason has a stable code and a
      human explanation. Evaluate four groups: **Plan** (bounded outcome,
      stable ids, dependencies, criteria, checks and scope); **Verification**
      (expected jobs exist, execute on the applicable head and cannot pass by
      skip/neutral); **Execution** (clean isolated workspace, provider and
      credentials available, durable recovery, budgets and one integration
      slot); **Authority** (branch rules compatible, allowed operations and
      forbidden paths explicit, pause/revoke available). Missing or unreadable
      evidence fails closed. Activation calls this evaluator; no UI or route
      may maintain a second readiness rule. _(state: planned)_
      `check: pwsh ./tests/Test-ExecutionReadiness.ps1 -FailOnError`

- [ ] **G39-04 — expose mandate preview and lifecycle without widening
      authority.** Add read, draft-preview, activate, pause and revoke API
      routes under `/api/execution/mandates`; require the existing authenticated
      mutation path and anti-forgery controls. Preview shows the exact roadmap
      fingerprint, work units, operations, forbidden paths, network policy,
      promotion mode, risk ceiling and every budget. Activation is one explicit
      operator action against the displayed mandate hash. Pause/revoke prevents
      new claims immediately; a running task observes it at its next phase
      boundary before another mutation. Expiry is deterministic from the stored
      timestamp. Add the panel to the existing work detail; do not create a new
      navigation destination. _(state: planned)_
      `check: pwsh ./tests/Test-MandateLifecycle.ps1 -FailOnError`

- [ ] **G39-05 — schedule only authorized dependency-ready work and survive
      restart.** Extend D-001's acyclic work graph with a pure selector whose
      inputs are mandate, normalized plan, current integration state and active
      work. Select only authorized, incomplete units whose dependencies are
      verified integrated; use declared priority then stable roadmap order as
      the tie-break. Permit one integration operation per repository and reuse
      the existing isolated-worktree mechanism. Persist selection before
      dispatch. Re-running after a crash returns the existing worktree, branch,
      run and PR; it never creates a duplicate. After each merge, refresh the
      repository, invalidate stale evidence and recompute the normalized plan
      fingerprint. Normalization ignores progress-only changes (checkbox/state,
      Built/Evidence lines and movement to completed history) but includes
      objective, scope, dependencies, acceptance criteria, check and permission
      changes; a material difference pauses `plan-drift` instead of silently
      inheriting prior approval. _(state: planned)_
      `check: pwsh ./tests/Test-AuthorizedScheduler.ps1 -FailOnError`

- [ ] **G39-06 — make promotion deterministic and posture-aware.** Implement
      `supervised` and `guarded`; reject `extended` in schema v1. Both require:
      active non-expired mandate, exact verified head SHA, required checks that
      actually executed and passed, required independent review whose evidence
      is produced outside the implementation result (and, when model-based, by
      a provider or reviewer identity other than the implementer), mergeable
      current head, permission-envelope
      compliance, risk at or below the mandate ceiling, remaining budgets, no
      unresolved escalation and no head movement after evidence collection.
      Supervised additionally requires owner-reviewed approval bound to that SHA.
      Guarded requires the mandate to authorize policy promotion. Regardless of
      mode, owner review remains mandatory for `.github/workflows/**`, CI gates,
      `docs/governance/**`, branch protection, credentials/permissions,
      production deployment, destructive data change, `backend/config/**`, a
      `modelVersion` change or any diff classified as altering what the product
      claims. Never bypass repository rules; wait for required human review or
      a merge queue when GitHub requires it. Record every policy input and
      result before merge, then verify the actual merge commit is reachable
      from the intended target branch before emitting `COMPLETE`. _(state:
      planned)_
      `check: pwsh ./tests/Test-PromotionPolicy.ps1 -FailOnError`

- [ ] **G39-07 — bound remediation and produce decision-ready escalations.**
      Reuse Release 3.8's `RemediationPacket`, `HandoffPacket`, attempt counters
      and provider switching; do not create a parallel retry engine. Classify
      failure as `transient | implementation | authority | plan | evidence |
    budget`. Transient and implementation failures may retry only inside the
      stored attempt/remediation/time/cost budgets and only after changed
      remediation or new evidence. All others pause the affected unit and write
      one escalation containing: mandate/work-unit/run ids, exact limit or rule,
      evidence references, smallest proposed deviation, impact, safe state,
      available operator decisions and the consequence of each. Mandatory
      escalations include ambiguity, material scope expansion, exhausted
      budgets, missing evidence, unresolved independent-review risk, production,
      destructive data, credentials, permissions, governance, CI policy and
      canonical-claim changes. The UI never asks only "May I continue?"
      _(state: planned)_
      `check: pwsh ./tests/Test-ExecutionEscalation.ps1 -FailOnError`

- [ ] **G39-08 — reconcile integration, authority consumption and phase
      completion.** After every verified merge, atomically record merge commit,
      target branch, completed unit, consumed attempts/time/cost, remaining
      mandate scope and the refreshed plan fingerprint. Update the roadmap view
      from repository state; never write completion from an agent result. If
      eligible work remains, queue exactly one next unit; if none remains and
      every authorized unit is integrated, complete the mandate; if a unit is
      blocked, keep the mandate active or paused according to the recorded
      reason. Startup reconciliation repairs interrupted `MERGING`, `MERGED` and
      `POST_MERGE_VERIFYING` states idempotently. Expose a single trace from
      mandate → unit → run → PR → checks/review → policy → merge → next unit.
      _(state: planned)_
      `check: pwsh ./tests/Test-PostMergeReconciliation.ps1 -FailOnError`

- [ ] **G39-09 — prove one guarded multi-PR phase on a low-risk real
      repository.** Select the pilot deterministically: local clean checkout,
      protected default branch compatible with automation, not this repository,
      not archived/excluded, no production deploy/migration/secrets/workflows/
      governance/config changes, at least two dependency-ordered actionable
      units, and runnable acceptance checks already present or explicitly in
      scope. `scripts/Select-GuardedAutonomyPilot.ps1` emits candidates and
      reasons; choose the highest-ranked eligible candidate, not a flattering
      substitute. The operator previews and activates one phase mandate. Repo
      Manager then completes at least two PRs without another dispatch or
      routine approval, including exact-head verification, policy promotion,
      merge verification, roadmap reconciliation and next-unit selection.
      Demonstrate bounded remediation with a controlled failing fixture before
      the real run, and demonstrate decision-ready escalation with a separate
      fixture that requests a forbidden-path change; do not manufacture either
      event in the real repository. Record the complete proof in
      `evidence/verified/guarded-autonomy-pilot-<date>.md` with mandate id/hash,
      plan fingerprint, work units, PRs, merge commits, checks, reviews, policy
      decisions, transitions, operator touches, elapsed time and final state.
      _(state: planned)_
      `check: pwsh ./tests/Test-GuardedAutonomyPilot.ps1 -EvidencePath evidence/verified/guarded-autonomy-pilot-*.md -FailOnError`

#### Acceptance criteria

- One activation authorizes a pinned phase; no routine action asks for approval
  already present in the mandate.
- A material roadmap change, expired/revoked mandate, moved head, skipped check,
  failed independent review, forbidden path or exhausted budget prevents
  promotion with a stable reason code.
- The implementation provider cannot verify, review, authorize, merge or mark
  complete its own result through its structured output.
- Every lifecycle transition is reconstructible from mandate revision, policy
  version, repository state and evidence; model prose is never the sole reason.
- Restarting at any phase produces no duplicate worktree, branch, run, PR,
  remediation or merge.
- The pilot completes at least two real PRs and proves remediation and
  escalation through controlled fixtures.

#### Out of scope

- Extended autonomy across multiple phases or repositories.
- More than one integration operation per repository.
- Bypassing branch protection, required human review or GitHub authorization.
- Autonomous changes to governance, CI, product-claim config, credentials,
  permissions, production systems or destructive data.
- Adaptive provider optimization, pricing inference or learned routing; those
  belong to Release 4.0.
- Rewriting roadmap objectives or acceptance criteria during execution.

#### Validation plan

Every decision function is pure over fixtures before it is connected to a
mutation. Each new gate is shown red against at least one violating fixture.
Module smoke covers schemas, state transitions, normalization, readiness,
scheduling, promotion and escalation; API-host smoke covers authenticated
lifecycle routes and restart reconciliation; frontend unit tests cover preview,
pause/revoke, posture labels and escalation rendering. The real pilot is the
only acceptance evidence for the end-to-end claim and may not be replaced by a
smoke fixture.

#### Risks

- A plan fingerprint that changes on ordinary progress would revoke every
  mandate after its first PR; normalization is therefore an explicit contract.
- A fingerprint that ignores objective, scope, dependency, criterion, check or
  permission changes would allow approval to drift; all remain hash inputs.
- Treating a green/skipped/neutral check alike would promote unverified work;
  the verifier records which expected jobs actually executed.
- Giving the orchestration credential branch-protection bypass would erase the
  independent boundary this release exists to prove; it is forbidden.
- A pilot selected because it is easy rather than because it is the highest
  eligible candidate would not prove general operation.

**Dependencies:** Value-proven MVP decision; D-001; one manifest walk; Release
3.8's WorkPacket, provider adapters, exact-head verification, independent
review, remediation/handoff and canonical execution events; GitHub repository
rules compatible with the chosen posture. Missing external authorization is an
operator-queue item, not authority to weaken a gate.

---

### Release 4.0 — Adaptive Routing

**Status:** planned — renumbered from 3.9 on 2026-09-18. Design authority is
[`Agent-Execution-Governance.md`](docs/governance/Agent-Execution-Governance.md),
which absorbed Ben's _Multi-Provider Agent Execution Strategy_ the same day.
Follows Release 3.9, and cannot precede it: every milestone consumes telemetry
that 3.8 records, while its selected work must still pass the authority,
readiness and integration controls that 3.9 proves.

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

**Dependencies:** Release 3.8 for the telemetry these milestones read,
especially cost and duration in the canonical event vocabulary; Release 3.9
for the mandate, readiness and policy-controlled promotion path that safely
executes the work the adaptive router selects.

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
lane" placement is "Labels match what they count". Phase A depends on those
three. What is new:

- [ ] **One ranking function for Today and the Dispatch Board.** Today ranks
      through `frontend/lib/todayRanking.ts` over the value score; the board
      ranks the queue through `Get-RankedQueue`
      (`backend/modules/execution/Execution.Ledger.ps1`). They disagree: one
      repository read #1 on Today and #8 on the board, on scores with different
      scales. One server-side ranking, one scale, consumed by both, with the
      rank's inputs on the payload. Done when: a fixture portfolio ranks
      identically on both routes and the frontend holds no ranking arithmetic.
      _(state: planned)_
      `check: pwsh ./tests/Test-OneRanking.ps1 -FailOnError`
- [ ] **Counts reconcile on every scan, and the header says when they do not.**
      A gate asserts, per snapshot, that status counts sum to the total and
      that scanned, in-scope, assessed and ledger counts each carry one stated
      definition. The product runs the same assertion after every scan and
      shows a header badge naming the mismatch when it fails, instead of two
      tabs quietly disagreeing. _(state: planned)_
      `check: pwsh ./tests/Test-CountsReconcile.ps1 -FailOnError`
- [ ] **One hold card per repository.** "Blocking a lane" showed one
      repository four times, once per hold code; a repository renders one card
      listing its codes. Columns that never carry a value (Effort, assessed
      time) leave the table. _(state: planned)_
      `check: npx vitest run frontend/components/TodayView.test.tsx`

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
- [ ] **A run that closes records `completedAt`, the verdict, the vendor and
      usage.** 47 of 51 runs have no `completedAt`, so agent time and
      completion rate read "unmeasured" and per-lane usage has nothing to
      attribute. Every run-close event — finished, failed, cancelled,
      capacity-wait — writes the four fields on the run record and the
      execution event (`Execution.Ledger.ps1`, `Execution.Events.ps1`); a
      close with any of them empty fails the gate by name. _(state: planned)_
      `check: pwsh ./tests/Test-RunCloseFields.ps1 -FailOnError`
- [ ] **Each vendor's balance feed confirms balance left and reset time.**
      Copilot is counted in premium requests; Anthropic and OpenAI in dollars.
      The feed records both figures in the vendor's own unit against the 3.8
      capacity window, and nothing is converted into a shared unit — a
      converted number is a guess wearing a unit. A vendor with no feed reads
      "unconfirmed", never 0. _(state: planned)_
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
      with ids, each a predicate over queue item, agent, lock and budget
      fields, with a plain-language `because`. _(state: planned)_
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

- [ ] **Dashboard: Now plus lane cards.** Now shows health KPIs and gaps;
      each lane card shows its agent, its step, phase n of N, the rule ids
      behind the assignment, its trend and its usage in the vendor's unit; an
      empty lane shows why. Dashboard is the only place an action can be
      taken. The Dispatch Board and Today's queue retire once Dashboard does
      everything they do, not before. _(state: planned)_
      `check: npx vitest run frontend/components/LaneCards.test.tsx`
- [ ] **Six destinations.** Dashboard (Now + Lanes), Queue (read-only),
      Insights (read-only), Portfolio, Runs, Settings. No other tab, and no
      control outside Dashboard mutates anything. _(state: planned)_
      `check: npx vitest run frontend/components/AppNavigation.test.tsx`
- [ ] **Queue and Insights open the v2 read-only views, not v1.** Their
      routes render the new views, with no action control on either; the v1
      panels are unreachable from navigation once these land.
      _(state: planned)_
      `check: npx vitest run frontend/components/QueueView.test.tsx frontend/components/InsightsView.test.tsx`
- [ ] **The idle state shows the last activity.** A lane with nothing running
      shows its last run with its outcome pipeline (the phases it reached and
      the verdict) and the next action the assigner would take, never a blank
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

**Dependencies:** Lane 0.22's actionable-lines, one-snapshot and labels items
for phase A; 3.8's WorkPacket and adapters (built) for phase B; 3.9's
performance store for the per-agent first-pass number; D-024 (decided) for
phase E.

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

_The action, not the command._ `POST /api/roadmap/runner/start` and
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

_The kill switch._ `roadmap-task-runner.hold.json` is the durable half the stop
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

_One pane._ [`RunnerControlPanel.tsx`](frontend/components/RunnerControlPanel.tsx)
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
  writes the real agent-run ledger, `roadmap-writeback.jsonl` and the packaging
  queue.
- **"One click, no preview": not true.** The board's Dispatch button opens the
  task preview, not a dispatch. Its "Ready" label still ignores holds.

**Keep as they are:** the work-item trace (a stage-by-stage chain with a named
broken link, the best diagnostic in the product); Leverage's "Not captured yet",
which names missing measurements instead of showing zeros; the "Previews first;
nothing is applied" copy and Private Scope; and Help's "Computed from" lines.

**Open, in order.** The first two lead Current focus: test fixtures never reach
live state, and one dispatch-eligibility rule. Then:

- [ ] **Only actionable roadmap lines become work.** Before ranking, each
      candidate is classified `actionable | done-statement | deferred | guidance |
    fragment`. Only `actionable` is ranked, queued or offered for dispatch, and
      each repository shows "Excluded (n)" with the reason for each line. A run
      that completes writes its item back as done, and the same item hash cannot
      be dispatched again inside a cooldown unless the operator overrides.
      _(state: planned)_
      `check: pwsh ./tests/Test-WorkItemQuality.ps1 -FailOnError`
- [ ] **Stuck work is detected, not noticed.** Each state has a limit. A
      runner heartbeat older than N minutes with approved work waiting is stuck,
      and so is a lane running past its limit, a dispatch with no branch after
      24 h, an approval that never reached the queue, or a scan stuck in one
      phase. Each surfaces once, on Today, with its remedy (start runner, poll
      GitHub, re-enqueue or discard, cancel and requeue). Durations read "27h",
      never "99293.3s" or "1655m". A lane completes on merge evidence, as its
      trace already states, not through a manual Complete button.
      _(state: planned)_
      `check: pwsh ./tests/Test-StuckWork.ps1 -FailOnError`
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
      _from the agent_ but nothing carries an operator's cancel _to_ it. Ben,
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
      WORKING, LOCAL*VERIFYING, PUSHING, PR_OPEN, CI_PENDING,
      CI_PASSED/CI_FAILED, READY_FOR_PROMOTION, MERGING, MERGED,
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
      tile. *(state: planned)\_
      `check: npx vitest run frontend/components/ExecutionLaneTile.test.tsx`
- [ ] **Labels match what they count.** "N need you" counts repositories, not
      holds × codes (it read 63 for 59 repositories). "Blocking a lane" appears
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

---

## 8. Risks and Guardrails

Full list in [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md);
headline guardrails for the active release and near-term roadmap:

- Do not auto-dispatch tasks without one canonical readiness verdict and an
  active mandate that contains the selected work unit.
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
- Promotion is posture-aware. In `supervised`, merge remains an explicit
  operator action bound to the verified head SHA. In `guarded`, deterministic
  policy may promote only when the active mandate explicitly authorizes it and
  every G39-06 input passes. `extended` is unsupported until separately proved.
- Governance, CI, branch protection, credentials/permissions, production,
  destructive data, `backend/config/**`, `modelVersion` and product-claim
  changes always require owner review regardless of posture.
- **Do not leave a control enabled that cannot succeed.** A disabled control
  names its unmet precondition; an enabled one is a promise.
- **Do not emit delivery completion while an item still names an outstanding
  integration proof.** Split independently verifiable work. A `[x]` and archive
  edit on a PR branch is a proposed post-merge state, not proof that it landed.
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
- **Promotion authority applies to a verified head SHA, never a pull request
  number.** Any head change invalidates verification and the prior operator or
  policy decision. Supervised work requires renewed operator approval; guarded
  work requires a fresh deterministic evaluation under the unchanged mandate.
- **A mandate cannot widen itself.** Material plan drift, expiry, revocation,
  exhausted budget or a forbidden operation pauses the affected work before
  the next mutation and produces a decision-ready escalation.

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

**A milestone is verified when its `check:` exits 0 in CI on the exact PR head;
it is delivered only when that verified change is merged into the intended
target branch and the integration is independently reconciled.** Nothing less
may emit `COMPLETE`.

Every milestone delivery therefore requires:

- the check exercises real behaviour — a route returning mock data fails it
- the check is in the repository and runs under `-FailOnError` in the smoke workflow
- every expected job actually ran on the applicable head; skipped, neutral,
  stale or unrelated status is not success
- affected docs changed in the same PR when behaviour changed (`Test-RoadmapCapabilityRecord.ps1`)
- the milestone it closes is staged as `[x]` and archived in the same PR so the
  target branch receives code and its proposed record atomically
- a signal it adds to a dashboard resolves to source data (`Test-BadgeProvenance.ps1`, or add it)
- promotion eligibility is recorded from operator approval or deterministic
  mandate policy against the same verified SHA
- the actual merge commit is reachable from the intended target branch, and
  post-merge reconciliation records the milestone, roadmap and next-unit state

**A release is done when every milestone is integrated on the intended branch
and its execution history can reconstruct that fact.** Field proof for the
release is a separate line in the operator queue and does not hold the release
unless that proof is part of the release's explicit product claim.

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
