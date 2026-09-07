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

### D-006 — Which repository represents external management in the value trial?

- **Asked** 2026-09-05 during the approved Release 3.7 preparation.
- **Question.** Which repository is externally managed? Confirm or correct the archived-ignore Genesys-Telecom-Powershell candidate for the abandoned category as well.
- **Why it is not an agent's call.** External management and abandonment are owner intent; neither follows from an old commit or an xfaith4 remote.
- **Ruling so far (Ben, 2026-09-06) — the question itself stays open.**
  External management is an **intent classification** and must not be inferred
  from repository age, activity, remote ownership or documentation maturity.
  `Genesys-Telecom-Powershell` may remain a provisional abandoned-category
  candidate, but neither abandonment nor external management may be recorded as
  fact without owner intent. **If no repository in the portfolio is
  intentionally externally managed, the trial records that the category has no
  natural cohort member** rather than manufacturing one — an empty category is
  a valid trial outcome, not a gap to be filled.
- **Default if unanswered.** Nine named candidates and one category recorded as
  unrepresented in `evidence/trials/release-3.7/cohort.json`. The trial proceeds
  with nine; no substitution is chosen for conformance.
- **Blocks.** No longer the cohort — the empty-category rule above releases it.
  Only the owner-intent labels themselves still need Ben.

---

## Decided

Move entries here with the decision and its date. Keep the original question
intact — the reasoning is what stops the next agent reopening a settled point.

### D-001 — May a managed roadmap declare dependencies between its items?

- **Asked** 2026-09-04, from [Lane 0.18](../../ROADMAP.md).
- **Question.** Today an item is selected by readiness and value. Should the
  roadmap contract gain a `depends_on` notion, so item 2 can declare that it
  needs item 1 first?
- **Why it was not an agent's call.** It changes what a managed roadmap _is_,
  and the contract in `standards/roadmap` is imposed on every repository in the
  portfolio. That is a product-shape decision, not an implementation detail.
- **Decision (Ben, 2026-09-06).** **Yes — optionally, and dependencies gate
  dispatch eligibility.** An item whose dependencies are not complete is not
  ready for execution regardless of its value score. The first implementation
  covers dependencies **within one repository** and keys on stable roadmap item
  identifiers, never titles or table position. Dependencies must be acyclic.
  Cross-repository dependencies are deferred until there is demonstrated need.
  A roadmap that declares none keeps today's readiness-and-value behaviour
  exactly.
- **What it changes.**
  [`ROADMAP_TEMPLATE.md`](../../standards/roadmap/ROADMAP_TEMPLATE.md) already
  recommends stable `[[M3]]` milestone ids and an inline `(depends: M3)` tag,
  and nothing reads either — the schema has no field and the parser ignores the
  tag. The work is to promote an existing authoring convention into the
  contract, not to invent a notation. Unblocks the ordering item in Lane 0.18
  and supplies the dependency clause of Release 3.8's eligibility check.

### D-002 — Is a repository nested inside another repository its own portfolio entry?

- **Asked** 2026-09-04, found while explaining the 70-versus-72 repository gap.
- **Question.** `custom_SereneHarmonySite` is a git repository living inside
  `SereneHarmony_Site_Starter`, which is also one. The scan counts both. Should
  it, or is the inner one an implementation detail of the outer?
- **Why it was not an agent's call.** Both readings are defensible. Counting
  both is honest about what is on disk; counting one is honest about what is a
  _project_. Which the portfolio should report depends on how you think about
  your own work, not on the code.
- **Decision (Ben, 2026-09-06).** **Not by default.** A nested git repository is
  discovered and reported, but is not an independently managed portfolio entry
  unless it is explicitly classified as one. The portfolio represents managed
  projects, not merely every `.git` boundary present on disk. A nested
  repository therefore carries a visible `nested` classification so it is never
  silently lost, and an explicit opt-in can promote one to independently managed
  when it genuinely has its own lifecycle.
- **What it changes.** `Get-RepoScopeClassification`
  ([`Portfolio.Scope.ps1`](../../backend/modules/portfolio/Portfolio.Scope.ps1))
  gains `nested` beside `vendored` and `archived`. The portfolio total falls by
  one when it lands, so the Release 3.7 trial record must not read that as
  drift. Tracked in Lane 0.12.

### D-003 — Grant the PAT `Checks: Read`, or decline permanently?

- **Asked** 2026-08-10, from [Lane 0.2](../../ROADMAP.md). Restated here because
  it has been open longest and is one answer away from closing.
- **Question.** The token 403s on check-runs and GraphQL `statusCheckRollup`.
  Granting the scope only adds `gh pr checks --watch` detail.
- **Why it was not an agent's call.** It is a permissions posture question about
  a credential outside this repository.
- **Decision (Ben, 2026-09-06).** **Grant `Checks: Read`.** Detailed CI state is
  becoming a first-class input to orchestration, remediation and merge readiness
  rather than optional UI detail. The permission stays read-only and within
  least privilege. `mergeStateStatus` may remain a fallback, but it is no longer
  the primary CI contract wherever exact check-run information is available.
- **What it changes.** Two halves. The grant is an operator action outside this
  repository, batched with the Release 2.9 operator session. The engineering
  half is new: `MergeReadiness.ps1` reads `mergeable_state` from the Pulls API
  today, which is why `BLOCKED` cannot distinguish a pending required check from
  a failed one. Release 3.8's CI-failure evidence collection wants the finer
  signal.

