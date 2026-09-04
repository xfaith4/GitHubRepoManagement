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

## Decided

Move entries here with the decision and its date. Keep the original question
intact — the reasoning is what stops the next agent reopening a settled point.

Nothing has been decided yet.
