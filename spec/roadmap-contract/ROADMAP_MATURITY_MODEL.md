# Roadmap Maturity Model

This model grades whether a `ROADMAP.md` is safe for roadmap-driven coding-agent dispatch.
The score is computed from `roadmap-audit-rules.json` against the normalized contract produced by `Test-RoadmapContract.ps1`.

## Overview

| Level | Name | Score range | Dispatch safety |
| --- | --- | ---: | --- |
| L0 | Absent | 0 | Not dispatchable — no roadmap exists. |
| L1 | Informal | 1–39 | Not dispatchable — too ambiguous or unparseable. |
| L2 | Structured | 40–64 | Manual dispatch only. Operator must interpret scope. |
| L3 | Contract-Ready | 65–84 | Supervised dispatch permitted. Operator reviews task package before launch. |
| L4 | Orchestration-Ready | 85–100 | Autonomous or semi-autonomous dispatch permitted. Requires zero critical and warning findings. |

## Level definitions

### L0 — Absent

No roadmap file exists at the expected path.

Blocked:

- Roadmap parsing
- Next-item selection
- Agent dispatch
- Maturity scoring beyond L0

Required to reach L1:

- Create `ROADMAP.md` from `standards/roadmap/ROADMAP_TEMPLATE.md`.

### L1 — Informal

A roadmap exists but is missing enough structure to be treated as a safe work contract.
It may be prose-only, a flat list, unparseable, vague, or missing core product intent.

Blocked:

- Reliable automated dispatch
- Trustworthy task packaging
- Completion tracking by release

Required to reach L2:

- Add parseable checklist items.
- Rewrite vague items into concrete milestones.
- Add a product intent/scope/purpose section.

### L2 — Structured

The roadmap has useful checklist structure and some grouping, but it still lacks enough release-contract detail for supervised dispatch.

Typical gaps:

- No formal `## Release X.Y — Title` sections
- Missing acceptance criteria on one or more releases
- Missing clear release statuses
- Insufficient validation context

Permitted:

- Manual dispatch with operator interpretation
- Human roadmap repair

Required to reach L3:

- Use formal release sections.
- Add acceptance criteria to every non-archived release.
- Use known release status vocabulary.

### L3 — Contract-Ready

The roadmap is parseable, release-scoped, and suitable for supervised coding-agent dispatch.

Required properties:

- Product intent exists.
- Release sections are stable and machine-detectable.
- Every non-archived release has acceptance criteria.
- Critical findings are absent.
- Any remaining warnings are understood and accepted by an operator.

Permitted:

- Supervised Copilot/coding-agent dispatch
- Portfolio work queue inclusion
- Task packaging from next pending item

Required to reach L4:

- Resolve all warning findings.
- Add out-of-scope boundaries to every non-archived release.
- Ensure checklist items are concrete and testable.
- Keep only one active execution target.
- Provide active-release validation and traceability.
- Define at least two releases for forward visibility.

### L4 — Orchestration-Ready

The roadmap is a complete work contract. It supports autonomous or semi-autonomous dispatch with minimal operator intervention.

Required properties:

- Score is within the L4 range.
- There are zero critical findings.
- There are zero warning findings.
- Release sections, acceptance criteria, and out-of-scope boundaries are present.
- Multiple releases provide forward visibility.
- Active execution has a validation plan.
- Done releases contain no unchecked work.

Permitted:

- Autonomous or semi-autonomous task dispatch
- Automated portfolio orchestration
- Automated roadmap drift detection
- Mature work-queue prioritization

## Score computation

```text
score = 100 - sum(scoreWeight for each failed rule)
```

The score is clamped between 0 and 100.

Then maturity caps are applied. For example:

- Missing roadmap caps maturity at L0.
- Parse error caps maturity at L1.
- Missing release sections caps maturity at L2.
- Missing acceptance criteria caps maturity at L2.
- Any critical finding caps maturity at L1.
- Any warning finding caps maturity at L3, because L4 requires no critical or warning findings.

## Maintenance rule

When `roadmap-audit-rules.json` changes, update this document and the schema together. The rule pack is the executable source of truth; this document explains the rules in human terms.