### D-004 — Should the product treat RoadmapOrchestrator as a third dispatch target?

- **Asked** 2026-09-04, from [Lane 0.18](../../ROADMAP.md).
- **Question.** Hand a whole well-formed roadmap to a closed-loop executor
  beside the existing `copilot` and `claude` targets, rather than porting its
  mechanisms into this console piecemeal.
- **Why it was not an agent's call.** It is a direction-of-travel decision about
  two products you own, and it changes what this console is _for_.
- **Decision (Ben, 2026-09-06).** **No.** GitHub Repo Manager is becoming the
  orchestration authority, and a second closed-loop orchestrator beneath it
  would create overlapping ownership of task selection, execution state,
  budgeting, remediation and completion. Reusable mechanisms come across into
  this architecture where useful. If RoadmapOrchestrator is integrated later it
  participates through a **bounded execution contract**, never as a second
  orchestration authority.
- **What it changes.** The Lane 0.18 non-blocker proposing a third
  `dispatchTarget` is withdrawn. Release 3.8's provider-adapter interface is the
  bounded contract this names: an adapter translates packets and events, and
  makes no roadmap, merge or portfolio-priority decisions.

### D-005 — Record whether a repository externalizes its completion history?

- **Asked** 2026-08-08, from [Lane 0.7](../../ROADMAP.md).
- **Question.** A roadmap that archives completed work to a separate file
  reports `completedCount` near zero forever. Nothing distinguishes "history
  archived" from "history deleted". Add an explicit signal to the contract?
- **Why it was not an agent's call.** The lane states the intent as
  **awareness, not enforcement**, and where that line sits is a judgement about
  how much the standard should impose on managed repositories.
- **Decision (Ben, 2026-09-06).** **Yes, as awareness metadata rather than an
  enforcement requirement.** The contract may state that completion history is
  externalized and, where known, where that history lives, so a consumer can
  tell an actively maintained roadmap whose completed work was archived from one
  with no recorded completion history at all. The signal does not require any
  repository to externalize history and does not prescribe an archive format.
  Its purpose is semantic accuracy for portfolio reporting, progress calculation
  and future automation.
- **What it changes.** An optional field in
  [`roadmap-contract.schema.json`](../../standards/roadmap/roadmap-contract.schema.json)
  set from a pointer link in the roadmap and surfaced in the audit payload; the
  `spec/roadmap-contract` mirror moves with it. Tracked in Lane 0.7.

### D-007 — How long may a lane sit before the board calls it stuck?

- **Asked** 2026-09-06, from [Lane 0.17](../../ROADMAP.md), while giving the
  Dispatch Board observed run state.
- **Question.** A lane's `stalled` flag needs a threshold per non-terminal
  verdict. The shipped defaults are queued **15 minutes**, working **90
  minutes**, awaiting-review **24 hours**. Are those the right patience?
- **Why it was not an agent's call.** It is a tolerance judgement, not a
  derivable fact: it depends on how long your Copilot agents actually take and
  how quickly you want to be told something is wrong. Set too low it cries
  wolf, too high it is the silence the lane already had.
- **Decision (Ben, 2026-09-06).** **Keep the shipped defaults as bootstrap
  thresholds.** They are initial operational heuristics, not permanent product
  constants — already configurable through `-PatienceMinutes`
  ([`Execution.LaneObservation.ps1`](../../backend/modules/execution/Execution.LaneObservation.ps1)),
  and every verdict ships the threshold that produced it, so a wrong value is
  visible rather than mysterious. There is little value in delaying the feature
  to predict ideal values. As real Copilot, Codex and Claude execution history
  accumulates, the governor may derive provider- and task-specific expectations
  from observed duration; until that evidence exists these remain the fallback.
  **A stalled verdict is an observability signal, never an automatic failure or
  cancellation.**

### D-008 — Should Dispatch really dispatch from every surface that previews a task?

- **Asked** 2026-09-06, from [Lane 0.17](../../ROADMAP.md), as a consequence of
  the D-010 decision below.
- **Question.** `CopilotTaskPreviewModal` is opened from the Dispatch Board,
  the Work Queue and Operations. `Dashboard.tsx` passes the dispatch callback
  unconditionally, so the button now queues real agent work and spends quota
  from all three — where before it only wrote a ledger row.
- **Why it was not an agent's call.** It is a question about which surfaces
  should be able to spend agent budget, which is an operating-posture choice.
- **Decision (Ben, 2026-09-06).** **No — dispatch authority belongs to the
  Dispatch Board.** Work Queue and Operations may preview the same well-formed
  task and expose its readiness, estimated resource requirement and intended
  provider, but previewing a task must not implicitly grant authority to consume
  agent quota. The Dispatch Board is the deliberate transition from prepared
  work to execution; other surfaces navigate the operator to that task on the
  board rather than independently invoking the dispatch endpoint. This also
  gives the capacity governor, provider selection, budget impact and final
  execution confirmation **one** consistent surface to be shown on before work
  begins.
- **What it changes.** This **reverses the default shipped the same day** under
  D-010: [`Dashboard.tsx`](../../frontend/components/Dashboard.tsx) passes
  `onDispatch` to the modal unconditionally today. Tracked in Lane 0.17 as its
  own item, with a component test proving the button is absent from the two
  preview-only surfaces.

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
