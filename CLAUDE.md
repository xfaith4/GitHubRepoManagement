# GITHUBREPOMANAGEMENT — repo context

> **The operating contract lives in [`AGENTS.md`](AGENTS.md), not here.**
> Read it first: it is model-agnostic and is what Copilot and other tools are
> given too. This file holds only what is specific to Claude Code. Rules added
> here instead of there are invisible to every other tool — which is how a
> convention silently stops applying.

## Claude Code specifics

- `.claude/hooks/` holds the versioned hook scripts. `.claude/settings.local.json`
  is per-machine and untracked; policy never goes there.
- **A green check is the merge** (D-023, 2026-09-15; the rule is
  [`docs/governance/merge-policy.md`](docs/governance/merge-policy.md)). Open
  the PR, poll `mergeStateStatus`, merge on `CLEAN` without asking again,
  delete the branch, name the merge in the handoff. That includes
  `backend/config/`, `docs/governance/`, gates and verdicts. The merge
  tripwire in the suite decides what the check cannot see: it **holds** the
  trust rule, the gates and the CI definition for Ben (`HELD` — red until he
  adds the `operator-approved` label and re-runs), and **fails** a secret or
  a loosened guard outright. You never apply that label. At most two held
  PRs wait at once. Neither authorization extends to other repositories,
  where the merge is the operator's call.
- A scheduled wakeup must carry its own verification command inline, because
  the wakeup prompt is the only text guaranteed to be in context when it
  fires. Write it as an end-state to verify, never as a list of steps.

## Open decisions — surface, don't solve

- `value-scoring.json` scoring semantics (max-vs-sum within a dimension,
  `effortFit` floor for mixed items) — **RESOLVED 2026-07-06.** Ben chose
  **MAX within a dimension + an `effortFit` floor** (a larger-surface keyword
  caps `effortFit` low even when a bounded verb also matched). Encoded as
  `aggregation.{withinDimension, effortFitFloor}` in `value-scoring.json`
  (model 1.1), implemented in `Portfolio.ValueScorer.ps1`, and covered by the
  module-smoke "effortFit floor" assertion. No longer a drive-by hazard.

## Roadmap turn rule

A session ends with the first `[ ]` in ROADMAP.md "Current focus" started or a PR
opened against it — never with a status summary, a "record, not an action"
paragraph, or a request for the operator to verify something. If the item needs an
operator action, split it: keep the agent half with its `check:`, append the human
half to `docs/governance/operator-queue.md` with `Add-OperatorVerification.ps1`,
and take the agent half. `pwsh ./tools/Test-RoadmapStructure.ps1 -FailOnError` must
pass before the PR is opened; R020–R022 are errors, not warnings.
