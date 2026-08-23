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

**Central principle (2026-08-23).** The product does not prescribe what a
repository should become. It identifies and strengthens the foundations that
allow each repository to succeed at what it is intended to be. Every
repository in the portfolio ends with an **explainable conclusion** — and a
next action only where improvement is warranted. Remaining roadmap work is
prioritized on **operational efficiency and actionable improvement**: the
product's purpose should be obvious from the first interaction (what it
evaluates, what problems it uncovers, how its findings strengthen a
portfolio), and discovery → remediation should read as one informative
workflow that says what was found, why it matters, and what can be improved.
The admission rule for any roadmap item follows from this: **one hour spent
on this product must save more than one hour across the portfolio it
manages.** An item that only makes the product better at managing,
validating, or describing itself is maintenance, not roadmap work.

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

## Foundation Domains

The product evaluates repositories against **foundation domains** — the
building blocks that make virtually any repository stronger regardless of
purpose, technology, maturity level, or operating model. Five are the
starting set:

| Domain | The question it answers | Where it shows today |
| --- | --- | --- |
| **Documentation** | Can a newcomer understand and use this repository from what is written down? | README contract (`ai-doc-templates.json` → `readmeContract`), `doc-standards.json` findings |
| **Purpose** | Is it clear what this repository is for and who it serves? | README Overview / Usage contract; the portfolio scope classifier |
| **Planning** | Is there a credible plan or roadmap for what comes next? | Roadmap contract audit, maturity L0–L4, pending work and next item |
| **Structure** | Is the layout maintainable and navigable by intent? | `repo-structure-standards.json` presence audit |
| **Intentional engineering** | Is there evidence the work is deliberate — tests, CI, releases, conventions? | Partial today (Actions and merge-readiness checks); to be defined before it is scored |

These are **domains, not a fixed scoring taxonomy.** The product should
refine them — split, merge, add, or re-weight — as it meets new repository
types and operating models. The implementation of each domain varies by
repository; the principle behind it does not. Standards stay flexible enough
for a library, a script collection, a service, an archived experiment, and a
minimal utility each to be judged on what it is intended to be.

**An outcome is not necessarily a repair.** For every repository the product
must reach one of three conclusions:

- **Strengthen** — a domain is missing, weak, or unclear, and a preview-first
  next action is offered (repair the README, roadmap, or structure, or
  package a task).
- **Appropriate as-is** — the repository is healthy, intentionally minimal,
  externally managed, archived, or out of scope, and the product can say so
  and say why.
- **Insufficiently understood** — the product cannot yet reach a conclusion
  and names what it would need (a classifier gap, an unreadable roadmap, a
  remote it cannot see). This is a finding about the product, not the repo.

The requirement in every case is an explainable conclusion grounded in
visible repository state.

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
- **Foundations, not destinations** — the product does not prescribe what a
  repository should become; it identifies and strengthens the foundations
  that allow each repository to succeed at what it is intended to be.
- **Every repository reaches an explainable conclusion** — strengthen,
  appropriate as-is, or insufficiently understood. "Not applicable" and "not
  dispatchable" are never a repository's final word.
- **Flexible standards, constant principles** — the foundation domains are
  refined as the product meets new repository types and operating models;
  implementation varies, the principle holds.

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

Step 3's "recommended next action" may be **none — appropriate as-is**. That
is a complete outcome, not a gap: a repository the product understands well
enough to leave alone has been served by steps 1–4 as fully as one it
repairs in step 5.

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
- Require a **sufficient execution contract** before any dispatch — scope,
  acceptance criteria, and a verification an agent can run — with the
  required contract sized to repository kind and task scope. A mature (L3+)
  roadmap is how a large application supplies it; a one-task utility may
  supply it in the task itself. (Replaced the blanket "L3+ before any
  dispatch" rule on 2026-08-23; maturity stays the default way
  roadmap-sourced work meets the bar, not a universal precondition.)
- Cap Copilot lane parallelism at two; never blend lanes within a single
  repo.
- Do not prescribe a destination. A conclusion of **appropriate as-is** is a
  valid, recorded outcome and must be explainable from visible repo state.
- A gate's refusal (for example, below L3 maturity) is never a repository's
  final word: the refusal must name the foundation to strengthen, or the
  conclusion that the repository is appropriate as-is.
- Treat the foundation domains as refinable data, not as a scoring taxonomy a
  repository must be forced to fit.

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
- every repository in the portfolio carries an explainable conclusion —
  strengthen, appropriate as-is, or insufficiently understood — and none
  reads as merely "not applicable" or "not dispatchable"
- each finding states what was found, why it matters, and what can be
  improved, and a newcomer can tell from the first screen what the product
  evaluates and what its findings are for
- foundation coverage is measurable over time, so a quarter's work is visible
  as foundations gained rather than features shipped
- standards flex by repository kind without the principle behind them
  changing
