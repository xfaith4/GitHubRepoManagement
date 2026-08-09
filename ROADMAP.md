# GitHub Repo Management ??? Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 2.7 ??? Guarded Scheduled Automation (Curated-Subset, Preview-First)**
> **Next active release:** **Release 2.9 ??? Operator Field Proof and Mobile Completion**
> **Work ordering:** dependency-driven, not insertion order ??? see
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
interchangeable ??? mixing them is what previously made the roadmap read as
"everything is done" while real gaps sat unlabelled:

1. **Correctness regressions** ??? something shipped and then broke. The two
   open on 2026-08-07 (the tracked `settings.json` fixture path, and the
   silent workspace-path failure) both closed 2026-08-08; see Lanes 0.1
   and 0.6.
2. **Credential-gated proof** ??? the code path is written and smoke-tested,
   but no live round trip has ever run (live submit-PR).
3. **Genuinely unbuilt engineering** ??? Release 2.7 Phases C and D, two
   mobile surfaces, and four cross-cutting hygiene items.
4. **Elevated / hardware / human verification** ??? needs SYSTEM rights, a
   physical Android phone, or an operator sitting at an authenticated
   Claude Code session. No autonomous test can produce these.
5. **Calendar-gated accrual** ??? the 7/90-day trend windows fill only as
   time passes with capture running.

**Current focus (next agent actions), in order:**

- [ ] **Release 2.7 Phase A ??? the live submit-PR proof.** Now unblocked: the
      service reads a Machine-scoped token and returns private repos
      (Lane 0.2, closed 2026-08-08). Phase A is in turn the gate for Phase C,
      the largest remaining product increment.
- [ ] **Release 3.0 ??? operator-context execution.** Dispatch cannot run from
      the service at all (`gh agent-task` requires OAuth; LocalSystem cannot
      hold one), so the guided-improvement wizard dead-ends at its last step.
      Approach decided 2026-08-08; no prerequisites.
- [ ] **Lane 0.5 / 0.6 cosmetics** ??? the GitHub rate-limit readout that is
      always null, the portal TLS certificate password, and the zero-scope
      action hint. All non-blockers; **Lane 0.3 closed entirely 2026-08-09.**

