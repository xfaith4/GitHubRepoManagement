# GITHUBREPOMANAGEMENT — repo context

> **The operating contract lives in [`AGENTS.md`](AGENTS.md), not here.**
> Read it first: it is model-agnostic and is what Copilot and other tools are
> given too. This file holds only what is specific to Claude Code. Rules added
> here instead of there are invisible to every other tool — which is how a
> convention silently stops applying.

## Claude Code specifics

- `.claude/settings.json` is the versioned repo contract (hooks, permissions).
  `settings.local.json` is per-machine and gitignored; policy never goes there.
- The monitor-to-green-then-merge loop in `AGENTS.md` is **durably authorized
  for this repository** — open the PR, poll `mergeStateStatus`, merge on
  `CLEAN` without asking again. That authorization does not extend to other
  repositories, where the merge is the operator's call.
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
