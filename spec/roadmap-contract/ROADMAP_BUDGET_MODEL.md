# Roadmap Budget and Cost Accounting Model

This document defines how the cost of roadmap phases is measured, allocated,
and controlled for agent-driven development. It is part of the Roadmap
Contract Standard and is referenced by the optional **Budget guardrail**
section in `ROADMAP_TEMPLATE.md`.

The core insight: **do not treat "cost" as only dollars.** A subscription
usage window is itself a scarce resource. A phase can have $0 direct spend
and still be expensive because it consumed the session window another
project needed.

```text
Phase Cost =
  Allocated subscription cost
+ Direct credit spend
+ External tool/runtime spend
+ Human review time
+ Quota/session-window consumption
```

---

## Operating principles

1. **Never bury quota burn inside USD.** Money and window capacity are
   different scarcities; graph them separately.
2. **Store raw observations; derive valuations at report time.** Events
   and roadmap annotations record what was observed (units, tokens,
   minutes, timestamps, spend actually billed). Valuation parameters
   (monthly subscription cost, hourly rate, work-type weights, allocation
   formula) live in editable config. Dollars-per-phase are computed when a
   report is rendered — never written into append-only history, so
   changing a formula later does not invalidate past records.
3. **Automate first; manual telemetry decays.** Every field a human must
   fill at a session boundary will eventually be skipped, and a
   half-populated dataset is worse than a small honest one. Required
   fields must be capturable automatically; human-observed fields are
   optional enrichment that must never block work.
4. **Your own ledger is the primary quota counter.** Providers do not
   expose remaining-quota consistently, and their meters change. Count
   your own consumption against your own configured budgets;
   provider-observed remaining-units are optional corroboration.

---

## Measurement tiers

| Tier | Capture | Fields | Role |
| ---- | ------- | ------ | ---- |
| **1 — Automatic (required)** | Recorded by tooling with zero operator effort | Run/dispatch counts, retries, timestamps and time-to-deliver, prompt count, reported token usage, direct API spend, normalized AI work units (raw counts × config weights) | The durable backbone; quota guards and burn rate run on this |
| **2 — Human-observed (optional)** | Entered by the operator when available | Provider-UI remaining units, credit-prompt-seen, human review minutes | Valuable when present, never blocking |
| **3 — Derived (computed, never stored)** | Calculated at report time from tiers 1–2 plus valuation config | Subscription allocation USD, human time USD, total phase cost USD, overage risk, opportunity-cost summaries | Reporting views over raw history |

---

## The three cost dimensions

### 1. Cash cost — money attributable to the phase

Stored raw: `direct_credit_spend_usd`, `api_spend_usd`,
`external_service_spend_usd` (amounts actually billed), and
`human_time_minutes` (observed, tier 2).

Derived at report time: `subscription_allocation_usd` (see allocation
options below), `human_time_cost_usd` (minutes × configured rate), and
`total_cash_cost_usd`. Allocation is an accounting fiction — the marginal
cash cost of one more phase inside an included window is $0 — so it is a
useful display number, not a stored fact.

### 2. Quota cost — scarce usage-window capacity consumed

Stored raw (tier 1): `units_consumed` from your own ledger — raw activity
counts normalized via config weights. Stored when observed (tier 2):
`units_remaining_observed` from the provider UI, `credit_prompt_seen`,
`overage_triggered`.

Derived: burn rate, budget remaining (own-ledger consumption vs configured
monthly budget), and overage risk (units consumed vs caps — computed, not
a stored subjective enum).

### 3. Opportunity cost — capacity denied to other work

Record **events, not estimates**. When a session limit is hit, append a
`quota.exhausted` event capturing which queued/pending work existed at
that moment (repos with pending dispatches, the interrupted task).
Starvation is then countable from history. Do not store guessed
`estimated_delay_minutes`; counterfactual judgment entered by hand is
noise wearing a number's clothes.

---

## The normalized AI work unit

Plan limits differ by provider, product, and model, and they change. Define
a provider-agnostic unit so phases are comparable across time and tools:

> **AI work unit** — one meaningful interaction with a coding model or
> agent (one agent task submission, one substantial prompt-response cycle,
> one validation/debugging loop, one roadmap reconciliation pass).

Starting weights — these live in config, not in events, and are calibrated
over time using estimated-vs-actual data:

| Raw activity | Normalized units |
| ------------ | ---------------: |
| Small planning prompt | 0.5 |
| Substantial implementation prompt | 1 |
| One coding-agent run | 3 |
| One failed coding-agent retry | 2 |
| One roadmap reconciliation pass | 1 |
| One deep research task | 5 |
| One credit-triggered task | track separately |