**Closed 2026-08-09:** Lane 0.4's cold-scan request deadline ??? the freeze guard
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
module-smoke tripwire rather than just applied ??? the tripwire found two `F:\`
offenders that the item's own `G:\` file list could never have named.

**Closed 2026-08-08 and archived out of this file:** the settings.json
regression (Lane 0.1, which closed entirely), the silent workspace-path
failure, Lane 0.5's two data-integrity findings, the credential reissue and
live-validation probe, the service's readable token, the two smoke gaps,
scheduler failure alerting, two installer defects that had made the documented
credential fix a silent no-op, and the Copilot-dispatch OAuth diagnosis that
produced Release 3.0. Full text with evidence is in
[the archive](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).
**This file now carries open work only** ??? every remaining checkbox is
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

> scan portfolio ??? index repos ??? classify every repo ??? show lifecycle state ???
> identify blockers ??? repair README/roadmap/structure ??? rank highest-value
> next work ??? refine agent prompt ??? dispatch ??? monitor agent run ??? validate
> Actions ??? evaluate merge readiness ??? update roadmap / report progress

For the full thesis, ten core questions, principles, risks, and guardrails,
see
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md).

---

## 3. Implementation-State Vocabulary

Every milestone in this roadmap should carry one of these states. A `[x]`
checkbox alone is not enough ??? it does not distinguish "backend exists" from
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
for `operator-verified`" prose; those were split ??? the shipped half went to
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
| 0.4 - 1.1 | Foundation through Standardization and Guardrails                        | `done` ??? see [archive](docs/history/completed-releases.md)                                 |
| 1.2       | Enhanced Portfolio Intelligence                                          | `done` ??? closed 2026-07-05; see archive                                                    |
| 1.3 - 1.7 | Frontend build, repo evaluation, README generation, dispatch, git status | `done` ??? see archive                                                                       |
| 1.7.5     | Portfolio Mission Alignment, Indexed Scanning, Value-Ranked Planning     | `done` ??? shipped 2026-05-28; see archive                                                   |
| 1.8 - 2.0 | Operations workspace, AI doc cycles, agent-run monitoring                | `done` ??? see archive                                                                       |
| 2.1       | Persistent Data Layer                                                    | `done` (engineering) ??? closed 2026-08-07; operator sign-off tracked in 2.9                 |
| 2.2       | API Auth, Network Security, Onboarding, GitHub App                       | `done` (engineering) ??? 2026-07-05; optional live App-token exchange tracked in 2.9         |
| 2.3       | Portfolio Analytics, Trend Visualization, Distribution                   | `done` (engineering) ??? 2026-07-06; 7/90-day accrual is calendar-gated, tracked in 2.9      |
| 2.4       | Agent Integration Protocol and AI Repair Loop                            | `done` (engineering) ??? 2026-07-05; live submit-PR proof tracked in 2.7 Phase A             |
| 2.5       | Mobile-Friendly Operator Experience                                      | `done` (engineering) ??? 2026-07-05; two surfaces + device proof tracked in 2.9              |
| 2.6       | Interface Clarity and Operator Orientation                               | `done` ??? 2026-07-06; device sign-off tracked in 2.9                                        |
| **2.7**   | **Guarded Scheduled Automation (Curated-Subset, Preview-First)**         | **active** ??? Phase B done; **Phases A, C, D open**                                         |
| 2.8       | Local Claude Code Execution (queue + operator runner)                    | `done` (engineering) ??? 2026-07-15; real `claude` run tracked in 2.9                        |
| **2.9**   | **Operator Field Proof and Mobile Completion**                           | `planned` ??? collects every external-resource residual plus the two unbuilt mobile surfaces |
| **3.0**   | **Operator-Context Execution**                                           | `planned` ??? one dispatch model; the service enqueues, an operator session executes         |
| **3.1**   | **Closed-Loop Delivery**                                                 | `planned` ??? rank ??? dispatch ??? monitor ??? Actions ??? merge readiness ??? roadmap write-back     |
| **3.2**   | **Portfolio Scale and Responsiveness**                                   | `planned` ??? serve from the index; retire the cold-scan cliff and the deadline kill         |
| **3.3**   | **Steady-State Operation**                                               | `planned` ??? unattended for months: retention, restore, honest TLS, decision-grade digests  |

> **Note on `.5` numbering.** Release 1.7.5 was a deliberate course-correction
> release between 1.7 and 1.8. Reserve the `.5` pattern for similar course
> corrections; default new work to integer minor releases.

### Execution Order and Dependencies

Release numbers identify scope ??? they do not dictate sequence. Work through
open items in the order below, and update this section whenever a lane
closes or a new dependency appears.

**Step 0 ??? unblockers and correctness: closed 2026-08-08.** All three landed ???
the tracked `settings.json` scan roots, GitHub write credentials including a
token the LocalSystem service can actually read, and the two smoke gaps. Their
detail is in
[the archive](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).

**Two parallel lanes (no cross-dependency between them):**

- **Automation lane ??? Release 2.7 Phases A ??? C.** The largest remaining
  product increment: scheduled roadmap-item packaging. Phase A's credential
  gate is now open; Phase C stays strictly behind Phase A, because
  auto-ranking without a proven write path produces packets nobody can act on.
- **Reliability lane ??? Release 2.7 Phase D.** Zero prerequisites. The two
  remaining frontend items (value-tier and automation-scope vitest units,
  `Dashboard.tsx` decomposition) and freeze prevention are schedulable
  immediately and independently.

**After the lanes:**

1. **Release 2.9 mobile completion** (touch ergonomics beyond the Phase 1
   surfaces, tap-through agent-run list) ??? engineering work, no gates.
2. **Release 2.9 field proof** ??? batch the elevated/hardware/human checks
   into as few sessions as possible; several share a setup (an elevated
   shell covers the watchdog _and_ the service installer; a phone session
   covers 2.5 _and_ 2.6).
3. **Release 2.9 trend accrual** ??? closes itself as calendar time passes;
   requires only that capture keeps running.

**Then the 3.x arc ??? from "the pieces work" to "the console works":**

Releases 3.0-3.3 are the path to a finished product rather than a working one.
They are ordered by dependency, not by size:

1. **3.0 Operator-Context Execution** ??? nothing downstream can be proven while
   dispatch cannot run. Start here; it has no prerequisites.
2. **3.1 Closed-Loop Delivery** ??? needs 3.0 for dispatch and 2.7 Phase A for a
   proven write path. This is where the north-star workflow first runs whole.
3. **3.2 Portfolio Scale and Responsiveness** ??? independent of 3.0/3.1 and
   schedulable in parallel. Lane 0.4's deadline decision landed 2026-08-09
   (extended tier, not exemption), so 3.2 starts from a bounded 900-second
   scan budget it has to beat rather than from an open question.
4. **3.3 Steady-State Operation** ??? every milestone is independent; pick items
   up whenever a release lane is blocked on an external resource.

**Dependency map (open work only):**

| Open item                                            | Depends on                                           | Type                                          |
| ---------------------------------------------------- | ---------------------------------------------------- | --------------------------------------------- |
| Release 2.7 Phase A (live submit-PR proof)           | ???                                                    | none ??? credential gate closed 2026-08-08      |
| Release 2.7 Phase C (scheduled roadmap packaging)    | Release 2.7 Phase A                                  | hard ??? no auto-rank/PR without a proven write |
| Release 2.7 Phase D (two frontend items + freeze)    | ???                                                    | none ??? schedulable anytime                    |
| Release 2.7 Phase D freeze prevention                | Watchdog field proof (2.9) for the paired safety net | soft ??? ship prevention regardless             |
| Lane 0.3 layout follow-ups; Lane 0.4 worklog archive | ???                                                    | none ??? schedulable anytime                    |
| Release 2.9 mobile completion (ergonomics, run list) | ???                                                    | none ??? the responsive foundation is shipped   |
| Release 2.9 physical-Android proof (2.5 + 2.6)       | An Android device on the LAN                         | hard ??? hardware                               |
| Release 2.9 watchdog + service-installer proof       | An elevated (SYSTEM) session                         | hard ??? privilege                              |
| Release 2.9 real `claude` run (2.8)                  | An authenticated operator Claude Code session        | hard ??? human                                  |
| Release 2.9 GitHub App installation-token exchange   | A registered GitHub App                              | hard ??? optional; PAT supersedes               |
| Release 2.9 trend accrual (2.3 Ph2)                  | Days of live capture                                 | hard, time-gated                              |
| Release 3.0 operator-context execution               | ???                                                    | none ??? approach decided 2026-08-08            |
| Release 3.1 closed-loop delivery                     | Release 3.0; Release 2.7 Phase A; `Checks: Read`     | hard ??? needs dispatch and a proven write path |
| Release 3.2 scale and responsiveness                 | ???                                                    | none ??? deadline decision landed 2026-08-09    |
| Release 3.3 steady-state operation                   | ???                                                    | none ??? independent milestones, any order      |

---

## 5. Active Release Snapshot

### Active release detail ??? 2.7 Guarded Scheduled Automation

Release 2.7 was promoted 2026-08-07 after the Release 2.1 through 2.6 and 2.8
closeout. Phase B shipped 2026-07-06; Phases A, C, and D are open.

The full execution contract for the active release ??? goal, outcomes,
milestones, acceptance criteria, validation plan, risks, dependencies, known
issues, traceability, phase plan, and budget guardrail ??? lives in one place,
[Release 2.7 below](#release-27--guarded-scheduled-automation-curated-subset-preview-first),
per `ROADMAP_TEMPLATE.md`: the release section is the single source of truth
for its own status. This heading exists so the roadmap validator can resolve
the active-release pointer; it deliberately restates nothing.

**Current focus:** Phase A ??? its credential gate closed 2026-08-08, so the
live submit-PR proof that opens Phase C is now the highest-value move. Phase D
runs in parallel; it needs nothing from anyone.

---

## 6. Open Releases

### Release 2.7 ??? Guarded Scheduled Automation (Curated-Subset, Preview-First)

**Status:** active

**Goal:** turn the operator-driven pipeline into a scheduled one that
advances **favorite / portfolio-candidate** repos automatically ??? proposing
README/ROADMAP refinements and packaging the highest-value ready roadmap work
on an interval ??? while stopping at the human approval gate. No silent
mutation, no auto-merge: everything runs preview-first, inside the existing
quota/budget guard, with an append-only audit trail.

**Prerequisites:** Phase A needs valid GitHub write credentials (Lane 0.2).
Phase C needs Phase A. Phase D needs nothing.

#### Product outcomes

- The operator enables an interval and the app keeps the curated subset
  assessed and surfaces ready-to-approve improvements with no manual trigger.
- Scheduled runs package the top-value ready roadmap item per favorite repo
  into a review-ready task packet + repair-PR plan, inside the quota guard.
- Every scheduled action is recorded in append-only run history with a
  reason; failures raise an alert instead of failing silently.
- Archived/ignored repos are never touched ??? scope is exactly the curated set.
- The always-on portal does not freeze under ordinary daily load, and if it
  does, it recovers without operator intervention.

#### Engineering milestones

Phase A ??? Credential-gated proof:

- [ ] Prove a live submit-PR round trip on one write-enabled repo: branch
      push, PR creation, PR visible in the target repo, run recorded.
      Closes the Release 2.4 residual and opens Phase C.
      _(state: backend-complete ??? the write path was **built** 2026-08-09;
      the live round trip is the remaining step. Explicit
      operator-authorized action; Ben approved 2026-08-09, target = this
      repo.)_
      **This item was mis-scoped, and the correction matters.** It read as a
      credentials gate ??? "the dry-run plan path is smoke-tested; only the live
      round trip is missing", and the 2026-08-08 status note said Phase A was
      "now unblocked" because the service could read a token. In fact
      `POST /api/roadmap/repair/submit-pr` **had no live path at all**: even
      with `createPr=true` it returned `created=false` / `prUrl=null` and a
      note saying no branch was pushed. There was no checkout, commit, push,
      or PR creation anywhere in the route. The credentials were never what
      was blocking it. Half the machinery did exist ???
      `POST /api/roadmap-agent/approve-push` performs a real token-authenticated
      push ??? but it stops at the push ("Open the PR from GitHub when ready").
      **Built 2026-08-09:**
      [`Roadmap.PrSubmitter.ps1`](backend/modules/roadmap/Roadmap.PrSubmitter.ps1)
      does branch ??? write ??? commit ??? push ??? `POST /repos/{o}/{r}/pulls`, with
      the pure parts (branch naming, remote-slug parsing, the refusal matrix)
      split out so they are testable without a checkout or a token. Safety
      properties, each asserted: never force-pushes, never commits onto the
      base branch, always returns to the starting branch via `finally`,
      refuses a dirty working tree rather than sweeping unrelated edits into
      an automated PR, refuses a no-op diff rather than opening an empty PR,
      and keeps the token out of the git argv (base64 `http.extraheader`, the
      same approach `approve-push` uses). A refusal returns **409 with a named
      reason and category**, never `200` with `created=false` ??? the caller
      must not be able to read "no PR" as success, which is exactly how the
      stub behaved. The run is recorded as a `submit-pr` event in the existing
      append-only repair history, carrying `prUrl`/`prNumber`/`branch`/`repoSlug`.
      **Evidence so far:** module smoke exit 0 ??? `submit-PR ok: 4 remote forms
      parsed, 4 non-GitHub refused, 8 refusal categories named, token not in
      cleartext`.

Phase C ??? Scheduled roadmap-item packaging (the prize; gated on Phase A):

- [ ] For each favorite repo with a ready L3+ roadmap, select the top-value
      pending item using the settled scoring semantics (MAX within a
      dimension + `effortFit` floor), build a task packet + repair-PR plan,
      and queue it for approval. _(state: planned ??? blocked on Phase A)_
- [ ] Gate every packaged item through the quota/budget guard; skip and log
      when over budget. _(state: planned)_
- [ ] Notify per run; approval triggers dispatch (live PR once Phase A
      passes). No auto-merge. _(state: planned)_
- [ ] Smoke: a scheduled run ranks + packages one fixture repo's top item,
      honors the quota-refusal path, and dispatches only on explicit
      approval. _(state: planned)_

Phase D ??? Hardening & observability (parallelizable, autonomous, unblocked):

- [ ] **Freeze prevention (root cause), paired with the shipped watchdog.**
      Guarantee `/api/status` + assessment caching cannot regress off (a
      gutted cache caused the 2026-07-05 blocking-scan pile-up); add a
      per-request work timeout so one blocked native call ??? e.g. the SQLite
      bridge ??? cannot wedge the single-threaded accept loop; schedule
      `app.db` maintenance (VACUUM + snapshot retention; ~138 MB and
      growing). _(state: in progress ??? all three engineering parts are now
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
      windows are clamped **up** to a per-table floor ??? 180 days for every
      table with a history reader ??? because `GET /api/portfolio/trend` answers
      up to `days=180` and Release 2.9 is waiting on 7/90-day accrual; a low
      configured window must never delete the history that milestone needs.
      Append-only operational records (`execution_ledger`,
      `execution_history`, `agent_runs`, `repo_curation`) are never touched.
      **Evidence:** module smoke asserts report-only counts without deleting,
      the 180-day floor protecting 100-day-old rows against a 30-day request,
      VACUUM running, and `ops_log` untouched; api-host smoke
      `dbMaintenanceOk=True` asserts the floor survives the HTTP round trip.
- [x] Complete the frontend unit-test set (vitest). _(state: smoke-tested ???
      4 of 4 named units covered, closed 2026-08-09)_ `needsAttention` and
      `viewMeta` were already covered
      ([`needsAttention.test.ts`](frontend/lib/needsAttention.test.ts),
      [`viewMeta.test.ts`](frontend/viewMeta.test.ts)). The two gaps closed
      by extracting the logic out of the components that held it, so the
      tests cover the code that actually ships rather than a copy:
      **value tiers** ??? [`lib/valueTier.ts`](frontend/lib/valueTier.ts) +
      [`valueTier.test.ts`](frontend/lib/valueTier.test.ts), consumed by
      `WorkQueueView`; **automation scope selector** (operator curation) ???
      [`lib/curationScope.ts`](frontend/lib/curationScope.ts) +
      [`curationScope.test.ts`](frontend/lib/curationScope.test.ts),
      consumed by `RepoGrid`. The scope suite pins the Release 2.7 contract
      the backend also enforces: `archived-ignore` is never in automation
      scope, and neither is an uncurated repo ??? scope opts in, it never opts
      out, so an unrecognized curation state is excluded rather than
      admitted. **Evidence:** `npm run test:unit` 79 passing across 6 files,
      `npm run typecheck` exit 0; the never-touch assertion was
      adversarially proven ??? widening `isInAutomationScope` to
      `state !== 'none'` fails
      [`curationScope.test.ts:72`](frontend/lib/curationScope.test.ts#L72).
- [x] Decompose [`Dashboard.tsx`](frontend/components/Dashboard.tsx):
      extract the view-router/tab shell and the summary/mission sections.
      _(state: smoke-tested ??? both named extractions landed 2026-08-09)_
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
- [ ] **[non-blocker]** `Dashboard.tsx` is still 2,308 lines after the Phase D
      extractions (down from 2,519). The two sections Phase D named are out;
      what remains large is the ~600-line Insights block (Execution Throughput,
      Documentation Health, Portfolio Analytics/trend) and ~1,000 lines of
      hooks and handlers above the return. _(state: planned ??? recorded rather
      than folded into the milestone above, which asked for two specific
      extractions and got them. Worth doing, not worth blocking on.)_

#### Acceptance criteria

- Enabling automation runs unattended and produces, for the curated subset
  only, doc-improve previews + a digest ??? with nothing applied.
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
  schedule ??? preview ??? notify ??? history loop.

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

- **Blocked:** Phase A on GitHub write credentials (see Lane 0.2); Phase C
  on Phase A.
- **Risk ??? auto-ranking on unproven writes.** Packaging top-value items
  before one live PR round trip has succeeded produces review queues that
  cannot be acted on. This is why the sequence is hard, not advisory.
- **Risk ??? the portal freezes under load.** Observed twice (2026-07-05,
  2026-07-11): process alive, port listening, not responding. The watchdog
  safety net is shipped but unproven at SYSTEM; the root-cause prevention
  work is still open in Phase D.
- **Risk ??? `app.db` growth.** ~138 MB in daily use. **Mitigated 2026-08-08:**
  scheduled prune + VACUUM ships in Phase D and runs daily from
  `Invoke-DailyEvidence.ps1`; per-table retention floors keep the trend
  windows Release 2.9 is waiting on intact.
- **Risk ??? the freeze guard kills the host during a legitimate cold scan.**
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
      workspace exceeds that ??? so the guard that exists to protect the portal
      is the thing that stops it. Tracked as the top open item in Lane 0.4;
      Release 3.2 implements whichever way that decision lands.
- [ ] Phase C's approval-triggers-dispatch step has no working dispatcher.
      `gh agent-task` requires an OAuth token and the portal runs as
      LocalSystem, so packaged items cannot currently be dispatched from the
      service at all. Release 3.0 moves execution into an operator session;
      until it lands, Phase C can package and queue but not dispatch.

Both known issues that stood here on 2026-08-07 ??? the tracked `settings.json`
fixture path and the expired PAT ??? closed 2026-08-08; see
[the archive](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).

**Traceability:** Phase B shipped
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
| Phase A: Unblockers                  | Live submit-PR proof on one write-enabled repo                                                          | **planned ??? blocked on credentials (Lane 0.2)**          | ???          | ???           | ???          |
| Phase B: Scheduled doc refinement    | Scheduler + favorite-scoped doc-improve previews + digest + run history                                 | **done ??? smoke-tested** (2026-07-06) ??? see archive       | 2026-07-06 | ???           | ???          |
| Phase C: Scheduled roadmap packaging | Top-value item packaging + quota guard + approve-to-dispatch                                            | **planned ??? blocked on Phase A**                         | ???          | ???           | ???          |
| Phase D: Hardening & observability   | Frontend unit tests, Dashboard decomposition, failure alerting, freeze prevention, auth operator-verify | **in progress ??? 4 of 6 shipped; 2 open (frontend)**      | ???          | ???           | ???          |

#### Budget guardrail

- Scheduled automation consumes AI work units per packaged item; every run
  routes through the Release 2.0 quota/budget guard and refuses or annotates
  over-budget work rather than proceeding.
- Record raw observations per scheduled run (units consumed, credit/API
  spend, refusals) into the automation run history.

---

### Release 2.9 ??? Operator Field Proof and Mobile Completion

**Status:** planned

**Goal:** convert every surface that is `smoke-tested` but still waits on an
external resource into `operator-verified` with durable evidence, and finish
the two mobile surfaces that were left engineering-incomplete under Release
2.5. This release adds no new product capability ??? it closes the honesty gap
between "the automated suite is green" and "this works in the field."

**Prerequisites:** the mobile-completion milestones have none. Each field-proof
milestone names the one external resource it waits on; none block each other,
and several share a session ??? an elevated shell covers both SYSTEM milestones,
one phone session on the LAN covers both device milestones. Batch them rather
than scheduling six separate sessions.

#### Product outcomes

- No milestone is marked complete on the strength of an automated suite alone
  when what it claims needs hardware, elevation, credentials, or a human.
- The always-on portal is proven to recover from a real freeze, not a
  simulated one.
- The dashboard is proven usable on a real Android phone ??? touch, install,
  and all four target workflows ??? not only at an emulated 390px viewport.
- Trend charts show real 7- and 90-day windows.
- `evidence/` carries a durable record for each proof, so the next agent can
  read the evidence instead of re-litigating whether something works.

#### Engineering milestones

Mobile completion (no gates ??? build these first):

- [ ] Apply touch ergonomics beyond the Release 2.5 Phase 1 surfaces:
      minimum ~44px touch targets and a tap equivalent for every hover-only
      affordance (tooltips, row actions, rationale popovers) across the
      Phases 2-3 surfaces. _(state: scaffolded ??? Phase 1 surfaces done
      2026-07-04 (bottom nav 56px, card actions 44px); the rest was
      deferred and never built)_
- [ ] Add the tap-through mobile agent-run list from the agent-activity
      indicator: status, repo, phase, elapsed time. _(state: planned ??? the
      indicator ships and `/api/agent-runs` data is already reachable; only
      the mobile list view is missing)_

Field proof ??? elevated (SYSTEM) session, batch together:

- [ ] Run the elevated
      [`Install-PortalWatchdog.ps1`](scripts/service/Install-PortalWatchdog.ps1)
      and confirm a real freeze-and-recover: kill + `Restart-Service
