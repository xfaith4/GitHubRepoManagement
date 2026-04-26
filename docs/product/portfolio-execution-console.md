# Portfolio Execution Console — Product Direction

> **Canonical source.** This file is the authoritative statement of product
> thesis, principles, north-star workflow, risks, and guardrails for the
> GitHub Repo Management application. `ROADMAP.md` references this document
> for the long-form direction and focuses itself on the active and future
> release plan.

---

## Product Thesis

GitHub Repo Management is being reshaped from a general repo utility into a
**portfolio intelligence and execution console** that assesses an entire local
and GitHub repository collection, standardizes repo readiness, creates or
repairs roadmap contracts, ranks the highest-value incomplete roadmap work,
and prepares reviewed GitHub Copilot Agent prompts.

The long-term goal is not generic repository browsing. The goal is a
control surface that continuously assesses the whole collection, makes repo
health and progress obvious, creates missing roadmap contracts, improves weak
roadmaps and documentation, ranks the next best work by value, packages clean
Copilot Agent prompts, and reports progress without duplicate effort or
hidden ambiguity.

---

## Ten Core Questions the Product Must Answer

1. What repositories exist locally, on GitHub, or in both places?
2. Which repos are structurally healthy, well documented, and standardized
   enough to work on safely?
3. Which repos have a roadmap at all?
4. Which repos have a roadmap that is **contract-quality** rather than
   informal markdown?
5. Which repos need a new roadmap generated from real repo assessment?
6. Which repos have a clearly actionable next release or next pending work
   item?
7. Which incomplete roadmap item would bring the highest value if worked
   next?
8. Which repos are currently safe to dispatch to GitHub Copilot?
9. What prompt, context, constraints, and acceptance criteria should be sent
   to GitHub Copilot Agent?
10. What is the current status of the whole repository collection, in plain
    operator-readable terms?

---

## Product Principles

- **Roadmap-first workflow** — roadmap files are a primary source of truth
  for next work.
- **Roadmap as contract** — a roadmap is not merely documentation; it is a
  machine-readable work contract for execution and orchestration.
- **Explainable automation** — every audit, readiness score, and dispatch
  decision should be inspectable and grounded in visible repo state.
- **Human review before irreversible action** — preview repair, preview task
  packaging, and preview write-back before mutation.
- **Portfolio visibility over repo trivia** — make missing roadmaps, weak
  roadmaps, completed roadmaps, pending work, and blocked repos obvious.
- **Operational continuity** — preserve current launcher, logging, API host,
  and dashboard foundations rather than rebuilding from scratch.
- **Continuous improvement of roadmap quality** — roadmap format itself
  should improve over time to support better parsing and safer automation.

---

## North-Star Operator Workflow

Every feature in the product should serve one of these ten ordered steps:

1. **Scan portfolio** — discover every local and GitHub repository in scope.
2. **Classify every repo** — assign a single normalized state per repo
   combining git, docs, roadmap, maturity, structure, and execution signals.
3. **Show lifecycle state** — render that classification as one
   operator-facing badge with a one-line recommended next action.
4. **Identify blockers** — surface why a repo is not ready for work
   (missing README, weak roadmap, structural gaps, doc findings).
5. **Repair README, roadmap, or structure** — preview-first workflows that
   propose changes and require operator approval before write-back.
6. **Rank highest-value next work** — score every incomplete roadmap item by
   impact, unblock potential, risk reduction, maturity, effort, dependency
   reduction, and recency.
7. **Refine the Copilot prompt** — compose a Copilot Agent prompt from the
   selected roadmap item, repo context, constraints, acceptance criteria,
   and value rationale. Allow operator edits before dispatch.
8. **Dispatch** — send the reviewed prompt to GitHub Copilot Agent through
   the two-lane execution queue.
9. **Validate result** — re-run audits against the post-dispatch state and
   surface the diff.
10. **Update roadmap / report progress** — preview a roadmap-completion
    update, write it back on approval, and emit a portfolio-level status
    report in plain language.

Anything that does not serve one of these steps is out of scope for the
product direction.

---

## Risks

- Roadmap markdown may be too inconsistent across repos for safe automation.
- README quality may be insufficient for meaningful Copilot context.
- Queue automation can create duplicate or low-value work if readiness is
  weak.
- Hidden background execution can obscure failures if logs and history are
  not clear.
- Repair flows can accidentally erase real completed history if not handled
  carefully.

---

## Guardrails

- Do not auto-dispatch tasks without a visible readiness model.
- Do not treat all roadmap files as equal; parse confidence matters.
- Do not silently mark roadmap items complete based only on code churn.
- Prefer preview-first workflows before write-back or autonomous mutation.
- Keep the product operator-readable; this is a control console, not a
  magic box.
- Preserve genuine completion history when rewriting roadmaps.
- Treat roadmap audit failures as first-class findings, not hidden parser
  trivia.
- Enforce L3+ roadmap maturity as a gate before any Copilot dispatch.
- Cap Copilot lane parallelism at two; never blend lanes within a single
  repo.

---

## Definition of Useful Product Progress

The product is moving in the right direction when:

- missing or weak roadmaps become obvious immediately
- next pending work is visible without opening files
- repos can be filtered by dispatch readiness
- roadmap quality can be scored and explained, not merely guessed
- Copilot tasks are launched from structured context, not wishful prompting
- two active Copilot lanes can stay busy on separate repos without confusion
- progress history remains preserved while future work becomes increasingly
  formal and deterministic
- a single normalized lifecycle state per repo answers "what is the state of
  my collection, and what should I work on next?" without opening individual
  files
