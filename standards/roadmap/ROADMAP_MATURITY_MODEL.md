# Roadmap Maturity Model

This document defines the five maturity levels used to grade roadmap quality across managed repositories.
Each level describes what the roadmap contains and what can be safely done with it.

---

## Overview

| Level | Name | Score Range | Dispatch Safety |
|-------|------|-------------|-----------------|
| L0 | Absent | 0 | Not dispatchable — no roadmap |
| L1 | Informal | 1–39 | Not dispatchable — too ambiguous |
| L2 | Structured | 40–64 | Manual dispatch with caution |
| L3 | Contract-Ready | 65–84 | Supervised dispatch permitted |
| L4 | Orchestration-Ready | 85–100 | Autonomous dispatch permitted |

---

## Level Definitions

### L0 — Absent

**Description:** No ROADMAP.md or equivalent file exists in the repository.

**What is true at this level:**
- There is no roadmap to read, parse, or evaluate.
- No next work item can be surfaced from this repo.
- Dispatch readiness cannot be determined without a roadmap.

**What is blocked at this level:**
- All roadmap-driven task packaging.
- Any automated dispatch.
- Roadmap audit scoring.

**Required to reach L1:**
- Create a ROADMAP.md file with at least minimal content describing the project's direction.

---

### L1 — Informal

**Description:** A roadmap file exists but uses a flat or unstructured format. It may contain prose, a single list, or vague intentions without a clear release structure, acceptance criteria, or concrete tasks.

**What is true at this level:**
- The roadmap file is present and parseable (contains checkbox items).
- Work items may exist but are not bounded to a specific release.
- Items may be vague (e.g. "improve UI", "refactor backend").
- No acceptance criteria or out-of-scope boundaries are defined.

**What is blocked at this level:**
- Reliable automated dispatch — context is too ambiguous.
- Trustworthy task packaging — scope and doneness are unclear.

**Required to reach L2:**
- Add at least three concrete, testable checklist items.
- Remove or rewrite vague placeholder items.

---

### L2 — Structured

**Description:** The roadmap is organized with checklist items and some grouping, but may still lack formal release sections, acceptance criteria, or explicit out-of-scope boundaries.

**What is true at this level:**
- The roadmap has pending checkbox items that are concrete.
- Items are grouped into recognizable sections, even if not formal releases.
- A product intent or scope description is present.

**What is possible at this level:**
- Manual dispatch is reasonable — an operator can read the roadmap and identify next work.
- Automated task preview can extract a next pending item.

**Required to reach L3:**
- Reorganize into release-scoped sections with headings in the form `## Release X.Y — Title`.
- Add acceptance criteria to each release section.

---

### L3 — Contract-Ready

**Description:** The roadmap uses a formal release-scoped structure, includes acceptance criteria, and is fully parseable. It provides enough context for supervised Copilot dispatch.

**What is true at this level:**
- Release sections use consistent headings with stable release identifiers.
- Each release has a goal statement, checklist milestones, and acceptance criteria.
- The roadmap can be machine-parsed with high confidence.
- Product intent and principles are documented.

**What is possible at this level:**
- Supervised Copilot dispatch — an operator reviews the task package before launch.
- Roadmap audit scoring and maturity tracking.
- Task history tied to specific roadmap items and releases.

**Required to reach L4:**
- Add out-of-scope boundaries to each release section.
- Ensure all checklist items are concrete and testable (no vague placeholders).
- Ensure there are at least two release sections providing forward visibility.

---

### L4 — Orchestration-Ready

**Description:** The roadmap is a complete, machine-readable work contract that passes all critical and warning audit rules. It supports autonomous or semi-autonomous Copilot dispatch with minimal operator intervention.

**What is true at this level:**
- All L3 criteria are met.
- Out-of-scope boundaries are defined for each release.
- All checklist items are concrete, testable, and implementation-specific.
- Multiple releases are defined, providing a clear forward plan.
- The roadmap format is stable enough for reliable parsing across scan cycles.

**What is possible at this level:**
- Semi-autonomous or fully automated Copilot task dispatch.
- Portfolio-level orchestration using the execution queue.
- Automated detection of completed items and roadmap drift.

---

## How the Score Is Computed

The maturity score (0–100) is calculated by evaluating the roadmap contract against the rules defined in
`roadmap-audit-rules.json`. Each rule has a `scoreWeight`. The score starts at 100 and points are
deducted for each failing rule based on its weight.

```
score = 100 - sum(scoreWeight for each failing rule)
```

The resulting score maps to a maturity level using the thresholds defined in `roadmap-audit-rules.json`.

---

## Using the Maturity Model

### As an operator

- Use the Work Queue view to see each repo's maturity level and score.
- Repos at L3 or L4 are candidates for Copilot dispatch.
- Repos at L0–L2 should receive roadmap repair before dispatch.

### As a coding agent

- Do not assume a roadmap is valid; check the maturity level first.
- Use the roadmap contract model (from `roadmap-contract.schema.json`) as the source of truth.
- Treat L0 and L1 as insufficient context for safe task packaging.
- Treat acceptance criteria as the definition of done for each release.

---

## Maintenance

This maturity model should be updated when:

- The audit rule pack (`roadmap-audit-rules.json`) is extended with new rules.
- The product's requirements for Copilot dispatch readiness change.
- New evidence emerges about what makes a roadmap reliably parseable or actionable.
