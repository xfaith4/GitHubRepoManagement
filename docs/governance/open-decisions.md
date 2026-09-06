# Open decisions — Ben's call, not an agent's

Questions an agent surfaced, judged that it should **not** answer alone, and
parked here. Every one of these blocks or shapes real work.

**Why this file exists.** These used to be raised in a chat message and lost
when the session moved on. A decision mentioned once and never recorded is a
decision that gets made by default, usually by whichever agent touches the code
next. This is the durable place for them.

## How to use it

- **Ben:** answer the ones that matter. Record the answer inline under
  **Decision**, with the date. Then move the row to
  [Decided](#decided) and let the linked work proceed.
- **Agents:** when you find a question that turns on preference, product
  direction, risk appetite, or anything outside the repository, add a row here
  and keep going on the parts that do not depend on it. Do **not** invent an
  answer and do not stall the whole task waiting for one. State the default you
  proceeded under so a later reader knows what happens if the question is never
  answered.

Each entry carries: what is being asked, why it cannot be settled from the code,
what happens by default if it is never answered, and what it blocks.

---

## Open

### D-001 — May a managed roadmap declare dependencies between its items?

- **Asked** 2026-09-04, from [Lane 0.18](../../ROADMAP.md).
- **Question.** Today an item is selected by readiness and value. Should the
  roadmap contract gain a `depends_on` notion, so item 2 can declare that it
  needs item 1 first?
- **Why it is not an agent's call.** It changes what a managed roadmap _is_,
  and the contract in `standards/roadmap` is imposed on every repository in the
  portfolio. That is a product-shape decision, not an implementation detail.
- **Default if unanswered.** No dependency ordering. The operator keeps
  re-picking the next item by hand after each merge, and the sequencing item in
  Lane 0.18 stays blocked.
- **Blocks.** "Order work inside one repository's roadmap" (Lane 0.18), which is
  otherwise the one piece of RoadmapOrchestrator that transfers as code.

### D-002 — Is a repository nested inside another repository its own portfolio entry?

- **Asked** 2026-09-04, found while explaining the 70-versus-72 repository gap.
- **Question.** `custom_SereneHarmonySite` is a git repository living inside
  `SereneHarmony_Site_Starter`, which is also one. The scan counts both. Should
  it, or is the inner one an implementation detail of the outer?
- **Why it is not an agent's call.** Both readings are defensible. Counting both
  is honest about what is on disk; counting one is honest about what is a
  _project_. Which the portfolio should report depends on how you think about
  your own work, not on the code.
- **Default if unanswered.** Both are counted, which is current behaviour and is
  internally consistent. The portfolio total stays 72 rather than 71.
- **Blocks.** Nothing today. It decides whether nested repositories eventually
  get a scope classification like `vendored` and `archived` already have.

### D-003 — Grant the PAT `Checks: Read`, or decline permanently?

- **Asked** 2026-08-10, from [Lane 0.2](../../ROADMAP.md). Restated here because
  it has been open longest and is one answer away from closing.
- **Question.** The token 403s on check-runs and GraphQL `statusCheckRollup`.
  Granting the scope only adds `gh pr checks --watch` detail.
- **Why it is not an agent's call.** It is a permissions posture question about
  a credential outside this repository.
- **Default if unanswered.** The `mergeStateStatus` proxy remains the contract.
  It works, and has merged real pull requests through required-check branch
  protection.
- **Blocks.** Nothing. Under a minimal-permissions policy, "decline
  permanently" is a legitimate and final answer.

### D-004 — Should the product treat RoadmapOrchestrator as a third dispatch target?

- **Asked** 2026-09-04, from [Lane 0.18](../../ROADMAP.md).
- **Question.** Hand a whole well-formed roadmap to a closed-loop executor
  beside the existing `copilot` and `claude` targets, rather than porting its
  mechanisms into this console piecemeal.
- **Why it is not an agent's call.** It is a direction-of-travel decision about
  two products you own, and it changes what this console is _for_.
- **Default if unanswered.** The four Lane 0.18 items get built here
  individually, and the other repository stays a separate tool.
- **Blocks.** Nothing immediately. It should be settled before the Lane 0.18
  items are built, because it changes whether they are worth building.

### D-005 — Record whether a repository externalizes its completion history?

- **Asked** 2026-08-08, from [Lane 0.7](../../ROADMAP.md).
- **Question.** A roadmap that archives completed work to a separate file
  reports `completedCount` near zero forever. Nothing distinguishes "history
  archived" from "history deleted". Add an explicit signal to the contract?
- **Why it is not an agent's call.** The lane states the intent as **awareness,
  not enforcement**, and where that line sits is a judgement about how much the
  standard should impose on managed repositories.
- **Default if unanswered.** No signal. Nothing reads `completedCount` as
  progress today, so nothing breaks, but any future consumer that does would
  read a well-kept split repository as inert.
- **Blocks.** Nothing today. It is a latent trap for a future consumer.

---

### D-006 — Which repository represents external management in the value trial?

- **Asked** 2026-09-05 during the approved Release 3.7 preparation.
- **Question.** Which repository is externally managed? Confirm or correct the archived-ignore Genesys-Telecom-Powershell candidate for the abandoned category as well.
- **Why it is not an agent's call.** External management and abandonment are owner intent; neither follows from an old commit or an xfaith4 remote.
- **Default if unanswered.** Nine provisional named candidates and one unfilled external-management slot in `evidence/trials/release-3.7/cohort.json`; no substitution chosen for conformance and no measured execution claimed.
- **Blocks.** Final ten-repository cohort and measured Release 3.7 trial; consistency fixes and validation continue.

### D-007 — How long may a lane sit before the board calls it stuck?

- **Asked** 2026-09-06, from [Lane 0.17](../../ROADMAP.md), while giving the
  Dispatch Board observed run state.
- **Question.** A lane's `stalled` flag needs a threshold per non-terminal
  verdict. The shipped defaults are queued **15 minutes**, working **90
  minutes**, awaiting-review **24 hours**. Are those the right patience?
- **Why it is not an agent's call.** It is a tolerance judgement, not a
  derivable fact: it depends on how long your Copilot agents actually take and
  how quickly you want to be told something is wrong. Set too low it cries
  wolf, too high it is the silence the lane already had.
- **Default if unanswered.** The three values above, in
  `$script:LaneObservationDefaultPatienceMinutes`
  ([`Execution.LaneObservation.ps1`](../../backend/modules/execution/Execution.LaneObservation.ps1)).
  They are a parameter (`-PatienceMinutes`), not a constant, so tuning them is
  a one-line change and needs no redesign. Every verdict ships the threshold
  that produced it, so a wrong value is visible rather than mysterious.
- **Blocks.** Nothing. The board is useful at any of these values; only the
  false-positive rate changes.

### D-008 — Should Dispatch really dispatch from every surface that previews a task?

- **Asked** 2026-09-06, from [Lane 0.17](../../ROADMAP.md), as a consequence of
  the D-010 decision below.
- **Question.** `CopilotTaskPreviewModal` is opened from the Dispatch Board,
  the Work Queue and Operations. `Dashboard.tsx` passes the dispatch callback
  unconditionally, so the button now queues real agent work and spends quota
  from all three — where before it only wrote a ledger row.
- **Why it is not an agent's call.** It is a question about which surfaces
  should be able to spend agent budget, which is an operating-posture choice.
- **Default if unanswered.** All three can dispatch. The runner-presence gate
  and the full prompt preview stand in front of the button everywhere, and the
  modal is the confirm step by construction, so the exposure is the same one
  the Dispatch Board already accepted.
- **Blocks.** Nothing. Restricting it later is one conditional on the callback.

---

## Decided

Move entries here with the decision and its date. Keep the original question
intact — the reasoning is what stops the next agent reopening a settled point.

### D-009 — When an observed run reaches a terminal state, should the lane clear itself?

- **Asked** 2026-09-06, from [Lane 0.17](../../ROADMAP.md).
- **Question.** Once the board can observe that a run's PR merged, should a
  background pass release the lane and write a `completed (observed)` history
  record, or should it show the verdict and leave the click to the operator?
- **Why it was not an agent's call.** It decides whether the ledger is
  operator-owned state or derived state — a different product, not a different
  implementation.
- **Decision (Ben, 2026-09-06).** **Show the verdict; the operator still
  clicks.** The card names what happened ("PR #18 merged") and highlights the
  action that fits, but nothing mutates lane state behind the operator. A run
  closed without merging still needs a human to decide retry versus drop.

### D-010 — Should the Dispatch Board's Dispatch button really dispatch?

- **Asked** 2026-09-06, from [Lane 0.17](../../ROADMAP.md).
- **Question.** Closing the "Running is only bookkeeping" gap needed a run id
  that resolves to something. Either the board keeps writing ledger rows and
  only observes runs dispatched elsewhere, or its own button queues real work
  through the gated release-dispatch route.
- **Why it was not an agent's call.** The second option makes every click spend
  agent quota and create a GitHub task — an outward-facing, costly action.
- **Decision (Ben, 2026-09-06).** **Make Dispatch really dispatch.** The
  previewed prompt goes to `POST /api/roadmap/dispatch/execute` behind Release
  3.1's runner-presence gate, and the returned run id binds to the lane. The
  board is the dispatcher, and its lanes hold real runs.