RepoMgmtPortal`, with the action appended to
      `output/logs/service-watchdog.jsonl` and the `execution.failed`
      webhook fired. _(state: smoke-tested ??? needs `operator-verified`; the
      decision logic and a dry-run against the actual frozen host, PID 5704,
      are already proven)_
- [ ] Operator-verify the reworked
      [`Install-RepoManagementService.ps1`](scripts/Install-RepoManagementService.ps1):
      elevated install / repair / `icacls` / scheduled-task registration,
      and confirm secrets resolve from machine env vars with the tracked
      `settings.json` staying secret-free. _(state: smoke-tested ??? needs
      `operator-verified`; pure logic is covered by module smoke)_

Field proof ??? physical Android device on the LAN, batch together:

- [ ] Verify the four Release 2.5 workflows on a **physical Android phone**:
      repo health, agent activity, prompt refinement, roadmap dispatch ???
      plus real touch input and on-device home-screen install. Steps in
      [`lan-mobile-setup.md`](docs/reference/lan-mobile-setup.md).
      _(state: smoke-tested at an emulated 390px viewport ??? needs
      `operator-verified` on hardware)_
- [ ] Confirm the Release 2.6 clarity affordances pass on the same device:
      data-source indicator, per-tab subtitles, advanced-filters toggle, and
      the orientation overlay. _(state: smoke-tested ??? needs `operator-verified`)_

Field proof ??? human / credential / calendar:

- [ ] Operator-verify Release 2.1 against the live workspace and record the
      sign-off, closing the release formally. _(state: smoke-tested against
      live data ??? `output/app.db`, the real 68-repo `F:\Development` scan ???
      ??? needs a recorded human sign-off)_
- [ ] Execute one real `claude` run through
      [`Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1)
      in the operator's authenticated session: claim ??? branch ??? run ???
      verify ??? commit ??? `awaiting-review`. Closes the Release 2.8 residual.
      _(state: smoke-tested dry-run E2E ??? needs `operator-verified`)_
