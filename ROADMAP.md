# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Session start:** `pwsh ./tools/Get-SessionBriefing.ps1` (automatic in Claude Code). The handoff is the one pinned issue labelled `handoff`; nothing under `output/` or `docs/history/worklogs/` is a handoff.
> **Active release:** **Release 4.1 — Proof of Value** (2026-10-16 to 2026-11-15)
> **Owner decision (Ben, 2026-10-16):** until 2026-11-15 the product has one job: prove, on repositories other than this one, that it can find a worthwhile improvement, propose it with evidence, hand it to a suitable coding agent, get it verified, merged and recorded, and measure what all of that cost the operator. Feature work that the loop does not need is frozen, by name the v2 console (Release 4.0 phase E), Release 3.9 and Release 4.0 phases B–E. The success figures are targets, not incentives to inflate a metric. Frozen work does not resume on 2026-11-15 by default; the delivery evidence decides its priority.
> **Work ordering:** Must work now ([Current focus](#current-status-agent-context)) → Must improve next ([§7](#7-must-improve-next--observed-bottlenecks)) → Deferred ([`docs/governance/deferred-work.md`](docs/governance/deferred-work.md))
> **Canonical product direction:** [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
> **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
> **Dated change log:** [`CHANGELOG.md`](CHANGELOG.md)

---

## Current Status (Agent Context)

**Last updated:** 2026-10-20

**Where the product stands (evaluation of 2026-10-16, checked against live
data).** About eight merged PRs on other repositories, ever, almost all of them
roadmap-document changes, and none since 2026-09-07. No agent run outside the
smoke tests since 2026-09-01. 45 of 80 real runner runs failed: `gh agent-task`
auth and token conflicts, missing roadmap files, no actionable items, a runner
pid mismatch. One of 62 repositories is ready for work. Operator minutes have
never been recorded. The console's repair-PR button only ever built a dry-run
plan, and a real PR from the service would have failed: git under the SYSTEM
service had no commit identity.

**Success by 2026-11-15.** At least five meaningful, externally verified PRs
merged that the product initiated. At least ten repositories legitimately
ready for automated work. Average total operator effort of 20 minutes or less
per merged improvement, time spent on rejected proposals included. Evidence
that automation removes manual work rather than moving it. An auditable
history that keeps failures and rejections.

**Current focus — Must work now, in order.** Every item is agent-closable;
operator work is in the operator queue. Take the first `[ ]` not already in
flight.

- [ ] **Open a real roadmap-repair PR from the repair preview (loop steps 2
      and 5).** The console's repair-PR button only ever built a dry-run plan.
      From the preview it now opens a real pull request on the target
      repository, carrying the content the operator edited in the preview
      rather than the first draft. The service can commit: git has a commit
      identity when it runs under the service account. A failure at any step
      leaves the target clone clean, with no stray branch and no staged or
      untracked files. Merged to main 2026-10-16 in PR #329 with its check
      green there; the service runs it after the next restart. Leaves this
      file for the archive in the PR that records that restart. _(state: built)_
      `check: pwsh ./tests/Test-DeliveryLoop.ps1 -FailOnError`
- [ ] **Record every accept and reject, with the operator's time (loop steps 6
      and 8).** Each proposal the operator accepts, edits or rejects lands in
      one append-only decision ledger, with the proposal it answers, the
      repository, and the minutes spent on it. The workflow captures the time
      itself; nobody types it in afterwards. A rejected proposal keeps its
      minutes. This replaces the planned `Test-DecisionLedger.ps1` item (its
      text is preserved in `docs/governance/deferred-work.md`). Merged to main
      2026-10-16 in PR #329 with the item above; first record written
      2026-10-17 for the FreshStartFamily dispatch. _(state: built)_
      `check: pwsh ./tests/Test-DeliveryLoop.ps1 -FailOnError`
- [ ] **Lane 0.22 — one dispatch-eligibility rule, enforced everywhere (loop
      step 2).** The Dispatch Board read "Ready" for repositories Today holds
      for uncommitted changes, for a curated-out archived repository, for one
      whose own detail reads "blocked", and for folders not in the index. One
      server-side rule answers `{ ok, reasons[] }`. The board lists only
      eligible items and collapses the rest into "N held (why)". Every Dispatch
      control is disabled with its reason when `ok` is false. Slice 1, the
      server rule, is on this branch (rebased from PR #327, stacked on the
      roadmap change): `Get-DispatchEligibility` answers `{ ok, reasons[] }`
      and `GET /api/execution/queue` queues only eligible entries, with
      `heldSummary` for "N held (why)". Slice 2 is the board and the controls,
      and the dispatch route refusing when `ok` is false. _(state: built)_
      `check: pwsh ./tests/Test-DispatchEligibility.ps1 -FailOnError`
- [ ] **Record the outcome of every decision (loop step 7).** Each decision in
      the ledger gains its outcome as it happens: PR opened (URL and head SHA),
      the CI conclusion on that head, merged or closed unmerged, or rejected
      before any PR existed. Outcomes are read from GitHub, never typed in. A
      decision with no outcome yet says so; it does not count as a failure.
      From the ledger alone, total operator minutes per merged improvement is
      one computation over all decisions, rejected ones included.
      _(state: planned)_
      `check: pwsh ./tests/Test-DeliveryOutcomes.ps1 -FailOnError`
- [ ] **A baseline now, then a weekly delivery report (loop step 8).** One
      command writes the report from the ledgers and GitHub: PRs the product
      initiated on other repositories, how many passed CI on their head, how
      many merged, proposals rejected, operator minutes in total and per merged
      improvement, agent-run failures by cause, and repositories ready for
      automated work. Every figure carries its unit, basis, window and source
      (`New-PortfolioMetric`); one the ledgers cannot compute reads "not
      measured" with its reason, never 0. The first run reproduces the
      2026-10-16 evaluation's figures as the baseline under
      `evidence/baseline/<date>/`, and each weekly run says what moved since.
      _(state: planned)_
      `check: pwsh ./tests/Test-DeliveryReport.ps1 -FailOnError`
- [ ] **Only actionable roadmap lines become work (Lane 0.22; loop step 1).**
      Before ranking, each candidate is classified `actionable | done-statement |
      deferred | guidance | fragment`. Only `actionable` is ranked, queued or
      offered for dispatch, and each repository shows "Excluded (n)" with the
      reason for each line. A run that completes writes its item back as done,
      and the same item hash cannot be dispatched again inside a cooldown unless
      the operator overrides. _(state: planned)_
      `check: pwsh ./tests/Test-WorkItemQuality.ps1 -FailOnError`
- [ ] **A dispatched agent run ends in a pull request on another repository
      (loop steps 3 to 5).** The push and PR-opening code exists (Release 3.8
      H38-21 and H38-22, archived), but no agent run outside the smoke tests
      has happened since 2026-09-01 and 45 of 80 real runner runs failed. The
      local Claude runner pushes its branch and opens the pull request, or the
      approve-push route does, and the run records the PR URL. A run whose
      runner pid no longer matches the heartbeat is closed as abandoned, with
      its reason, and is never left `running`. Done when a fixture run (stubbed
      `gh`, local bare remote) reaches a recorded PR URL, and a fixture run
      with a dead runner pid closes as abandoned. The 2026-10-18 runner repair
      in `scripts/Invoke-RoadmapTaskRunner.ps1` handles readiness tasks with no
      selected checkbox when committing; `tests/Test-DeliveryLoop.ps1` covers
      objective and run-ID commit labels. Since #349 (2026-10-19) a run branch
      starts at the freshly fetched PR base, not the clone's checkout, so its
      PR carries only the agent's change; the same gate covers it. These
      bounded repairs do not establish dispatch-to-PR or live recovery proof.
      _(state: planned)_
      `check: pwsh ./tests/Test-DispatchToPr.ps1 -FailOnError`
- [ ] **At least ten repositories legitimately ready for automated work.** One
      of 62 is ready today, and an investigation into why is under way. The
      rule changes it leads to come from that evidence: each names the
      repositories it was observed on and bumps `modelVersion`. None loosens a
      threshold until the count looks better (steering §6). Ready means the
      dispatch-eligibility rule passes and the repository carries an actionable
      item with acceptance criteria and a runnable check. The check named here
      is a placeholder until the investigation names the gate.
      _(state: planned)_
      `check: pwsh ./tests/Test-ReadinessEvidence.ps1 -FailOnError`

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

Since 2026-10-16 the file holds three tiers. **Must work now** is the
Current focus list: what the delivery loop cannot run without. **Must improve
next** (§7) is work an observed bottleneck justifies. **Deferred** work is not
here at all: it lives, verbatim, in
[`docs/governance/deferred-work.md`](docs/governance/deferred-work.md), each
item with the reason it was deferred and the evidence that would bring it back.

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

**The loop Release 4.1 proves (2026-10-16).** Every Must work now item serves
one step of it, on a repository other than this one:

1. Discover a legitimate improvement.
2. Assess readiness and propose an evidence-based change.
3. Dispatch it to an appropriate coding agent.
4. Implement it and verify it locally.
5. Open a PR and verify CI on its head.
6. Present it for the operator's approval.
7. Merge it and record the outcome.
8. Measure the operator's total effort.

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

A `built` or `verified` milestone's `check:` must be a step CI runs, with every
argument the line passes (validator R024). A check CI does not run can never go
green there, so the state would rest on nobody's word.

`verified` is the terminal state for this file. It is the only state that earns `[x]`,
and `[x]` means the item leaves this file for the archive in the same PR.

**Field proof is not a state.** "Seen working on the live portal", "ran under SYSTEM",
"confirmed on the phone" are recorded as ratchets in
[`docs/governance/operator-queue.md`](docs/governance/operator-queue.md) via
`scripts/Add-OperatorVerification.ps1`. A ratchet may be recorded any time after
`verified`, may be recorded never, and never blocks a later milestone. The
promotion boundary — merge to the protected default branch on an operator-approved
verified head SHA — is unchanged and lives in §8; it gates *merge*, not *the next item*.

**Milestone format.** One bullet, action-first, with exactly one
`_(state: ...)_` marker kept on one line and the check on its own line; the
Current focus items above are the model. (The worked example that used to sit
here was itself an open checkbox, so every parser counted it as pending work;
kind detection shipped and was archived on 2026-09-14.)

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

| Version | Title | Status |
| --- | --- | --- |
| 0.4 – 2.8, 3.0 – 3.6 | Foundation through Every Repository Gets an Outcome | `done` — see the [archive](docs/history/completed-releases.md) |
| 2.9 | Operator Field Proof + Mobile Completion | `deferred` 2026-10-16 — engineering half archived; its field proofs are operator-queue rows ([deferred work](docs/governance/deferred-work.md)) |
| 3.7 | Portfolio Value Proof | `deferred` 2026-10-16 — its measured trial is absorbed by 4.1 ([deferred work](docs/governance/deferred-work.md)) |
| 3.8 | Provider-Aware Execution | `done` 2026-09-11 — archived 2026-10-16 |
| 3.9 | Adaptive Routing | `deferred` 2026-10-16 — frozen by name ([deferred work](docs/governance/deferred-work.md)) |
| 4.0 | Rule-Driven Lane Assignment | `deferred` 2026-10-16 — slice 4.0-1 verified and archived; the rest of phase A and phases B–E frozen ([deferred work](docs/governance/deferred-work.md)) |
| **4.1** | **Proof of Value** | **active** 2026-10-16 to 2026-11-15 |

Release 4.1 follows 4.0 in number although 4.0 is deferred: release numbers
name scope, not sequence. The full 2026-09-30 index is in the archive.

### Execution Order and Dependencies

Work Must work now in the Current focus order. Release numbers identify scope;
they do not dictate sequence. The earlier execution order (3.7 trial
sequencing, where 3.8 sat, the old dependency map) is preserved in
[`docs/governance/deferred-work.md`](docs/governance/deferred-work.md).

**Dependency map (agent-closable work only; operator rows live in
[`operator-queue.md`](docs/governance/operator-queue.md)):**

| Open item | Depends on | Type |
| --- | --- | --- |
| Real repair PR from the preview | the commit-identity fix on the same branch | none — in flight |
| Decision ledger with operator time | nothing | none — in flight |
| Dispatch-eligibility rule | nothing; slice 1 is PR #327 | none |
| Outcome of every decision | the decision ledger | hard |
| Baseline and weekly report | the ledger and outcomes for minutes; the rest of the baseline can be taken now | soft — sequencing |
| Only actionable lines become work | nothing | none |
| Dispatch ends in a PR on another repository | the eligibility rule; actionable lines | soft — sequencing |
| Ten repositories ready | the eligibility rule; actionable lines; the readiness investigation | soft — evidence |
| §7 items | an observed bottleneck each, named on the item | soft — evidence |

---

## 5. Active Release Snapshot

### Active release detail — 4.1 Proof of Value

Release 4.1 became the active release on 2026-10-16 by Ben's decision, quoted
in the status block at the top of this file. It runs to 2026-11-15. Its
execution contract lives in one place,
[Release 4.1 below](#release-41--proof-of-value); this heading exists so the
validator can resolve the active-release pointer.

**Current focus:** the eight Must work now items, in order. The first two are
in flight on a separate branch, and slice 1 of the third is PR #327.

---

## 6. Open Releases

### Release 4.1 — Proof of Value

**Status:** active — 2026-10-16 to 2026-11-15, by Ben's decision of 2026-10-16.
It replaces Release 2.9 as the active release; 2.9, 3.7, 3.9 and 4.0 are
deferred.

**Goal:** a proof of value in thirty days. The product runs its delivery loop
end to end on repositories other than this one, and the value is measured as
the operator's total effort per merged improvement. The loop is: discover a
legitimate improvement; assess readiness and propose an evidence-based change;
dispatch it to an appropriate coding agent; implement and verify it locally;
open a PR and verify CI; present it for operator approval; merge it and record
the outcome; measure total operator effort.

#### Product outcomes

- The operator can point at merged pull requests on other repositories that
  the product initiated, each with its decision, its CI evidence on the merged
  head, and the minutes it cost.
- Whether the product returns more operator time than it takes is answered
  from a ledger, not an impression, with failures and rejections counted.

#### Engineering milestones

**Must work now** — the eight milestones in
[Current focus](#current-status-agent-context), in that order. They are listed
once, there, so the release and the focus list cannot disagree.

**Must improve next** — [§7](#7-must-improve-next--observed-bottlenecks). Each
item names the bottleneck that justifies it. One moves into Current focus only
when the delivery evidence shows it blocks the loop.

**Deferred** — [`docs/governance/deferred-work.md`](docs/governance/deferred-work.md).
A deferred item comes back only with the evidence its own row names.

#### Acceptance criteria

- At least five meaningful pull requests on repositories other than this one,
  initiated through the product, passing CI on their head SHA and merged, each
  traceable from proposal to merge in the decision ledger.
- At least ten repositories legitimately ready for automated work under the
  dispatch-eligibility rule, with the evidence for each.
- Average total operator effort of 20 minutes or less per merged improvement,
  with the time spent on rejected proposals included in the total.
- The weekly delivery report shows automation reducing manual work rather than
  relocating it: where the operator's minutes went, not only how many.
- An auditable history: every proposal, rejection, failed run and failed check
  stays in the ledgers and the weekly report.
- A count reached by loosening a rule, splitting one change into several PRs,
  or choosing trivial edits does not meet these targets (steering §6).

#### Out of scope

- Everything in `docs/governance/deferred-work.md`, unless the delivery
  evidence shows a change is needed to complete the loop. Such a change moves
  back into this file with its check and the evidence that justified it.
- Counting changes to this repository as improvements. This repository's own
  PRs build the loop; they are not its proof.
- Automatic merge. Promotion stays an operator action on a verified head SHA
  (§8).

**Validation plan:** each milestone's own `check:` runs in CI through
`scripts/Invoke-TestSuite.ps1` once it is built, alongside the module smoke,
the api-host smoke where the host changes, and `npm run test:unit` where a
surface changes; CI is the arbiter. The release itself is validated by the
weekly delivery report against the acceptance criteria, and by the PRs on other
repositories, whose own CI decides whether each one passed.

**Risks:** metric inflation — most product PRs so far changed roadmap
documents, so whether a PR is meaningful is judged per PR and recorded, never
assumed; operator effort that moves outside the console instead of shrinking,
which the report must name as unmeasured rather than omit; the service
boundary — git under the SYSTEM service had no commit identity, and the runner
needs the operator's own credentials; frozen work leaking back in as
"necessary" without the evidence its deferred row names.

**Dependencies:** the commit-identity fix and the repair-PR branch (in flight,
2026-10-16); PR #327 for the eligibility rule; the readiness investigation;
operator time at the console for proposals and merges (OQ-15 in
[`docs/governance/operator-queue.md`](docs/governance/operator-queue.md)).

**Known issues:**

- 45 of 80 real runner runs failed (causes in Current Status). The dispatch
  milestone and §7's Copilot and stuck-work items own them.
- `scripts/Invoke-PhaseProtocolTest.ps1` fails its dogfood assertion against
  this file (`no-phase-plan`, `missing-protocol-columns`). It failed the same
  way before the 2026-10-16 rewrite and is not a CI gate. Recorded, not fixed
  here.
- `AGENTS.md` ties supervised posture to "Release 3.9 G39-01 through G39-06",
  ids no roadmap revision has carried. Release 3.9 is now deferred, so that
  sentence needs an owner decision; it is not edited here.

**Traceability:** the decision is Ben's of 2026-10-16, recorded in this file's
status block and in `CHANGELOG.md` under 2026-10-16. The evaluation figures are
in Current Status. Decisions and outcomes go to the decision ledger, run
history to `output/agent-runs`, and each weekly report to `evidence/`. Deferred
requirements are in `docs/governance/deferred-work.md`; reconciled ones are in
`docs/history/completed-releases.md` under "Reconciled 2026-10-16".

---

## 7. Must Improve Next — Observed Bottlenecks

Continuous, not release-scoped. Each item below is justified by a bottleneck
that operation actually showed, named on the item, and is ordered by what it
costs the loop. An item moves into Current focus only when the delivery
evidence shows it blocks the loop. Work without that evidence is in
[`docs/governance/deferred-work.md`](docs/governance/deferred-work.md); closed
lanes are in [the archive](docs/history/completed-releases.md).

- [ ] **Copilot dispatch reaches a live task (from Release 2.9).** `gh
      agent-task` auth and token conflicts are among the causes of the 45
      failed runner runs. gh ignores its stored OAuth login whenever
      `GH_TOKEN` or `GITHUB_TOKEN` is set, and this machine sets
      `GITHUB_TOKEN` at Machine scope.
      [`Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1)
      clears both before polling, and
      [`Start-GitHubCopilotTask.ps1`](scripts/Start-GitHubCopilotTask.ps1)
      probes with both cleared. The work left: match each recorded auth
      failure to the code path that launched it. A failure that predates the
      clearing is closed by the live run (OQ-6); a path that still launches
      `gh agent-task create` with a token set is fixed under a module-smoke
      gate. Done when every recorded auth failure is attributed to a code path
      and no launch path passes a token through; the live task, with its URL
      in the run summary, is OQ-6 and closes the Release 3.0 residual.
      _(state: built)_
      `check: pwsh ./scripts/Invoke-ModuleSmokeTest.ps1`
- [ ] **D-012 — the permission envelope binds on every local run.** For each
      local adapter (Claude headless and interactive, Codex) the runner reads
      what the run's branch adds over its base (`base...HEAD`) plus anything
      left uncommitted, after every commit and before the push decision. A
      path under a `forbiddenPaths` entry, or under `.github/workflows/**`,
      which binds even when a packet omits it, fails the run by name with the
      path and the rule, and the branch is not pushed; `failed` is also a
      status Approve & push refuses. A run whose base cannot be read fails
      closed. Provider deny rules stay a first layer, never the only one, and
      `.github/workflows-proposed/` is not forbidden. Built 2026-10-20
      (`Test-RunPermissionEnvelope` in the runner, `Find-ForbiddenPathChange`
      in `Execution.WorkPacket.ps1`); the gate failed on a copy whose refusal
      did not return. _(state: built)_
      `check: pwsh ./tests/Test-PermissionEnvelope.ps1 -FailOnError`
- [ ] **D-012, the rest: cloud runs, proposed workflows and the network
      allowlist.** A Copilot cloud task pushes from GitHub, so the runner's
      check never sees its branch; the host applies the same check before it
      records that PR as the product's. An agent that needs CI changed names
      its `.github/workflows-proposed/` file as waiting in its result. A packet
      that needs the network declares an allowlist the owner approves;
      `network false` is never loosened silently. Why next: the first
      dispatched runs that push to other repositories make this real, and
      until it binds for cloud runs the PR review is their only guard.
      _(state: planned)_
      `check: pwsh ./tests/Test-EnvelopeCloudAndNetwork.ps1 -FailOnError`
- [ ] **The L0 road: a repository with no roadmap gets a first plan.** About
      49 scanned repositories sit at L0 with no roadmap file, "missing roadmap
      files" is a cause of failed runner runs, and one of 62 repositories is
      ready. For a repository with no roadmap, the product proposes a small
      first plan — its purpose in the owner's own words from the README, one
      release, and actionable items with checks — previewed and accepted like
      any other proposal. It never skips the repository silently, and it never
      queues a run against a roadmap file that does not exist.
      _(state: planned)_
      `check: pwsh ./tests/Test-L0Road.ps1 -FailOnError`
- [ ] **Next actions beyond roadmap rewrites.** Almost every merged product PR
      on another repository changed a roadmap document, and 3.7's first cohort
      pass found every actionable repository given the same next action; M4c
      only split it by the kind of planning gap. When the limiting foundation
      is documentation, tests, CI or structure, the next action proposes that
      change: a README section, a first test, a CI proposal for the owner to
      apply, a structure fix. It goes through the same preview, accept and
      dispatch path, with the route chosen by data in `backend/config/` rather
      than code. _(state: planned)_
      `check: pwsh ./tests/Test-KindAwareNextActions.ps1 -FailOnError`
- [ ] **A stale base or a dirty tree is surfaced, not discovered.** Today holds
      repositories for uncommitted changes while the board read them "Ready"
      (Lane 0.22), and a run against a stale or dirty clone fails late or
      leaves the clone dirtier. Before preview and before dispatch, the product
      checks the target clone: uncommitted changes, behind its remote, on a
      branch other than the default, a leftover agent branch. Each condition
      shows on the repository and in the preview with its remedy. A remedy
      that touches nothing the operator owns, such as a fast-forward of a clean
      clone, runs from the console; nothing is ever stashed or discarded
      automatically. _(state: planned)_
      `check: pwsh ./tests/Test-WorkspaceState.ps1 -FailOnError`
- [ ] **Stuck work is detected, not noticed (Lane 0.22).** Each state has a
      limit. A runner heartbeat older than N minutes with approved work
      waiting is stuck, and so is a lane running past its limit, a dispatch
      with no branch after 24 h, an approval that never reached the queue, or
      a scan stuck in one phase. Each surfaces once, on Today, with its remedy
      (start runner, poll GitHub, re-enqueue or discard, cancel and requeue).
      Durations read "27h", never "99293.3s" or "1655m". A lane completes on
      merge evidence, as its trace already states, not through a manual
      Complete button. Observed 2026-09-15: a heartbeat 27.6 h old, a lane
      running 1,655 minutes, a run with no branch or PR six days after
      dispatch. _(state: planned)_
      `check: pwsh ./tests/Test-StuckWork.ps1 -FailOnError`
- [ ] **A run that closes records `completedAt`, the verdict, the vendor and
      usage (from Release 4.0 phase B).** 47 of 51 runs have no `completedAt`,
      so agent time and completion rate read "unmeasured" and per-lane usage
      has nothing to attribute. Every run-close event — finished, failed,
      cancelled, capacity-wait — writes the four fields on the run record and
      the execution event (`Execution.Ledger.ps1`, `Execution.Events.ps1`); a
      close with any of them empty fails the gate by name. Why next: the
      weekly report's failure counts and agent time read these fields.
      _(state: planned)_
      `check: pwsh ./tests/Test-RunCloseFields.ps1 -FailOnError`
- [ ] **[non-blocker] README standardization history is read where it is
      written (Lane 0.22).** Found by the fixture-isolation sweep (2026-09-16).
      The apply step treats the target repository as its workspace, so it
      writes backups and `standardization-history.jsonl` under `output\`
      inside the managed repository. The host reads that history from this
      workspace's `output\`, so an applied change never shows in its history.
      Write both to the workspace output root, and stop writing into the
      managed repository. Why next: those files leave the target clone dirty,
      which then holds the repository from dispatch. _(state: planned)_
      `check: pwsh ./tests/Test-ReadmeStandardizationHistory.ps1 -FailOnError`

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
- **The proof-of-value figures are measured, never manufactured** (added
  2026-10-16). Do not split one change into several PRs, pick trivial edits,
  or relax a readiness rule to move a Release 4.1 count. A rejected proposal
  and a failed run stay in the record and in the report.

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
