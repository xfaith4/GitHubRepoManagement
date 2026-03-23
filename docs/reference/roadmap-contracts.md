# Roadmap Contracts

This document explains what a roadmap contract is, how roadmap quality is evaluated, and how
release-scoped roadmaps should be authored for use with this tool.

---

## What Is a Roadmap Contract?

A **roadmap contract** is a normalized representation of a repository's `ROADMAP.md` file.
It is derived by parsing the markdown and extracting structure — checklist items, sections, release
boundaries, acceptance criteria, and out-of-scope declarations — into a stable, machine-readable model.

A roadmap contract differs from a plain roadmap document in the following ways:

| Aspect | Plain Roadmap | Roadmap Contract |
| -------- | -------------- | ----------------- |
| Format | Markdown prose | Normalized structured model |
| Purpose | Human communication | Audit, scoring, and dispatch input |
| Validity | Always exists (it is just a file) | Validated against a schema and rule pack |
| Maturity | Implicit | Scored and graded (L0–L4) |
| Completeness | Unknown | Explicitly checked against required sections |

A roadmap that passes all contract quality rules is described as **contract-ready** (L3) or
**orchestration-ready** (L4). Only repos at L3 or higher should be dispatched to Copilot.

---

## Roadmap Quality Scoring

When this tool scans a repository's roadmap, it produces a **maturity score** (0–100) by evaluating
the parsed contract against the rules defined in
`standards/roadmap/roadmap-audit-rules.json`.

The score determines the **maturity level**:

| Score | Level | Meaning |
| -------- | -------------- | ----------------- |
| 0 | L0 — Absent | No roadmap file |
| 1–39 | L1 — Informal | Roadmap exists but is structurally weak |
| 40–64 | L2 — Structured | Organized checkboxes but missing formal sections |
| 65–84 | L3 — Contract-Ready | Release sections, acceptance criteria, parseable |
| 85–100 | L4 — Orchestration-Ready | Passes all critical and warning rules |

See `standards/roadmap/ROADMAP_MATURITY_MODEL.md` for the full level definitions and what is
blocked or permitted at each level.

---

## How Roadmap Contracts Are Used

### In the Work Queue

The Work Queue view displays each repo's dispatch readiness, which depends on both documentation
quality and roadmap contract quality. A repo can only be `ready` for dispatch if:

- Its roadmap is at L3 or higher (or at minimum has pending items that are parseable)
- Its README and required docs pass the documentation standards check

### In Task Packaging

When a Copilot task is previewed or started, the roadmap contract provides:

- The next pending checklist item to execute
- The surrounding section context
- The release acceptance criteria
- The out-of-scope boundaries to include in guardrails

Without a contract-quality roadmap, the task package contains weaker context and may produce
less reliable results.

### In Audit Findings

Each repo receives audit findings per failed rule (e.g. `ROADMAP-004: no product intent section`).
These findings are displayed in the repo details panel with severity and recommended actions.

---

## How to Author a Contract-Quality Roadmap

To reach L3 or higher, a `ROADMAP.md` file should follow the canonical template at
`standards/roadmap/ROADMAP_TEMPLATE.md`.

### Required structure

```markdown
# {Project Name} — Product & Engineering Roadmap

## 1. Product Intent
{What the product does, who it serves, and why it exists.}

## 5. Release Roadmap

## Release X.Y — {Release Title}

**Goal:** {One sentence describing the outcome this release delivers.}

### Engineering milestones
- [ ] {Concrete, testable step}

### Acceptance criteria
- {Observable condition that indicates the release is complete}

### Out of scope
- {Work explicitly deferred from this release}
```

### Checklist item authoring

Good items:

- `- [ ] Add structured roadmap parser for checkbox items and section grouping`
- `- [ ] Implement doc-standards.json integrity check in CI smoke workflow`
- `- [ ] Surface nextPendingRoadmapItem in the main dashboard grid row`

Bad items (vague — will trigger `ROADMAP-010`):

- `- [ ] Improve roadmap`
- `- [ ] Refactor backend`
- `- [ ] Fix stuff`
- `- [ ] Update docs`

---

## Roadmap Repair

If a repo's roadmap is at L1 or L2, the **Roadmap Repair** preview workflow can propose a
normalized rewrite. Use the repair prompt at `standards/roadmap/roadmap-repair-prompt.md`.

Key constraints when applying a repair:

- **Never delete completion history** — checked items (`- [x]`) must be preserved exactly.
- **Never invent milestones** — repair only restructures what is already present.
- **Always preview before applying** — do not write back without operator approval.
- **Log the repair action** — record original maturity level, proposed level, and timestamp.

---

## Roadmap Standard Assets

The following files make up the Roadmap Contract Standard package:

| File | Purpose |
| ------ | --------- |
| `standards/roadmap/ROADMAP_TEMPLATE.md` | Canonical authoring template for new roadmaps |
| `standards/roadmap/roadmap-contract.schema.json` | JSON Schema for the normalized contract model |
| `standards/roadmap/roadmap-audit-rules.json` | Weighted scoring rules and maturity thresholds |
| `standards/roadmap/ROADMAP_MATURITY_MODEL.md` | Human-readable maturity level definitions |
| `standards/roadmap/roadmap-repair-prompt.md` | Prompt template for preview-based roadmap repair |

These files are loaded by the backend at runtime via `GET /api/roadmap/standard`. This means
audit rules and thresholds can be updated without code changes — only the JSON data files
need to be edited.

---

## API Reference

### `GET /api/roadmap/standard`

Returns the loaded roadmap standard assets (audit rules and maturity thresholds).

**Response:**

```json
{
  "success": true,
  "data": {
    "version": "1.0",
    "ruleCount": 10,
    "maturityLevels": ["L0-Absent", "L1-Informal", "L2-Structured", "L3-Contract-Ready", "L4-Orchestration-Ready"],
    "rules": [ /* array of rule objects from roadmap-audit-rules.json */ ],
    "maturityThresholds": { /* thresholds map from roadmap-audit-rules.json */ },
    "loadedAt": "2026-03-16T00:00:00.000Z"
  }
}
```

Returns `404` if the standard assets cannot be located. Returns `500` if the JSON is malformed.
