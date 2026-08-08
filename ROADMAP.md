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

**Last updated:** 2026-08-07

Releases 0.4 through 2.6 and Release 2.8 are **engineering-complete and
archived**. Their full text moved to
[`docs/history/completed-releases.md`](docs/history/completed-releases.md)
on 2026-08-07; this file now carries open work only.

What remains falls into five kinds of work, and they are **not**
interchangeable — mixing them is what previously made the roadmap read as
"everything is done" while real gaps sat unlabelled:

1. **Correctness regressions** — something shipped and then broke. One is
   open and is the highest-priority item in this file (the tracked
   `settings.json` now points every scan at a smoke fixture directory).
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

- [ ] **Lane 0.1 — restore `backend/config/settings.json`.** Highest impact,
      smallest change. Blocks nothing formally but corrupts every scan until
      fixed.
- [ ] **Lane 0.2 — confirm GitHub write credentials.** Gate for Release 2.7
      Phase A, which is in turn the gate for Phase C — the largest remaining
      product increment.
- [ ] **Release 2.7 Phase D** — schedulable immediately, needs nothing from
      anyone, and its freeze-prevention item is production-reliability work.
- [ ] **Lane 0.3 / 0.4 hygiene + smoke gaps** — cheap, and they stop the next
      regression of the class that produced Lane 0.1.

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
- [x] Add `GET /api/portfolio/assessment` route. *(state: smoke-tested)*
```

**Checkbox rule (added 2026-08-07).** `[x]` means *nothing remains for that
item in this roadmap*. An item whose engineering is complete but whose proof
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
| **2.7**   | **Guarded Scheduled Automation (Curated-Subset, Preview-First)**         | **active** — Phase B done; **Phases A, C, D open**                                         |
| 2.8       | Local Claude Code Execution (queue + operator runner)                    | `done` (engineering) — 2026-07-15; real `claude` run tracked in 2.9                        |
| **2.9**   | **Operator Field Proof and Mobile Completion**                           | `planned` — collects every external-resource residual plus the two unbuilt mobile surfaces |

> **Note on `.5` numbering.** Release 1.7.5 was a deliberate course-correction
> release between 1.7 and 1.8. Reserve the `.5` pattern for similar course
> corrections; default new work to integer minor releases.

### Execution Order and Dependencies

Release numbers identify scope — they do not dictate sequence. Work through
open items in the order below, and update this section whenever a lane
closes or a new dependency appears.

**Step 0 — unblockers and correctness (small, do first):**

1. **Restore the tracked `settings.json` scan roots** (Lane 0.1). A
   correctness regression, not a feature. Everything downstream that reads
   the portfolio is wrong until this lands.
2. **Confirm GitHub write credentials** (Lane 0.2). Opens Release 2.7
   Phase A, which opens Phase C.
3. **Close the two smoke gaps** (Lane 0.4) so the routes shipped since
   2026-07-05 are covered by the same tripwire as everything else.

**Then two parallel lanes (no cross-dependency between them):**

- **Automation lane — Release 2.7 Phases A → C.** The largest remaining
  product increment: scheduled roadmap-item packaging. Strictly sequential
  behind credentials, because auto-ranking without a proven write path
  produces packets nobody can act on.
- **Reliability lane — Release 2.7 Phase D.** Zero prerequisites. Frontend
  unit tests, `Dashboard.tsx` decomposition, scheduler failure alerting, and
  freeze prevention are all schedulable immediately and independently.

**After the lanes:**

1. **Release 2.9 mobile completion** (touch ergonomics beyond the Phase 1
   surfaces, tap-through agent-run list) — engineering work, no gates.
2. **Release 2.9 field proof** — batch the elevated/hardware/human checks
   into as few sessions as possible; several share a setup (an elevated
   shell covers the watchdog *and* the service installer; a phone session
   covers 2.5 *and* 2.6).
3. **Release 2.9 trend accrual** — closes itself as calendar time passes;
   requires only that capture keeps running.

**Dependency map (open work only):**

| Open item                                            | Depends on                                           | Type                                          |
| ---------------------------------------------------- | ---------------------------------------------------- | --------------------------------------------- |
| Lane 0.1 settings.json restore                       | —                                                    | none — do first; corrupts scans until fixed   |
| Release 2.7 Phase A (live submit-PR proof)           | Valid GitHub write credentials (Lane 0.2)            | hard — external credential                    |
| Release 2.7 Phase C (scheduled roadmap packaging)    | Release 2.7 Phase A                                  | hard — no auto-rank/PR without a proven write |
| Release 2.7 Phase D (all four items)                 | —                                                    | none — schedulable anytime                    |
| Release 2.7 Phase D freeze prevention                | Watchdog field proof (2.9) for the paired safety net | soft — ship prevention regardless             |
| Lane 0.3 layout follow-ups; Lane 0.4 smoke gaps      | —                                                    | none — schedulable anytime                    |
| Release 2.9 mobile completion (ergonomics, run list) | —                                                    | none — the responsive foundation is shipped   |
| Release 2.9 physical-Android proof (2.5 + 2.6)       | An Android device on the LAN                         | hard — hardware                               |
| Release 2.9 watchdog + service-installer proof       | An elevated (SYSTEM) session                         | hard — privilege                              |
| Release 2.9 real `claude` run (2.8)                  | An authenticated operator Claude Code session        | hard — human                                  |
| Release 2.9 GitHub App installation-token exchange   | A registered GitHub App                              | hard — optional; PAT supersedes               |
| Release 2.9 trend accrual (2.3 Ph2)                  | Days of live capture                                 | hard, time-gated                              |

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

**Current focus:** Phase D first (it needs nothing from anyone and carries
the production-reliability work), while Lane 0.2 resolves the credential
gate that opens Phase A → Phase C.

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

**Prerequisites:** Phase A needs valid GitHub write credentials (Lane 0.2).
Phase C needs Phase A. Phase D needs nothing.

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

- [ ] Prove a live submit-PR round trip on one write-enabled repo: branch
      push, PR creation, PR visible in the target repo, run recorded.
      Closes the Release 2.4 residual and opens Phase C.
      *(state: planned — the dry-run plan path is smoke-tested; only the
      live round trip is missing. Explicit operator-authorized action.)*

Phase C — Scheduled roadmap-item packaging (the prize; gated on Phase A):

- [ ] For each favorite repo with a ready L3+ roadmap, select the top-value
      pending item using the settled scoring semantics (MAX within a
      dimension + `effortFit` floor), build a task packet + repair-PR plan,
      and queue it for approval. *(state: planned — blocked on Phase A)*
- [ ] Gate every packaged item through the quota/budget guard; skip and log
      when over budget. *(state: planned)*
- [ ] Notify per run; approval triggers dispatch (live PR once Phase A
      passes). No auto-merge. *(state: planned)*
- [ ] Smoke: a scheduled run ranks + packages one fixture repo's top item,
      honors the quota-refusal path, and dispatches only on explicit
      approval. *(state: planned)*

Phase D — Hardening & observability (parallelizable, autonomous, unblocked):

- [ ] **Freeze prevention (root cause), paired with the shipped watchdog.**
      Guarantee `/api/status` + assessment caching cannot regress off (a
      gutted cache caused the 2026-07-05 blocking-scan pile-up); add a
      per-request work timeout so one blocked native call — e.g. the SQLite
      bridge — cannot wedge the single-threaded accept loop; schedule
      `app.db` maintenance (VACUUM + snapshot retention; ~138 MB and
      growing). *(state: planned — highest-impact Phase D item; the
      watchdog is the net, this is the fix)*
- [ ] Complete the frontend unit-test set (vitest). `needsAttention` and
      `viewMeta` are covered
      ([`needsAttention.test.ts`](frontend/lib/needsAttention.test.ts),
      [`viewMeta.test.ts`](frontend/viewMeta.test.ts)); **value tiers** and
      the **automation scope selector** are not. *(state: planned —
      2 of 4 named units covered)*
- [ ] Decompose [`Dashboard.tsx`](frontend/components/Dashboard.tsx):
      extract the view-router/tab shell and the summary/mission sections.
      *(state: planned — 2,376 lines as of 2026-08-07)*
- [ ] Add scheduler failure alerting (webhook) + an automation-status
      surface in the dashboard, so a scheduled run that stops running is
      visible rather than silently absent. *(state: planned)*

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

- **Blocked:** Phase A on GitHub write credentials (see Lane 0.2); Phase C
  on Phase A.
- **Risk — auto-ranking on unproven writes.** Packaging top-value items
  before one live PR round trip has succeeded produces review queues that
  cannot be acted on. This is why the sequence is hard, not advisory.
- **Risk — the portal freezes under load.** Observed twice (2026-07-05,
  2026-07-11): process alive, port listening, not responding. The watchdog
  safety net is shipped but unproven at SYSTEM; the root-cause prevention
  work is still open in Phase D.
- **Risk — `app.db` growth.** ~138 MB in daily use with no scheduled
  VACUUM or snapshot retention.

**Dependencies:** `/api/scan/schedule` (1.2), repo curation states (2.3
Ph5), AI doc-improve preview/apply (1.9), the notification hub (1.1), the
quota/budget guard (2.0 Ph4), `roadmap-events.jsonl` (2.4), and valid
GitHub write credentials for Phase A onward.

**Known issues:**

- [ ] Tracked `backend/config/settings.json` points `inventory.localRoots`
      at a WSL smoke-fixture directory (Lane 0.1). Any scheduled automation
      run enumerates fixtures instead of the real portfolio until it is
      fixed — so **Lane 0.1 gates meaningful Phase D validation**, even
      though it is not a formal Phase D dependency.
- [ ] The `GITHUB_TOKEN` fine-grained PAT provisioned 2026-07-06 carried a
      ~30-day window and is presumed expired (Lane 0.2). `GET
      /api/auth/github/status` reporting `mode=pat` does **not** prove the
      token is still valid — it reports configuration, not liveness.

**Traceability:** Phase B shipped
[`Automation.DocRefinement.ps1`](backend/modules/automation/Automation.DocRefinement.ps1)
(`Select-AutomationDocTargets`, `Invoke-ScheduledDocRefinement`,
`New-AutomationDigestPayload`, `Write-AutomationRunRecord` /
`Get-AutomationRunHistory`), `POST /api/automation/run`, `GET
/api/automation/history`, and the `automation` block on `GET
/api/scan/schedule`, with module + api-host smoke coverage. Phase D's
shipped half is [`Watch-PortalHealth.ps1`](scripts/service/Watch-PortalHealth.ps1),
[`Install-PortalWatchdog.ps1`](scripts/service/Install-PortalWatchdog.ps1),
and the reworked
[`Install-RepoManagementService.ps1`](scripts/Install-RepoManagementService.ps1).
Verification runs through `scripts/Invoke-TestSuite.ps1` (`npm test`), mirrored
in [`.github/workflows/ci-smoke.yml`](.github/workflows/ci-smoke.yml); the
Phase D frontend units live beside
[`frontend/lib/needsAttention.test.ts`](frontend/lib/needsAttention.test.ts).
Operator-facing behavior is documented in
[`docs/reference/operator-guide.md`](docs/reference/operator-guide.md).

#### Phase plan (within this release)

| Phase                                | Scope                                                                                                   | Status                                                   | Completed  | Token usage | Work units |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ---------- | ----------- | ---------- |
| Phase A: Unblockers                  | Live submit-PR proof on one write-enabled repo                                                          | **planned — blocked on credentials (Lane 0.2)**          | —          | —           | —          |
| Phase B: Scheduled doc refinement    | Scheduler + favorite-scoped doc-improve previews + digest + run history                                 | **done — smoke-tested** (2026-07-06) — see archive       | 2026-07-06 | —           | —          |
| Phase C: Scheduled roadmap packaging | Top-value item packaging + quota guard + approve-to-dispatch                                            | **planned — blocked on Phase A**                         | —          | —           | —          |
| Phase D: Hardening & observability   | Frontend unit tests, Dashboard decomposition, failure alerting, freeze prevention, auth operator-verify | **planned — 2 of 6 items shipped; 4 open, none blocked** | —          | —           | —          |

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
one phone session on the LAN covers both device milestones. Batch them rather
than scheduling six separate sessions.

#### Product outcomes

- No milestone is marked complete on the strength of an automated suite alone
  when what it claims needs hardware, elevation, credentials, or a human.
- The always-on portal is proven to recover from a real freeze, not a
  simulated one.
- The dashboard is proven usable on a real Android phone — touch, install,
  and all four target workflows — not only at an emulated 390px viewport.
- Trend charts show real 7- and 90-day windows.
- `evidence/` carries a durable record for each proof, so the next agent can
  read the evidence instead of re-litigating whether something works.

#### Engineering milestones

Mobile completion (no gates — build these first):

- [ ] Apply touch ergonomics beyond the Release 2.5 Phase 1 surfaces:
      minimum ~44px touch targets and a tap equivalent for every hover-only
      affordance (tooltips, row actions, rationale popovers) across the
      Phases 2-3 surfaces. *(state: scaffolded — Phase 1 surfaces done
      2026-07-04 (bottom nav 56px, card actions 44px); the rest was
      deferred and never built)*
- [ ] Add the tap-through mobile agent-run list from the agent-activity
      indicator: status, repo, phase, elapsed time. *(state: planned — the
      indicator ships and `/api/agent-runs` data is already reachable; only
      the mobile list view is missing)*

Field proof — elevated (SYSTEM) session, batch together:

- [ ] Run the elevated
      [`Install-PortalWatchdog.ps1`](scripts/service/Install-PortalWatchdog.ps1)
      and confirm a real freeze-and-recover: kill + `Restart-Service
      RepoMgmtPortal`, with the action appended to
      `output/logs/service-watchdog.jsonl` and the `execution.failed`
      webhook fired. *(state: smoke-tested → needs `operator-verified`; the
      decision logic and a dry-run against the actual frozen host, PID 5704,
      are already proven)*
- [ ] Operator-verify the reworked
      [`Install-RepoManagementService.ps1`](scripts/Install-RepoManagementService.ps1):
      elevated install / repair / `icacls` / scheduled-task registration,
      and confirm secrets resolve from machine env vars with the tracked
      `settings.json` staying secret-free. *(state: smoke-tested → needs
      `operator-verified`; pure logic is covered by module smoke)*

Field proof — physical Android device on the LAN, batch together:

- [ ] Verify the four Release 2.5 workflows on a **physical Android phone**:
      repo health, agent activity, prompt refinement, roadmap dispatch —
      plus real touch input and on-device home-screen install. Steps in
      [`lan-mobile-setup.md`](docs/reference/lan-mobile-setup.md).
      *(state: smoke-tested at an emulated 390px viewport → needs
      `operator-verified` on hardware)*
- [ ] Confirm the Release 2.6 clarity affordances pass on the same device:
      data-source indicator, per-tab subtitles, advanced-filters toggle, and
      the orientation overlay. *(state: smoke-tested → needs `operator-verified`)*

Field proof — human / credential / calendar:

- [ ] Operator-verify Release 2.1 against the live workspace and record the
      sign-off, closing the release formally. *(state: smoke-tested against
      live data — `output/app.db`, the real 68-repo `F:\Development` scan —
      → needs a recorded human sign-off)*
- [ ] Execute one real `claude` run through
      [`Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1)
      in the operator's authenticated session: claim → branch → run →
      verify → commit → `awaiting-review`. Closes the Release 2.8 residual.
      *(state: smoke-tested dry-run E2E → needs `operator-verified`)*
