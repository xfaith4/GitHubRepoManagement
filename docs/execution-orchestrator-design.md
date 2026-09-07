# Execution Orchestrator — design (superseded 2026-09-06)

> **Status: superseded — do not build from this document.** The design
> authority for execution is now
> [Agent Execution Governance](governance/Agent-Execution-Governance.md),
> carried as **Release 3.8 — Provider-Aware Execution** in
> [`ROADMAP.md`](../ROADMAP.md). What follows is kept for two reasons: its
> **P0 record**, which is the only part ever built (phase-plan protocol,
> write-back and the agent-readiness gate, 2026-07-08), and the reasoning
> behind the decisions the new spec revisits.
>
> **Two of its decisions locked on 2026-07-07 are reversed.**
>
> - **"Merge — automatic when green"** is reversed. Promotion is an explicit
>   operator action against a **verified head SHA**. A well-formed roadmap
>   grants permission to prepare and execute work; it never grants permission
>   to merge that work into the protected default branch.
> - **"Governor threshold — adaptive, not preset"** survives only as the
>   lowest-confidence capacity source. Capacity is observed per provider in the
>   provider's own unit and ranked by confidence, with provider-reported status
>   preferred over a ceiling discovered by hitting a `429`.
>
> Its single-provider assumption is gone too: the orchestrator routes between
> Codex, Claude Code and GitHub Copilot, and a provider limit is **state**, not
> a failed task.
>
> Original status line, retained: _design, not built. This captures the
> decisions from the planning discussion so we can redline before writing
> code._

## Mission

Complete the tasks on the roadmaps. All README/roadmap **readiness** work has
been building the launchpad; this is the launch. The orchestrator keeps coding
agents working roadmap phases across the portfolio, governed so that **throughput
is maximized and token usage is minimized** — the agent count (1…N) is an output
of the governor, not a fixed target.

## Guiding principles

- **Governor-throttled, dynamic concurrency.** Start with **1 worker**. The
  governor decides when work runs and when it pauses; concurrency scales later
  without changing the model.
- **Minimize tokens two ways:** the governor throttles *how much* runs, and
  **RTK** compresses *what each run costs* (verified ~72% savings on dev CLI
  output — every worker runs under the RTK hook).
- **The roadmap is the protocol.** A well-formed `### Phase plan` table is the
  machine-readable contract the worker and governor read and write. No well-formed
  roadmap → repo is not agent-eligible → route it back to readiness/repair first.
- **Autonomous by default; you hold the brakes.** Runs proceed unattended — your
  interaction is not a per-step gate. Workers push branches; merge is automatic
  when merge-readiness passes (a well-formed roadmap is the standing approval).
  Safety lives in the automated gate + branch-only work + an explicit **Stop**.
- **Self-calibrating from experience.** Both the governor's token ceiling and the
  time/token estimates start rough and sharpen as phases complete — the system
  learns its own limit and its own velocity instead of relying on preset numbers.

## MVP scope: governor + 1 worker

Get the plumbing working end-to-end with a single agent before any concurrency.

```text
  GOVERNOR LOOP  (checks budget, then assigns next work)
     │  budget OK?  ──no──►  PAUSE until session window cools / retry-after
     │  yes
     ▼
  pick next work  ──►  WORKER (Claude Agent SDK, in repo clone, RTK hook on)
     (Strategy)          1. PLAN the phase        (read phase-plan row + repo)
                         2. EXECUTE the phase     (implement on a branch)
                         3. VALIDATE & PUSH       (tests/build, commit, push)
                         4. REPORT back           (tokens used, result)
     ▲                                                     │
     │   PR ► merge-readiness ► auto-merge-when-green ► VERIFY post-merge Actions
     │                                                   │  green → phase DONE
     │                                                   │  red   → remediate ↺
     └──  write phase-plan row (done · date · tokens) ── only after DONE ──┘
```

## The per-phase loop (decision 2, confirmed)

Each unit of work is **one phase**. The worker runs Plan → Execute → Validate &
Push → Report, then hands control back to the governor to assign the next work.
Pauses happen **between phases** (clean boundaries, roadmap state consistent).

A phase is **DONE only when it is merged *and* the repo's post-merge workflows come
back green** (or there are none) — see *Post-merge verification* below. The
phase-plan row is written back at that point, not at push time.

## Next-work selection & control (Strategy)

**Autonomy:** runs unattended by default — your interaction is **not** a per-step
gate. Three explicit controls:

- **Begin Work** — start (or resume) execution.
- **Stop** — halt a run at any time. Stops at the nearest clean checkpoint so a repo
  is never left half-edited (finish or roll back the current step; no hard-kill
  mid-edit).
- **Strategy change** — when you express a new direction, workers **stop and
  re-orient** to it, then wait for **Begin Work** before resuming. A direction change
  is a deliberate pause + re-plan, not a silent reprioritization.

**Next work** (while running): the next unchecked phase of the **same** roadmap by
default; a Strategy override can point at a different repo (an explicit pin, or the
`Portfolio.ValueScorer` when unpinned), taking effect at the next phase boundary.

