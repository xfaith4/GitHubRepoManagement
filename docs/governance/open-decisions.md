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
  direction, or risk appetite, add a row here and keep going on the parts that
  do not depend on it. Do **not** invent an answer and do not stall the whole
  task waiting for one. State the default you proceeded under so a later reader
  knows what happens if the question is never answered.

Each entry carries: what is being asked, why it cannot be settled from the code,
what happens by default if it is never answered, and what it blocks.

**Before adding a row, apply this test.** Ask whether the answer would be the
same for every person who installs this product. If it would, it belongs here.
If it differs per machine, per account, or per month — _is that tool installed,
is that account funded, which plan is it on_ — it is **not a decision**, it is
**state to be detected** and shown in the setup wizard and Settings, the way
`git`, the GitHub CLI and the GitHub token already are. "It cannot be settled
from the code" is not sufficient grounds for a row: an agent's own machine
cannot settle what is on someone else's, and asking the owner still produces an
answer that is wrong for every other installation. Two entries were filed
against that mistaken test and had to be withdrawn; see
[Withdrawn](#withdrawn).

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

### D-012 — What may an agent touch, and may it edit workflow files?

- **Asked** 2026-09-06, from
  [Release 3.8 milestone 1](../../ROADMAP.md) and the spec's _Permission
  envelope_.
- **Question.** The spec's example envelope is `filesystemWrite true`,
  `shell true`, `network false`, `githubWrite false`, with `forbiddenPaths`
  of `.github/workflows/**`. Confirm it, and rule on whether an agent may
  edit workflow files. The superseded July design said yes and flagged it.
- **Why it is not an agent's call.** It is the security posture of every
  agent run, and the workflow question is self-referential: an agent that can
  edit `.github/workflows/**` can edit the CI that reviews its own work.
- **Default if unanswered.** The config ships the spec's example marked
  provisional and every work packet carries it, so the envelope is visible on
  each run. **No adapter enforces it** — nothing maps it onto a provider's
  own permission flags until this is decided.
- **Blocks.** The enforcement half of packet H38-05 and the Codex sandbox
  mapping in H38-16. The envelope still travels; it just does not yet bind.

### D-021 — Which foundations do not apply to which kinds?

- **Asked** 2026-09-14, building 3.7 M4b. Applicability is per kind
  (steering Rung 1: "modest repositories are not graded against enterprise
  standards"); the mechanism, the check and the reason rendering are M4b's.
  Which rows the table carries is product policy.
- **Question.** Beyond the Release 3.6 starting set (minimal → planning;
  externally-managed → planning, structure; archived → planning, structure,
  intentional-engineering), which domains do not apply to `application`,
  `library`, `firmware`, `experiment`, `tooling`, `script-collection`,
  `service`? Steering names two examples — a script collection is not
  missing a test suite; a firmware sketch is not missing a Dockerfile — but
  both live in `intentional-engineering`'s sub-areas (test, operational),
  and applicability is per domain, not per sub-area. Marking the whole
  domain not-applicable for those kinds says more than the sentence does.
- **Why it is not an agent's call.** Every row changes which repositories the
  product tells Ben need nothing, and steering section 6 forbids adding a
  row to make one repository come out right.
- **Default proceeded under (2026-09-14).** One row: `experiment` → planning
  not applicable ("an experiment plans by trying; a roadmap is optional until
  it has a direction"), fixture-only, recorded in the kind's
  `applicabilityBasis`. Every other new kind keeps every scored domain
  applicable. `intentional-engineering` stays `not-scored` for all of them;
  its per-kind sub-area applicability is decided when it is scored.
- **Blocks.** Nothing. M4b's check holds whatever the table says; a row is a
  data change with a `modelVersion` bump.

### D-022 — Is the console four destinations with one vocabulary?

- **Asked** 2026-09-15, from a UX assessment of build `fa18be4` made through
  the UI alone. Its defects are Lane 0.22; its structural recommendations are
  this decision, because each changes what the product is rather than fixing
  what it shows.
- **What the assessor saw.** Seven tabs (Today, Grid, Insights, Operations,
  Doc Readiness, Dispatch Board, Dependencies) reflecting internal pipelines,
  not operator questions; several answering the same question, none fully.
  Four status vocabularies (Today's three conclusions; Operations' six
  lifecycle labels; Doc Readiness's Needs Docs / dispatch-ready; Dispatch's
  Ready / Blocked / Idle / Complete) plus L0–L4 on top of all of them, with
  Help admitting three meanings of "ready" and two of "blocked". Three or four
  ways to start agent work. The one system-level blocker, a runner down 27 h,
  was absent from Today and reachable only through a header popover and a tab
  labelled read-only analytics. Two lists of the same repositories (Grid,
  Operations) with different columns, and a drill-down reachable from one.
- **Proposed.**
  1. **Four destinations:** Today (what needs me, what is stuck, what is next),
     Portfolio (Grid + Operations + Doc Readiness as a filter + Dependencies as
     a column), Work (Dispatch Board + packaged work + agent runs + trace +
     "Execution right now"), Trends (Insights without the execution panels,
     keeping Leverage). Utilities: a System drawer (runner, scanner, index
     freshness, GitHub auth, providers, automation policy), Settings, Help, the
     Local/GitHub source.
  2. **One repository lifecycle** — Needs plan → Plan needs approval → Ready for
     agents → Agent working → In review → Healthy / Archived — with orthogonal
     flags (Uncommitted changes, CI failing, Behind remote, Docs gap). L-levels
     become a detail score, not a headline. Hold codes stay as secondary tags.
  3. **Today as an exception inbox:** a system banner shown only when something
     is abnormal; decisions grouped by type with bulk actions; actions only the
     operator can take; stuck work with remedies; the next five eligible items;
     a digest; everything else collapsed to counts. The KPI cards become
     Decisions waiting · Stuck · Ready for agents.
  4. **One Work pipeline:** Proposed → Approved → Queued → Running → In review →
     Done, plus a Needs-attention lane; the trace as each card's detail and its
     broken-link diagnosis as the card's status; one "Send to agent" action with
     a preview and provider choice; lanes retired as an operator concept unless
     the lane count is something the operator tunes.
  5. **Batched roadmap proposals:** the product generates roadmap drafts and
     checklist conversions in the background, and Today offers "49 proposals
     ready for review" with a diff queue and keyboard approve/reject.
- **Why it is not an agent's call.** (1) and (4) replace surfaces the operator
  works in daily. (2) renames the three conclusions the steering contract
  defines, so it is a steering change. (5) calls AI routes without the operator
  in the loop, against the no-one-click-egress ruling of 2026-09-14, and
  spends provider budget by policy. Steering's product lens says every
  remaining item is ranked on operational efficiency; this is the largest
  such item there is, and its shape is the owner's.
- **Default proceeded under (2026-09-15).** None of the five. Lane 0.22 fixes
  the defects inside the current structure, so every surface at least tells
  the truth before any of them is merged or removed. Lane 0.21 does the same
  for load time. Where a Lane 0.22 item touches a surface this decision might
  remove (the Dependencies tab, the Doc Readiness buttons), it makes the
  smallest honest change and does not restructure.
- **Blocks.** Nothing agent-executable. Rung 2 work that builds new surfaces
  waits on it.

---

## Withdrawn

A question belongs here when it should never have been asked of the owner —
not because it was answered, but because it was the wrong kind of question.
The record stays so the next agent can recognise the shape and not re-file it.

**The shape:** a decision register holds questions whose answer is the same for
everyone who installs this product — risk posture, security posture, product
behaviour. It must not hold questions whose answer differs per installation and
changes over time. _"Do you have an account with this provider?"_ has a
different answer for every operator, and a different answer for the same
operator next month. Writing that answer into a governance file, or into a
committed config file, makes one machine's state a fact about the product.

**Where those questions go instead:** they are **detected at runtime** and
surfaced in the setup wizard and Settings, exactly as `git`, the GitHub CLI and
the GitHub token already are by `GET /setup/prerequisites`. The repository
records only what is true of the repository — `providers.<name>.supported`,
meaning a conforming adapter exists here, which CI can verify.

### D-014 — Which Copilot billing mode does this account use? _(withdrawn 2026-09-07)_

- **Asked** 2026-09-06, from
  [Release 3.8 milestone 2](../../ROADMAP.md) and the spec's _GitHub Copilot
  adapter_.
- **Question, as originally put.** Does this account meter agent work as AI
  credits, or under the legacy premium-request allowance?
- **Why it was withdrawn.** Billing mode is a property of whichever GitHub
  account is signed in, so there is no single answer to record. The original
  entry said as much — _"the answer is on the account, not in the repo"_ — and
  then filed it as an owner decision anyway, which is the contradiction.
- **What replaces it.** The Copilot adapter reports billing mode as observed,
  or `unknown` with `confidence: "none"` when it cannot tell, and routing
  treats Copilot as **eligible but unmeasured** until an observation arrives.
  That was already the "default if unanswered", and it is simply the behaviour
  now — a capacity record whose confidence is honest needs no ruling.
- **Still genuinely open:** nothing. The spec's ban on assuming the generation
  is satisfied by reporting `unknown` rather than by asking the owner.

### D-015 — Is Codex available on the operator's machine? _(withdrawn 2026-09-07)_

- **Asked** 2026-09-06, from
  [Release 3.8 milestone 3](../../ROADMAP.md).
- **Question, as originally put.** Is the `codex` CLI installed on the
  operator's machine with an account that has capacity — and will two
  transcripts be recorded so its adapter can be gated offline?
- **Why it was withdrawn.** Two unrelated questions were fused into one. The
  first — _is it installed and funded_ — is per-installation state that must be
  detected, never decided; if ten people run this product, the committed answer
  is wrong for most of them. The second — _will transcripts be recorded_ — was
  already dissolved by rule R12: every fixture is authored synthetically, so no
  packet waits on a transcript and none spends provider quota to obtain one.
  Nothing was left to decide once both halves were examined.
- **What replaces it.** `Test-AgentProviderAvailability` probes the PATH and
  reports per provider, feeding `GET /setup/prerequisites` (so the setup wizard
  shows it on first launch) and a Settings section where the operator may opt a
  provider **out**. Authentication is deliberately **not** probed: proving an
  account works means spending its quota, so it is learned from the first real
  run instead. The Codex adapter is built regardless — it costs an operator
  without Codex nothing, and the router simply never selects an unavailable
  provider.
- **Still genuinely open:** nothing. H38-16 is unblocked and H38-15b implements
  the detection.

---

## Decided

Move entries here with the decision and its date. Keep the original question
intact — the reasoning is what stops the next agent reopening a settled point.

### D-011 — Are the capacity reserves right, and what does a task cost?

- **Asked** 2026-09-06, from
  [Release 3.8 milestone 2](../../ROADMAP.md) and the
  [execution spec](Agent-Execution-Governance.md)'s _Capacity reserves_.
- **Question.** The spec proposes holding back **15%** of a short window and
  **20%** of a weekly window, with remediation drawing from inside the weekly
  reserve. Are those the right numbers? And what should a single task be
  assumed to consume, which the spec does not say at all?
- **Why it is not an agent's call.** Reserve size is the risk posture of the
  whole release. Too high starves ordinary work of capacity that was never
  going to be needed; too low exhausts a subscription and leaves nothing for
  the remediation that a failure will demand. Neither number is derivable
  until real consumption has been observed.
- **Decision** 2026-09-07, Ben. **The reserves stand exactly as the spec wrote
  them: 15% of a short window, 20% of a weekly window, remediation drawing from
  inside the weekly reserve.** They are no longer provisional — the
  `provisional` flag comes off `reserves` in `agent-providers.json`, because
  these are now a ruling rather than an assumption.
- **Decision, second half.** The per-task consumption estimate **stays `0.05`
  and stays provisional.** It was never ruled on, only left at its default,
  and it is the one number nobody can know before real runs report usage.
- **The consequence, which is not obvious.** Enforcement does **not** turn on.
  A reserve can only refuse work if you know what a task costs, so
  `enforced` requires **both** `reserves.provisional` and
  `estimates.provisional` to be clear — not `reserves` alone, as H38-09 was
  originally written. Clearing one flag while the cost model is still a guess
  would have silently started refusing dispatches on an unmeasured number.
  Capacity verdicts are therefore computed and recorded, and refuse nobody: a
  wrong estimate can look wrong, but it cannot block work.
- **What lifts the remaining flag.** Observed consumption, not another ruling.
  Once completed runs have reported real usage the estimate stops being a
  guess, and the flag comes off on evidence.
- **Blocks.** Nothing. It gated the enforcement half of the capacity verdict;
  that half now waits on measurement instead.

### D-013 — What are the provider ranking weights, and how is a tie broken?

- **Asked** 2026-09-06, from
  [Release 3.8 milestone 3](../../ROADMAP.md) and the
  [execution spec](Agent-Execution-Governance.md)'s _Provider selection_,
  which says only that "the exact scoring weights are configuration" and
  names no tie rule at all.
- **Question.** When more than one provider is eligible for a task, the
  router scores each and takes the highest. Eight factors feed that sum:
  `suitability`, `usableCapacity`, `history`, `fitsWindow`, `sessionReuse`
  and `timeToReset` count for it, `estimatedConsumption` and
  `recentFailureRate` count against it. What weight does each carry, and what
  happens when two providers score exactly the same?
- **Why it was not an agent's call.** The spec pushes the weights to
  configuration precisely because they encode preference rather than fact.
  Nothing in the code says whether remaining capacity should outrank past
  success on a repository, and no tie rule is neutral — every one of them
  quietly prefers some provider.
- **Decision (Ben, 2026-09-07).** **Keep all eight weights as they ship, for
  the first run.** Every positive factor carries `1` and both negative
  factors carry `-1`. Tuning a scoring function against no observed execution
  history produces numbers nobody can later explain or defend, and with Codex
  disabled the router is choosing between Claude and Copilot, which
  eligibility and measured capacity separate long before the weights matter.
  These are a first-run baseline to revisit against real routing evidence,
  in the same spirit as the D-007 patience thresholds.
- **Tie-break, adopted with the same decision.** `nearest-reset-first`: among
  tied candidates the one whose nearest window resets soonest wins, a
  candidate with no known reset time sorts last, and alphabetical order
  applies only when no tied candidate has one. The reasoning is
  use-it-or-lose-it. Allowance that refills in two hours is worth spending
  now, because unspent it simply disappears, which serves the governor's
  stated objective of conserving scarce capacity. This also **corrects the
  two options originally offered with the question**: plain `alphabetical`
  silently makes Claude the permanent winner of every tie, and "nearest reset
  last" had the conservation argument backwards.
- **What it changes.** `backend/config/agent-providers.json` carries the
  weights and `"tieBreak": "nearest-reset-first"` without a `provisional`
  flag, since they are now ruled on rather than assumed. More consequentially
  it **turns provider routing on**: the config ships
  `dispatch.autoEnabled = false` with a default target of `claude` precisely
  so that nothing could write a dispatch target the runner was unable to
  claim, and packet H38-17 flips both once the router exists. Until this
  decision, every board dispatch and every remediation entry would have run
  on Claude regardless of what else was eligible.

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

---

### D-016 — Should `Add-OperatorVerification.ps1` append to the operator queue?

- **Asked** 2026-09-13, while applying the roadmap vocabulary rewrite.
- **Question.** ROADMAP §3 and `docs/governance/operator-queue.md` both say
  ratchets are recorded in the queue "via `scripts/Add-OperatorVerification.ps1`".
  The script writes only `evidence/operator-verification-log.jsonl`; it has no
  queue mode. The rewrite's six steps do not include changing it.
- **Why it was not an agent's call.** The queue's row shape (Id / Needs /
  Action / Ratchets) is Ben's, and whether a done row is deleted by the script
  or by hand decides who owns that file.
- **Decision (Ben, 2026-09-13).** **Yes — the script appends; it never
  deletes.** Two governance documents describing an end state the script does
  not implement is the same silent drift the structure policy forbids between
  the audit script and `.gitignore`; leaving it was the worst of the three
  options. Appending a Ratchets row does not transfer ownership of the queue:
  the row is a record of something a person verified, and removing a done row
  remains a human act, in the same spirit as D-009 (show the verdict, the
  operator clicks). The JSONL log stays the source of truth.
- **What it changes.** `Add-OperatorVerification.ps1` gains a queue write
  after the JSONL append. It is **idempotent on Id** — re-running for a
  verification already in the queue changes nothing — and it writes the log
  first, so a failed queue edit leaves the log complete rather than the
  reverse. It has no delete path. ROADMAP §3 and `operator-queue.md` need no
  change; they now describe what exists.
- **Blocks.** Nothing.

### D-017 — Where does the "four kinds of work" taxonomy live?

- **Asked** 2026-09-13, while applying the roadmap vocabulary rewrite.
- **Question.** R022 bounds the Current Status preamble to 25 lines. After the
  dated records moved to `CHANGELOG.md` the preamble was still 34 lines, all of
  it the 19-line "four kinds of work" list. It was moved verbatim to §1 ("What
  This Document Is"), which the rewrite did not name. Its kinds 2 and 3
  (human verification; decisions) now have their own ledgers — the operator
  queue and this file — so the list may be redundant rather than misplaced.
- **Why it was not an agent's call.** Deleting a taxonomy Ben wrote is his
  call; relocating it kept the text intact.
- **Decision (Ben, 2026-09-13).** **It moves to governance; §1 keeps one
  sentence.** The roadmap follows a contract imposed on every repository in
  the portfolio, and that contract should not carry a 19-line description of
  how this one repository organises its work. An agent reading the roadmap
  needs only the kind the roadmap tracks. Kinds 2 and 3 already have ledgers,
  so the list was mostly pointing elsewhere; the full text is worth keeping
  because it is the one place all four kinds and their homes are named
  together.
- **What it changes.** The list moves verbatim to
  `docs/governance/kinds-of-work.md` beside `operator-queue.md`, and each kind
  links to its ledger. ROADMAP §1 replaces it with a single sentence naming
  the four kinds and linking that file. The preamble stays within R022 with
  room to spare. If kinds 1 or 4 have no home of their own, the governance
  file is their pointer until they do.
- **Blocks.** Nothing.

### D-018 — Convert the existing `(state: …)` markers to the new vocabulary?

- **Asked** 2026-09-13, while applying the roadmap vocabulary rewrite.
- **Question.** §3 now defines `planned` / `built` / `verified` only, but ~60
  open milestones still carry `scaffolded`, `smoke-tested` and the other
  retired states in their `_(state: …)_` clause, and Release 3.6's six
  milestones are all `smoke-tested` under a release in `validation`. By the
  new rule a milestone whose check is green in CI is `verified`, which is
  `[x]`, which means it archives in the same PR — a sweep the rewrite's six
  steps did not ask for and R020 does not enforce (it checks for `check:`
  only). Nothing was converted.
- **Why it was not an agent's call.** Marking 3.6 `verified` closes the release;
  its field proof would move wholesale to OQ-1. That is the rewrite's intent,
  but it is a release closure, not a rename.
- **Decision (Ben, 2026-09-13).** **Convert everything now, deliberately, in
  two PRs.** The default — each marker converts when next touched, with R020
  escalating to an error — hands the closure of Release 3.6 to whichever agent
  trips the rule first. That is the exact failure this file exists to prevent:
  a decision made by default, by whoever touches the code next.
  **Conversion is by evidence, not by name.** A milestone whose `check:` is
  green in CI is `verified`. A milestone with a `check:` that is not green, or
  carrying `scaffolded` / `smoke-tested` with no check, is `built`. A milestone
  with no implementation is `planned`. The retired names carry no information
  the check does not.
  **`verified` means the CI check is green.** Operator verification is a
  separate fact recorded in the operator queue and the JSONL log, never
  implied by `verified` or by archiving. An agent must neither refuse to
  convert on the grounds that `verified` needs Windows/WSL proof, nor read an
  archived milestone as operator sign-off.
- **What it changes.**
  **PR 1 — mechanical sweep.** Every open marker outside Release 3.6 converts
  by the rule above. The same PR promotes R020 from warning to error, since
  after the sweep nothing is left to warn about; promoting it before the
  sweep would have blocked the sweep itself.
  **PR 2 — closure of Release 3.6, titled as such.** The six milestones move
  to `verified`, archive per the rewrite, and their field proof moves to
  OQ-1. The PR adds a tracked `evidence/verified/release-3.6/` entry — the
  structure policy carves that path out precisely so a closure is reviewable
  in the PR rather than inferred from a state flip. It is not merged by a
  watch on green; Ben reviews it.
- **Blocks.** Nothing. R020's promotion to error waits on PR 1.

### D-019 — Which changes may merge on a green check, and which wait for Ben?

- **Asked** 2026-09-14, evaluating `docs/governance/steering.md` against
  `CLAUDE.md`. #295 (3.7 M4a) had just merged on green; it changed what the
  product says about every repository and added a CI gate.
- **Question.** `CLAUDE.md` said the monitor-to-green-then-merge loop was
  durably authorized for this repository. Steering contract 10 says nothing
  that changes governance, CI, or what the product claims about itself merges
  on a green light alone. Both cannot hold.
- **Why it was not an agent's call.** It decides who carries review load, and
  it is self-referential: an agent that may merge a change to the gates on
  green is reviewing its own work.
- **Decision (Ben, 2026-09-14).** **Steering contract 10 governs; `CLAUDE.md`
  is narrowed to match.** Pure engineering with a green check merges on green.
  Anything touching `backend/config/`, a CI gate, `docs/governance/`, or what
  a verdict says about a repository waits for Ben's review. The review load is
  Ben's to carry; that is what the contract costs. #295 stays — the kind work
  is sound; the breach was the merge path, not the content — and its
  follow-through (first item in Current focus) brings it under contract 6.
- **What it changes.** `CLAUDE.md` and `AGENTS.md` state the boundary. A PR
  that crosses it is opened, left for review, and named as waiting in the
  handoff. #294 (Release 3.6 closure) and PR 0 (this decision, the steering
  document, the re-sequenced Current focus and the M4b/M4c property checks)
  are reviewed together.
- **Blocks.** Nothing.

### D-020 — Should curation state gate the lifecycle model as it gates conclusions?

- **Asked** 2026-09-14, from the lifecycle/conclusion consistency contract
  (#298). Its one explained disagreement is Genesys-Telecom-Powershell:
  `lifecycleState = needs-roadmap-repair`, `conclusion = appropriate-as-is`,
  evidence `kind rule: curationState=archived-ignore`. The conclusion model
  reads curation; `_ResolveLifecycleState` never does.
- **Question.** The pair is *explained*, but the lifecycle's next action still
  sends an operator to Roadmap Repair on a repository Ben curated
  `archived-ignore`. Is that an accepted asymmetry or a wrong next action?
- **Why it is not an agent's call.** Curation is the owner's declared intent
  (contract 7); whether it silences the lifecycle model's action is a product
  stance on what "archived-ignore" means, not something the code can settle.
- **Decision (Ben, 2026-09-14).** **A wrong next action, not an accepted
  asymmetry.** Default **yes**: `archived-ignore` resolves to a distinct
  curated-out lifecycle state with no next action, so the two models agree by
  construction and the operator is never sent to repair a repository they
  chose to leave alone.
- **What it changes.** `_ResolveLifecycleState` gains a curation gate right
  after `archived`; the index writer applies the same state through the
  resolver's own helper because curation is joined at index build and the
  host reuses cached assessments for unchanged repositories. The assessment
  vocabulary, the consistency table (`curated-out` agrees with
  appropriate-as-is), the report module, the console's lifecycle styles, and
  the reference doc carry the new state. Implemented stacked on 3.7 M4b.
- **Blocks.** Nothing.
