# GITHUBREPOMANAGEMENT — agent operating contract

> **Revision 2026-09-18 — governed execution alignment.** This revision aligns
> agent conduct with `docs/governance/steering.md` and the active execution
> roadmap. It separates verified implementation from integrated delivery,
> replaces implicit green-to-merge authority with explicit execution posture,
> binds autonomous work to a versioned mandate, and reserves lifecycle
> transitions for deterministic orchestration.

This is the canonical, model-agnostic operating contract for every agent or
tool working in this repository. `CLAUDE.md` and
`.github/copilot-instructions.md` may add provider mechanics, but they may not
restate, weaken, or widen this contract. A provider-specific instruction that
conflicts with this file is invalid.

## Authority and document roles

The governing documents have different jobs:

1. [`docs/governance/steering.md`](docs/governance/steering.md) defines product
   purpose, invariants, proof, owner-reserved decisions, and forbidden actions.
2. [`ROADMAP.md`](ROADMAP.md) defines approved work, ordering, dependencies,
   acceptance criteria, checks, and product-maturity boundaries.
3. An active execution mandate defines the bounded actions authorized for one
   repository, plan fingerprint, phase, and set of work units.
4. This file defines how work is performed in this repository.
5. Provider overlays define only provider-specific invocation, state, and
   result-handling mechanics.

A lower layer may narrow authority but never widen it. An execution mandate
cannot override Steering, branch protection, repository policy, or the
owner-review classes below. No prior successful action implies authority for a
later one.

Read in this order before modifying anything:

1. Steering.
2. This file.
3. The active roadmap and, when an item appears absent, completed-release
   history.
4. The active mandate and WorkPacket, when execution is orchestrated.
5. Current repository, worktree, branch, PR, CI, cancellation, and mandate
   state.

Revalidate the premise of any queued task, scheduled continuation, handoff, or
old prompt before acting. Stale instructions do not become authority because
they were once correct.

## What this product is

GitHub Repo Management is a portfolio intelligence and execution console for
80+ repositories. It indexes, assesses, explains, strengthens, plans, dispatches,
verifies, and reconciles repository work against declared standards. Everything
it emits must be decision-grade: what happened, why it matters, what evidence
supports it, and what may happen next.

The product may execute a plan without repeated operator attendance only when a
valid mandate already grants that authority and deterministic policy verifies
every required condition. Agents do not create or interpret their own
authority.

## Transitional execution posture

Until ROADMAP Release 3.9 G39-01 through G39-06 are integrated, this repository
operates in **supervised** posture:

- Agents may prepare work, edit authorized files, run checks, update the
  proposed roadmap state, commit, push when assigned, open or update a PR, and
  monitor evidence.
- Promotion requires operator approval bound to the exact verified head SHA.
- The former D-019 permission to merge pure engineering merely because GitHub
  reports `CLEAN` is retired.
- Do not simulate a mandate, guarded promotion, or automatic phase continuation
  before the corresponding schemas, policy, and gates exist.

After G39-06, the active execution posture controls promotion:

- **supervised** — operator approval is required for the verified head SHA;
- **guarded** — deterministic policy may promote only when an active mandate
  explicitly authorizes it and every policy input passes;
- **extended** — unsupported until a later release proves and enables it.

## Roadmap work and state

`ROADMAP.md` is an execution contract, not a wish list. A run begins by reading
it and a run that changes implementation or roadmap state closes by reconciling
it.

### Selecting work

- Without an active mandate, take the first dependency-ready item in Current
  focus that is agent-executable. Work remains supervised.
- With an active mandate, execute only the work unit selected by the
  orchestrator. Do not substitute another open checkbox or expand into a nearby
  concern.
- An operator-only action belongs in
  [`docs/governance/operator-queue.md`](docs/governance/operator-queue.md), not
  in an agent milestone.
- A non-blocking discovery is recorded with a bounded follow-up and does not
  silently enlarge the active unit.

### Proposal state is not delivery state

Every roadmap milestone has one proposal state and one runnable `check:`:

| State | Meaning |
| --- | --- |
| `planned` | The contract exists; no implementation exists on a work branch. |
| `built` | Implementation exists; required exact-head verification is not green. |
| `verified` | Required checks actually ran and passed on the exact applicable PR head. |

These states do not establish integration:

- `[x]` on a PR branch describes the post-merge repository state proposed by
  that PR.
- `[x]` on `main` describes an integrated milestone.
- `COMPLETE` may be emitted only after the intended merge commit is verified as
  reachable from the intended target branch and post-merge reconciliation
  succeeds.