Record both raw counts and normalized totals.

---

## Allocating flat subscription cost (report-time only)

**Option A — simple proportional:**

```text
phase_subscription_cost =
  monthly_subscription_cost
  × phase_quota_units_consumed
  ÷ total_month_quota_units_consumed
```

**Option B — per-project monthly budgets (preferred):** give each repo a
monthly USD and unit budget; phases draw down their project's budget. This
is the model the pre-dispatch quota guard enforces, because it prevents
one project from starving the others.

**Option C — work-type weighting:** multiply raw units by a complexity
weight (planning 0.5 · implementation 1.0 · debugging 1.5 · architecture
2.0 · multi-agent orchestration 2.0 · deep research 2.5) before
allocation.

Whichever option is configured, it is applied when reports are rendered.
Past events remain valid if the option changes.

---

## The budget ledger

The control mechanism is a small, editable budget file read before
dispatch. In managed repos this is `ROADMAP_BUDGET.yaml` next to the
roadmap; in this application the same data lives in host settings /
`backend/config`.

```yaml
budget:
  period: "2026-06"
  currency: "USD"

subscription:
  plan_name: "{plan}"
  monthly_cost_usd: 20.00

credit_policy:
  allow_paid_credits: false
  require_manual_approval_before_credits: true
  stop_work_when_credit_prompt_seen: true

global_quota_guard:
  soft_stop_remaining_units: 10
  hard_stop_remaining_units: 5
  max_units_per_phase: 25
  max_units_per_session: 12

unit_weights:
  planning_prompt: 0.5
  implementation_prompt: 1
  agent_run: 3
  failed_agent_retry: 2
  roadmap_reconciliation: 1
  deep_research: 5

valuation:
  human_time_rate_usd_per_hour: 60
  allocation_option: "B"

projects:
  "{repo-name}":
    monthly_budget_usd: 6.00
    monthly_quota_budget_units: 60
    priority: 1
```

---

## Quota guard and checkpoints

The guard is the highest-value piece of this model because it changes
behavior before spend happens, rather than describing it afterward:

- Pre-dispatch, estimate the session's work units (from the phase plan's
  `Work units` annotation when present). **Do not start** a session whose
  estimate exceeds `max_units_per_session`; split any phase likely to
  exceed `max_units_per_phase`.
- The guard runs on tier-1 own-ledger counts against the project's
  configured budget — it does not depend on provider-reported quota.
- If a usage-limit warning or credit-purchase prompt appears: **stop
  work** and record a `quota.exhausted` event (including pending work
  elsewhere, for starvation counting). Paid credits require explicit
  manual approval.
- Optional tier-2 `quota.checkpoint` events before/after a session record
  provider-observed remaining units when the operator has them visible;
  they corroborate the ledger but are never required.

### Session planning rule

Agents must not run open-ended:

```text
One session = one commit-sized slice.
One phase   = multiple commit-sized slices.
One project = one monthly quota budget.
```

Dispatch prompts should instruct: implement only the next incomplete task,
stop after one coherent commit-sized slice, do not continue into the next
task, record quota/cost event data.

---

## Phase completion record

At phase closure, the canonical `phase.completed` event stores the raw
observations; reports render the valuations:

```text
P02 completed.
  Stored:  AI work units consumed: 15 (estimated: 12)
           Direct credit spend: $0.00 · API spend: $0.00
           Human review: 45 min (observed)
           Credit prompt seen: no · Overage triggered: no
  Derived: Subscription allocation: $1.80 (Option B)
           Human review cost: $45.00 · Total allocated phase cost: $46.80
```

Estimated-vs-actual units per phase is the forecast-accuracy signal that
calibrates the unit weights and makes future phase sizing trustworthy.

---

## Dashboard metrics this model enables

All derived at report time from raw events plus valuation config:

| Metric | Why it matters |
| ------ | -------------- |
| Quota units consumed by phase / by repo | Subscription-window burn; prevents one project starving others |
| Direct credit + API spend by phase | Real marginal dollars; overage visibility |
| Starvation events (`quota.exhausted` with pending work) | Opportunity cost, counted not guessed |
| Estimated vs actual units | Forecast accuracy; calibrates unit weights |
| `credit_prompt_seen` events | Overage warning trail |
| Total cash cost by phase (derived) | Allocated spend view |
| Human review minutes by phase | Review burden |
| Cost per completed task (derived) | Efficiency |