## Roadmap phase-plan contract (the linchpin)

The worker/governor operate on the `### Phase plan` table already parsed by
`Roadmap.Parser.ps1` (`Phase | Scope | Status | Completed | Token usage | Work
units`). Two additions make it a live protocol:

1. **Write-back:** after a phase, the worker updates that row — `Status → done`,
   `Completed → date`, `Token usage → actual` (feeding better future estimates).
2. **Agent-readiness gate:** a pre-flight check ("does this repo's roadmap have a
   valid phase-plan table at L3+?"). Fail → send to the readiness pipeline, don't
   dispatch. This is the handshake where curation meets execution.

## The governor

- **Meters** cumulative tokens for the current rolling session window by summing
  each worker's SDK-reported `usage` per API call (real tokens, not estimates —
  the gap the current work-unit "budget" can't fill).
- **Adaptive threshold — no preset ceiling.** The first time a worker actually hits
  the provider limit (`429`), the governor records the tokens consumed in that
  window and the reset timing — that observed point becomes the learned ceiling.
  From then on it pauses **proactively** at a safety margin below the learned ceiling
  and keeps tuning it as more windows are observed. Early runs discover the limit the
  hard way; later runs never touch it.
- **Backpressure**: always respect `429` / `retry-after` as the hard floor; resume
  when the window rolls.
- **Reports** per window: tokens spent, tokens **saved via RTK** (`rtk gain`),
  phases completed, the learned ceiling + margin, and projected next-available time.

## Post-merge verification & self-remediation

Some repos run workflows on merge to `main` (deploy, integration, release builds)
that a PR check never exercises — so "green at merge" ≠ "green after merge." The
loop after an auto-merge:

1. **Watch** — poll the merge commit's workflow runs (GitHub Actions API / `gh`).
   Reuses the Actions reconciliation already in `AgentRuns`.
2. **Detect** — any failed / errored run flips the repo's `main` to **red**.
3. **Diagnose** — pull the failing job logs and summarize the failure (the existing
   `gh-fix-ci` pattern is a direct fit).
4. **Correct** — dispatch a **remediation task**. The fix may be to application code
   **or to the workflow files themselves** (`.github/workflows/*.yml`). Same rails:
   branch → validate → auto-merge → re-verify.
5. **Cap & escalate** — bounded retries (default ~2). Still red → mark the phase
   **blocked**, surface it in Mission Control + the activity feed, and wait for you.

**Orchestration rule — freeze a red `main`.** While a repo's `main` is red, the
orchestrator dispatches **only remediation** for it — no new phases stack changes on
top of a broken build until it's green again.

**Guardrail.** Editing `.github/workflows` is powerful (it changes what "green"
means), so workflow-file changes stay on the same branch→validate→auto-merge path
and are flagged **distinctly** in the activity feed — a CI change is never invisible.

This also sharpens P0's readiness gate: the "meaningful validation signal" a repo
needs to be auto-merge-eligible *is* its PR checks + post-merge workflows. A repo
with none can't be safely auto-merged and is held back like an un-formed roadmap.

## Mission Control — observability

The operator's window into the running system: where everything stands at a
glance, with the ability to zoom into any repo in flight. **Fed by structured
events emitted from P0–P3** (see the build plan), so it shows real data from the
first phase instead of being computed at the end.

**Portfolio tier (the glance):**

- In-flight / queued / blocked / **remediating** / done repo counts; which repo+phase
  the worker is on **right now**, and governor state (running · cooling down · paused,
  with a resume ETA).
- **Portfolio completion gauge** — work-unit-weighted % done across the portfolio
  (a 5-unit phase counts more than a 1-unit phase).
- Token economics: live burn vs. session-window budget, **RTK savings**, burn
  rate, projected window exhaustion.
- **Activity feed** — recent phases completed and features shipped, across repos
  (from phase-plan write-backs + merged PRs).

**Repo tier (the zoom-in):**

- This repo's **completion gauge** (work-unit-weighted phases done / total) and the
  current phase's sub-state (Plan → Execute → Validate → Push).
- Phases completed with **what each delivered** (scope + PR/commit link), and
  per-phase actuals: duration, tokens (actual vs. estimated).
- **Build health** — `main` green/red, the post-merge workflow run for the latest
  phase, and any remediation in progress (with attempt count).
- **Estimated work left** (below).

**Estimation model — self-calibrating from experience:**

- **Time left** = average duration of completed phases × remaining phase count.
  Real timing comes from the `AgentRuns` ledger (`dispatchedAt` →
  `agentCompletedAt`, `timeToDeliverSeconds`). Projected in **tokens** the same way
  (avg tokens/phase × remaining).
- **Rough early, sharper over time.** With few completed phases the number is
  soft — shown with the sample size ("based on 3 phases") and a spread, tightening as
  experience accrues. Same philosophy as the adaptive governor: start rough, learn
  from what actually happened.
- Caveat surfaced: it assumes phases are of similar scope; one big phase skews it.

## Components — reuse vs. build

| Component | Status | Source |
|---|---|---|
| Pick work (phase parse, value rank) | reuse | `Roadmap.Parser`, `Portfolio.ValueScorer` |
| Run ledger + PR/Actions reconcile | reuse | `AgentRuns` |
| Merge gating | reuse | `MergeReadiness` |
| Durable state (JSONL/SQLite) | reuse | `Persistence.Store` |
| Token compression | reuse | **RTK** hook in each worker |
| **Worker adapter** (Claude Agent SDK + RTK, run a phase) | **build** | — |
| **Governor** (real token metering + pause/resume) | **build** | — |
| **Orchestrator loop** (durable slot-fill + Strategy) | **build** | replaces in-memory `AgentClaims` |
| **Phase-plan write-back + readiness gate** | **build** | extends `Roadmap.Parser`/auditor |
| **Post-merge verify + self-remediation** (watch Actions, fix code/workflow) | **build** | extends `AgentRuns` Actions reconcile + `gh-fix-ci` pattern |
| **Mission Control** (gauges, activity feed, estimates, zoom) | **build** | extends agent-runs/operations UI |
| Structured phase/feature events (feed the dashboard) | **build** | extends webhook event set + `AgentRuns` |

## Phased build plan (each independently shippable)

- **P0 — Phase-plan contract. ✅ built + verified (2026-07-08).** Made the parser
  heading-level tolerant (real roadmaps nest releases, so headings are ###/####, not
  ##/###); added `Set-RoadmapPhaseState` (surgical, EOL-preserving write-back) and
  `Test-RoadmapAgentReadiness` (releases + full protocol columns + L3+ + CI signal)
  in `Roadmap.PhaseProtocol.ps1`, covered by `scripts/Invoke-PhaseProtocolTest.ps1`
  (21 assertions) with the module smoke green. **Dogfooded:** this repo's ROADMAP.md
  phase-plan tables were upgraded to the full 6-column protocol (Completed / Token
  usage / Work units appended append-only; completion dates back-filled from each
  phase's status) — it is now **agent-eligible** (gate: eligible, 6/6 tables conform).
  Bringing each other repo's roadmap to the full column set is the first readiness
  task the engine will demand of it.
- **P1 — Worker adapter.** Given (repo, phase), spawn a Claude Agent SDK worker
  (RTK hook on) that does Plan→Execute→Validate&Push→Report. One phase, by hand.
- **P2 — Governor.** Real token metering per window + soft/hard throttle +
  pause/resume; wire worker usage in.
- **P3 — Orchestrator + Strategy.** Durable loop: governor gate → Strategy pick →
  dispatch → on report, next. Also owns **post-merge verification**: watch the
  merge's Actions, **freeze a red `main`**, dispatch remediation (cap N), and mark a
  phase DONE only when post-merge is green. This is the "1 agent, always fed" MVP.
- **P4 — Mission Control.** Portfolio + repo dashboards: completion gauges,
  activity feed, token economics, estimated work-left, Strategy controls,
  pause/resume + cooldown. Builds on the agent-runs/operations UI.

**Observability is emitted, not bolted on.** Each of P0–P3 emits the structured
events + metrics the dashboard renders (phase started/completed, tokens per phase,
feature shipped), so Mission Control has real data from the first phase. P4
*assembles* them into the operator surface; it does not compute them after the
fact.

MVP = P0→P3 **plus a minimal live view** (current repo/phase, token burn vs.
window, one completion gauge) so the 1-agent plumbing is watchable end-to-end. The
full Mission Control — activity feed, calibrated estimates, portfolio/repo zoom —
is P4. Concurrency >1 is a later, additive change to the orchestrator.

## Decisions (locked 2026-07-07)

1. **Governor threshold — adaptive, not preset.** Discover the real limit from the
   first `429`, record it, and tune a safety margin from experience. No hardcoded
   ceiling.
2. **Merge — automatic when green.** A well-formed roadmap is the standing approval;
   no per-merge human sign-off. The automated merge-readiness gate (validation
   green, no conflicts) governs *when* it fires.
3. **Autonomy — you are not a gate.** Runs proceed unattended; **Stop** halts a run,
   **Begin Work** starts/resumes. Work stays on branches, never direct to `main`.
4. **Strategy change — stop, re-orient, resume on Begin Work.** A direction change
   pauses workers, refocuses on the new direction, and waits for an explicit Begin
   Work.
5. **Estimation — avg completed-phase duration × remaining phases.** Self-calibrating;
   rough early, sharper with experience.

### Small follow-ups (settle during build, not blockers)

- Exact **safety margin** below the learned ceiling (start ~15–20%, tune).
- **Stop granularity** — nearest clean checkpoint (end of Plan/Execute/Validate/Push
  step) vs. end of phase.
- What counts as a **"feature shipped"** in the activity feed (merged PR · phase
  marked done · labeled item).
- **Remediation cap** (default ~2 attempts) before a phase is marked blocked.
- Confirm agents may edit `.github/workflows` (default **yes**, flagged in the feed).