- An agent result, local test, green check, approval, roadmap checkbox, or PR
  merge claim is not independently sufficient.

When a PR ships a roadmap capability, update the corresponding milestone in the
same PR and write the roadmap among the last files changed. Once exact-head CI
is green and the PR is otherwise promotion-eligible, stage `[x]` and move the
milestone verbatim to
[`docs/history/completed-releases.md`](docs/history/completed-releases.md).
That edit remains prospective until the PR merges.

Never rebuild work merely because it is absent from the active roadmap. Check
completed-release history, the repository, branches, PRs, and execution history
first.

## Execution authority and permission envelope

Before the first mutation and again at every phase boundary, establish:

- the repository and target branch are the intended ones;
- the work unit is dependency-ready and within the selected roadmap scope;
- any required mandate is active, unexpired, unpaused, and unrevoked;
- the normalized plan fingerprint still matches;
- scope paths, forbidden paths, network rules, and allowed operations permit
  the proposed action;
- attempt, remediation, duration, cost, and concurrency budgets remain;
- no cancellation or unresolved escalation is waiting;
- the workspace and branch state are safe for the next operation.

Provider settings, sandboxes, or CLI permissions are additional restrictions.
They never grant an operation absent from the WorkPacket, mandate, repository
policy, or Steering.

For every adapter, a post-run diff touching `forbiddenPaths` fails the packet by
name and prevents push. `.github/workflows/**` remains forbidden to agents; a
needed workflow is proposed under `.github/workflows-proposed/` or in the
handoff. Network access is denied unless the packet carries the approved
allowlist.

## Separation of responsibilities

The following are separate logical roles even when implemented in one service:

| Role | Responsibility |
| --- | --- |
| Planner/scheduler | Select a dependency-ready authorized unit. |
| Implementation agent | Modify in-scope files, run local checks, and emit a structured result. |
| Verification service | Execute checks and bind evidence to the exact head SHA. |
| Independent reviewer | Assess correctness, scope, and material risk outside the implementation claim. |
| Policy engine | Evaluate readiness and promotion from recorded inputs. |
| Orchestrator | Perform authorized transitions, promotion, reconciliation, and continuation. |

The implementation agent may recommend a transition but may not verify,
approve, merge, widen authority, or mark complete its own work through prose or
structured output. When review is model-based, the configured review policy
determines whether another provider or reviewer identity is required.

## Repository layout and state

- `backend/config/` contains application policy consumed by the API host.
  Config files use `"schemaVersion": "v1"`, never `"version"`.
- `scripts/model-routing/` contains development-tooling configuration. It does
  not import or redefine application policy.
- `output/` contains gitignored operational state such as `app.db`, indexes,
  WorkPackets, run summaries, mandate state, and JSONL ledgers. A clean clone
  does not contain these directories; fixtures create isolated roots.
- `evidence/baseline/<date>/` contains immutable permanent snapshots. Copy into
  it; never edit a baseline in place or let retention delete it.
- `evidence/verified/` and `evidence/trials/` contain curated judgements and
  proof. Regenerable run output does not enter source control.

Test fixtures must never write live operational roots. Every smoke or test path
uses an explicit temporary root and proves that live ledgers, queues, mandates,
and roadmap writeback remain unchanged.

## Config authority rules

Do not re-derive these:

1. `ai-doc-templates.json` → `readmeContract` is the single authority for
   required README sections. `doc-standards.json` references it and does not
   redefine the list. `repo-structure-standards.json` is presence-only.
2. A missing universal README section is `warning`; a missing profile-specific
   section is `info`. Universal sections are Overview, Installation, Usage, and
   License.
3. A change to one application config requires checking the other application
   config files for contract drift before commit.
4. Config, `modelVersion`, verdict semantics, governance, CI, branch protection,
   credentials/permissions, production, and destructive-data changes always
   require owner review regardless of execution posture.

## Gates and verification

Rules that matter must become failing gates. Documents explain; gates preserve
the rule across providers and sessions.

- Derive scope. Do not maintain hand-curated lists of files, screens, providers,
  or checks when the repository can discover them.
- A new gate is not trusted until it has been shown red against a real violating
  fixture and green after the correction.
- A check that examined zero applicable items is a failure unless zero is an
  explicitly valid, recorded outcome.
- Required jobs must actually execute against the applicable head. `skipped`,
  `neutral`, stale, or unrelated status is not success.