- [ ] Operator-verify the auth + shared-LAN path so automation runs on a bound,
      authenticated host. _(state: planned ??? carried over from 2.7 Phase D)_
- [ ] (Optional) Prove live GitHub App installation-token exchange
      (`Get-GitHubAppInstallationToken`) + auto-refresh on one registered
      app, closing the Release 2.2 residual. _(state: planned ??? not
      required; the PAT path supersedes it)_
- [ ] Let the Release 2.3 Phase 2 trend windows accrue: confirm
      `GET /api/portfolio/trend` reports a real 7-day, then 90-day, window.
      _(state: smoke-tested ??? rollup logic is live and
      `status=history-backed`; only calendar time is missing. Keep
      [`Invoke-DailyEvidence.ps1`](scripts/Invoke-DailyEvidence.ps1)
      running ??? it accrues history as a side effect.)_

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

- New product capability ??? this release only proves and finishes what exists.
- Remote (non-LAN) mobile access; native apps or app-store distribution.

---

### Release 3.0 ??? Operator-Context Execution

**Status:** planned

**Goal:** make dispatch work by running it as the operator rather than as the
service. Every dispatch path ??? roadmap task, guided repository improvement,
agent repair ??? enqueues from the portal and executes in a session that already
holds the credential the work needs. The LocalSystem host stops attempting to
wield delegated authority it structurally cannot hold.

