# {Project Name} — Product & Engineering Roadmap

> Status: Active
>
> Active release: {X.Y}
>
> Product direction: {One-sentence description of the product direction and intended outcome}

## 1. Product Intent

{Two to four sentences describing what the product does, who it serves, and what problem it solves. Focus on operator/user outcomes rather than implementation details.}

---

## 2. Product Principles

- **{Principle name}** — {One-sentence explanation of the principle and why it matters.}
- **{Principle name}** — {One-sentence explanation of the principle and why it matters.}
- **{Principle name}** — {One-sentence explanation of the principle and why it matters.}

---

## 3. Current State Summary

{One paragraph describing what already exists, what is currently reliable, and what gap remains before the active release can be delivered.}

---

## 4. Release Index

| Release | Status | Purpose | Dispatch readiness |
| --- | --- | --- | --- |
| {X.Y} | active | {Short purpose} | ready / blocked / needs repair |
| {X.Z} | planned | {Short purpose} | planned |

---

## 5. Release Roadmap

## Release {X.Y} — {Release Title}

> Status: active
>
> Completed: {YYYY-MM-DD — include only when status is done}
>
> Token usage: {~N tokens — optional; cumulative AI/agent tokens spent delivering this release}

**Goal:** {One sentence describing the functioning version this release should deliver. State what the product can do after this release that it cannot do before.}

### Product outcomes

- {Observable outcome for an operator or user}
- {Observable outcome for an operator or user}

### Engineering milestones

- [x] {Completed implementation step} *(completed: {YYYY-MM-DD})*
- [ ] {Concrete, testable implementation step — include file, function, command, or behavior where possible}
- [ ] {Concrete, testable implementation step}

### Acceptance criteria

- {The release can be judged complete when this is verifiably true}
- {The release can be judged complete when this is verifiably true}

### Out of scope

- {Explicitly deferred work that will not be delivered in this release}
- {Explicitly deferred work}

### Validation plan

- Run `{test/build/lint command}` and confirm it exits successfully.
- Perform `{manual smoke test or workflow}` and record the result.

### Risks and blockers

- {Risk, blocker, or “None currently known.”}

### Dependencies

- {Dependency, prerequisite, or “None.”}

### Known issues

- {Known issue, pipeline feedback item, or “None currently known.”}

### Traceability

- {Issue, PR, commit, ADR, workflow, test file, doc path, or “Not yet linked.”}

### Phase plan optional

| Phase | Scope | Status | Completed | Token usage | Work units est → actual |
| --- | --- | --- | --- | --- | --- |
| Phase 1: {Name} | {Bounded commit-sized slice} | planned | — | — | {est. N} |

### Budget guardrail optional

See `standards/roadmap/ROADMAP_BUDGET_MODEL.md` for the full model.

- Estimated AI work units for this release: {N} · Max per phase: {N}
- Before dispatch: check the budget ledger; do not start a session whose estimate exceeds the per-session cap.
- Stop work if a usage-limit or credit-purchase prompt appears.
- At each phase closure, record raw observations only: units consumed, token usage, direct credit/API spend, human review minutes, and credit-prompt/overage flags.

---

## Release {X.Z} — {Next Release Title}

> Status: planned

**Goal:** {One sentence describing the functioning version this future release should deliver.}

### Product outcomes

- {Observable outcome for an operator or user}

### Engineering milestones

- [ ] {Concrete, testable implementation step}
- [ ] {Concrete, testable implementation step}

### Acceptance criteria

- {The release can be judged complete when this is verifiably true}

### Out of scope

- {Explicitly deferred work}

---

## 6. Recently Completed

{Preserve prior completed history here. Do not delete it. Every completed item carries an absolute completion date so the roadmap doubles as a project timeline.}

- [x] {Completed milestone or feature — short, verifiable description} *(completed: {YYYY-MM-DD})*

---

## 7. Cross-Cutting Engineering Work

These items support all releases and should be advanced continuously without obscuring the active release contract.

- [ ] {Ongoing quality or infrastructure task}
- [ ] {Ongoing quality or infrastructure task}

---

## 8. Risks and Design Guardrails

### Risks

- {Risk description — what could go wrong and why}

### Guardrails

- {Explicit rule to prevent a known failure mode}

---

## 9. Definition of Done for Release Execution

A release should not be marked `done` unless:

- All checklist items for that release are implemented, moved to a future release, or explicitly blocked.
- Acceptance criteria are verifiably satisfied.
- Validation commands and smoke tests have been run or explicitly documented as unavailable.
- UI elements are connected to real behavior rather than placeholders.
- Affected docs are updated where workflow or product behavior changed.
- Logging and error handling are sufficient to diagnose failures.
- Later releases were not partially started just to create the illusion of momentum.
- The release and each completed phase carry absolute completion dates in `YYYY-MM-DD` format where applicable.
