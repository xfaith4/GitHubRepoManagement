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

### Completion dates and token usage

Completed work should carry an absolute completion date so the roadmap doubles
as a referencable, reportable project timeline:

- **Completed checklist items:** append an italic annotation —
  `- [x] Add structured roadmap parser *(completed: 2026-06-11)*`
- **Completed releases:** add a `> Completed: YYYY-MM-DD` line under the
  release status, and optionally `> Token usage: ~N tokens`.
- **Multi-phase releases:** use the optional phase plan table from the
  template, which carries `Completed` and `Token usage` columns per phase.

Conventions:

- Always use absolute ISO dates (`YYYY-MM-DD`), never relative wording
  ("last week", "recently").
- Token usage is optional and approximate (e.g. `~1.2M tokens`). Record it
  when the work was executed by a metered AI/coding agent and the usage is
  known from dispatch or run records; omit it rather than estimating after
  the fact.
- For full per-phase cost accounting — cash cost, quota/session-window
  burn, and opportunity cost tracked separately, plus budget guardrails
  for agent sessions — see
  `standards/roadmap/ROADMAP_BUDGET_MODEL.md`.
- Dates and token annotations are additive metadata. They must not alter the
  checklist syntax (`- [x]`, `- [ ]`) that the roadmap parser depends on,
  and roadmap repairs must preserve them exactly like completion history.

---

## The Release Execution Contract

Beyond document shape, a roadmap is an **execution contract**. The
`tools/Test-RoadmapStructure.ps1` validator checks whether each release — and
especially the *active* one — carries enough information to be dispatched,
validated, and merged against. See
[docs/operations/roadmap-validation.md](../operations/roadmap-validation.md)
for how to run it, the full finding-code table, and configuration.

### Canonical release block

```markdown
## Release X.Y — Title

**Status:** planned | active | blocked | validation | done | archived

**Goal:** One sentence describing what the product can do after this release.

**Problem / motivation:** Why this release exists.

**Product outcomes:**
- Observable outcome for an operator or user.

**Engineering milestones:**
- [ ] Concrete, testable implementation step.

**Acceptance criteria:**
- [ ] Observable, verifiable condition for "done".

**Validation plan:**
- [ ] Run `npm test`, `npm run build`, and `Invoke-Pester`; CI must be green.

**Risks and blockers:**
- What could go wrong, or what is currently blocking the work.

**Dependencies:**
- Upstream releases, services, or external work this release needs.

**Known issues / discovered during development:**
- Bugs, failed tests, CI/build failures, and follow-ups found during execution.

**Non-goals:**
- Work explicitly out of scope for this release.

**Traceability:**
- Issue: #123
- PR: #456
- Tests: `tests/...`
- ADR: `docs/adr/...`
```

### Allowed statuses

| Status | Meaning |
| ------ | ------- |
| `planned` | Proposed; not yet started. |
| `active` | The single release currently being executed. |
| `blocked` | Started but stopped by a named blocker. |
| `validation` | Implementation complete; under test / verification. |
| `done` | Complete; should move to `docs/history/completed-releases.md`. |
| `archived` | Historical; full detail should not dominate the active roadmap. |

Legacy wording is normalized automatically: `pending` → `planned`,
`in progress` → `active`, `complete` / `completed` → `done`.

### Required vs recommended sections

- **Always required (every release):** Goal, Product outcomes, Engineering
  milestones, Acceptance criteria.
- **Required/strongly recommended for `active` / `blocked` / `validation`:**
  Status, Validation plan, Risks and blockers, Dependencies,
  Known issues / discovered during development, Traceability.
- **Recommended for `planned` / future:** Problem / motivation, Dependencies,
  Non-goals.
- **`blocked`** must list at least one blocker. **`validation`** must have a
  meaningful validation plan. **`done`** should have its criteria checked and
  should not remain as full active detail in `ROADMAP.md`.

### Good vs weak release blocks

**Good** — observable, traceable, validatable:

```markdown
## Release 2.0 — Agent Run Monitoring

**Status:** active

**Goal:** Operators can watch a dispatched agent run and gate merge on CI.

**Acceptance criteria:**
- [ ] `GET /api/agent/run/:id` returns live status, verified by `npm test`.

**Validation plan:**
- [ ] `npm run build`, `Invoke-Pester ./backend`, and the CI smoke workflow pass.

**Risks and blockers:**
- GitHub Actions rate limits may throttle status polling.

**Dependencies:**
- Release 1.9 prompt-dispatch records.

**Known issues / discovered during development:**
- None currently known.

**Traceability:**
- Issue: #142  ·  PR: #150  ·  Tests: `tests/agent-run.Tests.ps1`
```

**Weak** — vague, unverifiable, untraceable (flags `RQ004`, `RQ005`, `RQ006`,
`RQ009`):

```markdown
## Release 2.0 — Monitoring

**Status:** active

**Acceptance criteria:**
- [ ] works
- [ ] polish

**Validation plan:**
- [ ] make sure it's good
```

---

## Completion History and the External Archive

By default, completed work that leaves the Release Roadmap survives inside the
roadmap itself, in the template's "Recently Completed" section (Section 6).

A repository may instead **externalize** that history: completed release
sections and checked items move **verbatim** to a separate history file —
conventionally `docs/history/completed-releases.md` — and `ROADMAP.md` carries
open work only. This split layout is a **supported shape of the standard**,
not a deviation, provided the roadmap is self-describing about it:

- **Pointer line (required).** The roadmap's header blockquote must carry a
  link line naming the archive file:

  ```markdown
  > **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
  ```

- **Verbatim moves only.** Archived sections and `- [x]` items keep their
  wording, checklist syntax, and absolute completion dates unchanged.
- **No penalty, no invisibility.** Nothing in the audit rules penalizes a
  split repo, but without the pointer line an external archive is
  indistinguishable from deleted history. The pointer is what marks in-file
  completion counts (e.g. the contract's `completedCount`) as "archived
  elsewhere" rather than "never done" — expect them to sit near zero in a
  split repo.
- **Repair must respect the split.** A roadmap repair must preserve the
  pointer line and must never copy archived history back into the roadmap,
  just as it must never delete in-file completion history.

This repository is itself the reference example of the split layout: its
`ROADMAP.md` carries open work only, and the header pointer links to
[`docs/history/completed-releases.md`](../history/completed-releases.md),
which holds the full text of every completed release.

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
| `standards/roadmap/ROADMAP_BUDGET_MODEL.md` | Cost/quota accounting model and budget guardrails for agent-driven phases |

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