**Prerequisites:** none. The approach was decided 2026-08-08 (Lane 0.2) after
`gh agent-task` was confirmed to reject a PAT, and it reuses the queue-plus-
runner pattern Release 2.8 already shipped for Claude Code.

#### Product outcomes

- One dispatch model instead of two: the portal enqueues, an operator-session
  runner executes, status returns through the existing run summary.
- No dispatch path requires a long-lived OAuth token stored on disk.
- A dispatch that cannot run says so **at enqueue time**, naming the missing
  runner, rather than failing at the last step of a wizard.

#### Engineering milestones

- [ ] Route the guided-improvement wizard's PR handoff through the queue
      instead of invoking the launcher in-process. _(state: planned ??? the API
      host calls `Start-GitHubCopilotTask.ps1` directly at
      [`Start-RepoManagementApiHost.ps1:8952`](backend/api-host/Start-RepoManagementApiHost.ps1#L8952);
      `Start-RoadmapCopilotTask.ps1` already models the enqueue path as
      `-DispatchMode claude`)_
- [ ] Add `dispatchTarget` (`claude` | `copilot`) to the queue entry and teach
      [`Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1) to
      execute a copilot entry via `gh agent-task create` in the operator
      session, recording the resulting task URL in the run summary.
      _(state: planned)_
- [ ] Surface runner presence ??? last heartbeat and claimed-entry count ??? so the
      portal can warn before queueing work nothing will pick up.
      _(state: planned)_
- [ ] Ship a per-user logon scheduled-task installer for the runner
      (interactive session, never SYSTEM), mirroring the watchdog installer's
      shape. _(state: planned)_
- [ ] Make the API host refuse in-service cloud dispatch with a route-level
      409 that names the runner, keeping `-DispatchMode copilot` reachable only
      from an operator shell. _(state: planned)_

#### Acceptance criteria

- The wizard's final step returns a queue id and makes no `gh` call from the
  service process.
- A queued copilot entry executed by the operator runner reaches a real GitHub
  agent task, with its URL in the run summary.
- With no runner registered, queueing reports the missing runner in the UI.
- Module smoke covers the `dispatchTarget` round-trip and the runner's copilot
  branch.

#### Out of scope

- Re-hosting the portal service under a named user account ??? that trades
  always-on-before-login for the whole product to fix one route.
- Unattended dispatch with no operator session present.

---

### Release 3.1 ??? Closed-Loop Delivery

**Status:** planned

**Goal:** close the north-star loop end to end, repeatedly, with explicit
operator gates at apply, dispatch, and merge. Today the console can rank work
and prepare a prompt, and it can read merge readiness, but no single work item
has ever travelled the whole chain ??? so the loop's real failure modes are
unknown.

**Prerequisites:** Release 2.7 Phase A (live submit-PR proof) for the write
path, Release 3.0 for a dispatch that runs, and the PAT's `Checks: Read` grant
(Lane 0.2) for per-check merge detail.

#### Product outcomes

- One roadmap item is carried from "ranked highest value" to "merged, with the
  managed repo's roadmap updated" without a human stitching the steps.
- Every stage transition is inspectable after the fact from one trace, rather
  than reconstructed from four ledgers.
- Roadmap write-back is preview-first: the console proposes the completion
  edit and the operator applies it.

#### Engineering milestones

- [ ] Add a per-work-item trace view joining rank ??? prompt ??? dispatch ??? agent
      run ??? Actions result ??? merge readiness ??? write-back, keyed by `runId`.
      _(state: planned ??? every stage already writes its own ledger; nothing
      joins them)_
- [ ] Generate the managed repo's roadmap completion edit from merge evidence
      and present it as a reviewed diff. _(state: planned ??? write-back is the
      last unbuilt step of the north-star workflow)_
- [ ] Gate write-back on merge evidence: refuse to mark an item complete from
      code churn or a green run alone. _(state: planned ??? guardrail in
      section 8 exists; no enforcement)_
- [ ] Record a full-loop proof for one real item in `evidence/`, naming each
      stage's artifact. _(state: planned)_

#### Acceptance criteria

- A single `runId` resolves to every stage artifact through one route.
- A write-back attempt with no merge evidence is refused and says why.
- The loop proof exists in `evidence/` with the PR, the Actions result, and
  the applied roadmap diff.

#### Out of scope

- Automatic merge ??? merge stays an explicit operator action after readiness
  passes.
- Multi-repo parallel dispatch; one item end to end first.

---

### Release 3.2 ??? Portfolio Scale and Responsiveness

**Status:** planned

**Goal:** make an 80+ repo portfolio feel immediate. Reads serve from the
persistent index; a cold full assessment becomes a visible background job
instead of a synchronous request that can outlive its own deadline.

**Prerequisites:** Lane 0.4's decision on whether the request deadline exempts
long-running scan routes or the cold scan is bounded ??? this release implements
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
      and a cancel. _(state: planned ??? a cold scan currently exceeds both the
      smoke's client timeout and the 180s request deadline on the real
      75-repo workspace)_
- [ ] Bound per-repo git work with a timeout and a concurrency cap so one
      pathological repo cannot stall a sweep. _(state: planned)_
- [ ] Declare and enforce a performance budget for the portfolio read path,
      with the measured figure reported next to it. _(state: planned ??? no
      target exists today, so regressions are invisible)_
- [ ] Virtualize the repo grid so row count stops driving render cost.
      _(state: planned ??? pairs with the `Dashboard.tsx` decomposition already
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

### Release 3.3 ??? Steady-State Operation

**Status:** planned

**Goal:** run unattended for months without an operator babysitting it ??? bounded
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
      policy stated in config and the pruned range logged. _(state: planned ???
      `service-watchdog.jsonl` reached 6.9 MB from one-minute probes)_
- [ ] Add a documented backup and restore path for `app.db`, including a schema
      migration story. _(state: planned)_
- [ ] Make the portal's self-reported transport match reality, closing behind
      Lane 0.2's certificate recovery. _(state: planned ??? the host degrades to
      plain HTTP on a certificate it cannot open, while config still claims
      TLS)_
- [ ] Bring every export and digest up to the decision-grade contract: data
      window, units, headline finding, recommended next action.
      _(state: planned ??? the digest payload ships; the framing does not)_

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
Completed cross-cutting items were archived 2026-08-07 ??? see
[the archive](docs/history/completed-releases.md#cross-cutting-engineering-work-completed-items) ???
and again 2026-08-08, when Lane 0.1 closed entirely and Lanes 0.2, 0.4, 0.5,
and 0.6 shed their closed items to
[the 2026-08-08 batch](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).

### Lane 0.2 ??? Credential freshness

- [ ] **Grant the PAT `Checks: Read`.** _(state: planned ??? non-blocker)_
      The reissued token still 403s on
      `repos/{owner}/{repo}/commits/{ref}/check-runs`
      (`Resource not accessible by personal access token`), so
      `gh pr checks <n> --watch` is unusable and the merge loop relies on
      `mergeStateStatus` as a proxy. Metadata, Contents, Pull requests, and
      Actions reads all pass. Verified 2026-08-07.
- [ ] **Populate `rateLimit` on the authenticated GitHub insights path.**
      _(state: planned ??? non-blocker, cosmetic, surfaced 2026-08-08)_
      `Get-GitHubReposViaApi` returns a hardcoded `rateLimit = $null`
      ([`Start-RepoManagementApiHost.ps1:2758`](backend/api-host/Start-RepoManagementApiHost.ps1#L2758)),
      so `insightsMeta.rateLimit` is always null and the GitHub view's
      rate-limit readout stays blank even though every call already receives
      `X-RateLimit-Limit` / `-Remaining` / `-Reset` headers. Capture the
      headers from the last response instead of returning null. Confirmed
      2026-08-08 against the live service: `POST /api/github/status`
      returned 50 repos and `rateLimit: null`.
- [ ] **Recover or replace the portal TLS certificate password.** _(state:
      planned ??? non-blocker, surfaced 2026-08-08)_ Machine-scoped
      `REPO_MGMT_TLS_PFX_PASSWORD` (17 chars) does not open the configured
      pfx, so the portal has been serving plain HTTP on loopback while its
      config claims TLS. Loopback-only keeps this off the critical path.
      Either recover the original password or regenerate with
      `scripts\New-RepoManagementTlsCertificate.ps1` and re-run
      `-Action Reconfigure -PfxPath ??? -PfxPassword ???`.

### Lane 0.3 ??? Layout follow-ups from the 2026-07-15 cleanup

- [x] Normalize hardcoded `G:\Development\GitHubRepoManagement`
      `-WorkspaceRoot` defaults to `$PSScriptRoot`-derived paths so the
      suite runs unmodified from any clone location. _(state: smoke-tested ???
      confirmed 2026-08-07 still present in `backend/adapters/Adapters.ps1`,
      `backend/api-host/Start-RepoManagementApiHost.ps1`,
      `backend/modules/docreview/Invoke-DocReviewInventory.ps1`, and both
      reconcile modules ??? a wider blast radius than the original note
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
      wrong in both directions ??? worth recording, because the same mistake
      produced the 2026-08-07 "wider blast radius than the original note"
      correction:
      **(a) Three of the five named `backend/` files were not `-WorkspaceRoot`
      defaults at all.** `Adapters.ps1`, `Invoke-DocReviewInventory.ps1`, and
      the reconcile modules hardcoded `$LocalRoots` / `$RootPath` ??? **scan
      targets**, i.e. where the operator's repos live, not where the tool
      lives. `$PSScriptRoot` derivation is meaningless for those. Every caller
      already passed them explicitly, so the defaults were dead code whose only
      possible effect was to scan a nonexistent drive and return "no repos"
      instead of "misconfigured". They now default to empty and throw a named
      error. Removing them exposed a hidden coupling:
      `Invoke-Reconciliation.ps1`'s empty-roots check ran even under
      `-LoadFunctionsOnly`, and had been passing only because the dead
      `G:\Development` default made the array non-empty ??? so `Adapters.ps1`
      broke the moment the default was honest. The check is now correctly
      skipped when only loading functions.
      **(b) Seven files were missing from the list**, including
      `Invoke-AuthSmokeTest.ps1` and `Invoke-PhaseProtocolTest.ps1`, which
      hardcode **`F:\`** ??? the current machine's drive, so they work here and
      break on every other clone. A `G:\` grep could never have found them.
      **The instances are fixed and the pattern is now enforced:**
      [`Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1) fails
      if any tracked `backend/`, `scripts/`, or `tools/` script declares a
      `[string]$Param = 'X:\...'` default (`*.Tests.ps1` exempt ??? those use
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
      orchestration-ready. _(state: smoke-tested ??? closed 2026-08-09)_
      **The model contradicted itself, and Ben chose the resolution
      2026-08-09.** `ROADMAP-011` (>1 active release) carried a named L2 cap
      _and_ `critical` severity; applying the blanket critical cap literally
      would have forced it to L1 and made its own documented L2 cap
      unreachable. Rather than add a precedence rule, **the severity was the
      bug**: `ROADMAP-011` is now `warning` (rules **v1.5**), so it takes the
      L3 blanket cap plus its named L2 cap and lands at L2 exactly as
      documented ??? and "any critical finding caps at L1" became literally
      true. Ambiguous dispatch is still a hard gate, because L2 is below the
      L3 contract-ready bar. Caps now **compose**: the effective ceiling is
      the lowest that applies. **Both rule-pack mirrors and both
      `ROADMAP_MATURITY_MODEL.md` copies moved in lockstep**, and the model
      now records why the severity must not be re-promoted.
      **The parity tripwire earned its keep:** implementing the caps in the
      backend auditor alone broke it immediately
      (`maturityScore module=84 cli=92`), because
      [`Test-RoadmapContract.ps1`](tools/Test-RoadmapContract.ps1) carries its
      own cap block ??? exactly the "two figures, one truth" divergence this
      product exists to catch. Both evaluators now implement the same
      composed caps. **Evidence:** module smoke exit 0 ???
      `maturity caps ok: critical -> L1-Informal (<= 39); 1 warning finding(s)
      -> L3-Contract-Ready (<= 84)`, `2 active -> ROADMAP-011 (warning) +
      capped at L2-Structured`, and `evaluator parity ok: 4 fixtures agree`.
      A new assertion fails the gate if `ROADMAP-011` is ever re-promoted to
      `critical`.
- [x] Repair `CLAUDE.md`'s dangling `@_base.md` and
      `@.claude/modes/implementer.md` imports ??? neither file exists.
      _(state: done ??? closed 2026-08-09)_ The note said to "fix at the tool
      level" because `ccmode.ps1` manages the mode line, but **`ccmode.ps1`
      does not exist either** ??? not in this repo and not under any `.claude`
      directory on this machine ??? so there was no tool level to fix at. Ben
      chose removal 2026-08-09: both imports are gone, replaced by a comment
      recording what they were and that `ccmode.ps1` can re-add its own line
      if it is ever restored. Nothing was fabricated to satisfy them.
- [x] Tune `tools/Test-RoadmapStructure.ps1` for the template's own layout:
      `ROADMAP_TEMPLATE.md` puts the full execution contract inside the
      `## Release X ??? Title` block, so R013's 120-line cap fired on any
      conformant active release, and RQ001 wanted a `Status` line on the
      "Active release detail" pointer that must not restate it (declaring it
      twice is an RQ003 error). _(state: smoke-tested ??? closed 2026-08-09;
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
      `R000-NO-RELEASES` could fire ??? `ROADMAP_TEMPLATE.md` itself is such a
      file, so the linter could not lint its own template. Both fixed.
      **The linter had no smoke coverage at all**, which is how it drifted
      into contradicting the template it lints;
      [`Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1) now
      pins both relaxations _and_ proves each rule still fires when genuinely
      violated. **Evidence:** module smoke exit 0; adversarially proven ???
      reverting either relaxation fails the gate at the matching assertion.
      The first version of that coverage captured only `2>&1`, so every
      "must fire" assertion passed vacuously while the finding scrolled past
      on the console; it captures `*>&1` now, which is what the linter's
      `Write-Host` findings actually use.

**Shipped 2026-08-07 (from this lane):** a standards???spec drift tripwire and an
"every shipped audit rule is implemented by the auditor" tripwire, both in
`scripts/Invoke-ModuleSmokeTest.ps1`. The second closes the `d2cc6cc` /
`c6662cf` regression class ??? a rule added to the pack but never evaluated
still contributes its `scoreWeight` to the denominator, silently inflating
every maturity score. Both were adversarially proven to fail when violated.

### Lane 0.4 ??? Smoke coverage gaps

- [x] **The cold-scan request deadline ??? decided and shipped 2026-08-09.**
      _(state: smoke-tested)_ `POST /api/automation/run` calls
      `Get-OperationsReposPayload`, which does a **cold full-portfolio
      assessment**. That step was fast only while the tracked `settings.json`
      pointed at a fixture directory; with the real root restored (Lane 0.1)
      it exceeded the smoke's default `-RequestTimeoutSec 180` on the real
      75-repo workspace. Worse, the **Phase D request deadline also defaulted
      to 180s and terminates the host on expiry** ??? so a legitimate cold scan
      tripped the freeze guard, and Shawl/SCM recovery restarted the host
      straight back into the same scan. The guard was manufacturing the
      outage it exists to prevent.
      **Decision: an extended tier, not an exemption.** Exempting the scan
      routes outright would restore the unbounded wedge the Phase D guard was
      built to stop, and bounding the cold scan itself is a Release 3.2
      performance problem, not a reliability fix ??? so the deadline now
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
      `REPO_MGMT_REQUEST_TIMEOUT_SECONDS` override** ??? the two workarounds
      this item existed to remove.
      **This decision is the input Release 3.2 was waiting on** (see the
      dependency map): 3.2 inherits a bounded 900-second scan budget as the
      number its responsiveness work has to beat, not an unbounded route.
- [ ] Archive the root worklogs `findings.md`, `progress.md`, and
      `task_plan.md` to [`docs/history/worklogs/`](docs/history/worklogs/),
      matching the 2026-07-15 cleanup convention they were re-created
      against. _(state: planned ??? cosmetic, but the root keeps re-accruing
      these; consider a `.gitignore` entry or a documented worklog location
      so the convention holds without a manual sweep each time.)_

### Lane 0.6 ??? Workspace-path failure was silent (P0, 2026-08-08)

- [ ] Point the zero-scope action hint at the specific cause when a root is
      missing. _(state: planned ??? non-blocker, cosmetic)_ The ActionBar hint
      still reads the generic "Scan a workspace first ??? set the workspace path
      in Settings, then Refresh" while the red alert directly above it names
      the actual missing path. The remedy it names is correct, so this is
      redundancy rather than a wrong instruction.

### Lane 0.5 ??? Portal UX follow-ups (empty-state audit 2026-08-08)

Surfaced by a walkthrough of the Repository Grid, Insights, Operations, and
Doc Readiness Queue tabs against a workspace that scanned 0 repos. The two
data-integrity findings from that audit were fixed the same day and are in
[the archive](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd);
these two are design-dependent and deliberately deferred.

- [ ] **Add a confirmation step to implicit bulk-scope actions.** _(state:
      planned ??? non-blocker)_ With no rows selected, Pull/Fetch/Report apply
      to the **entire filtered set**. The amber callout in
      [`ActionBar.tsx`](frontend/components/ActionBar.tsx) is honest about
      this and now names the count, but a banner alone still lets one click
      run a bulk git operation across the whole portfolio. Gate the
      no-selection path behind a `window.confirm`-style step naming the
      count ("This will run on 47 repositories ??? continue?"), matching the
      pattern `handleArchive` already uses. Deferred because the right
      threshold (always, or only above N repos) is a product call, and
      because `Report` is read-only and may not warrant the same friction.
- [ ] **Progressive disclosure for the six-tab dashboard.** _(state: planned
      ??? non-blocker, design-dependent)_ Grid, Insights, Operations, Doc
      Readiness Queue, Copilot Execution Lanes, and Dependencies each render
      a dense multi-widget surface, which is heavy for the primary daily
      workflow (triage the repos needing attention). Candidate direction: a
      simplified default view with drill-down, or a collapsible "advanced
      analytics" section, extending the inline-tooltip pattern already used
      on **Needs Attention**. Deferred because it changes primary navigation
      shape and should not be done incrementally.

### Lane 0.7 ??? Roadmap-standard fidelity: split-history awareness (2026-08-08)

Surfaced by asking whether the standard this product applies to 80+ repos
accounts for a roadmap that archives its completed work to a separate file ???
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

**Zero managed repos use the split layout** ??? this repo is the only instance in
the estate. That makes the repair path the live risk rather than the scoring
path: repair would push all 32 toward in-file history, and would do the same to
any repo that later adopts the split. The intent here is **awareness, not
enforcement** ??? the split keeps an agent's context minimal and focused, so the
standard should recognize and preserve it, never "correct" it.

Two further survey findings, both independent of the split question:

- **28 of 32 repos use no release sections at all** ??? a far larger conformance
  gap than anything about history placement, and the reason so many sit at L2.
- **No repo scored identically under both evaluators** (0/32), and three flipped
  the L3 dispatch-readiness threshold. **Closed 2026-08-08** ??? detection moved
  into the rule pack (v1.2, v1.3) and the two evaluators now agree on every
  roadmap in the estate; a module-smoke tripwire fails on any divergence. Full
  text and evidence in
  [the archive](docs/history/completed-releases.md#lane-07--the-two-roadmap-evaluators-disagreed-on-the-same-file).

- [x] **Fold `tools/Test-RoadmapStructure.ps1` into the shared detection
      contract ??? it was the third private copy.** _(state: done 2026-08-08)_
      The linter now reads `detection.releaseStatusPattern` and
      `detection.statusVocabulary` from the rule pack at load
      (`Import-RoadmapStatusContract`); the literals it keeps are a declared
      mirror for standalone use in a repo that does not vendor the standards
      tree, byte-identical to the JSON and guarded by a test that diffs them
      against it. Its private map was **not** a subset of the pack's ??? it knew
      `pending` and `released`, which were merged into `statusVocabulary` when
      this was found, and it was missing twelve the pack had (`deferred`,
      `on hold`, `in review`, `paused`, ???), so the same word could read as a
      status in one tool and as unknown in the other. Folding it in also
      forced a **rule-pack 1.4** correction: the linter's regex tolerated
      `Status: done. Shipped 2026-05.` and `Status: active, pending review`,
      which the 1.3 pattern matched **not at all**, so adopting 1.3 unchanged
      would have converted readable statuses into `RQ001-MISSING-STATUS`
      warnings. Sentence punctuation (`.`, `,`, `;`) is now a status
      terminator in the shared pattern; tolerance still applies to reading
      only. That widening immediately exposed a second defect the linter's
      stricter copy did not have: 1.3 made the **colon optional**, so any
      prose line opening with the word "status" parsed as a declaration ??? this
      lane's own write-up tripped `RQ002-INVALID-STATUS` on a sentence. The
      colon is mandatory in 1.4, which makes the shared pattern strictly more
      precise than 1.3 rather than only more tolerant. Evidence: `Test-RoadmapStructure.Tests.ps1` 27/27 (3 new cases ???
      punctuation tolerance, full alias vocabulary, and a pack-vs-mirror
      equality guard), linter output on this `ROADMAP.md` byte-identical
      before and after, `Invoke-ModuleSmokeTest.ps1` exit 0, and
      `Invoke-TestSuite.ps1 -SkipApiHost` 11/11 gates green. `Test-RoadmapStructure.Tests.ps1`
      28/28 (4 new cases ??? punctuation tolerance, mandatory colon, full alias
      vocabulary, and a pack-vs-mirror equality guard).
- [x] **"Product Direction" accepted into the product-intent vocabulary.**
      _(state: done 2026-08-08 ??? decided in the standard, not in this repo's
      file)_ `productIntentHeadingPattern` recognized `product intent`,
      `product scope`, `overview`, `about`, `purpose`, `background`, and
      `what this does/is`, but not **`Product Direction`** ??? the heading
      section 2 actually uses, and a plain synonym of the already-accepted
      `product intent` rather than a missing section. Renaming this repo's
      heading would have left the same false negative in place estate-wide for
      any repo using the synonym, so the vocabulary was widened in rule pack
      1.4 instead. `productIntentNote` now records that synonyms are added on
      evidence, not speculatively. Evidence: this repo's contract score
      **92 ??? 100** (`L4-Orchestration-Ready` both before and after) with
      ROADMAP-004 the only rule that changed state.
- [ ] **Record whether a repo externalizes its completion history.**
      _(state: planned)_ The contract carries `completedCount` as a required
      field, and a split roadmap reports ~0 forever. No rule reads it today,
      so nothing breaks ??? but nothing distinguishes "history archived to
      `docs/history/`" from "history deleted", and any future consumer that
      treats `completedCount` as progress would read a well-kept split repo as
      inert. Add an explicit signal (e.g. `historyLocation` / `archiveRef`)
      to [`roadmap-contract.schema.json`](standards/roadmap/roadmap-contract.schema.json),
      set from a pointer link in the roadmap, and surface it in the audit
      payload.
- [ ] **Sanction the external-archive pattern in the standard.** _(state:
      planned ??? documentation)_ `ROADMAP_TEMPLATE.md` Section 6 anticipates
      release sections being "archived or removed" but assumes the surviving
      history stays **in** the roadmap; no part of the standard, schema, or
      the 12 audit rules mentions an external archive file. Document it as a
      supported option with a required pointer convention, so a split repo is
      self-describing rather than merely unpenalized.

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

<!-- Release 2.7 Phase A ??? live submit-PR evidence.
     This note was written, committed, pushed, and opened as a pull request by
     POST /api/roadmap/repair/submit-pr (createPr=true) at 2026-08-09 12:27:36 UTC.
     Its existence in a PR IS the Phase A artifact: it proves the write path
     runs end to end against a real repo, not just the dry-run plan. -->