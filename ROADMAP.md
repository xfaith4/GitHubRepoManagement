# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 2.7 — Guarded Scheduled Automation (Curated-Subset, Preview-First)**
> **Next active release:** **Release 2.9 — Operator Field Proof and Mobile Completion**
> **Work ordering:** dependency-driven, not insertion order — see
> [Execution Order and Dependencies](#execution-order-and-dependencies)
> **Canonical product direction:** [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
> **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
> **Dated change log:** [`CHANGELOG.md`](CHANGELOG.md)

---

## Current Status (Agent Context)

**Last updated:** 2026-08-09

Releases 0.4 through 2.6 and Release 2.8 are **engineering-complete and
archived**. Their full text moved to
[`docs/history/completed-releases.md`](docs/history/completed-releases.md)
on 2026-08-07; this file now carries open work only.

What remains falls into five kinds of work, and they are **not**
interchangeable — mixing them is what previously made the roadmap read as
"everything is done" while real gaps sat unlabelled:

1. **Correctness regressions** — something shipped and then broke. The two
   open on 2026-08-07 (the tracked `settings.json` fixture path, and the
   silent workspace-path failure) both closed 2026-08-08; see Lanes 0.1
   and 0.6.
2. **Credential-gated proof** — the code path is written and smoke-tested,
   but no live round trip has ever run (live submit-PR).
3. **Genuinely unbuilt engineering** — Release 2.7 Phases C and D, two
   mobile surfaces, and four cross-cutting hygiene items.
4. **Elevated / hardware / human verification** — needs SYSTEM rights, a
   physical Android phone, or an operator sitting at an authenticated
   Claude Code session. No autonomous test can produce these.
5. **Calendar-gated accrual** — the 7/90-day trend windows fill only as
   time passes with capture running.

**Current focus (next agent actions), in order:**

- [ ] **Release 3.1 — closed-loop delivery.** Its two hard prerequisites both
      landed (2.7 Phase A's proven write path, and 3.0's dispatch that runs), so
      the north-star loop can now be driven end to end for one real item. Only
      the PAT's `Checks: Read` grant is still missing, and that affects
      per-check detail rather than the loop.
- [ ] **Release 3.2 — portfolio scale.** Independent of 3.1 and schedulable in
      parallel; it starts from the bounded 900-second scan budget Lane 0.4
      settled rather than from an open question.
- [ ] **Lane 0.2's two items still need an operator action outside this
      repository** — the PAT's `Checks: Read` grant and the portal TLS
      certificate password. **Lane 0.5 closed 2026-08-10** once Ben settled the
      product calls it was waiting on. **Lanes 0.3, 0.4 and 0.6 closed
      2026-08-09.**

**Closed 2026-08-10 — Lane 0.5, and a navigation defect hiding under it.** The
"six-tab dashboard is dense" complaint had a concrete cause: **the Insights tab
rendered its content above the tab bar.** Clicking Insights inserted ~560 lines
above the control just clicked, pushing the tab strip off-screen, while the panel
underneath held only "Insights widgets are shown above this section." Fixed by
extracting `InsightsView.tsx` and mounting it inside the panel — which also took
`Dashboard.tsx` from 2,308 to 1,752 lines. Bulk-scope confirmation shipped
alongside it on the rule Ben settled: mutating actions always confirm, read-only
ones keep their single click. The wider progressive-disclosure question stays
open and is now a smaller one.

**Closed 2026-08-09 (third pass) — Release 3.0, the dispatch that could never
run.** All five milestones ship: the guided-improvement wizard enqueues with
`dispatchTarget: 'copilot'` instead of calling the launcher in-process, the
operator-session runner executes it with `gh agent-task create` and records the
task URL, runner presence is readable before work is queued, a logon-task
installer registers the runner as an interactive user (and refuses SYSTEM), and
in-host cloud dispatch is a 409 that names the runner. **Release 3.0 is
engineering-complete and archived** (its full text moved to
[the archive](docs/history/completed-releases.md#release-30--operator-context-execution)
the same day, per the split rule in section 8); the one live `gh agent-task`
round trip belongs to 2.9's
operator session, batched with the 2.8 `claude` run it shares a prerequisite
with. Two corrections worth carrying: the token check in front of the old
dispatch was answering the wrong question (a PAT passed it and the dispatch still
failed), and the refusal had to be unconditional rather than service-conditional.

**Closed 2026-08-09 (second pass) — every recorded non-blocker that did not need
an operator decision.** Phase C's two: the approval queue now has an operator UI
on the Operations tab (mirroring the backend's transition matrix so it cannot
offer an action that 409s), and packaging has its own overdue alert from a
second health reader over its own history file. Plus Lane 0.2's null rate-limit
readout, Lane 0.4's root worklogs (archived, gitignored, documented, and now
tripwired), and Lane 0.6's zero-scope action hint. Two of these were larger than
their notes implied: the rate-limit item named one call site and a source
tripwire found a second, and the worklog item asked for a move that would have
overwritten genuine earlier history.

**Closed 2026-08-09 — Release 2.7 Phase C, the largest remaining product
increment.** Scheduled roadmap-item packaging is built and smoke-tested end to
end: a scheduled run ranks each curated L3+ repo's pending work, packages the
top-value item into a task packet + repair-PR plan, prices it through the
quota guard (skipping over-budget repos with the guard's own code), notifies,
and stops at the approval gate. Dispatch happens only through an explicit
approval, which enqueues to the Release 2.8 operator-runner queue. **Release
2.7 is now engineering-complete** — every remaining item in it is either an
external-resource proof (Phase D's elevated service install) or a recorded
non-blocker. Detail and evidence are on the Phase C milestones below.

**Closed 2026-08-09:** Lane 0.4's cold-scan request deadline — the freeze guard
now classifies routes into a 180-second default tier and a 900-second
full-portfolio-scan tier, so a legitimate cold scan no longer trips the guard
into a restart loop, and neither smoke gate needs a timeout override any more.
Also **both remaining Phase D frontend items**: the unit-test set reached 4 of 4
named units by extracting the value-tier and curation-scope logic into pure
`frontend/lib` modules the components now consume, and the `Dashboard.tsx`
decomposition landed its two named extractions (tab shell, summary/mission).
**Release 2.7 Phase D is now engineering-complete** except for the live service
deployment its freeze-prevention item has always been waiting on (an elevated
Windows install). The only open 2.7 work is Phase A and the Phase C it gates.
Also Lane 0.3's hardcoded workspace defaults, where the fix is now enforced by a
module-smoke tripwire rather than just applied — the tripwire found two `F:\`
offenders that the item's own `G:\` file list could never have named.

**Closed 2026-08-08 and archived out of this file:** the settings.json
regression (Lane 0.1, which closed entirely), the silent workspace-path
failure, Lane 0.5's two data-integrity findings, the credential reissue and
live-validation probe, the service's readable token, the two smoke gaps,
scheduler failure alerting, two installer defects that had made the documented
credential fix a silent no-op, and the Copilot-dispatch OAuth diagnosis that
produced Release 3.0. Full text with evidence is in
[the archive](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).
**This file now carries open work only** — every remaining checkbox is
something still to do.

**Forward arc.** Releases 3.0-3.3 were added 2026-08-08 to describe the
finished product rather than the working one: dispatch that runs (3.0), the
north-star loop closing end to end (3.1), an 80+ repo portfolio that feels
immediate (3.2), and unattended operation (3.3).

---

## 1. What This Document Is

This is the **active execution roadmap**. Its job is to answer two questions
for any operator or coding agent:

1. What is the current active release?
2. What is the next concrete work item?

Long-form product direction (thesis, principles, north-star workflow, risks,
guardrails) lives in
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
and is summarized below in section 2. The full text of every completed
release (0.4 through 2.6, plus 2.8) lives in
[`docs/history/completed-releases.md`](docs/history/completed-releases.md);
this document references them by version + status only.

---

## 2. Product Direction (summary)

GitHub Repo Management is a **portfolio intelligence and execution console**
that assesses an entire local and GitHub repository collection, standardizes
repo readiness, creates or repairs roadmap contracts, ranks the
highest-value incomplete roadmap work, prepares reviewed agent prompts,
monitors agent execution, and reports whether work is safe to merge.

The **north-star operator workflow** every release should serve is:

> scan portfolio → index repos → classify every repo → show lifecycle state →
> identify blockers → repair README/roadmap/structure → rank highest-value
> next work → refine agent prompt → dispatch → monitor agent run → validate
> Actions → evaluate merge readiness → update roadmap / report progress

For the full thesis, ten core questions, principles, risks, and guardrails,
see
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md).

---

## 3. Implementation-State Vocabulary

Every milestone in this roadmap should carry one of these states. A `[x]`
checkbox alone is not enough — it does not distinguish "backend exists" from
"end-to-end working."

| State               | Meaning                                                                      |
| ------------------- | ---------------------------------------------------------------------------- |
| `planned`           | Proposed; no code yet                                                        |
| `scaffolded`        | Files / route / UI exist but stubbed or returns mock data                    |
| `backend-complete`  | Server-side logic implemented; no UI consumer yet                            |
| `ui-connected`      | Frontend wires through to live backend; manual smoke ok                      |
| `smoke-tested`      | Automated module / api-host smoke covers it                                  |
| `operator-verified` | Confirmed working end-to-end against the live workspace                      |
| `done`              | All four of: backend-complete, ui-connected, smoke-tested, operator-verified |

Render the state inline on each milestone in italics, e.g.:

```markdown
- [x] Add `GET /api/portfolio/assessment` route. _(state: smoke-tested)_
```

**Checkbox rule (added 2026-08-07).** `[x]` means _nothing remains for that
item in this roadmap_. An item whose engineering is complete but whose proof
is still outstanding stays `[ ]` and names the resource it waits on. The
2026-08-07 reorganization found several `[x]` items carrying "remaining
for `operator-verified`" prose; those were split — the shipped half went to
the archive, the unproven half became an open item in Release 2.9.

**Pending-item phrasing rule:** use semantic compression. Prefer
action-first, surface-specific wording a coding agent can select without
rereading surrounding prose: `verb + artifact/route/module + verification
boundary`. Omit filler, repeated rationale, and narrative transitions
already covered by release goals or acceptance criteria.

---

## 4. Release Index

| Version   | Title                                                                    | Status                                                                                     |
| --------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| 0.4 - 1.1 | Foundation through Standardization and Guardrails                        | `done` — see [archive](docs/history/completed-releases.md)                                 |
| 1.2       | Enhanced Portfolio Intelligence                                          | `done` — closed 2026-07-05; see archive                                                    |
| 1.3 - 1.7 | Frontend build, repo evaluation, README generation, dispatch, git status | `done` — see archive                                                                       |
| 1.7.5     | Portfolio Mission Alignment, Indexed Scanning, Value-Ranked Planning     | `done` — shipped 2026-05-28; see archive                                                   |
| 1.8 - 2.0 | Operations workspace, AI doc cycles, agent-run monitoring                | `done` — see archive                                                                       |
| 2.1       | Persistent Data Layer                                                    | `done` (engineering) — closed 2026-08-07; operator sign-off tracked in 2.9                 |
| 2.2       | API Auth, Network Security, Onboarding, GitHub App                       | `done` (engineering) — 2026-07-05; optional live App-token exchange tracked in 2.9         |
| 2.3       | Portfolio Analytics, Trend Visualization, Distribution                   | `done` (engineering) — 2026-07-06; 7/90-day accrual is calendar-gated, tracked in 2.9      |
| 2.4       | Agent Integration Protocol and AI Repair Loop                            | `done` (engineering) — 2026-07-05; live submit-PR proof tracked in 2.7 Phase A             |
| 2.5       | Mobile-Friendly Operator Experience                                      | `done` (engineering) — 2026-07-05; two surfaces + device proof tracked in 2.9              |
| 2.6       | Interface Clarity and Operator Orientation                               | `done` — 2026-07-06; device sign-off tracked in 2.9                                        |
| **2.7**   | **Guarded Scheduled Automation (Curated-Subset, Preview-First)**         | **active** — Phases A, B, C done; Phase D awaits an elevated service install               |
| 2.8       | Local Claude Code Execution (queue + operator runner)                    | `done` (engineering) — 2026-07-15; real `claude` run tracked in 2.9                        |
| **2.9**   | **Operator Field Proof and Mobile Completion**                           | `planned` — collects every external-resource residual plus the two unbuilt mobile surfaces |
| 3.0       | Operator-Context Execution                                               | `done` (engineering) — 2026-08-09; see archive. Live proof tracked in 2.9                  |
| **3.1**   | **Closed-Loop Delivery**                                                 | `planned` — rank → dispatch → monitor → Actions → merge readiness → roadmap write-back     |
| **3.2**   | **Portfolio Scale and Responsiveness**                                   | `planned` — serve from the index; retire the cold-scan cliff and the deadline kill         |
| **3.3**   | **Steady-State Operation**                                               | `planned` — unattended for months: retention, restore, honest TLS, decision-grade digests  |

> **Note on `.5` numbering.** Release 1.7.5 was a deliberate course-correction
> release between 1.7 and 1.8. Reserve the `.5` pattern for similar course
> corrections; default new work to integer minor releases.

### Execution Order and Dependencies

Release numbers identify scope — they do not dictate sequence. Work through
open items in the order below, and update this section whenever a lane
closes or a new dependency appears.

**Step 0 — unblockers and correctness: closed 2026-08-08.** All three landed —
the tracked `settings.json` scan roots, GitHub write credentials including a
token the LocalSystem service can actually read, and the two smoke gaps. Their
detail is in
[the archive](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).

**Two parallel lanes (no cross-dependency between them):**

**Both Release 2.7 lanes closed 2026-08-09.** The automation lane (Phases A → C)
is done: the write path is proven live and scheduled packaging ships behind it.
The reliability lane (Phase D) is engineering-complete; only its live service
deployment waits on an elevated Windows install. What follows is the 3.x arc.

**After the lanes:**

1. **Release 2.9 mobile completion** (touch ergonomics beyond the Phase 1
   surfaces, tap-through agent-run list) — engineering work, no gates.
2. **Release 2.9 field proof** — batch the elevated/hardware/human checks
   into as few sessions as possible; several share a setup (an elevated
   shell covers the watchdog _and_ the service installer; a phone session
   covers 2.5 _and_ 2.6).
3. **Release 2.9 trend accrual** — closes itself as calendar time passes;
   requires only that capture keeps running.

**Then the 3.x arc — from "the pieces work" to "the console works":**

Releases 3.0-3.3 are the path to a finished product rather than a working one.
They are ordered by dependency, not by size:

1. ~~**3.0 Operator-Context Execution**~~ — **done 2026-08-09.** Dispatch now
   runs, so what was blocking everything downstream is gone.
2. **3.1 Closed-Loop Delivery** — needed 3.0 for dispatch and 2.7 Phase A for a
   proven write path; **both landed 2026-08-09**, so this is now the next
   release. It is where the north-star workflow first runs whole.
3. **3.2 Portfolio Scale and Responsiveness** — independent of 3.0/3.1 and
   schedulable in parallel. Lane 0.4's deadline decision landed 2026-08-09
   (extended tier, not exemption), so 3.2 starts from a bounded 900-second
   scan budget it has to beat rather than from an open question.
4. **3.3 Steady-State Operation** — every milestone is independent; pick items
   up whenever a release lane is blocked on an external resource.

**Dependency map (open work only):**

| Open item                                            | Depends on                                           | Type                                          |
| ---------------------------------------------------- | ---------------------------------------------------- | --------------------------------------------- |
| Release 2.7 Phase D (freeze prevention, live deploy) | An elevated (SYSTEM) Windows install                 | hard — privilege                              |
| Release 2.7 Phase D freeze prevention                | Watchdog field proof (2.9) for the paired safety net | soft — ship prevention regardless             |
| Lane 0.2 `Checks: Read`; TLS certificate password    | An operator action outside this repository           | hard — external                               |
| Lane 0.5 bulk-scope confirmation; tab disclosure     | A product decision, not engineering time             | hard — design                                 |
| Release 2.9 mobile completion (ergonomics, run list) | —                                                    | none — the responsive foundation is shipped   |
| Release 2.9 physical-Android proof (2.5 + 2.6)       | An Android device on the LAN                         | hard — hardware                               |
| Release 2.9 watchdog + service-installer proof       | An elevated (SYSTEM) session                         | hard — privilege                              |
| Release 2.9 real `claude` run (2.8)                  | An authenticated operator Claude Code session        | hard — human                                  |
| Release 2.9 GitHub App installation-token exchange   | A registered GitHub App                              | hard — optional; PAT supersedes               |
| Release 2.9 trend accrual (2.3 Ph2)                  | Days of live capture                                 | hard, time-gated                              |
| Release 3.0 live `gh agent-task` proof (via runner)  | An operator session with `gh auth login`             | hard — human; batch with the 2.8 `claude` run |
| Release 3.1 closed-loop delivery                     | `Checks: Read` (3.0 and 2.7 Phase A both landed)     | soft — per-check detail only; loop unblocked  |
| Release 3.2 scale and responsiveness                 | —                                                    | none — deadline decision landed 2026-08-09    |
| Release 3.3 steady-state operation                   | —                                                    | none — independent milestones, any order      |

---

## 5. Active Release Snapshot

### Active release detail — 2.7 Guarded Scheduled Automation

Release 2.7 was promoted 2026-08-07 after the Release 2.1 through 2.6 and 2.8
closeout. Phase B shipped 2026-07-06; Phases A, C, and D are open.

The full execution contract for the active release — goal, outcomes,
milestones, acceptance criteria, validation plan, risks, dependencies, known
issues, traceability, phase plan, and budget guardrail — lives in one place,
[Release 2.7 below](#release-27--guarded-scheduled-automation-curated-subset-preview-first),
per `ROADMAP_TEMPLATE.md`: the release section is the single source of truth
for its own status. This heading exists so the roadmap validator can resolve
the active-release pointer; it deliberately restates nothing.

**Current focus:** none — Phases A, B, and C are done and Phase D is
engineering-complete. What remains in this release is the elevated Windows
install its freeze-prevention item has always waited on, plus two recorded
non-blockers under Phase C. The next active release is 2.9.

---

## 6. Open Releases

### Release 2.7 — Guarded Scheduled Automation (Curated-Subset, Preview-First)

**Status:** active

**Goal:** turn the operator-driven pipeline into a scheduled one that
advances **favorite / portfolio-candidate** repos automatically — proposing
README/ROADMAP refinements and packaging the highest-value ready roadmap work
on an interval — while stopping at the human approval gate. No silent
mutation, no auto-merge: everything runs preview-first, inside the existing
quota/budget guard, with an append-only audit trail.

**Prerequisites:** all met. Phase A's credential gate closed 2026-08-08 and the
live proof landed 2026-08-09; Phase C followed it the same day. Phase D's
remaining step needs an elevated (SYSTEM) Windows session.

#### Product outcomes

- The operator enables an interval and the app keeps the curated subset
  assessed and surfaces ready-to-approve improvements with no manual trigger.
- Scheduled runs package the top-value ready roadmap item per favorite repo
  into a review-ready task packet + repair-PR plan, inside the quota guard.
- Every scheduled action is recorded in append-only run history with a
  reason; failures raise an alert instead of failing silently.
- Archived/ignored repos are never touched — scope is exactly the curated set.
- The always-on portal does not freeze under ordinary daily load, and if it
  does, it recovers without operator intervention.

#### Engineering milestones

Phase A — Credential-gated proof:

- [x] Prove a live submit-PR round trip on one write-enabled repo: branch
      push, PR creation, PR visible in the target repo, run recorded.
      Closes the Release 2.4 residual and opens Phase C.
      _(state: **done** — proven live 2026-08-09 against this repo,
      [PR #96](https://github.com/xfaith4/GitHubRepoManagement/pull/96):
      6 additions / 0 deletions, 1 file, `MERGEABLE`, left open for review.
      **Phase C is now unblocked.**)_
      **Evidence, each verified independently rather than inferred from a
      success message:** the route returned `created=true` with a `prUrl`;
      a separate GitHub API read confirmed `state=open head=roadmap-repair/…
      base=main changed_files=1`; the append-only repair history carries a
      matching `submit-pr` record with the PR number and branch; and the
      checkout was left back on `main` and clean, proving the `finally`
      restore works on the success path and not only on failure.
      **This item was mis-scoped, and the correction matters.** It read as a
      credentials gate — "the dry-run plan path is smoke-tested; only the live
      round trip is missing", and the 2026-08-08 status note said Phase A was
      "now unblocked" because the service could read a token. In fact
      `POST /api/roadmap/repair/submit-pr` **had no live path at all**: even
      with `createPr=true` it returned `created=false` / `prUrl=null` and a
      note saying no branch was pushed. There was no checkout, commit, push,
      or PR creation anywhere in the route. The credentials were never what
      was blocking it. Half the machinery did exist —
      `POST /api/roadmap-agent/approve-push` performs a real token-authenticated
      push — but it stops at the push ("Open the PR from GitHub when ready").
      **Built 2026-08-09:**
      [`Roadmap.PrSubmitter.ps1`](backend/modules/roadmap/Roadmap.PrSubmitter.ps1)
      does branch → write → commit → push → `POST /repos/{o}/{r}/pulls`, with
      the pure parts (branch naming, remote-slug parsing, the refusal matrix)
      split out so they are testable without a checkout or a token. Safety
      properties, each asserted: never force-pushes, never commits onto the
      base branch, always returns to the starting branch via `finally`,
      refuses a dirty working tree rather than sweeping unrelated edits into
      an automated PR, refuses a no-op diff rather than opening an empty PR,
      and keeps the token out of the git argv (base64 `http.extraheader`, the
      same approach `approve-push` uses). A refusal returns **409 with a named
      reason and category**, never `200` with `created=false` — the caller
      must not be able to read "no PR" as success, which is exactly how the
      stub behaved. The run is recorded as a `submit-pr` event in the existing
      append-only repair history, carrying `prUrl`/`prNumber`/`branch`/`repoSlug`.
      **Evidence so far:** module smoke exit 0 — `submit-PR ok: 4 remote forms
      parsed, 4 non-GitHub refused, 8 refusal categories named, token not in
      cleartext`.

Phase C — Scheduled roadmap-item packaging (the prize; gated on Phase A):

Built 2026-08-09 in
[`Automation.RoadmapPackaging.ps1`](backend/modules/automation/Automation.RoadmapPackaging.ps1),
behind `POST /api/automation/package-run`, `GET /api/automation/packages`, and
`POST /api/automation/packages/approve` / `/reject`.

- [x] For each favorite repo with a ready L3+ roadmap, select the top-value
      pending item using the settled scoring semantics (MAX within a
      dimension + `effortFit` floor), build a task packet + repair-PR plan,
      and queue it for approval. _(state: smoke-tested — closed 2026-08-09)_
      Scope is resolved by `Resolve-AutomationPackagingScope`, which returns a
      decision per repo and **names every refusal** rather than shrinking the
      list silently: `archived-ignore`, `not-curated`, `roadmap-not-ready`
      (below L3), `no-pending-work`, `no-scored-item`, `missing-local-path`.
      Scope opts **in** — an unrecognized curation state is excluded, the same
      contract `curationScope.ts` pins on the frontend. Ranking reuses the
      assessment's already-scored items (`Select-TopValueRoadmapItem`: highest
      `valueScore`, earlier `roadmapOrder` breaks the tie, exactly as
      `_SelectTopValueItem` does) so a packet and the dashboard can never
      disagree about "the top item", and an **unscored** item is never
      packaged. The packet carries the item, its score/tier/rationale, a
      namespaced `roadmap-item/<slug>-<id>` branch, an item-scoped prompt that
      forbids widening the scope, and a repair-PR plan naming the Phase A
      write path (`POST /api/roadmap/repair/submit-pr`) with `submitted=false`.
- [x] Gate every packaged item through the quota/budget guard; skip and log
      when over budget. _(state: smoke-tested — closed 2026-08-09)_
      `Test-PackagingQuota` delegates to the Release 2.0
      `Test-AgentDispatchQuota`, prices each item from the roadmap's own
      annotated phase estimate (falling back to a configured default), and a
      refusal is recorded as a skip carrying **the guard's own `blockedCode`
      and message**. The guard is **fail-closed**: if `BudgetLedger.ps1` is not
      loaded the item is refused with `quota-guard-unavailable` rather than
      admitted — a guard that cannot be evaluated is not a pass. The quota is
      re-checked at approval time, because budget can be consumed between
      packaging and approval.
- [x] Notify per run; approval triggers dispatch (live PR once Phase A
      passes). No auto-merge. _(state: smoke-tested — closed 2026-08-09)_
      Each run emits a digest (webhook when configured, dry-run otherwise)
      listing what was packaged and what was skipped with its reason, and a
      degraded run fires the same `execution.failed` event Phase D wired.
      **A scheduled run never dispatches** — `dispatchedCount` is an invariant
      and `Write-PackagingRunRecord` refuses to persist a run claiming
      otherwise, the same defense-in-depth Phase B applies to `appliedCount`.
      Dispatch happens only through the explicit approval action, which
      enqueues to the Release 2.8 operator-runner queue (queue line **and** the
      `queued` run summary the runner claims on — one without the other is a
      task nothing picks up). `Test-PackagedItemTransition` is the single
      definition of what may follow what; a refusal is a **409 with a named
      category**, never a 200 that reads like success, and a dispatched packet
      is terminal so it cannot be dispatched twice.
- [x] Smoke: a scheduled run ranks + packages one fixture repo's top item,
      honors the quota-refusal path, and dispatches only on explicit
      approval. _(state: smoke-tested — closed 2026-08-09)_
      **Module smoke** (exit 0): `packaging scope ok: 2 selected, 7 refusals
      each named`; `packaging rank ok: max score, earlier roadmap order breaks
      the tie, unscored selects nothing`; `packaging quota ok: over-budget
      skipped+logged with the guard code, nothing queued, missing guard fails
      closed` (the fail-closed branch is proven in a fresh runspace where
      `BudgetLedger.ps1` was never loaded); `packaging run ok: 2 packet(s)
      queued for approval, dispatched=0 applied=0, dispatch queue absent,
      invariant-violating runs refused`; `packaging approval ok: 8 transitions
      enforced, queue+summary written on dispatch, fold keeps 3-step history,
      sibling packet untouched`; and a **drift tripwire** — `queue contract ok:
      10 fields identical to the canonical writer` — that fails if
      `Add-RoadmapTaskToQueue.ps1`'s entry shape ever changes without this
      writer following, which would otherwise strand approved work in the queue
      as entries the runner silently mishandles.
      **Api-host smoke** (exit 0, `packagingOk=True`) against a live host:
      `packaged 'Add the operator dashboard export route with smoke test
      coverage' (score 93, order 2) not the first item, over-budget twin
      skipped at stage=quota, dispatch only on approval (run
      20260809-105754-0c048a3f), re-approval 409`. Two fixture repos are used
      because the pre-existing fixture's roadmap is deliberately below L3; the
      over-budget twin differs **only** by a phase-plan estimate above the
      per-session cap, so the refusal is caused by the budget and nothing else,
      and the packaged item is asserted to be neither the first pending item nor
      merely whatever the route returned.
- [x] The approval queue now has an operator UI on the Operations tab.
      _(state: smoke-tested — closed 2026-08-09)_ Approving was an API call
      (`POST /api/automation/packages/approve`); the loop worked but a packaged
      item was less discoverable than a doc-improve preview in the AI Docs
      panel. [`PackagedItemQueue.tsx`](frontend/components/PackagedItemQueue.tsx)
      renders the queue over a pure
      [`lib/packagedItems.ts`](frontend/lib/packagedItems.ts) that **mirrors
      `Test-PackagedItemTransition`'s matrix rather than reinventing it**, so the
      UI can never offer an action the backend answers with a 409 (nor hide one
      it would allow) — `dispatched` and `rejected` are terminal in both places.
      A rejection prompts for a reason and it is written to the append-only
      audit trail. **`dispatched` is deliberately not labelled "done"**: approval
      enqueues to the operator runner, which stops at a reviewed branch, so a
      "Complete" badge here would be exactly the decorative badge section 8
      forbids — a unit test asserts the label never reads done/complete/merged.
      **Evidence:** `npm run test:unit` 112 passing across 8 files (23 new
      assertions in `packagedItems.test.ts`), `npm run typecheck` and
      `npm run build` exit 0.
- [x] Packaging now has an overdue alert of its own.
      _(state: smoke-tested — closed 2026-08-09)_ `Get-AutomationHealth`
      deliberately reads only the doc-refinement history (interleaving kinds
      would let a live packaging cron mask a dead doc cron), so a packaging cron
      that stopped was invisible. The fix is the second reader the item
      specified — `Get-PackagingHealth` / `Get-PackagingRunOutcome` over
      `packaging-runs.jsonl`, **never a merged file** — surfaced as a
      `packaging` block on `GET /api/automation/status` beside the unchanged
      doc-refinement fields, and rendered as a second badge on the Operations
      tab. Alert codes are packaging-specific (`packaging-never-ran`,
      `packaging-overdue`, `packaging-run-failed`, `packaging-run-partial`)
      because `automation-overdue` on both would leave a webhook unable to say
      which scheduler stopped. A **skip is not a failure** — an over-budget repo
      is the guard working, so a run that only skipped classifies `ok`.
      Interval falls back to `automation.intervalMinutes` when no
      `automation.packaging.intervalMinutes` is set, so a single cron hitting
      both routes is not reported as "never ran" for want of a second setting.
      **Evidence:** module smoke — `packaging health ok: never-ran/overdue/
      partial named packaging-specifically, skips are not failures, doc runs
      cannot mask it` (that last assertion is the independence proof: a
      workspace holding only a fresh doc-refinement run still reports
      `packaging-never-ran`); api-host smoke asserts both blocks are present and
      self-identify (`kind=doc-refinement` / `kind=roadmap-packaging`) so the
      route can never return the doc verdict twice.

Phase D — Hardening & observability (parallelizable, autonomous, unblocked):

- [ ] **Freeze prevention (root cause), paired with the shipped watchdog.**
      Guarantee `/api/status` + assessment caching cannot regress off (a
      gutted cache caused the 2026-07-05 blocking-scan pile-up); add a
      per-request work timeout so one blocked native call — e.g. the SQLite
      bridge — cannot wedge the single-threaded accept loop; schedule
      `app.db` maintenance (VACUUM + snapshot retention; ~138 MB and
      growing). _(state: in progress — all three engineering parts are now
      built and smoke-tested; only live service deployment (elevated Windows
      install) remains.)_ Cache-off regression guards and the 180-second host
      request deadline landed 2026-08-08; the deadline records the
      route/correlation ID and exits a wedged host so Shawl/SCM recovery
      restarts it. **Scheduled `app.db` maintenance landed 2026-08-08:**
      `Invoke-AppDbMaintenance` prunes the seven snapshot/history tables and
      runs `VACUUM`, exposed as report-only `GET /api/maintenance/database`
      and mutating `POST /api/maintenance/database`, and driven daily from
      [`Invoke-DailyEvidence.ps1`](scripts/Invoke-DailyEvidence.ps1) through
      the host's own route (the host holds the SQLite connections, so an
      out-of-process VACUUM would contend for the write lock). Retention
      windows are clamped **up** to a per-table floor — 180 days for every
      table with a history reader — because `GET /api/portfolio/trend` answers
      up to `days=180` and Release 2.9 is waiting on 7/90-day accrual; a low
      configured window must never delete the history that milestone needs.
      Append-only operational records (`execution_ledger`,
      `execution_history`, `agent_runs`, `repo_curation`) are never touched.
      **Evidence:** module smoke asserts report-only counts without deleting,
      the 180-day floor protecting 100-day-old rows against a 30-day request,
      VACUUM running, and `ops_log` untouched; api-host smoke
      `dbMaintenanceOk=True` asserts the floor survives the HTTP round trip.
- [x] Complete the frontend unit-test set (vitest). _(state: smoke-tested —
      4 of 4 named units covered, closed 2026-08-09)_ `needsAttention` and
      `viewMeta` were already covered
      ([`needsAttention.test.ts`](frontend/lib/needsAttention.test.ts),
      [`viewMeta.test.ts`](frontend/viewMeta.test.ts)). The two gaps closed
      by extracting the logic out of the components that held it, so the
      tests cover the code that actually ships rather than a copy:
      **value tiers** → [`lib/valueTier.ts`](frontend/lib/valueTier.ts) +
      [`valueTier.test.ts`](frontend/lib/valueTier.test.ts), consumed by
      `WorkQueueView`; **automation scope selector** (operator curation) →
      [`lib/curationScope.ts`](frontend/lib/curationScope.ts) +
      [`curationScope.test.ts`](frontend/lib/curationScope.test.ts),
      consumed by `RepoGrid`. The scope suite pins the Release 2.7 contract
      the backend also enforces: `archived-ignore` is never in automation
      scope, and neither is an uncurated repo — scope opts in, it never opts
      out, so an unrecognized curation state is excluded rather than
      admitted. **Evidence:** `npm run test:unit` 79 passing across 6 files,
      `npm run typecheck` exit 0; the never-touch assertion was
      adversarially proven — widening `isInAutomationScope` to
      `state !== 'none'` fails
      [`curationScope.test.ts:72`](frontend/lib/curationScope.test.ts#L72).
- [x] Decompose [`Dashboard.tsx`](frontend/components/Dashboard.tsx):
      extract the view-router/tab shell and the summary/mission sections.
      _(state: smoke-tested — both named extractions landed 2026-08-09)_
      The tab shell became
      [`DashboardViewTabs.tsx`](frontend/components/DashboardViewTabs.tsx)
      over a pure [`lib/viewTabs.ts`](frontend/lib/viewTabs.ts); the summary
      and mission blocks became
      [`PortfolioSummarySection.tsx`](frontend/components/PortfolioSummarySection.tsx)
      and
      [`PortfolioMissionSection.tsx`](frontend/components/PortfolioMissionSection.tsx).
      The extraction also closed two latent drift hazards it exposed: four of
      the six tabs hardcoded their label instead of reading `VIEW_META` (the
      exact drift [`viewMeta.ts`](frontend/viewMeta.ts) exists to prevent), and
      the badge-visibility rule was written three different ways inline. Both
      are now single definitions. **Evidence:** `npm run test:unit` 91 passing
      across 7 files (12 new `viewTabs` assertions), `npm run typecheck` and
      `npm run build` exit 0; tab labels and order are unchanged because
      `VIEW_META` already carried the same six labels in the same order.
- [ ] **[non-blocker]** `Dashboard.tsx` is **1,752 lines** (2,519 → 2,308 after
      the Phase D extractions → 1,752 on 2026-08-10). The ~600-line Insights
      block this item named is out: it became
      [`InsightsView.tsx`](frontend/components/InsightsView.tsx) over a pure
      [`lib/portfolioTrendView.ts`](frontend/lib/portfolioTrendView.ts) as a
      side effect of fixing the Lane 0.5 tab-inversion defect. What remains is
      ~1,000 lines of hooks and handlers above the return — a different shape of
      problem from the JSX blocks, and one with no user-visible symptom driving
      it. _(state: planned — worth doing, not worth blocking on.)_

#### Acceptance criteria

- Enabling automation runs unattended and produces, for the curated subset
  only, doc-improve previews + a digest — with nothing applied.
- A scheduled packaging run ranks favorites by the settled value score,
  packages the top item, and stops at the approval gate; over-budget items
  are skipped and logged.
- `GET /api/automation/history` returns an ordered, append-only record of
  every scheduled run and its decisions.
- Archived/ignored repos never appear in any automation run.
- No automation path applies a doc change, dispatches, or merges without an
  explicit operator approval action.
- One live PR exists in a real repo, created through the submit-PR route.
- A blocked native call no longer wedges the accept loop, and `app.db`
  maintenance runs on a schedule.
- `npm run typecheck` and `npm test` pass; new automation smoke covers the
  schedule → preview → notify → history loop.

#### Out of scope

- Auto-merge, or any write that bypasses the operator approval gate.
- Autonomous execution on non-curated (default) repos.
- Multi-tenant scheduling or per-agent automation credentials.

**Validation plan:** run `npm run typecheck`, `npm test`
(`scripts/Invoke-TestSuite.ps1`, mirroring `ci-smoke.yml`), and the
automation smoke; confirm each exits 0. Drive a scheduled run against a
fixture favorite set and confirm previews + digest + history with **zero**
applied changes. For Phase C, additionally assert the quota-refusal path and
that dispatch fires only on an explicit approval action.

**Risks and blockers:**

- **Cleared 2026-08-09:** Phase A's credential/write-path blocker and the
  Phase C dependency it gated. The sequence held — packaging shipped only
  after one live PR round trip proved the write path.
- **Risk — auto-ranking on unproven writes.** Retired: packaging now sits
  behind a write path proven live (PR #96), so a packet's repair-PR plan
  names a route that demonstrably opens a PR.
- **Risk — the portal freezes under load.** Observed twice (2026-07-05,
  2026-07-11): process alive, port listening, not responding. The watchdog
  safety net is shipped but unproven at SYSTEM; the root-cause prevention
  work is still open in Phase D.
- **Risk — `app.db` growth.** ~138 MB in daily use. **Mitigated 2026-08-08:**
  scheduled prune + VACUUM ships in Phase D and runs daily from
  `Invoke-DailyEvidence.ps1`; per-table retention floors keep the trend
  windows Release 2.9 is waiting on intact.
- **Risk — the freeze guard kills the host during a legitimate cold scan.**
  The Phase D request deadline defaults to 180s and terminates the host on
  expiry, but a cold full-portfolio assessment over the real 75-repo
  workspace exceeds that. Tracked as the top open item in Lane 0.4.

**Dependencies:** `/api/scan/schedule` (1.2), repo curation states (2.3
Ph5), AI doc-improve preview/apply (1.9), the notification hub (1.1), the
quota/budget guard (2.0 Ph4), `roadmap-events.jsonl` (2.4), and valid
GitHub write credentials for Phase A onward.

**Known issues:**

- [ ] The freeze guard can kill the host during a legitimate cold scan. The
      Phase D request deadline defaults to 180s and terminates the host on
      expiry, but a cold full-portfolio assessment over the real 75-repo
      workspace exceeds that — so the guard that exists to protect the portal
      is the thing that stops it. Tracked as the top open item in Lane 0.4;
      Release 3.2 implements whichever way that decision lands.
- [ ] Phase C dispatches to the **operator runner**, not to the cloud. `gh
      agent-task` requires an OAuth token the LocalSystem service structurally
      cannot hold, so approval enqueues to the Release 2.8 queue
      (`output/roadmap-task-queue.jsonl` + a `queued` run summary) and
      `Invoke-RoadmapTaskRunner.ps1` executes it in the operator's session.
      That is the one dispatch path that works from a service today, and it is
      proven in both smokes. Cloud (Copilot) dispatch for packaged items still
      needs Release 3.0. An approved packet therefore reaches a **branch with
      committed work awaiting review**, not an open PR — the PR is opened
      through Phase A's submit-PR route, which the packet's repair-PR plan
      names, as a further operator action. Nothing auto-merges.

Both known issues that stood here on 2026-08-07 — the tracked `settings.json`
fixture path and the expired PAT — closed 2026-08-08; see
[the archive](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).

**Traceability:** Phase C shipped
[`Automation.RoadmapPackaging.ps1`](backend/modules/automation/Automation.RoadmapPackaging.ps1)
(`Resolve-AutomationPackagingScope`, `Select-TopValueRoadmapItem`,
`New-RoadmapItemTaskPacket`, `Test-PackagingQuota`,
`Invoke-ScheduledRoadmapPackaging`, `Write-PackagingRunRecord` /
`Get-PackagingRunHistory`, `Get-PackagedItemQueue`,
`Test-PackagedItemTransition`, `Submit-PackagedItemToRunner`), the routes
`POST /api/automation/package-run`, `GET /api/automation/packages`, and
`POST /api/automation/packages/approve` / `/reject`, a `kind` filter plus
both-kind merge on `GET /api/automation/history`, and
`/api/automation/package-run` added to the extended request-deadline tier in
[`RequestDeadline.ps1`](backend/api-host/RequestDeadline.ps1) (it reaches the
same full-portfolio scan `/api/automation/run` does). Operator-facing behavior
is documented in
[`local-task-runner.md`](docs/reference/local-task-runner.md). Phase B shipped
[`Automation.DocRefinement.ps1`](backend/modules/automation/Automation.DocRefinement.ps1)
(`Select-AutomationDocTargets`, `Invoke-ScheduledDocRefinement`,
`New-AutomationDigestPayload`, `Write-AutomationRunRecord` /
`Get-AutomationRunHistory`), `POST /api/automation/run`, `GET
/api/automation/history`, and the `automation` block on `GET
/api/scan/schedule`, with module + api-host smoke coverage. Phase D's
shipped half is [`Watch-PortalHealth.ps1`](scripts/service/Watch-PortalHealth.ps1),
[`Install-PortalWatchdog.ps1`](scripts/service/Install-PortalWatchdog.ps1),
the reworked
[`Install-RepoManagementService.ps1`](scripts/Install-RepoManagementService.ps1),
[`RequestDeadline.ps1`](backend/api-host/RequestDeadline.ps1) with the
cache-off regression guards, `Invoke-AppDbMaintenance` /
`Get-AppDbMaintenanceRetentionDays` in
[`Persistence.Store.ps1`](backend/modules/persistence/Persistence.Store.ps1)
behind `GET`/`POST /api/maintenance/database`, and `Get-AutomationHealth` /
`Get-AutomationRunOutcome` in
[`Automation.DocRefinement.ps1`](backend/modules/automation/Automation.DocRefinement.ps1)
behind `GET /api/automation/status`, surfaced by
[`AutomationStatusBadge.tsx`](frontend/components/AutomationStatusBadge.tsx).
Verification runs through `scripts/Invoke-TestSuite.ps1` (`npm test`), mirrored
in [`.github/workflows/ci-smoke.yml`](.github/workflows/ci-smoke.yml); the
Phase D frontend units live beside
[`frontend/lib/needsAttention.test.ts`](frontend/lib/needsAttention.test.ts).
Operator-facing behavior is documented in
[`docs/reference/operator-guide.md`](docs/reference/operator-guide.md).

#### Phase plan (within this release)

| Phase                                | Scope                                                                                                   | Status                                                   | Completed  | Token usage | Work units |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ---------- | ----------- | ---------- |
| Phase A: Unblockers                  | Live submit-PR proof on one write-enabled repo                                                          | **done — proven live** (PR #96)                          | 2026-08-09 | —           | —          |
| Phase B: Scheduled doc refinement    | Scheduler + favorite-scoped doc-improve previews + digest + run history                                 | **done — smoke-tested** (2026-07-06) — see archive       | 2026-07-06 | —           | —          |
| Phase C: Scheduled roadmap packaging | Top-value item packaging + quota guard + approve-to-dispatch + approval UI + packaging health           | **done — smoke-tested**; both non-blockers closed        | 2026-08-09 | —           | —          |
| Phase D: Hardening & observability   | Frontend unit tests, Dashboard decomposition, failure alerting, freeze prevention, auth operator-verify | **in progress — 4 of 6 shipped; 2 open (frontend)**      | —          | —           | —          |

#### Budget guardrail

- Scheduled automation consumes AI work units per packaged item; every run
  routes through the Release 2.0 quota/budget guard and refuses or annotates
  over-budget work rather than proceeding.
- Record raw observations per scheduled run (units consumed, credit/API
  spend, refusals) into the automation run history.

---

### Release 2.9 — Operator Field Proof and Mobile Completion

**Status:** planned

**Goal:** convert every surface that is `smoke-tested` but still waits on an
external resource into `operator-verified` with durable evidence, and finish
the two mobile surfaces that were left engineering-incomplete under Release
2.5. This release adds no new product capability — it closes the honesty gap
between "the automated suite is green" and "this works in the field."

**Prerequisites:** the mobile-completion milestones have none. Each field-proof
milestone names the one external resource it waits on; none block each other,
and several share a session — an elevated shell covers both SYSTEM milestones,
one phone session covers both device milestones, one authenticated operator
shell covers both runner milestones. Batch them.

#### Product outcomes

- No milestone is marked complete on the strength of an automated suite alone
  when what it claims needs hardware, elevation, credentials, or a human.
- The always-on portal is proven to recover from a real freeze, not a simulated
  one, and the dashboard from a real Android phone — touch, install, and all
  four target workflows — not only at an emulated 390px viewport.
- Trend charts show real 7- and 90-day windows.
- `evidence/` carries a durable record for each proof, so the next agent can
  read the evidence instead of re-litigating whether something works.

#### Engineering milestones

Mobile completion (no gates — build these first):

- [ ] Apply touch ergonomics beyond the Release 2.5 Phase 1 surfaces: ~44px
      minimum touch targets and a tap equivalent for every hover-only
      affordance (tooltips, row actions, rationale popovers) across the
      Phases 2-3 surfaces. _(state: scaffolded — Phase 1 done 2026-07-04
      (bottom nav 56px, card actions 44px); the rest was never built)_
- [ ] Add the tap-through mobile agent-run list from the agent-activity
      indicator: status, repo, phase, elapsed time. _(state: planned — the
      indicator ships and `/api/agent-runs` data is already reachable; only
      the mobile list view is missing)_

Field proof — elevated (SYSTEM) session, batch together:

- [ ] Run the elevated
      [`Install-PortalWatchdog.ps1`](scripts/service/Install-PortalWatchdog.ps1)
      and confirm a real freeze-and-recover: kill + `Restart-Service
RepoMgmtPortal`, the action appended to `output/logs/service-watchdog.jsonl`,
      and the `execution.failed` webhook fired. _(state: smoke-tested → needs
      `operator-verified`; decision logic and a dry-run against the actual
      frozen host, PID 5704, are already proven)_
- [ ] Operator-verify the reworked
      [`Install-RepoManagementService.ps1`](scripts/Install-RepoManagementService.ps1):
      elevated install / repair / `icacls` / scheduled-task registration, with
      secrets resolving from machine env vars and the tracked `settings.json`
      staying secret-free. _(state: smoke-tested → needs `operator-verified`)_

Field proof — physical Android device on the LAN, batch together:

- [ ] Verify the four Release 2.5 workflows on a **physical Android phone**:
      repo health, agent activity, prompt refinement, roadmap dispatch — plus
      real touch input and on-device home-screen install. Steps in
      [`lan-mobile-setup.md`](docs/reference/lan-mobile-setup.md). _(state:
      smoke-tested at an emulated 390px viewport → needs `operator-verified`)_
- [ ] Confirm the Release 2.6 clarity affordances pass on the same device:
      data-source indicator, per-tab subtitles, advanced-filters toggle, and
      the orientation overlay. _(state: smoke-tested → needs `operator-verified`)_

Field proof — human / credential / calendar:

- [ ] Operator-verify Release 2.1 against the live workspace and record the
      sign-off, closing the release formally. _(state: smoke-tested against
      live data — `output/app.db`, the real 68-repo `F:\Development` scan —
      → needs a recorded human sign-off)_
- [ ] Execute one real `claude` run through
      [`Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1)
      in the operator's authenticated session: claim → branch → run →
      verify → commit → `awaiting-review`. Closes the Release 2.8 residual.
      _(state: smoke-tested dry-run E2E → needs `operator-verified`)_
- [ ] Same session: run one real **copilot** entry through the runner —
      `gh agent-task create` reaches a live task, URL in the run summary.
      Closes the Release 3.0 residual. _(state: smoke-tested → needs
      `operator-verified`. Requires `gh auth login` and **no**
      `GH_TOKEN`/`GITHUB_TOKEN` set; gh ignores stored OAuth when one is.)_
- [ ] Operator-verify the auth + shared-LAN path so automation runs on a bound,
      authenticated host. _(state: planned — carried over from 2.7 Phase D)_
- [ ] (Optional) Prove live GitHub App installation-token exchange
      (`Get-GitHubAppInstallationToken`) + auto-refresh on one registered
      app, closing the Release 2.2 residual. _(state: planned — not
      required; the PAT path supersedes it)_
- [ ] Let the Release 2.3 Phase 2 trend windows accrue: confirm
      `GET /api/portfolio/trend` reports a real 7-day, then 90-day, window.
      _(state: smoke-tested — rollup logic is live and `status=history-backed`;
      only calendar time is missing. Keep
      [`Invoke-DailyEvidence.ps1`](scripts/Invoke-DailyEvidence.ps1) running —
      it accrues history as a side effect.)_

#### Acceptance criteria

- Every milestone above carries an entry in
  `evidence/operator-verification-log.jsonl`, appended via
  [`Add-OperatorVerification.ps1`](scripts/Add-OperatorVerification.ps1).
- A deliberately frozen portal is detected and recovered by the installed
  watchdog without operator intervention, with the ledger line to prove it.
- All four mobile workflows complete on a physical Android phone, and the
  app installs to the home screen and opens standalone.
- `GET /api/portfolio/trend` returns a 7-day and then a 90-day window with
  real data.
- One real `claude` run reaches `awaiting-review` with a commit on a
  `roadmap/<runId>` branch and nothing pushed.
- Every hover-only affordance has a tap equivalent, and the agent-activity
  indicator taps through to a usable run list at 390px.
- Release 2.1 is formally closed with a recorded sign-off.

#### Out of scope

- New product capability — this release only proves and finishes what exists.
- Remote (non-LAN) mobile access; native apps or app-store distribution.

---

### Release 3.1 — Closed-Loop Delivery

**Status:** planned

**Goal:** close the north-star loop end to end, repeatedly, with explicit
operator gates at apply, dispatch, and merge. Today the console can rank work
and prepare a prompt, and it can read merge readiness, but no single work item
has ever travelled the whole chain — so the loop's real failure modes are
unknown.

**Prerequisites:** all but one are met. Release 2.7 Phase A (the live submit-PR
proof) and Release 3.0 (a dispatch that runs) both closed 2026-08-09. Only the
PAT's `Checks: Read` grant (Lane 0.2) is outstanding, and it affects per-check
merge detail rather than the loop — `mergeStateStatus` already answers the
merge-readiness question this release gates on.

#### Product outcomes

- One roadmap item is carried from "ranked highest value" to "merged, with the
  managed repo's roadmap updated" without a human stitching the steps.
- Every stage transition is inspectable after the fact from one trace, rather
  than reconstructed from four ledgers.
- Roadmap write-back is preview-first: the console proposes the completion
  edit and the operator applies it.

#### Engineering milestones

- [ ] Add a per-work-item trace view joining rank → prompt → dispatch → agent
      run → Actions result → merge readiness → write-back, keyed by `runId`.
      _(state: planned — every stage already writes its own ledger; nothing
      joins them)_
- [ ] Generate the managed repo's roadmap completion edit from merge evidence
      and present it as a reviewed diff. _(state: planned — write-back is the
      last unbuilt step of the north-star workflow)_
- [ ] Gate write-back on merge evidence: refuse to mark an item complete from
      code churn or a green run alone. _(state: planned — guardrail in
      section 8 exists; no enforcement)_
- [ ] Record a full-loop proof for one real item in `evidence/`, naming each
      stage's artifact. _(state: planned)_

#### Acceptance criteria

- A single `runId` resolves to every stage artifact through one route.
- A write-back attempt with no merge evidence is refused and says why.
- The loop proof exists in `evidence/` with the PR, the Actions result, and
  the applied roadmap diff.

#### Out of scope

- Automatic merge — merge stays an explicit operator action after readiness
  passes.
- Multi-repo parallel dispatch; one item end to end first.

---

### Release 3.2 — Portfolio Scale and Responsiveness

**Status:** planned

**Goal:** make an 80+ repo portfolio feel immediate. Reads serve from the
persistent index; a cold full assessment becomes a visible background job
instead of a synchronous request that can outlive its own deadline.

**Prerequisites:** Lane 0.4's decision on whether the request deadline exempts
long-running scan routes or the cold scan is bounded — this release implements
whichever way that lands.

#### Product outcomes

- No portal action can trip the freeze guard that exists to protect it.
- Portfolio reads are served from `app.db` and refreshed incrementally, so
  repeated views cost nothing.
- Scan progress is visible while it runs, rather than a spinner that may or may
  not still be alive.

#### Engineering milestones

- [ ] Serve portfolio assessment from the persistent index with incremental
      refresh; make a cold full scan an explicit background job with progress
      and a cancel. _(state: planned — a cold scan currently exceeds both the
      smoke's client timeout and the 180s request deadline on the real
      75-repo workspace)_
- [ ] Bound per-repo git work with a timeout and a concurrency cap so one
      pathological repo cannot stall a sweep. _(state: planned)_
- [ ] Declare and enforce a performance budget for the portfolio read path,
      with the measured figure reported next to it. _(state: planned — no
      target exists today, so regressions are invisible)_
- [ ] Virtualize the repo grid so row count stops driving render cost.
      _(state: planned — pairs with the `Dashboard.tsx` decomposition already
      open in Release 2.7 Phase D)_

#### Acceptance criteria

- A cold full-portfolio assessment completes without tripping the request
  deadline, and its progress is observable while it runs.
- Repeated portfolio reads after a warm index are served without a rescan.
- The performance budget is stated in the repo and checked by smoke.

#### Out of scope

- Distributed or multi-machine scanning.
- Replacing SQLite.

---

### Release 3.3 — Steady-State Operation

**Status:** planned

**Goal:** run unattended for months without an operator babysitting it — bounded
storage, honest transport, a restore path, and reports that state their own data
window.

**Prerequisites:** none; each milestone is independent.

#### Product outcomes

- Append-only evidence stays append-only without growing without bound.
- What the portal claims about its own transport and credentials matches what
  it is actually doing.
- A lost or corrupted `app.db` is recoverable from evidence already on disk.
- Every export and digest states its data window, units, headline finding, and
  recommended next action.

#### Engineering milestones

- [ ] Add retention and compaction for the JSONL ledgers and `app.db`, with the
      policy stated in config and the pruned range logged. _(state: planned —
      `service-watchdog.jsonl` reached 6.9 MB from one-minute probes)_
- [ ] Add a documented backup and restore path for `app.db`, including a schema
      migration story. _(state: planned)_
- [ ] Make the portal's self-reported transport match reality, closing behind
      Lane 0.2's certificate recovery. _(state: planned — the host degrades to
      plain HTTP on a certificate it cannot open, while config still claims
      TLS)_
- [ ] Bring every export and digest up to the decision-grade contract: data
      window, units, headline finding, recommended next action.
      _(state: planned — the digest payload ships; the framing does not)_

#### Acceptance criteria

- Ledger growth is bounded by a stated policy, and pruning is itself logged.
- A restore from backup produces a working portal with its history intact.
- The transport the portal reports is the transport it serves.
- Every export names its window, units, headline, and next action.

#### Out of scope

- Multi-tenant or hosted operation.
- Log shipping to an external observability platform.

---

## 7. Cross-Cutting Engineering Work

Continuous, not release-scoped. **This section carries open work only.**
Completed cross-cutting items were archived 2026-08-07 — see
[the archive](docs/history/completed-releases.md#cross-cutting-engineering-work-completed-items) —
and again 2026-08-08, when Lane 0.1 closed entirely and Lanes 0.2, 0.4, 0.5,
and 0.6 shed their closed items to
[the 2026-08-08 batch](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).

### Lane 0.2 — Credential freshness

- [ ] **Grant the PAT `Checks: Read`.** _(state: planned — non-blocker)_
      The reissued token still 403s on
      `repos/{owner}/{repo}/commits/{ref}/check-runs`
      (`Resource not accessible by personal access token`), so
      `gh pr checks <n> --watch` is unusable and the merge loop relies on
      `mergeStateStatus` as a proxy. Metadata, Contents, Pull requests, and
      Actions reads all pass. Verified 2026-08-07.
- [x] **Populate `rateLimit` on the GitHub insights path.** _(state:
      smoke-tested — closed 2026-08-09)_ `Get-GitHubReposViaApi` returned a
      hardcoded `rateLimit = $null`, so `insightsMeta.rateLimit` was always null
      and the readout stayed blank even though every call already receives
      `X-RateLimit-Limit` / `-Remaining` / `-Reset`. The parser and the
      last-observation snapshot live in a dot-sourced
      [`GitHubRateLimit.ps1`](backend/api-host/GitHubRateLimit.ps1) — the shape
      `RequestDeadline.ps1` uses — because a helper defined inside the host
      script cannot be loaded without starting the listener, and a parser only
      reachable through a live HTTP request is a parser nothing tests.
      Three calls switched from `Invoke-RestMethod` to `Invoke-WebRequest`
      (`Invoke-RestMethod` discards headers on Windows PowerShell); the snapshot
      is cleared per request and takes the **newest** observation, because the
      limit is consumed by every call in the sweep, not just the first.
      **The item named one call site and there were two.** A source tripwire
      over the whole file — not the named line — caught
      `POST /api/github/status`'s **`gh` CLI fallback** returning its own
      hardcoded null. That path has no response object to read, so it resolves
      from `GET /rate_limit` (which does not itself consume quota) through
      `ConvertFrom-GitHubRateLimitPayload`, which **reuses the header parser**
      so the two paths cannot emit differently-shaped readouts.
      **Absent or unparseable headers still yield `$null`, never a zeroed
      object** — a fabricated "0/5000" would read as an exhausted quota and look
      like a real measurement. **Evidence:** module smoke —
      `both header shapes parsed, /rate_limit payload shares the shape, newest
      observation wins, absent headers stay null` (PS 5.1's
      `Dictionary[string,string]` and PS 7's `Dictionary[string,string[]]` are
      both asserted; a parser handling one silently reads blank on the other).
- [ ] **Recover or replace the portal TLS certificate password.** _(state:
      planned — non-blocker, surfaced 2026-08-08)_ Machine-scoped
      `REPO_MGMT_TLS_PFX_PASSWORD` (17 chars) does not open the configured
      pfx, so the portal has been serving plain HTTP on loopback while its
      config claims TLS. Loopback-only keeps this off the critical path.
      Either recover the original password or regenerate with
      `scripts\New-RepoManagementTlsCertificate.ps1` and re-run
      `-Action Reconfigure -PfxPath … -PfxPassword …`.

### Lane 0.3 — Layout follow-ups from the 2026-07-15 cleanup

- [x] Normalize hardcoded `G:\Development\GitHubRepoManagement`
      `-WorkspaceRoot` defaults to `$PSScriptRoot`-derived paths so the
      suite runs unmodified from any clone location. _(state: smoke-tested —
      confirmed 2026-08-07 still present in `backend/adapters/Adapters.ps1`,
      `backend/api-host/Start-RepoManagementApiHost.ps1`,
      `backend/modules/docreview/Invoke-DocReviewInventory.ps1`, and both
      reconcile modules — a wider blast radius than the original note
      recorded)_ **Partly closed 2026-08-08:**
      [`scripts/Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1)
      now defaults to `(Split-Path -Parent $PSScriptRoot)`. This one mattered
      more than the note implied: the required pre-commit gate failed on its
      first step for anyone invoking it without `-WorkspaceRoot`, which is
      exactly how `CLAUDE.md` documents running it. **Evidence:** gate re-run
      with no arguments, exit 0.
      [`scripts/Invoke-ApiHostSmokeTest.ps1`](scripts/Invoke-ApiHostSmokeTest.ps1)
      was fixed the same way, so **both** required gates now run unmodified from
      any clone location. **Closed 2026-08-09**, and the file list above was
      wrong in both directions — worth recording, because the same mistake
      produced the 2026-08-07 "wider blast radius than the original note"
      correction:
      **(a) Three of the five named `backend/` files were not `-WorkspaceRoot`
      defaults at all.** `Adapters.ps1`, `Invoke-DocReviewInventory.ps1`, and
      the reconcile modules hardcoded `$LocalRoots` / `$RootPath` — **scan
      targets**, i.e. where the operator's repos live, not where the tool
      lives. `$PSScriptRoot` derivation is meaningless for those. Every caller
      already passed them explicitly, so the defaults were dead code whose only
      possible effect was to scan a nonexistent drive and return "no repos"
      instead of "misconfigured". They now default to empty and throw a named
      error. Removing them exposed a hidden coupling:
      `Invoke-Reconciliation.ps1`'s empty-roots check ran even under
      `-LoadFunctionsOnly`, and had been passing only because the dead
      `G:\Development` default made the array non-empty — so `Adapters.ps1`
      broke the moment the default was honest. The check is now correctly
      skipped when only loading functions.
      **(b) Seven files were missing from the list**, including
      `Invoke-AuthSmokeTest.ps1` and `Invoke-PhaseProtocolTest.ps1`, which
      hardcode **`F:\`** — the current machine's drive, so they work here and
      break on every other clone. A `G:\` grep could never have found them.
      **The instances are fixed and the pattern is now enforced:**
      [`Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1) fails
      if any tracked `backend/`, `scripts/`, or `tools/` script declares a
      `[string]$Param = 'X:\...'` default (`*.Tests.ps1` exempt — those use
      absolute paths as synthetic fixtures). **Evidence:** the tripwire was
      written before the last two fixes and caught them, which is how they were
      found; module smoke and adapter smoke both exit 0, the latter run with no
      `-WorkspaceRoot` argument at all; each of the three adapter guards was
      confirmed to raise its named error when the root is omitted.
- [x] Implement the documented maturity **caps** that the auditor did not
      apply: `ROADMAP_MATURITY_MODEL.md` states "any critical finding caps
      maturity at L1" and "any warning finding caps maturity at L3", but
      `Invoke-AuditRoadmapContract` only did weighted-score arithmetic, so a
      roadmap could carry a critical finding and still score
      orchestration-ready. _(state: smoke-tested — closed 2026-08-09)_
      **The model contradicted itself, and Ben chose the resolution
      2026-08-09.** `ROADMAP-011` (>1 active release) carried a named L2 cap
      _and_ `critical` severity; applying the blanket critical cap literally
      would have forced it to L1 and made its own documented L2 cap
      unreachable. Rather than add a precedence rule, **the severity was the
      bug**: `ROADMAP-011` is now `warning` (rules **v1.5**), so it takes the
      L3 blanket cap plus its named L2 cap and lands at L2 exactly as
      documented — and "any critical finding caps at L1" became literally
      true. Ambiguous dispatch is still a hard gate, because L2 is below the
      L3 contract-ready bar. Caps now **compose**: the effective ceiling is
      the lowest that applies. **Both rule-pack mirrors and both
      `ROADMAP_MATURITY_MODEL.md` copies moved in lockstep**, and the model
      now records why the severity must not be re-promoted.
      **The parity tripwire earned its keep:** implementing the caps in the
      backend auditor alone broke it immediately
      (`maturityScore module=84 cli=92`), because
      [`Test-RoadmapContract.ps1`](tools/Test-RoadmapContract.ps1) carries its
      own cap block — exactly the "two figures, one truth" divergence this
      product exists to catch. Both evaluators now implement the same
      composed caps. **Evidence:** module smoke exit 0 —
      `maturity caps ok: critical -> L1-Informal (<= 39); 1 warning finding(s)
      -> L3-Contract-Ready (<= 84)`, `2 active -> ROADMAP-011 (warning) +
      capped at L2-Structured`, and `evaluator parity ok: 4 fixtures agree`.
      A new assertion fails the gate if `ROADMAP-011` is ever re-promoted to
      `critical`.
- [x] Repair `CLAUDE.md`'s dangling `@_base.md` and
      `@.claude/modes/implementer.md` imports — neither file exists.
      _(state: done — closed 2026-08-09)_ The note said to "fix at the tool
      level" because `ccmode.ps1` manages the mode line, but **`ccmode.ps1`
      does not exist either** — not in this repo and not under any `.claude`
      directory on this machine — so there was no tool level to fix at. Ben
      chose removal 2026-08-09: both imports are gone, replaced by a comment
      recording what they were and that `ccmode.ps1` can re-add its own line
      if it is ever restored. Nothing was fabricated to satisfy them.
- [x] Tune `tools/Test-RoadmapStructure.ps1` for the template's own layout:
      `ROADMAP_TEMPLATE.md` puts the full execution contract inside the
      `## Release X — Title` block, so R013's 120-line cap fired on any
      conformant active release, and RQ001 wanted a `Status` line on the
      "Active release detail" pointer that must not restate it (declaring it
      twice is an RQ003 error). _(state: smoke-tested — closed 2026-08-09;
      this file is now 0 errors / 1 warning, and the one left is the true
      R010 file-length signal)_ R013 now skips the active release; RQ001 now
      skips a pointer block whose release declares a valid status, and its
      message names both places when neither does. **Two pre-existing crashes
      surfaced while testing the relaxations**, both in the
      "linter dies on exactly the file it should diagnose" shape: a roadmap
      with no status lines anywhere hit `Cannot bind argument ... empty array`
      before RQ001 could report it (six rule parameters were missing the
      `[AllowEmptyCollection()]` that a seventh already had), and a file with
      no release headings hit a StrictMode `$null.Count` before
      `R000-NO-RELEASES` could fire — `ROADMAP_TEMPLATE.md` itself is such a
      file, so the linter could not lint its own template. Both fixed.
      **The linter had no smoke coverage at all**, which is how it drifted
      into contradicting the template it lints;
      [`Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1) now
      pins both relaxations _and_ proves each rule still fires when genuinely
      violated. **Evidence:** module smoke exit 0; adversarially proven —
      reverting either relaxation fails the gate at the matching assertion.
      The first version of that coverage captured only `2>&1`, so every
      "must fire" assertion passed vacuously while the finding scrolled past
      on the console; it captures `*>&1` now, which is what the linter's
      `Write-Host` findings actually use.

**Shipped 2026-08-07 (from this lane):** a standards↔spec drift tripwire and an
"every shipped audit rule is implemented by the auditor" tripwire, both in
`scripts/Invoke-ModuleSmokeTest.ps1`. The second closes the `d2cc6cc` /
`c6662cf` regression class — a rule added to the pack but never evaluated
still contributes its `scoreWeight` to the denominator, silently inflating
every maturity score. Both were adversarially proven to fail when violated.

### Lane 0.4 — Smoke coverage gaps

- [x] **The cold-scan request deadline — decided and shipped 2026-08-09.**
      _(state: smoke-tested)_ `POST /api/automation/run` calls
      `Get-OperationsReposPayload`, which does a **cold full-portfolio
      assessment**. That step was fast only while the tracked `settings.json`
      pointed at a fixture directory; with the real root restored (Lane 0.1)
      it exceeded the smoke's default `-RequestTimeoutSec 180` on the real
      75-repo workspace. Worse, the **Phase D request deadline also defaulted
      to 180s and terminates the host on expiry** — so a legitimate cold scan
      tripped the freeze guard, and Shawl/SCM recovery restarted the host
      straight back into the same scan. The guard was manufacturing the
      outage it exists to prevent.
      **Decision: an extended tier, not an exemption.** Exempting the scan
      routes outright would restore the unbounded wedge the Phase D guard was
      built to stop, and bounding the cold scan itself is a Release 3.2
      performance problem, not a reliability fix — so the deadline now
      classifies routes instead. `Get-LongRunningScanRoutePattern` in
      [`RequestDeadline.ps1`](backend/api-host/RequestDeadline.ps1) names the
      routes that reach a full-portfolio assessment
      (`/api/portfolio/assessment`, `/api/operations/repos`,
      `/api/automation/run`, `/api/digest/*`, `/api/reconcile`,
      `/api/docreview/run`, `/api/badges/*`, `/api/v1/agent/*`); those get
      **900 seconds** (`REPO_MGMT_SCAN_REQUEST_TIMEOUT_SECONDS`, same 30-3600
      clamp, never below the default tier), everything else keeps 180. The
      deadline is now recorded per request, so an incident record reports the
      tier that actually fired rather than the startup default.
      `Invoke-ApiHostSmokeTest.ps1` dot-sources the same classifier for its
      client timeout, so client and server cannot drift apart.
      **Evidence:** module smoke asserts the classification both ways (five
      scan paths in, five ordinary paths plus the empty path out), the
      trailing-slash form, the 900/180 selection, and that the extended tier
      can neither drop below the default tier nor exceed the 3600 ceiling;
      the assertion was adversarially proven to throw with the pattern list
      emptied. `./scripts/Invoke-ApiHostSmokeTest.ps1 -Port 7099` passes with
      **no `-RequestTimeoutSec 900` and no
      `REPO_MGMT_REQUEST_TIMEOUT_SECONDS` override** — the two workarounds
      this item existed to remove.
      **This decision is the input Release 3.2 was waiting on** (see the
      dependency map): 3.2 inherits a bounded 900-second scan budget as the
      number its responsiveness work has to beat, not an unbounded route.
- [x] Archive the root worklogs `findings.md`, `progress.md`, and
      `task_plan.md` to [`docs/history/worklogs/`](docs/history/worklogs/),
      matching the 2026-07-15 cleanup convention they were re-created against.
      _(state: smoke-tested — closed 2026-08-09)_ They went to
      `docs/history/worklogs/2026-08-08-guided-improvement/` rather than the
      directory root: the three files already archived there are a **different**
      set from the pre-2026-07-15 layout, and overwriting real history to
      satisfy a filename would have destroyed it. **The convention is now
      enforced rather than restated** — the note explaining it lived only inside
      a completed release, which is why the files came back within three weeks.
      All three fixes ship together: a `.gitignore` rule stops new ones
      appearing, [`docs/history/worklogs/README.md`](docs/history/worklogs/README.md)
      states the convention where worklogs are actually written, and a
      module-smoke tripwire fails the required pre-commit gate if a worklog is
      tracked at the root again (gitignore alone cannot stop an already-tracked
      file, or a `git add -f`). **Evidence:** module smoke —
      `no worklogs tracked at the repository root; the convention is
      documented`.

### Lane 0.6 — Workspace-path failure was silent (P0, 2026-08-08)

- [x] Point the zero-scope action hint at the specific cause when a root is
      missing. _(state: smoke-tested — closed 2026-08-09)_ The ActionBar hint
      read the generic "Scan a workspace first — set the workspace path in
      Settings, then Refresh" while the red alert directly above it named the
      actual missing path. `repoActionsBlockedReason` now takes the same
      `missingRoots` the alert reads and, when one is present, names the path
      and the thing to check ("reconnect the drive or correct the path"), since
      telling an operator to scan a workspace they have already configured is
      redundancy, not guidance. The generic remedy survives for the genuine
      nothing-configured case, where it is the correct next step. **Blank
      entries fall back rather than manufacturing a claim about nothing.**
      **Evidence:** `npm run test:unit` — five new `dataProvenance` assertions
      covering single root, multi-root summarisation, blank-root fallback, and
      that a populated scope stays unblocked even with a missing root.

### Lane 0.5 — Portal UX follow-ups (empty-state audit 2026-08-08)

- [x] **A render error in any component no longer white-screens the portal.**
      _(state: smoke-tested — closed 2026-08-10)_ No error boundary existed
      anywhere: one render-time throw in any of ~38 components killed the
      entire UI with no message and no recovery.
      [`ErrorBoundary.tsx`](frontend/components/ErrorBoundary.tsx) now mounts
      twice — `index.tsx` wraps `<App />` as the last resort, and Dashboard
      wraps the active tab panel with `key={activeView}`, so a crashed view
      degrades to a card naming the view and the error while the header, tab
      strip, and the other five views keep working; switching tabs resets the
      boundary. **Evidence:** four DOM tests — untouched happy path, named
      card with `role="alert"`, Try-again genuinely re-renders after the
      cause is gone, and a still-broken child re-shows the card.

Surfaced by a walkthrough of the Repository Grid, Insights, Operations, and
Doc Readiness Queue tabs against a workspace that scanned 0 repos. The two
data-integrity findings from that audit were fixed the same day and are in
[the archive](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd);
these two are design-dependent and deliberately deferred.

- [x] **Add a confirmation step to implicit bulk-scope actions.** _(state:
      smoke-tested — closed 2026-08-10)_ With no rows selected, Pull/Fetch/Report
      applied to the **entire filtered set** (75 repos on the real workspace)
      behind nothing but an amber banner. **Ben settled the deferred product
      call 2026-08-10: mutating actions always confirm; read-only ones keep
      their single click.** So Pull and Fetch gate on a `window.confirm` naming
      the command and the count; `Report` (and Doc Review, and Roadmap Scan) are
      read-only and reversible, and spending the dialog there would train the
      operator to dismiss the one that matters. The rule is **"mutating +
      implicit", not "mutating + big"** — no threshold, because two working
      trees the operator did not name is still two they did not name. An
      explicit selection never re-asks: that selection _is_ the operator naming
      the scope. Encoded in [`lib/bulkScope.ts`](frontend/lib/bulkScope.ts),
      which lists the mutating actions **by name** so a new bulk action is a
      deliberate decision on both sides of the line rather than silently
      defaulting to no confirmation. **Evidence:** 11 new `bulkScope`
      assertions.
- [x] **Progressive disclosure for the six-tab dashboard — the navigation
      defect underneath it.** _(state: smoke-tested — closed 2026-08-10)_
      Investigating the density complaint found a concrete cause rather than a
      taste question: **the Insights tab rendered its content above the tab
      bar.** 558 lines and six widgets sat in a container preceding
      `<DashboardViewTabs>`, while the Insights tab panel held one sentence —
      "Insights widgets are shown above this section." Clicking Insights
      inserted ~560 lines above the control the operator had just clicked,
      pushing the tab bar off-screen; the panel then pointed back upward. The
      tab metaphor was inverted for one of six tabs.
      Fixed by extracting
      [`InsightsView.tsx`](frontend/components/InsightsView.tsx) over a pure
      [`lib/portfolioTrendView.ts`](frontend/lib/portfolioTrendView.ts) and
      mounting it **inside** the panel. **Enforced, not just fixed:** a
      module-smoke tripwire fails if `<InsightsView>` ever precedes
      `<DashboardViewTabs>` in source, if any `activeView === '…'` render gate
      sits above the tab strip (so a _future_ tab cannot repeat it), or if the
      "shown above this section" apology copy returns. Adversarially proven —
      re-injecting the old layout fires both assertions.
      **This also took `Dashboard.tsx` from 2,308 to 1,752 lines**, closing the
      larger half of the Phase D decomposition non-blocker below.
      **Evidence:** `npm run test:unit` 149 passing across 11 files (22 new
      `portfolioTrendView` assertions covering the sparkline edge cases —
      empty series, flat series, single point — that previously rendered as
      `NaN` path data, i.e. a silently blank chart); `npm run typecheck` and
      `npm run build` exit 0; module smoke exit 0.
- [ ] **[non-blocker]** The wider progressive-disclosure question is still
      open, and is now a smaller one. With Insights no longer competing for the
      same vertical space as the tab strip, the remaining candidates are a
      triage-first default view with drill-down, collapsible advanced sections,
      or regrouping the six peers into three. _(state: planned — design
      -dependent; deliberately not decided while fixing the defect underneath
      it, since the density judgement changes once the layout is honest.)_

### Lane 0.7 — Roadmap-standard fidelity: split-history awareness (2026-08-08)

Surfaced by asking whether the standard this product applies to 80+ repos
accounts for a roadmap that archives its completed work to a separate file —
the shape this repo adopted 2026-08-08. It partly does and partly does not, and
the gaps are asymmetric: nothing penalizes a split repo, but nothing can tell
one apart from a repo that simply deleted its history.

**Portfolio survey, 2026-08-08** (89 repo directories under
`F:\Development\20_Staging`, 32 with a root `ROADMAP.md`;
`output/roadmap-layout-survey.{csv,json}`):

| Roadmap history layout  | Repos |
| ----------------------- | ----- |
| inline `[x]` only       | 15    |
| no history recorded     | 15    |
| in-file history section | 2     |
| **split (archive)**     | **0** |

**Zero managed repos use the split layout** — this repo is the only instance in
the estate. That makes the repair path the live risk rather than the scoring
path: repair would push all 32 toward in-file history, and would do the same to
any repo that later adopts the split. The intent here is **awareness, not
enforcement** — the split keeps an agent's context minimal and focused, so the
standard should recognize and preserve it, never "correct" it.

Two further survey findings, both independent of the split question:

- **28 of 32 repos use no release sections at all** — a far larger conformance
  gap than anything about history placement, and the reason so many sit at L2.
- **No repo scored identically under both evaluators** (0/32), and three flipped
  the L3 dispatch-readiness threshold. **Closed 2026-08-08** — detection moved
  into the rule pack (v1.2, v1.3) and the two evaluators now agree on every
  roadmap in the estate; a module-smoke tripwire fails on any divergence. Full
  text and evidence in
  [the archive](docs/history/completed-releases.md#lane-07--the-two-roadmap-evaluators-disagreed-on-the-same-file).

- [x] **Fold `tools/Test-RoadmapStructure.ps1` into the shared detection
      contract — it was the third private copy.** _(state: done 2026-08-08)_
      The linter now reads `detection.releaseStatusPattern` and
      `detection.statusVocabulary` from the rule pack at load
      (`Import-RoadmapStatusContract`); the literals it keeps are a declared
      mirror for standalone use in a repo that does not vendor the standards
      tree, byte-identical to the JSON and guarded by a test that diffs them
      against it. Its private map was **not** a subset of the pack's — it knew
      `pending` and `released`, which were merged into `statusVocabulary` when
      this was found, and it was missing twelve the pack had (`deferred`,
      `on hold`, `in review`, `paused`, …), so the same word could read as a
      status in one tool and as unknown in the other. Folding it in also
      forced a **rule-pack 1.4** correction: the linter's regex tolerated
      `Status: done. Shipped 2026-05.` and `Status: active, pending review`,
      which the 1.3 pattern matched **not at all**, so adopting 1.3 unchanged
      would have converted readable statuses into `RQ001-MISSING-STATUS`
      warnings. Sentence punctuation (`.`, `,`, `;`) is now a status
      terminator in the shared pattern; tolerance still applies to reading
      only. That widening immediately exposed a second defect the linter's
      stricter copy did not have: 1.3 made the **colon optional**, so any
      prose line opening with the word "status" parsed as a declaration — this
      lane's own write-up tripped `RQ002-INVALID-STATUS` on a sentence. The
      colon is mandatory in 1.4, which makes the shared pattern strictly more
      precise than 1.3 rather than only more tolerant. Evidence: `Test-RoadmapStructure.Tests.ps1` 27/27 (3 new cases —
      punctuation tolerance, full alias vocabulary, and a pack-vs-mirror
      equality guard), linter output on this `ROADMAP.md` byte-identical
      before and after, `Invoke-ModuleSmokeTest.ps1` exit 0, and
      `Invoke-TestSuite.ps1 -SkipApiHost` 11/11 gates green. `Test-RoadmapStructure.Tests.ps1`
      28/28 (4 new cases — punctuation tolerance, mandatory colon, full alias
      vocabulary, and a pack-vs-mirror equality guard).
- [x] **"Product Direction" accepted into the product-intent vocabulary.**
      _(state: done 2026-08-08 — decided in the standard, not in this repo's
      file)_ `productIntentHeadingPattern` recognized `product intent`,
      `product scope`, `overview`, `about`, `purpose`, `background`, and
      `what this does/is`, but not **`Product Direction`** — the heading
      section 2 actually uses, and a plain synonym of the already-accepted
      `product intent` rather than a missing section. Renaming this repo's
      heading would have left the same false negative in place estate-wide for
      any repo using the synonym, so the vocabulary was widened in rule pack
      1.4 instead. `productIntentNote` now records that synonyms are added on
      evidence, not speculatively. Evidence: this repo's contract score
      **92 → 100** (`L4-Orchestration-Ready` both before and after) with
      ROADMAP-004 the only rule that changed state.
- [ ] **Record whether a repo externalizes its completion history.**
      _(state: planned)_ The contract carries `completedCount` as a required
      field, and a split roadmap reports ~0 forever. No rule reads it today,
      so nothing breaks — but nothing distinguishes "history archived to
      `docs/history/`" from "history deleted", and any future consumer that
      treats `completedCount` as progress would read a well-kept split repo as
      inert. Add an explicit signal (e.g. `historyLocation` / `archiveRef`)
      to [`roadmap-contract.schema.json`](standards/roadmap/roadmap-contract.schema.json),
      set from a pointer link in the roadmap, and surface it in the audit
      payload.
- [ ] **Sanction the external-archive pattern in the standard.** _(state:
      planned — documentation)_ `ROADMAP_TEMPLATE.md` Section 6 anticipates
      release sections being "archived or removed" but assumes the surviving
      history stays **in** the roadmap; no part of the standard, schema, or
      the 12 audit rules mentions an external archive file. Document it as a
      supported option with a required pointer convention, so a split repo is
      self-describing rather than merely unpenalized.

### Lane 0.8 — Verification gate integrity (CI audit 2026-08-10)

Surfaced by asking what actually gates a merge. Findings, each verified:
**the frontend has no gate anywhere** — `ci-smoke.yml` (9 gates) and
`Invoke-TestSuite.ps1` (11 gates) run zero frontend checks, so the 149 vitest
assertions, `typecheck`, and the Vite build run only when someone types them;
**`ci.yml` is a no-op green check** — it calls `reusable-ci.yml` with
`node/python/dotnet: false`, so every step body is `if [ "false" = "true" ]`
(run 31357209466: green in 9s with Setup Node skipped), yet it counts toward
`mergeStateStatus: CLEAN`, half the merge evidence for PRs #99–#101;
**no linter runs anywhere** (no ESLint config exists; PSScriptAnalyzer is
installed for the Copilot sandbox and read by `Roadmap.Evaluator.ps1` to score
_other_ repos — the product grades the portfolio on validation signals it does
not apply to itself); **`main` had no branch protection**, so even the check
list was convention. A green tick that cannot fail spends trust it never earned.
_Resolved 2026-08-10 after the gates became honest:_ `main` now requires the
`smoke` check (the full 17-gate suite), `enforce_admins` included; force
pushes and branch deletion are blocked. `mergeStateStatus: CLEAN` is
enforcement now, not convention.

Safe path, in order — cover must never drop between steps:

- [x] **Make the gate honest, then delete `ci.yml`.** _(state: smoke-tested —
      closed 2026-08-10)_ Implemented in a **stronger form than planned**:
      instead of mirroring the gate list into `ci-smoke.yml` and policing the
      two copies, CI now **invokes `Invoke-TestSuite.ps1` itself** (checkout →
      setup-node → `npm ci --include=optional` → the suite), so local
      `npm test` and CI are one list **by construction** — mirroring would
      also have preserved the reverse gap, since the local suite already
      covered three gates CI never ran (OpenAPI spec, spec dir,
      roadmap-audit-action). The suite gained the three frontend gates
      (`typecheck`, `test:unit`, `build`) via `Invoke-NpmGate`, which **fails
      with a named cause** when npm or `node_modules` is missing rather than
      skipping — a suite that silently passes without Node is the vacuous
      green this item exists to kill. `ci.yml` and `reusable-ci.yml` are
      deleted (no external caller per `gh search code`). Folded-in hardening:
      the suite's default port moved **7071 → 7171** — `Clear-ListenerPort`
      kills whatever listens on the target port, so a bare `npm test`
      previously terminated the operator's live portal. **Evidence:** full
      suite exit 0 with the three frontend gates in the summary; the landing
      PR's own CI Smoke run is the first honest CI pass — that green is the
      live proof, not a prior claim.
- [x] **Tripwire: CI must cover the local suite.** _(state: smoke-tested —
      closed 2026-08-10)_ Module smoke now fails if `ci-smoke.yml` stops
      invoking the suite, smuggles in `-SkipApiHost`, adds a `paths` filter
      (filtered PRs merge on no evidence), drops the `pull_request` trigger,
      skips `npm ci`, or if either vacuous workflow file returns; and it
      fails if the suite itself is hollowed (≥7 script gates asserted, and
      `typecheck`/`test:unit`/`build` by name). Comment lines are stripped
      before matching, per the Lane 0.5 precedent. **Evidence:** module
      smoke — `ci-smoke.yml runs the full suite (7 script gates, 3 npm
      gates)`; adversarially proven with seven scratch mutations (baseline
      passes, six hollowings each fire the specific assertion).
- [x] **Close the render gap.** _(state: smoke-tested — closed 2026-08-10)_
      jsdom + `@testing-library/react`; `*.test.tsx` files run under jsdom via
      a per-file pragma so the pure-logic tests keep the cheaper node
      environment. Fifteen DOM tests across three components, each asserting
      the half its pure-logic twin cannot see: **ActionBar** — the component
      actually consults `requiresBulkConfirmation`, Cancel really stops the
      action, explicit selection skips the dialog, read-only Report never
      shows it, and the zero-scope hint names the missing root;
      **DashboardViewTabs** — every `VIEW_META` view is reachable, selection
      fires, the subtitle tracks the active view; **InsightsView** — the
      panel body renders (the DOM half of the Lane 0.5 contract), an idle
      ledger stays visible with an explanation while never-loaded metrics
      show the distinct unavailable state, a failed refresh labels the stale
      snapshot, and the analytics Retry is wired to the trend loader.
      **`playwright` removed** from root devDependencies — unused; its only
      codebase reference was a keyword string in the roadmap linter.
      Folded-in hardening: `npm audit fix` cleared 4 advisories (3 high,
      incl. the vite Windows UNC-path fs.deny bypass) → **0 vulnerabilities**.
      **Evidence:** `npm run test:unit` 164 passing across 14 files (15 new
      DOM assertions); typecheck, build, module smoke all exit 0.
- [x] **Linting — failing gates from day one, with the debt ratcheted.**
      _(state: smoke-tested — closed 2026-08-10)_ Landed stronger than the
      report-only plan: both linters are **failing suite gates immediately**,
      with pre-existing debt held by ratchets that only tighten. **ESLint**
      (flat config, typescript-eslint + react-hooks): initial wall was 185;
      real defects fixed at adoption — `RepoGrid`'s
      `declare global JSX IntrinsicElements: any` escape hatch **deleted**
      (it disabled element-name typechecking app-wide; typecheck stayed clean,
      so nothing hid behind it), `RoadmapViewerModal` use-before-declaration
      reordered, `ChangeHistoryPanel` impure `Date.now()` render moved to a
      lazy initializer, `apiClient` dead assignments removed and the scan
      timeout now carries its `cause`, ~20 dead imports/vars deleted. Debt
      rules (`no-explicit-any` 123, `set-state-in-effect` 31) downgraded to
      warn under `--max-warnings 161`. **PSScriptAnalyzer**
      ([`Invoke-LintGate.ps1`](scripts/Invoke-LintGate.ps1) +
      `PSScriptAnalyzerSettings.psd1` + `scripts/pssa-baseline.json`): the
      one Error-severity finding **fixed** (`New-AdapterResponse`'s `$Error`
      parameter shadowed the automatic variable; JSON key unchanged), Errors
      hard-zero forever, 598 warnings baselined per-rule (17 rules), any
      growth or new rule fails, `-UpdateBaseline` locks improvements in.
      `PSAvoidUsingWriteHost` (723) excluded as **policy** — gate scripts'
      operator UI — not counted as debt. **Evidence:** ratchet adversarially
      proven (+1 `Invoke-Expression` → FAIL naming rule/delta/site; removed →
      PASS); suite now 17 gates; typecheck, lint, 164 unit tests, build,
      module smoke all exit 0.

---

## 8. Risks and Guardrails

The full list lives in
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md).
Headline guardrails for the active release and near-term roadmap:

- Do not auto-dispatch tasks without a visible readiness model.
- Do not silently mark roadmap items complete based only on code churn.
- Prefer preview-first workflows before write-back or autonomous mutation.
- Preserve genuine completion history when rewriting roadmaps.
- Enforce L3+ roadmap maturity before any dispatch.
- Do not treat an AI-improved README or ROADMAP as accepted until the
  operator reviews the side-by-side diff and explicitly applies it.
- Do not show merge readiness unless the app can identify the PR, latest
  Actions result, validation evidence, and unresolved blockers.
- Do not let dashboard badges become decorative; every badge must drill
  into the source data or explanation that produced it.
- Do not merge automatically; merge must remain an explicit operator action
  after readiness passes.
- **Do not mark an item `[x]` while it still names an outstanding proof.**
  Split it: archive the shipped half, keep the unproven half open.

---

## 9. Roadmap Contract Standard for Managed Repos

The full Roadmap Contract Standard is documented in
[`docs/reference/roadmap-contracts.md`](docs/reference/roadmap-contracts.md)
and shipped as a package under
[`standards/roadmap/`](standards/roadmap/) (template, schema, audit rules,
maturity model, repair prompt), with the publishable copy under
[`spec/roadmap-contract/`](spec/roadmap-contract/). Managed repos should
converge toward the release-oriented format described there.

---

## 10. Definition of Done for Release Execution

A release should not be marked complete unless:

- all checklist items for that release are truly implemented or explicitly
  blocked
- UI elements are connected to real behavior rather than placeholders
- affected docs are updated where workflow or product behavior changed
- logging and error handling are sufficient to diagnose failures
- later releases were not partially started just to create the illusion of
  momentum
- dashboard signals can be traced back to their source data
- preview-first flows have explicit apply/dispatch/submit/merge actions
- validation and smoke coverage exist for new routes or workflows

This roadmap intentionally treats each release as a bounded, agent-usable
execution contract.

---

## 11. Roadmap Structure Validation

Run the lightweight roadmap validator before handing this file to another
coding agent:

```powershell
pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md
```

The check is read-only. It reports release-order warnings, missing release
sections, active-release pointer/detail mismatches, duplicate headings,
stale "Immediate Next Focus" references, completed-release detail that
belongs in the archive, oversized future release sections, file-length
drift, and other obvious execution-roadmap issues. Optional outputs:

```powershell
pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md `
  -JsonOut ./output/roadmap-structure-findings.json `
  -CsvOut ./output/roadmap-structure-findings.csv
```

CI runs the same script with `-FailOnError`, so warnings remain advisory
while structural errors fail the smoke workflow.

<!-- Release 2.7 Phase A — live submit-PR evidence.
     This note was written, committed, pushed, and opened as a pull request by
     POST /api/roadmap/repair/submit-pr (createPr=true) at 2026-08-09 12:43:32 UTC.
     Its existence in a PR IS the Phase A artifact: it proves the write path
     runs end to end against a real repo, not just the dry-run plan. -->