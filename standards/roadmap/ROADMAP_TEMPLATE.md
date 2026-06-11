# {Project Name} — Product & Engineering Roadmap

> Status: Active
>
> Product direction: {One-sentence description of the product's direction and goal}

## 1. Product Intent

{Two to four sentences describing what the product does, who it serves, and what problem it solves.
Focus on outcomes for operators or users rather than on implementation details.}

---

## 2. Product Principles

- **{Principle name}** — {One-sentence explanation of the principle and why it matters.}
- **{Principle name}** — {One-sentence explanation of the principle and why it matters.}
- **{Principle name}** — {One-sentence explanation of the principle and why it matters.}

---

## 3. Current State Summary

{One paragraph describing the foundational pieces already in place and what gap remains before
the next release can be delivered.}

---

## 4. Recently Completed

{Preserve prior completed history here. Do not delete it. Every completed item carries an
absolute completion date so the roadmap doubles as a referencable project timeline.}

- [x] {Completed milestone or feature — short, verifiable description} *(completed: {YYYY-MM-DD})*
- [x] {Completed milestone or feature} *(completed: {YYYY-MM-DD})*

---

## 5. Release Roadmap

---

## Release {X.Y} — {Release Title}

> Status: {Pending | In Progress | Complete}
> Completed: {YYYY-MM-DD — include this line when Status is Complete}
> Token usage: {~N tokens — optional; cumulative AI/agent tokens spent delivering this release}

**Goal:** {One sentence describing the functioning version this release should deliver.
State what the product can do after this release that it cannot do before.}

### Product outcomes

- {Observable outcome for an operator or user}
- {Observable outcome for an operator or user}

### Engineering milestones

- [x] {Completed implementation step} *(completed: {YYYY-MM-DD})*
- [ ] {Concrete, testable implementation step — what file, function, or behavior changes}
- [ ] {Concrete, testable implementation step}

### Acceptance criteria

- {The release can be judged complete when this is verifiably true}
- {The release can be judged complete when this is verifiably true}

### Out of scope

- {Explicitly deferred work that will not be delivered in this release}
- {Explicitly deferred work}

### Phase plan (optional — for releases delivered in bounded phases)

| Phase | Scope | Status | Completed | Token usage | Work units (est → actual) |
| ----- | ----- | ------ | --------- | ----------- | ------------------------- |
| Phase 1: {Name} | {Bounded slice of this release} | done | {YYYY-MM-DD} | {~N tokens} | {12 → 15} |
| Phase 2: {Name} | {Bounded slice of this release} | planned | — | — | {est. 10} |

### Budget guardrail (optional — when AI/agent work is metered)

See `standards/roadmap/ROADMAP_BUDGET_MODEL.md` for the full cost model.

- Estimated AI work units for this release: {N} · Max per phase: {N}
  (split a phase that is likely to exceed its budget)
- Before dispatch: check the budget ledger; do not start a session whose
  estimate exceeds the per-session cap; stop work if a usage-limit or
  credit-purchase prompt appears, and record what other work was pending.
- At each phase closure record the raw observations only: units consumed
  (est → actual), token usage, direct credit / API spend, human review
  minutes, and credit-prompt / overage flags. Dollar valuations
  (subscription allocation, human time cost) are derived at report time
  from the budget config — do not write them into the roadmap or event
  history. Keep quota burn separate from USD.

---

## Release {X.Z} — {Next Release Title}

> Status: Pending

**Goal:** {One sentence describing the functioning version this release should deliver.}

### Product outcomes

- {Observable outcome for an operator or user}

### Engineering milestones

- [ ] {Concrete, testable implementation step}

### Acceptance criteria

- {The release can be judged complete when this is verifiably true}

### Out of scope

- {Explicitly deferred work}

---

## 6. Cross-Cutting Engineering Work

These items support all releases and should be advanced continuously:

- [ ] {Ongoing quality or infrastructure task}
- [ ] {Ongoing quality or infrastructure task}

---

## 7. Risks and Design Guardrails

### Risks

- {Risk description — what could go wrong and why}
- {Risk description}

### Guardrails

- {Explicit rule to prevent a known failure mode}
- {Explicit rule}

---

## 8. Definition of Done for Release Execution

A release should not be marked complete unless:

- All checklist items for that release are truly implemented or explicitly blocked
- UI elements are connected to real behavior rather than placeholders
- Affected docs are updated where workflow or product behavior changed
- Logging and error handling are sufficient to diagnose failures
- Later releases were not partially started just to create the illusion of momentum
- The release and each completed phase carry an absolute completion date
  (`YYYY-MM-DD`), and token usage is recorded where AI/agent work was metered

---

## 9. Immediate Next Focus

The recommended immediate execution target is:

### **Release {X.Y} — {Release Title}**

Specifically:

- {First concrete subtask to start}
- {Second concrete subtask to start}
