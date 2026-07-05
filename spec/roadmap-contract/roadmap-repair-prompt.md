# Roadmap Repair Prompt

Use this prompt when a repository roadmap is too informal for reliable dispatch and must be repaired into the canonical roadmap contract format.

The repair process must produce a **preview**, not an immediate file mutation.

## When to use

Use this when:

- Contract maturity is L1 or L2.
- The roadmap is a flat checklist.
- Release sections are missing or inconsistent.
- Acceptance criteria or out-of-scope boundaries are missing.
- Checklist items are vague and not testable.
- Product intent is missing.

Do not use this when:

- The roadmap is already L3 or L4 and only needs minor edits.
- Completion history cannot be verified.
- Active in-flight work exists outside the roadmap and has not been captured.

## Repair prompt template

```text
You are repairing ROADMAP.md for repository: {REPO_NAME}.

Current maturity level: {L0|L1|L2}
Current maturity score: {SCORE}
Audit findings:
{PASTE FINDINGS: rule ID, severity, message, recommended action}

Your task is to produce a PREVIEW of a repaired ROADMAP.md following:
standards/roadmap/ROADMAP_TEMPLATE.md

Rules:

1. Preserve all checked items (`- [x]`) exactly as they appear.
   - Do not delete them.
   - Do not reword them.
   - Preserve completion dates and token/cost annotations exactly.
2. Reorganize unchecked items into bounded release sections using:
   `## Release {X.Y} — {Title}`
3. Add a Product Intent section if missing.
4. Add or repair a Release Index.
5. Add acceptance criteria to every non-archived release.
6. Add out-of-scope boundaries to every non-archived release.
7. Add validation plan, risks/blockers, dependencies, known issues, and traceability for the active release.
8. Rewrite vague unchecked checklist items into concrete, testable milestones.
9. Do not invent features, requirements, or milestones not already implied by the current roadmap.
10. Do not mark pending work complete.
11. Do not create more than one active release.
12. Do not use an `Immediate Next Focus` section. The active release is the execution focus.

Return the FULL proposed ROADMAP.md content, clearly labeled as a PREVIEW.
Do not modify files.

Current ROADMAP.md:
---
{PASTE CURRENT ROADMAP.MD CONTENT}
---
```

## Post-preview checklist

Before applying the repaired roadmap, verify:

- [ ] Every original checked item is present and unchanged.
- [ ] Completion dates and token/cost annotations are preserved.
- [ ] No new features were invented.
- [ ] Every non-archived release has acceptance criteria.
- [ ] Every non-archived release has out-of-scope boundaries.
- [ ] Exactly one release is active, blocked, or in validation.
- [ ] The active release has validation, risks/blockers, dependencies, known issues, and traceability.
- [ ] Release identifiers remain stable.
- [ ] The proposed file is valid markdown and parseable by `Test-RoadmapContract.ps1`.

## Applying the repair

After operator approval:

1. Replace `ROADMAP.md` with the approved preview.
2. Run `tools/Invoke-RoadmapValidation.ps1`.
3. Confirm the new maturity level.
4. Log the repair action with old level, new level, operator approval, and timestamp.
