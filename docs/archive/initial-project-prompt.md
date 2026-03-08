# GitHub Repository Management Dashboard

Consolidate three Windows-focused GitHub repository-management tools into a single, well-documented Repository Management Dashboard (PowerShell/.NET, Windows-first). Produce commit-ready Markdown docs, architecture, migration plan, and feature artifacts; inspect local repos first or request uploads.

## Role

- Act as a technical design & documentation specialist and senior engineer with deep experience building and operating PowerShell- and .NET-based Windows automation tools.
- Work pragmatically and operationally: inspect the provided repos, extract features and patterns, design a maintainable Windows-first target architecture and UI/UX alignment, and produce production-ready GitHub-flavored Markdown artifacts and a sequenced migration plan a senior engineer can execute.

## Goals

- Read and review code and documentation from the three repository paths below. If any path is unreadable, immediately request an upload (zip/tar) of that repo and continue by producing templates with explicit TODO placeholders and a precise checklist of missing files.
  - G:\Development\20_Staging\GitHubRepoManagerDashboard
  - G:\Development\Doc_Review_Inventory
  - G:\Development\Repo_reconciliation-dashboard
- Produce a feature/component inventory and an overlap/conflict analysis across the three repos.
- Define a Windows-first, maintainable target architecture (backend tooling + frontend features).
- Recommend consistent UI/UX patterns for navigation, status/health, error handling, and operator interactions.
- Produce a prioritized, sequenced, low-risk migration plan that preserves usability and operational continuity.
- Harmonize documentation into a consistent structure, style, and cross-linked docs site.
- Produce a unified feature roadmap (delivered vs outstanding).
- Provide precise TODOs where repository-specific details are required but unavailable.

## Context

- Platform: single Windows workstation / home-lab environment. PowerShell and .NET are first-class citizens. Front-end should be lightweight and maintainable (plain HTML/JS or a simple SPA).
- Audience: senior cloud/automation engineers; expect technical precision, explicit trade-offs, and operational details.
- Priorities: robustness, maintainability, simplicity, and observability (structured logging, metrics, health checks).
- Operational note: Write-Host is available for console output. Scripts will run with typical home-lab permissions (not necessarily elevated unless noted).
- Do not invent concrete runtime/library versions. Where versions are unknown, add explicit TODOs and assumptions to verify.

Deliverables (exact, commit-ready Markdown artifacts)
Produce these files in a repository layout, ready to commit. Use GitHub-flavored Markdown, include Mermaid diagrams with ASCII fallbacks, and include PowerShell examples with inline comments.

## Root

- README.md (repo root)
  - Project overview and purpose.
  - Key features summary with link to docs/reference/features.md.
  - Architecture summary with link to docs/architecture/architecture.md.
  - Prerequisites and environment assumptions (Windows, PowerShell and .NET guidance — do NOT invent concrete versions; mark TODOs to verify).
  - Installation and setup: repo layout, build/run instructions for backend and frontend, configuration and secrets guidance.
  - Usage: common workflows, example invocations and scripts (realistic PowerShell snippets with inline comments).
  - Troubleshooting and diagnostics (how to enable verbose logging).
  - Observability summary (where logs/metrics/health endpoints live and how to read them).
  - Maintenance guidance and links to migration, features, and roadmap docs.
  - Surface a short migration-phase checklist (3–6 actionable steps) at the top for immediate action.

## Docs directory (docs/)

- docs/architecture/architecture.md — Architecture and Design Document
  - Executive summary: consolidation intent, clear non-goals, and success criteria.
  - Current-state overview — per repo:
    - purpose, major features, key components, dependencies, I/O.
    - known issues and gaps.
    - If code not available, include precise TODO placeholders specifying exact files/areas needed.
  - Feature inventory and overlap matrix: list features by repo; overlaps; conflicts; gaps; disposition (keep/merge/retire/defer).
  - Target architecture:
    - Components/services/modules (backend and frontend) with responsibilities and clear boundaries.
    - Data model and storage (if any), configuration strategy, secrets handling.
    - Interactions and data flow: Mermaid sequence/flow diagrams plus ASCII fallback.
    - Error handling and resilience: retry policies, idempotency guidance, backoff, circuit-breaker ideas if applicable.
    - Observability: structured logging schema and fields; metric names/types (counter/gauge/histogram) with descriptions; health checks/endpoints and expected semantics.
    - Windows-specific considerations: PowerShell/.NET runtime choices (no concrete versions), scheduling options, filesystem and UAC/service vs scheduled task trade-offs.
  - Technology decisions: chosen stacks/libraries with rationale and trade-offs; brief alternatives considered.
  - UI/UX alignment: navigation/layout, status/health surfaces, table/form patterns, pagination, filtering, error & empty states.
  - Testing and quality approach: unit/integration testing strategy for PowerShell and .NET, static analysis, linting/formatting, local dev workflow.
  - Risks and mitigations and ADR-style decision log (inline or linked).

- docs/planning/migration.md — Migration Plan (merge-specific)
  - Scope: explicit mapping of included repos and components; what will be merged vs deprecated.
  - Pre-migration checklist: backups, branch/tagging, CI gating, test baselines.
  - Mapping: explicit mapping of components/files/scripts from each source repo to target locations, proposed renames, and shared utilities to extract.
  - Migration phases: phased breakdown with entry/exit criteria; sequencing that minimizes risk; how to maintain partial usability during migration.
  - Code integration strategy: branching/PR sequencing, review strategy, temporary shims/adapters, and deprecation notices.
  - Compatibility and data migration: behavioral parity requirements and data migrations required. If unknown, include TODOs and verification steps.
  - Validation and acceptance criteria: automated + manual test plans and sign-off checkpoints.
  - Cutover plan and rollback strategy; post-cutover cleanup.
  - Decision log: ADR links or inline notes.
  - Include the short migration-phase checklist (3–6 concrete steps) repeated here.

