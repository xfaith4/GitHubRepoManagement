# Status Vocabulary — One Model, Mapped

**Release 3.5 milestone 7.** The adversarial review found three overlapping
status vocabularies with nothing mapping them: grid chips, Operations
lifecycle states, and roadmap maturity levels. `Genesys.Core` read **Ready**
on one tab and **blocked / L0-Absent** on another *in the same session* — both
correct, because they measured different dimensions wearing similar words.

The fix is not one merged status. A repository genuinely has **five
independent dimensions**, and collapsing them would recreate the lie the
snapshot contract exists to remove. The fix is this table: every label in the
UI belongs to exactly one dimension, and no two dimensions share a word.

## The five dimensions

| Dimension | Values | Source | Where it renders |
| --- | --- | --- | --- |
| **Working tree** | `clean` · `dirty` | local scan (`git status`) | grid status chip, Dirty KPI |
| **Remote drift** | `current` · `behind` · `ahead-or-unpushed` · `unknown` | local scan vs GitHub `pushed_at` (Release 3.1: drift, not age) | grid Stale column/chip, Stale KPI |
| **Dispatch readiness** | `ready` · `needs-doc-standardization` · `missing-roadmap` · `roadmap-complete` · `no-checklist` · `parse-error` · `blocked` | docs-audit cache | Doc Readiness rows, grid readiness filter |
| **Roadmap maturity** | `L0-Absent` → `L4-Orchestration-Ready` | roadmap contract audit | Insights maturity views, assessment |
| **Execution lane** | `idle` · `ready` · `running` · `blocked` · `complete` | execution ledger | Execution Queue lanes |

The Genesys.Core collision, decoded: *Ready* was **dispatch readiness**
(docs in shape to receive work); *blocked / L0-Absent* was **execution lane**
plus **roadmap maturity** (no lane assigned, no roadmap contract). All three
were true at once. They are different questions.

## The three "ready" metrics

Finding 1.3 (`READY QUEUE 21` · `Ready Queue 0` · `Ready 0`) was three
measurements wearing one label. The snapshot contract
(`Portfolio.Snapshot.ps1`) carries them as three metrics, and every surface
must use the dimension-qualified name:

| Snapshot metric | Meaning | UI name |
| --- | --- | --- |
| `executionReadyCount` | Execution-lane entries claimable now | **Claimable lanes** |
| `dispatchReadyCount` | Audited repos whose docs can receive agent work | **Dispatch-ready** |
| `maturityReadyCount` | Assessed repos at L3+ with pending items | **Work-ready (L3+)** |

## The two refresh verbs

Seven verbs (`Refresh All`, `Refresh`, `Scan All`, `Sync`, `Reload List`,
`Retry`, `Evaluate`) collapsed to two, each stating what it invalidates:

| Verb | Contract | Cost |
| --- | --- | --- |
| **Refresh** | Re-read from the current source (cache/index). Invalidates nothing. | Seconds |
| **Rescan** | Invalidate the index and recompute from disk/remote. | Minutes — the control says so |

`Retry` survives only as the verb on a *failed* fetch (the async-panel error
state), where it means "run the same read again" — it is Refresh after a
failure, not a third kind of load. `Evaluate` and `Sync` remain as **domain
actions** (merge-readiness evaluation; `git fetch` across repos) — they were
never refresh verbs and no longer borrow refresh styling.

## Consequence styling

Read-only actions (Audit, Lint, Evaluate, Preview) render neutral. Actions
that **start or write something** (Dispatch Release, Apply, Approve & push)
carry amber emphasis and name their consequence in the title. The rule is
Release 3.1's guardrail extended from availability to consequence: an enabled
control is a promise, and a promising control says what it commits you to.
