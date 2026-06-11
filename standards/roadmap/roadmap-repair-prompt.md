# Roadmap Repair Prompt

Use this prompt template when requesting a roadmap repair or rewrite from a coding agent (such as GitHub Copilot).
The goal is to produce a normalized, contract-quality roadmap from an informal or incomplete one — without losing
genuine completion history and without inventing work that was not already intended.

---

## When to Use This Prompt

Use this prompt when:

- A repo's roadmap is at maturity level L1 (Informal) or L2 (Structured) and needs to be elevated.
- The roadmap is a flat checklist that needs to be reorganized into bounded release sections.
- Acceptance criteria and out-of-scope boundaries are missing.
- The roadmap has vague placeholder items that need to be rewritten as concrete milestones.
- The roadmap needs a product intent section or principle statements.

Do **not** use this prompt when:

- The roadmap is already at L3 or L4 (it may only need minor augmentation, not a rewrite).
- You cannot verify what was genuinely completed (do not guess at completion history).
- The roadmap has active in-flight work that has not been captured yet.

---

## Instructions for Previewing a Repair

1. Read the current roadmap (`ROADMAP.md`) in full before proposing any changes.
2. Identify all checked items (`- [x]`) and treat them as confirmed completion history — do not delete or rewrite them.
3. Identify all unchecked items (`- [ ]`) and assess whether they are concrete and testable.
4. Identify any missing structural elements: product intent, release sections, acceptance criteria, out-of-scope.
5. Generate a **proposed** normalized roadmap following the canonical template (`ROADMAP_TEMPLATE.md`).
6. Present the proposed roadmap as a diff or side-by-side preview — do not apply it until the operator approves.
7. Log the repair action with: source roadmap state, proposed state, operator approval status, and timestamp.

---

## Repair Prompt Template

Copy this prompt and fill in the placeholders before submitting to a coding agent:

```
You are repairing the ROADMAP.md for the repository: {REPO_NAME}.

Current roadmap maturity level: {L0|L1|L2}
Audit findings that triggered this repair:
{PASTE AUDIT FINDINGS HERE — one per line, including rule ID, severity, and message}

Your task is to produce a PREVIEW of a repaired ROADMAP.md that:

1. Preserves all checked items (- [x]) exactly as they appear — do not delete or reword them,
   including any *(completed: YYYY-MM-DD)* or token-usage annotations attached to them.
2. Reorganizes unchecked items into bounded release sections using the heading format:
   ## Release {X.Y} — {Title}
3. Adds a product intent section at the top if one does not already exist.
4. Adds acceptance criteria to each release section.
5. Adds out-of-scope boundaries to each release section where feasible.
6. Rewrites any vague checklist items into concrete, testable, implementation-specific steps.
   Vague examples to avoid: "improve X", "refactor Y", "fix stuff", "finish Z".
7. Does NOT invent new features, requirements, or milestones that are not already implied by the current content.
8. Does NOT mark any pending items as complete unless directed to do so.

Use the canonical template at: standards/roadmap/ROADMAP_TEMPLATE.md

Present the output as the FULL proposed ROADMAP.md content, clearly labeled as a PREVIEW.
Do not modify the actual ROADMAP.md file without explicit operator approval.

Current ROADMAP.md content:
---
{PASTE CURRENT ROADMAP.MD CONTENT HERE}
---
```

---

## Post-Preview Checklist

Before applying the repaired roadmap, verify:

- [ ] All checked items (`- [x]`) from the original are present and unchanged.
- [ ] Completion dates and token-usage annotations from the original are preserved exactly.
- [ ] No new milestones were invented that do not reflect the original intent.
- [ ] Every release section has a goal statement, checklist, and acceptance criteria.
- [ ] Out-of-scope sections are accurate (not used to quietly defer real requirements).
- [ ] Release identifiers are stable and not renumbered from prior completed releases.
- [ ] The product intent section accurately describes the repo's actual purpose.
- [ ] The proposed file is valid markdown and parseable by the roadmap parser.

---

## Applying the Repair

Once the preview has been reviewed and approved:

1. Replace the contents of `ROADMAP.md` with the approved preview content.
2. Run a roadmap scan to verify the new file parses cleanly.
3. Confirm the maturity level has improved (L2 or higher).
4. Log the repair in the operations log with: repo name, original maturity level, new maturity level, and timestamp.

---

## Constraints

- Do not auto-apply roadmap rewrites. Always require explicit operator approval.
- Do not delete genuine completion history under any circumstances.
- Do not invent requirements. If the current roadmap is too sparse to restructure, state that and recommend adding content manually first.
- Do not change release identifiers that are referenced in task history.
