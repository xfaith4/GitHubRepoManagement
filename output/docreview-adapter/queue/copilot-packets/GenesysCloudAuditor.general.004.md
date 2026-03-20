# Queue Item: GenesysCloudAuditor.general.004

## Repo
- Name: GenesysCloudAuditor
- Path: G:\Development\20_Staging\GenesysCloudAuditor
- Repo Priority: High (70)

## Git State
- Branch: main
- Last Commit: 2026-03-18 12:34:23 -0400
- Uncommitted Changes: 16

## Batch
- Type: general
- Chunk: 4
- Complexity: medium
- Recommended Cooldown Seconds: 180
- Queue Score: 79
- Prompt Flavor: general-doc-improvement

## Files in Scope
- docs\examples\invalid-extensions.md
- docs\examples\stale-flows.md
- docs\examples\summary.md
- docs\extension-collision-tests.md

## Objectives
- Improve structure and readability
- Reduce repetition and vague wording
- Standardize formatting and headings
- Make content more deliberate and maintainable

## Warnings / Review Notes
- docs folder exists without docs/index.md
- Many markdown files fall into general or unclear categories
- Multiple README.md files detected across the repo
- Repo has 16 uncommitted change(s) - may be mid-surgery; verify before reviewing

## Constraints
- Preserve technical accuracy
- Do not invent implementation details, APIs, commands, or architecture facts
- Prefer structural improvements over cosmetic rewrites
- Keep changes concise, professional, and reviewable
- Use tree diagrams only where they materially improve understanding

## Suggested Copilot Prompt

```text
You are performing a general documentation improvement pass.

Priorities:
- improve clarity, structure, and professionalism
- reduce repetition and vague wording
- standardize headings and formatting
- make the documentation easier to navigate and maintain

Rules:
- preserve technical accuracy
- do not invent facts
- keep revisions concise and reviewable
```