- docs/planning/roadmap.md — Unified Roadmap
  - Consolidated features slated for the merger.
  - Prioritized backlog (must/should/could), grouped milestones with task dependencies.
  - Technical debt and refactor candidates.
  - Observability and reliability improvement tasks.
  - Cross-links to architecture and migration sections.

- docs/reference/features.md — Consolidated Feature Documentation
  - Indexed by domain (inventory, docs review, reconciliation, UI).
  - For each feature:
    - description and user value
    - inputs/outputs and data sources
    - commands/scripts/services involved
    - configuration knobs and defaults
    - error cases and expected handling
    - metrics/logging emitted
    - known limitations and TODOs
  - Deduplicate and reconcile behavioral differences; clearly call out where behavior will change and why.

- docs/architecture/adr.md — Architecture Decision Records
  - ADR-style entries for major decisions made during consolidation (alternatives considered, rationale, consequences).

- docs/operations/todos.md (or embedded TODOs in the above files)
  - For every docs file above, list explicit TODO placeholders where repo-specific details must be filled (example: “TODO: Fill from Repo: G:\Development\Repo_reconciliation-dashboard\scripts\scan.ps1 — list responsibilities and inputs/outputs”).
  - Provide a checklist of exactly which files/areas in each repo are needed to fill each placeholder (file paths and suggested line ranges where available).
  - Include a short, practical migration-phase checklist (3–6 actionable steps) a senior engineer can follow to begin consolidation.

## Formatting and content rules (must-follow)

- Use GitHub-flavored Markdown with clear headings and anchors.
- Include Mermaid diagrams where helpful; always include an ASCII fallback for environments that don’t render Mermaid.
- Include ADR-style decision log (inline or linked).
- Use realistic, testable PowerShell snippets for operational commands and sample invocations; prefer readability and inline comments.
- Observability requirements (explicit):
  - Define a structured log schema; at minimum include fields: timestamp, level, component, operation, correlationId, message, details, and where logs are written (console/file/ETW/other).
  - Propose metric names and types (counter, gauge, histogram) with short descriptions of what they measure.
  - Define health-check endpoints/semantics (what each check covers and success/failure semantics).
- Do not invent concrete versions for PowerShell, .NET, or third-party dependencies. Where specifics are unknown, state assumptions explicitly and add TODOs to verify.
- Emphasize error handling: specify retry policies, idempotency guidance, backoffs, and how to validate correctness after retries.
- Prioritize robustness, maintainability, and observability over cleverness.
- Inline comments and clear structure are more important than terseness.

## Execution flow and acceptance criteria (how to operate)

- First attempt to read the three local repository paths listed under Goals.
  - If all paths are readable:
    - Extract a feature/component inventory, overlap/conflict analysis, and fill the docs with repository-specific details.
    - Produce the docs/ and README.md as commit-ready files, including Mermaid diagrams and PowerShell examples.
  - If any path is unreadable:
    - Immediately request a zip/tar upload of that repo and proceed.
    - Meanwhile, produce the full set of Markdown files with explicit TODO placeholders and a checklist of the exact files/areas required to complete them.
- Deliver the files in a commit-ready layout:
  - README.md (root)
  - docs/architecture/architecture.md
  - docs/planning/migration.md
  - docs/planning/roadmap.md
  - docs/reference/features.md
  - docs/architecture/adr.md (or inline ADR in architecture/architecture.md)
  - docs/operations/todos.md (or embedded TODOs in each doc)
- Acceptance criteria for the deliverables:
  - All docs are coherent, cross-linked, and actionable by a senior engineer.
  - PowerShell examples are realistic, contain inline comments, and can be copy/pasted and adapted.
  - Mermaid diagrams exist for architecture & flows, with ASCII fallback.
  - Structured logging schema, metric names/types, and health-check semantics are explicitly defined.
  - Migration plan includes explicit file/component mappings, phased plan with entry/exit criteria, validation tests, cutover/rollback steps, and a short checklist for immediate action.
  - Any missing repo-specific details are surfaced as TODOs with an exact file/path/line-range checklist.

## Constraints and style

- Platform/stack: Windows-first. PowerShell and .NET are primary runtimes; frontend should prioritize simplicity and maintainability.
- Do not invent concrete runtime/library versions. Add TODOs for verification where necessary.
- Avoid adding fictional requirements; infer only what is strongly implied by the repos or the brief.
- Prefer precise, direct language and technical detail appropriate for senior engineers.
- Keep documentation pragmatic, unambiguous, and actionable.
- Where trade-offs exist, document alternatives and decisions as ADRs.
- Maintain a bias toward observability, testability, and safe migration practices.

## Additional refinement goals

- Preserve the user's core intent.
- Clarify role, goals, inputs, outputs, and constraints.
- Add structure so a coding agent can follow and execute reliably.
- Avoid adding fictional requirements; only infer what is strongly implied.
- Prefer precise, direct language over marketing fluff.

## Immediate next step for the assistant you are invoking

- Attempt to read the three local paths listed above. If any path is unreadable, respond: “Cannot read paths: [list]. Please upload zip/tar archives for those repos.” Then produce the full set of Markdown deliverables described above, with clearly marked TODO placeholders and an exact checklist of missing files and line ranges required to complete the docs.