- [ ] Operator-verify the auth + shared-LAN path so automation runs on a bound,
      authenticated host. *(state: planned — carried over from 2.7 Phase D)*
- [ ] (Optional) Prove live GitHub App installation-token exchange
      (`Get-GitHubAppInstallationToken`) + auto-refresh on one registered
      app, closing the Release 2.2 residual. *(state: planned — not
      required; the PAT path supersedes it)*
- [ ] Let the Release 2.3 Phase 2 trend windows accrue: confirm
      `GET /api/portfolio/trend` reports a real 7-day, then 90-day, window.
      *(state: smoke-tested — rollup logic is live and
      `status=history-backed`; only calendar time is missing. Keep
      [`Invoke-DailyEvidence.ps1`](scripts/Invoke-DailyEvidence.ps1)
      running — it accrues history as a side effect.)*

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

## 7. Cross-Cutting Engineering Work

Continuous, not release-scoped. Completed cross-cutting items were archived
2026-08-07 — see
[the archive](docs/history/completed-releases.md#cross-cutting-engineering-work-completed-items).

### Lane 0.1 — Configuration regression (P0)

- [ ] **Restore `backend/config/settings.json` `inventory.localRoots` to the
      real workspace root and prevent recurrence.** *(state: planned —
      open regression)* Commit `69dcc2d` (2026-08-01) committed a smoke-run
      mutation into the **tracked** config: `localRoots` is now
      `/mnt/f/Development/GitHubRepoManagement/output/smoke/api-host/portfolio-fixture-repos`
      (a WSL fixture path), replacing `F:\Development\20_Staging`. Every
      scan, assessment, index write, and scheduled automation run from a
      clean checkout therefore enumerates fixtures, not the portfolio.
      Fix in three parts: (1) restore the real root; (2) make the api-host
      smoke write its settings mutation to a temp copy, or restore
      byte-exact on exit as
      [`Invoke-DailyEvidence.ps1`](scripts/Invoke-DailyEvidence.ps1)
      already does; (3) add a pre-commit or test-suite tripwire that fails
      when the tracked `settings.json` names a path under `output/`.

### Lane 0.2 — Credential freshness

- [x] **Reissue GitHub write credentials — confirmed expired 2026-08-07.**
      *(state: done 2026-08-07)* The fine-grained PAT provisioned 2026-07-06
      carried a ~30-day window and expired; `gh api` returned
      `HTTP 401: Bad credentials`. Reissued 2026-08-07 and set as the
      **User**-scoped `GITHUB_TOKEN`. **Evidence:** `gh api user` returns
      `xfaith4`; `Github-Authentication-Token-Expiration: 2026-11-06
      03:41:59 UTC`. Two follow-ups below.
- [ ] **Grant the PAT `Checks: Read`.** *(state: planned — non-blocker)*
      The reissued token still 403s on
      `repos/{owner}/{repo}/commits/{ref}/check-runs`
      (`Resource not accessible by personal access token`), so
      `gh pr checks <n> --watch` is unusable and the merge loop relies on
      `mergeStateStatus` as a proxy. Metadata, Contents, Pull requests, and
      Actions reads all pass. Verified 2026-08-07.
- [ ] **Give the always-on service a readable token.** *(state: planned —
      blocks Release 2.7 Phase A)* `RepoMgmtPortal` runs as **LocalSystem**,
      which cannot see the User-scoped `GITHUB_TOKEN`; the ImagePath passes
      no `-GitHubToken` and Machine scope is unset, so the portal's GitHub
      calls run unauthenticated. Fix:
      `.\scripts\Install-RepoManagementService.ps1 -Action Repair
      -GitHubToken $env:GITHUB_TOKEN` (sets Machine scope, restarts).
      Confirm afterwards with `GET /api/auth/github/status?validate=1` →
      `tokenEnvScope=Machine`, `liveCheck.valid=true`. Verified unset
      2026-08-07.
- [x] **Add a live token-validation probe.** `GET /api/auth/github/status`
      reported the configured *mode* (`mode=pat`), not token liveness — it
      reported healthy throughout the expiry above. *(state: done
      2026-08-07)* The route now accepts `?validate=1`, which probes an
      authenticated `GET /user` and returns `liveCheck.{valid, login,
      expiresAt}`; Settings surfaces it behind a **Test connection** button.
      The same route also reports `tokenSource`, `tokenEnvScope`, and
      `runningAsService` so an unreadable variable is distinguishable from an
      unset one. **Evidence:** `scripts/Invoke-ApiHostSmokeTest.ps1` step
      *"GitHub auth — env-var-name indirection"* asserts the probe fields and
      the 400 rejections; run 2026-08-07 exit 0, summary
      `githubAuthProbeOk=True githubTokenSource=env`.
- [x] **Remove the last stored-secret path: `readme.copilotApiKey`.**
      *(state: done 2026-08-07)* `Readme.Generator.ps1` `_ResolveApiKey`
      accepted a literal Copilot key stored in `settings.json` (priority 1)
      ahead of the `readme.copilotApiKeyEnvVar` name — the same leak shape
      the `secrets.githubToken` removal closed. The literal path is gone;
      resolution starts at the env-var name. The startup stripper is now
      `Remove-StoredSecretsFromSettings` and clears **both** legacy slots.
      **Evidence:** module smoke exit 0; API-host smoke exit 0 with
      `githubAuthProbeOk=True`; `grep copilotApiKey` shows no remaining read
      of the literal key.

### Lane 0.3 — Layout follow-ups from the 2026-07-15 cleanup

- [ ] Normalize hardcoded `G:\Development\GitHubRepoManagement`
      `-WorkspaceRoot` defaults to `$PSScriptRoot`-derived paths so the
      suite runs unmodified from any clone location. *(state: in progress —
      confirmed 2026-08-07 still present in `backend/adapters/Adapters.ps1`,
      `backend/api-host/Start-RepoManagementApiHost.ps1`,
      `backend/modules/docreview/Invoke-DocReviewInventory.ps1`, and both
      reconcile modules — a wider blast radius than the original note
      recorded)* **Partly closed 2026-08-08:**
      [`scripts/Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1)
      now defaults to `(Split-Path -Parent $PSScriptRoot)`. This one mattered
      more than the note implied: the required pre-commit gate failed on its
      first step for anyone invoking it without `-WorkspaceRoot`, which is
      exactly how `CLAUDE.md` documents running it. **Evidence:** gate re-run
      with no arguments, exit 0. The five files above are still open.
- [ ] Implement the documented maturity **caps** that the auditor still does
      not apply: `ROADMAP_MATURITY_MODEL.md` states "any critical finding caps
      maturity at L1" and "any warning finding caps maturity at L3", but
      `Invoke-AuditRoadmapContract` only does weighted-score arithmetic. The
      >1-active-release cap was implemented 2026-08-07; these two remain
      doc-only. *(state: planned — pre-existing doc↔code drift, surfaced while
      fixing the rules v1.1 regression)*
- [ ] Repair `CLAUDE.md`'s dangling `@_base.md` and
      `@.claude/modes/implementer.md` imports — neither file exists. The
      mode line is managed by `ccmode.ps1`, so fix at the tool level.
      *(state: planned — confirmed still broken 2026-08-07)*
- [ ] Tune `tools/Test-RoadmapStructure.ps1` for the template's own layout:
      `ROADMAP_TEMPLATE.md` puts the full execution contract inside the
      `## Release X — Title` block, so R013's 120-line cap fires on any
      conformant active release, and RQ001 wants a `Status` line on the
      "Active release detail" pointer that must not restate it (declaring it
      twice is an RQ003 error). Exempt the active release from R013 and let
      the pointer block be status-free. *(state: planned — 3 advisory
      warnings today, 0 errors; surfaced 2026-08-07 when this repo was made
      conformant with its own standard)*

**Shipped 2026-08-07 (from this lane):** a standards↔spec drift tripwire and an
"every shipped audit rule is implemented by the auditor" tripwire, both in
`scripts/Invoke-ModuleSmokeTest.ps1`. The second closes the `d2cc6cc` /
`c6662cf` regression class — a rule added to the pack but never evaluated
still contributes its `scoreWeight` to the denominator, silently inflating
every maturity score. Both were adversarially proven to fail when violated.

### Lane 0.4 — Smoke coverage gaps

- [ ] Add a scoped-path assertion for the repo-scoped roadmap scan
      (`POST /api/roadmap/scan` with a `repoName`/`targetRepo` body) to the
      api-host smoke. The global-scope path is already asserted; the scoped
      branch and the RepoGrid per-row action are `ui-connected` only.
      *(state: ui-connected → needs `smoke-tested`)*
- [ ] Add an api-host smoke assertion for
      `POST /api/repository-improvement/preview` (the Guided Repository
      Improvement Workflow shipped 2026-08-01). It is the only API route
      added since 2026-07-05 with no coverage, which also means the
      route-census tripwire does not protect it. *(state: planned)*
- [ ] Archive the root worklogs `findings.md`, `progress.md`, and
      `task_plan.md` to [`docs/history/worklogs/`](docs/history/worklogs/),
      matching the 2026-07-15 cleanup convention they were re-created
      against. *(state: planned — cosmetic, but the root keeps re-accruing
      these; consider a `.gitignore` entry or a documented worklog location
      so the convention holds without a manual sweep each time.)*

### Lane 0.5 — Portal UX follow-ups (empty-state audit 2026-08-08)

Surfaced by a walkthrough of the Repository Grid, Insights, Operations, and
Doc Readiness Queue tabs against a workspace that scanned 0 repos. The two
data-integrity findings from that audit were fixed the same day (see
evidence below); these two are design-dependent and deliberately deferred.

- [x] **Reconcile the live-scan vs. persisted-index contradiction.**
      *(state: done 2026-08-08)* The header read the live scan (`repos`)
      while the Queue buckets, "68% Avg Maturity", and "15 Ready Repos" read
      the persisted indexes in `output/index/`, so a 0-repo scan rendered
      populated figures beside a `0 repos` count and read as a broken tool.
      Both figures were always real; only the provenance was missing. Added
      [`frontend/lib/dataProvenance.ts`](frontend/lib/dataProvenance.ts)
      (`resolveProvenance` → `live` / `stale-only` / `empty`) plus
      [`ProvenanceNotice.tsx`](frontend/components/ProvenanceNotice.tsx),
      mounted above the Portfolio Analytics KPI row and the Doc Readiness
      Queue; the scan label now reads "No repos in this scan". **Evidence:**
      `frontend/lib/dataProvenance.test.ts` (17 cases, incl. the
      unknown-live-count guard against a false banner); `npx vitest run`
      30/30; `tsc --noEmit` clean; module smoke exit 0.
- [x] **Disable repo-acting buttons when nothing is in scope.**
      *(state: done 2026-08-08)* Pull, Fetch, Report, Doc Review, and Roadmap
      Scan stayed clickable at 0 repos, letting the operator click into a
      no-op instead of being pointed at the blocker. `ActionBar` now takes a
      `repoCount` prop and gates those five on
      `canRunRepoActions(repoCount, isActionRunning)`, replacing the
      implicit-bulk-scope callout with the actual blocker ("Scan a workspace
      first…"). Refresh, Settings, Help, and API docs stay enabled — they are
      the way out of the empty state. **Evidence:** as above;
      `scripts/frontend-smoke.cjs` `bulkSelectionNotePromoted` made
      state-aware so it asserts the correct variant rather than breaking on
      the empty-workspace path.
- [ ] **Add a confirmation step to implicit bulk-scope actions.** *(state:
      planned — non-blocker)* With no rows selected, Pull/Fetch/Report apply
      to the **entire filtered set**. The amber callout in
      [`ActionBar.tsx`](frontend/components/ActionBar.tsx) is honest about
      this and now names the count, but a banner alone still lets one click
      run a bulk git operation across the whole portfolio. Gate the
      no-selection path behind a `window.confirm`-style step naming the
      count ("This will run on 47 repositories — continue?"), matching the
      pattern `handleArchive` already uses. Deferred because the right
      threshold (always, or only above N repos) is a product call, and
      because `Report` is read-only and may not warrant the same friction.
- [ ] **Progressive disclosure for the six-tab dashboard.** *(state: planned
      — non-blocker, design-dependent)* Grid, Insights, Operations, Doc
      Readiness Queue, Copilot Execution Lanes, and Dependencies each render
      a dense multi-widget surface, which is heavy for the primary daily
      workflow (triage the repos needing attention). Candidate direction: a
      simplified default view with drill-down, or a collapsible "advanced
      analytics" section, extending the inline-tooltip pattern already used
      on **Needs Attention**. Deferred because it changes primary navigation
      shape and should not be done incrementally.

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
