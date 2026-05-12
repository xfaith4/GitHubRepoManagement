ROLE
You are a senior product-minded full-stack engineer working on the GitHub Repo Management App.

OBJECTIVE
Update ROADMAP.md so it reflects the expanded product workflow:
portfolio indexing, differential scans, dashboard scoring, Operations tab,
AI README/ROADMAP improvement cycles, Copilot/agent prompt refinement,
agent-run monitoring, Actions-gated merge readiness, and later persistent
analytics.

SOURCE OF TRUTH
Use the current ROADMAP.md as the base. Preserve its disciplined structure:
release index, active release, future releases, cross-cutting engineering
work, risks/guardrails, roadmap contract standard, and definition of done.

REQUIRED CHANGES

1. Rename Release 1.7.5 to:
Portfolio Mission Alignment, Indexed Scanning, and Value-Ranked Work Planning

2. Expand Release 1.7.5 to include:
- canonical ordered repository index at output/index/repos.index.json
- normalized repo identity
- full scan artifact output under output/index/scans/
- differential scan mode
- GitHub Pages status/link
- latest GitHub Actions status/conclusion/timestamp
- GitHub createdAt and updatedAt timestamps
- README score, ROADMAP score, Documentation Health score
- dashboard signal model backed by the index

3. Replace the 1.7.5 phase table with:
- Phase 1: Assessment foundation
- Phase 2: Value ranking
- Phase 3A: Ordered portfolio index
- Phase 3B: GitHub metadata enrichment
- Phase 3C: Dashboard signal model
- Phase 4: Work Queue value display
- Phase 5: Expanded evaluator
- Phase 6: Prompt context packet foundation
- Phase 7: Collection report + docs

4. Add a new Release 1.8:
Operations Workspace and Prompt Refinement

It must include:
- Operations tab
- repo selection table
- repo detail workspace
- README/ROADMAP viewers
- GitHub panel
- audit findings panel
- prompt builder
- editable prompt preview
- custom operator instruction field
- prompt history per repo

5. Add a new Release 1.9:
AI Documentation Improvement Cycles

It must include:
- provider adapter contract
- OpenAI adapter
- Anthropic adapter
- built-in README templates
- built-in ROADMAP templates
- POST /api/ai/docs/improve/preview
- side-by-side diff viewer
- change summary
- estimated score movement
- improvement history
- explicit apply action with backup

6. Add a new Release 2.0:
Agent Run Monitoring and Actions-Gated Merge Readiness

It must include:
- agent-run ledger model
- active/completed/failed/blocked run status
- branch and PR association
- Actions refresh
- merge-readiness evaluator
- blocking conditions:
  - dirty worktree
  - no PR
  - failing/pending Actions
  - merge conflicts
  - missing validation evidence
  - unresolved audit blockers
- operator-controlled merge only after readiness passes

7. Move existing releases:
- Persistent Data Layer becomes Release 2.1
- API Authentication/Network Security and Guided Onboarding/GitHub App Integration become Release 2.2
- Portfolio Analytics, Trend Visualization, and Distribution becomes Release 2.3
- Agent Integration Protocol and AI Repair Loop becomes Release 2.4

8. Update Release Index to match the new numbering.

9. Add cross-cutting engineering work for:
- stable repo identity model
- preview-first writes
- source-explainable dashboard badges
- stale-cache diagnostics
- scan performance budget logging

10. Add guardrails for:
- AI-generated docs are never accepted without side-by-side operator review
- merge readiness requires PR, Actions, validation evidence, and blocker checks
- dashboard badges must drill into source data

CONSTRAINTS
- Preserve completed release history references.
- Do not delete useful existing roadmap content unless it is superseded by the new structure.
- Keep implementation-state vocabulary unchanged.
- Keep release sections agent-usable with product outcomes, engineering milestones, acceptance criteria, and out-of-scope notes.
- Use the existing markdown style.
- Do not mark planned work as done.
- Do not invent shipped implementation.

ACCEPTANCE TESTS
- ROADMAP.md has no duplicate release numbers.
- Release Index matches the release sections below.
- Active release is still 1.7.5.
- Releases 1.8, 1.9, 2.0, 2.1, 2.2, 2.3, and 2.4 exist in order.
- The roadmap explicitly covers:
  - ordered repo index
  - differential scans
  - README/ROADMAP scoring
  - GitHub Pages status
  - Actions status
  - Operations tab
  - AI improvement cycles
  - prompt refinement
  - agent-run monitoring
  - Actions-gated merge readiness
- Run:
  pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md
- Fix any structural errors reported by the validator.
