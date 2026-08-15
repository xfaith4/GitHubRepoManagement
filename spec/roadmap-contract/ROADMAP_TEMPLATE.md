# {Project Name} — Product & Engineering Roadmap

> Project status: {Active | Paused | Archived}
>
> Product direction: {One-sentence description of the product direction and intended outcome}

<!--
AUTHORING RULES (not rendered as a section; parsers and agents should still read this comment)

1. SINGLE SOURCE OF TRUTH FOR "ACTIVE": the active release is whichever release
   section below carries `> Status: active`. Do not restate which release is
   active up here in the header — a second field here would just be a second
   place for that fact to go stale. Exactly one release should be `active` at
   any time (see Section 8 guardrail).

2. STATUS VOCABULARY IS LOWERCASE AND FIXED: planned | active | blocked |
   validation | done | archived. Parsers normalize case and common aliases
   (e.g. "in progress" -> active, "shipped" -> done), but always author in
   lowercase to avoid relying on that normalization.

3. MILESTONE IDS (recommended, not required for L3/L4 scoring): prefix a
   checklist item with a short stable tag so it can be referenced from
   roadmap-events.jsonl and from other milestones without relying on the
   wording staying the same:
     - [ ] [[M3]] Implement retry backoff in Poll-Provider.ps1
   Reference a dependency inline when order matters and isn't top-to-bottom:
     - [ ] [[M4]] Wire backoff into dispatcher (depends: M3)
   Once assigned, an ID is permanent — never reassign it to a different item.

4. TOKEN / COST DATA LIVES IN THE LEDGER, NOT HERE: do not hand-maintain a
   running token or dollar total inline in this file. That number decays the
   moment it's not updated. roadmap-events.jsonl is the append-only, always-
   current source; ROADMAP_BUDGET_MODEL.md explains how it's valued. The
   optional Phase plan table below is a point-in-time *estimate* for planning,
   not a running actual.

5. "Recently Completed" (Section 6) is NOT a mirror of the `[x]` items already
   sitting inside active/planned release sections above — leave those where
   they are. Section 6 only holds completed work whose original release
   section has since been archived or removed from Section 5, so that
   history survives even after the section that produced it is gone.
   Alternatively, that surviving history may live in a separate archive file
   instead of Section 6 — a supported layout, not a deviation. See the
   "External archive option" under Section 6 for the required pointer
   convention that makes the split self-describing.

6. "Dispatch readiness" in the Release Index (Section 4) is a computed field
   (derived from `normalizedStatus` + open audit findings), not something to
   hand-author differently from what the tooling would compute. If you're
   filling this out by hand because no tooling exists yet, treat it as a
   best-effort mirror of release status + known blockers, not a separate
   judgment call.
-->

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

_Exactly one row above should show `active`. If a second release needs to become active, close out or explicitly re-status the first one in the same edit._

---

## 5. Release Roadmap

## Release {X.Y} — {Release Title}

> Status: active
>
> Completed: {YYYY-MM-DD — include only when status is done}

**Goal:** {One sentence describing the functioning version this release should deliver. State what the product can do after this release that it cannot do before.}

### Product outcomes

- {Observable outcome for an operator or user}
- {Observable outcome for an operator or user}

### Engineering milestones

- [x] [[M1]] {Completed implementation step} *(completed: {YYYY-MM-DD})*
- [ ] [[M2]] {Concrete, testable implementation step — include file, function, command, or behavior where possible}
- [ ] [[M3]] {Concrete, testable implementation step} (depends: M2)

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

- {Risk, blocker, or "None currently known."}

### Dependencies

- {Dependency, prerequisite, or "None."}

### Known issues

- {Known issue, pipeline feedback item, or "None currently known."}

### Traceability

- {Issue, PR, commit, ADR, workflow, test file, doc path, or "Not yet linked."} Reference milestone IDs where relevant, e.g. "M3 -> PR #482".

### Phase plan optional

_Planning-time estimate only — actuals are recorded in `roadmap-events.jsonl`, not edited back into this table._

| Phase | Scope | Status | Completed | Work units est → actual |
| --- | --- | --- | --- | --- |
| Phase 1: {Name} | {Bounded commit-sized slice} | planned | — | {est. N} → {see ledger} |

### Budget guardrail optional

See `standards/roadmap/ROADMAP_BUDGET_MODEL.md` for the full model.

- Estimated AI work units for this release: {N} · Max per phase: {N}
- Before dispatch: check the budget ledger; do not start a session whose estimate exceeds the per-session cap.
- Stop work if a usage-limit or credit-purchase prompt appears; record a `quota.exhausted` event.
- Actual consumption (units, tokens, spend, review minutes) is recorded as raw events at each phase closure — never re-typed into this file.

---

## Release {X.Z} — {Next Release Title}

> Status: planned

**Goal:** {One sentence describing the functioning version this future release should deliver.}

### Product outcomes

- {Observable outcome for an operator or user}

### Engineering milestones

- [ ] [[M1]] {Concrete, testable implementation step}
- [ ] [[M2]] {Concrete, testable implementation step}

### Acceptance criteria

- {The release can be judged complete when this is verifiably true}

### Out of scope

- {Explicitly deferred work}

---

## 6. Recently Completed

{History preserved from release sections that have since been archived or removed from Section 5. Do not delete. Every completed item carries an absolute completion date so the roadmap doubles as a project timeline. Do not duplicate items still visible inline in Section 5 — they belong there, not here.}

- [x] {Completed milestone or feature — short, verifiable description} *(completed: {YYYY-MM-DD}, from Release {X.Y})*

### External archive option

A repository MAY keep this history in a separate archive file instead of in
this section — for example `docs/history/completed-releases.md`. The split
layout is a **supported** shape of this standard, not a deviation. Using it
requires all three of the following, so an external archive stays
distinguishable from deleted history:

1. **Pointer line (required).** The roadmap's header blockquote carries a link
   line naming the archive file, so the split is self-describing:

   ```markdown
   > **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
   ```

2. **Verbatim moves only.** Completed release sections and `- [x]` items move
   to the archive unchanged — same wording, same checklist syntax, same
   absolute completion dates. Archiving is never a license to rewrite or
   summarize history, exactly as with in-file history above.

3. **This section defers to the archive.** Replace the item list here with a
   one-line reference to the archive file rather than maintaining history in
   two places.

Under the split layout, low in-file completed counts are expected and carry no
penalty; the pointer line is what marks history as archived rather than lost.
A roadmap repair must preserve the pointer line and must not copy archived
history back into the roadmap.

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

- Only one release may carry `Status: active` at a time; the active-release blockquote in Section 5 is the sole source of truth for this.
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
- Any milestone IDs referenced elsewhere (events, PRs, other milestones' `depends:` tags) still resolve — none were silently renumbered or removed.
