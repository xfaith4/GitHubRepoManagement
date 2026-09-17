# GITHUBREPOMANAGEMENT — repo context

> **The operating contract lives in [`AGENTS.md`](AGENTS.md), not here.**
> Read it first: it is model-agnostic and is what Copilot and other tools are
> given too. This file holds only what is specific to Claude Code. Rules added
> here instead of there are invisible to every other tool — which is how a
> convention silently stops applying.

## Claude Code specifics

- `.claude/settings.json` is the versioned repo contract (hooks, permissions).
  `settings.local.json` is per-machine and gitignored; policy never goes there.
- The monitor-to-green-then-merge loop in `AGENTS.md` is authorized for this
  repository **for pure engineering with a green check only** (D-019,
  2026-09-14, mirroring steering contract 10): open the PR, poll
  `mergeStateStatus`, merge on `CLEAN` without asking again. A change that
  touches `backend/config/`, a CI gate (`scripts/Invoke-TestSuite.ps1`,
  `tools/Test-*.ps1`, `.github/workflows/**`), `docs/governance/`, or what a
  verdict says about a repository is opened as a PR and **waits for Ben's
  review** — never merged by a watch on green. At most two such PRs wait
  unmerged at once; a third item is built on its branch and its PR waits
  for a slot. Neither authorization extends
  to other repositories, where the merge is the operator's call.
- Roadmap work runs as `claude --agent roadmap-lead` (Fable). The lead
  delegates to two Haiku helpers, `roadmap-scout` (read-only discovery) and
  `roadmap-builder` (mechanical edits); all three are defined in
  `.claude/agents/`. It must be the main session, because a subagent cannot
  delegate. The item fields they read are defined in `ROADMAP.md` §3.
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