- Capture PowerShell information streams with `*>&1`, not `2>&1`, when the
  assertion depends on the complete stream.

Before reporting implementation complete:

- Run [`scripts/Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1).
- If the API host changed, run
  [`scripts/Invoke-ApiHostSmokeTest.ps1`](scripts/Invoke-ApiHostSmokeTest.ps1).
- Run focused frontend tests, typecheck, and lint when their surfaces change.
- Validate edited JSON and require `schemaVersion` where applicable.
- Run [`tools/Test-RoadmapStructure.ps1`](tools/Test-RoadmapStructure.ps1) when
  the roadmap changes.
- Use [`scripts/Invoke-TestSuite.ps1`](scripts/Invoke-TestSuite.ps1) as the full
  local suite; CI remains authoritative for environment-sensitive evidence.

An unsuccessful check means the implementation is not verified. Report the
failure honestly; do not translate it into delivery failure, operator proof, or
success.

## Standard delivery workflow

1. Revalidate steering, roadmap, repository state, dependencies, authority, and
   the WorkPacket.
2. Create or resume the assigned isolated worktree and non-default branch.
3. Implement only the bounded work unit.
4. Run focused checks, then required local suites.
5. Update affected documentation and the prospective roadmap state in the same
   branch.
6. Emit the required structured `ExecutionResult`; do not use prose as the only
   record of files, checks, scope, residual work, or failure.
7. Let the assigned orchestration path push, open or reconcile the PR, and
   monitor CI. Do not duplicate an existing branch, run, PR, or remediation.
8. Bind verification and review evidence to the exact PR head SHA.
9. Evaluate promotion under the active posture. `mergeStateStatus: CLEAN` is
   useful but not sufficient by itself.
10. After promotion, verify the actual merge commit on the intended branch,
    reconcile roadmap and execution history, consume mandate authority, refresh
    dependencies, and only then select the next unit.

Never commit feature work directly to `main`, force-push, bypass protection,
silently rebase an operator branch, or merge on a stale verification result.

At most two unmerged review PRs may wait per repository. A third unit may be
built in an isolated worktree only when dependencies and conflict policy permit;
do not open a third review PR until a slot is free. Only one integration
operation per repository runs at a time.

## Failure, remediation, and escalation

Classify failure as `transient`, `implementation`, `authority`, `plan`,
`evidence`, or `budget`.

- Transient and implementation failures may be remediated only within stored
  limits and only after changed remediation or new evidence.
- Provider exhaustion is `CAPACITY_WAIT`, not task failure. Preserve worktree,
  branch, attempt, session, and result state for resumption or authorized
  handoff.
- Replaying the same failed action without new evidence is not remediation.
- Authority, plan, evidence, and budget failures pause the affected unit.

A decision-ready escalation records:

- repository, mandate, work-unit, and run identifiers;
- the exact rule, missing evidence, or exhausted limit;
- evidence references and current safe state;
- the smallest proposed deviation and its impact;
- the available operator decisions and the consequence of each.

Never ask only “May I continue?” A question turning on preference, risk posture,
or product direction belongs in
[`docs/governance/open-decisions.md`](docs/governance/open-decisions.md). Record
the safe default only when one exists; otherwise pause the affected work and
continue unrelated authorized work.

## Session completion and handoff

A provider session may end at any legitimate durable boundary:

- implementation result persisted;
- verification or review failure recorded;
- capacity wait entered;
- cancellation acknowledged;
- mandate paused, revoked, expired, or exhausted;
- decision-ready escalation created;
- integration reconciled and the next unit selected.

Do not manufacture a commit or open a PR merely to avoid ending with a status.
Before exit, persist what changed, exact checks and results, current branch and
head, WorkPacket/run/mandate identifiers, residual scope, incorrect assumptions,
decisions parked, authority consumed, and the next eligible transition. A later
session must be able to resume without depending on conversation memory.

## Conventions

- PowerShell is 5.1-compatible unless a file's `#Requires` says otherwise. Do
  not use `ForEach-Object -Parallel`, `Start-ThreadJob`, or `??`; use runspace
  pools when concurrency is required.
- Gates reading repository text tolerate CRLF and LF; use `\r?\n` rather than
  requiring a bare newline.
- Commit prefixes follow the existing form: `feat(release-N.M):`,
  `fix(validation):`, `chore(config):`.
- Never hide an error. Name it, record it, determine whether it blocks, and
  transition accordingly. `SilentlyContinue` may not erase a failure.
