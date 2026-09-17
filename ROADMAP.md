# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 2.9 — Operator Field Proof + Mobile Completion**
> **Next active release:** **Release 3.7 — Portfolio Value Proof**. Release 3.6 closed 2026-09-14 (archived; its field proof is OQ-1 in the operator queue). 3.7's cohort is selected and concluded; its agent-closable items lead Current focus, and the measured trial waits on OQ-3.
> **Work ordering:** dependency-driven, not insertion order — see
> [Execution Order and Dependencies](#execution-order-and-dependencies)
> **Canonical product direction:** [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
> **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
> **Dated change log:** [`CHANGELOG.md`](CHANGELOG.md)

---

## Current Status (Agent Context)

**Last updated:** 2026-09-17

Releases 0.4 through 2.6, 2.8, 3.0 and 3.8 are **engineering-complete and
archived**, as is every completed milestone from the releases and lanes still
open below. Their full text lives in
[`docs/history/completed-releases.md`](docs/history/completed-releases.md).

**This file carries open work only.** Every checkbox in it is something still
to do — if an item is `[x]` here it is a mistake, not a record (rule restored
by the 2026-08-11 archive pass, recorded in `CHANGELOG.md`).

**Current focus (next agent actions), in order.** Every item here is
agent-closable; the operator queue is a separate file. Take the first `[ ]`
that carries no `(depends: …)` list and open a PR. Every item uses the fields
defined in §3. The lead agent's runbook is
[`.claude/agents/roadmap-lead.md`](.claude/agents/roadmap-lead.md).

- [ ] [[L22-FIX]] **Lane 0.22 — test fixtures never reach live state.** _(state: built)_
      **Why:** 175 of 192 live agent-run records were the api-host smoke's
      `dispatch-success-smoke`, and 251 of 257 packaged items were
      `smoke-packaging-repo`. The smoke wrote the real agent-run ledger, the
      packaging queue, work packets, run summaries and `app.db`.
      **Built:** on `lane-022-fixture-isolation`, stacked on #309.
      `REPO_MGMT_OUTPUT_ROOT` moves all of `output\`, every host-starting
      gate sets it, and the named fixtures are hidden when the operator's own
      root is read. Every local gate passed, and a full api-host smoke run
      left the live ledgers unchanged.
      **Next:** when #309 merges, rebase onto `origin/main`, open the PR, and
      archive this item once its check is green in CI on the PR head.
      **PR:** review — it wires a suite gate; it waits for a free slot.
      `check: pwsh ./tests/Test-FixtureIsolation.ps1 -FailOnError`
- [ ] [[L22-ELIG]] **Lane 0.22 — one dispatch-eligibility rule, enforced everywhere.** _(state: planned)_
      **Why:** the Dispatch Board read "Ready" for repositories that Today
      holds for uncommitted changes, for a curated-out archived repository,
      for one whose own detail reads "blocked", and for folders not in the
      index.
      **Do:** one server-side function answers `{ ok, reasons[] }` per
      repository from the index, curation, dispatch blockers and the hold
      conditions Today uses (computed client-side today, in
      `frontend/lib/repoHolds.ts`). The board lists only eligible items and
      collapses the rest into "N held (why)". Every Dispatch control is
      disabled with its reason when `ok` is false.
      **Done when:** each of the four cases above answers `ok: false` with a
      named reason; an eligible fixture answers `ok: true`; the board and the
      repository detail read the same answer.
      **Start at:** `backend/modules/execution/Execution.Ledger.ps1`
      (`dispatchReadiness`, `Get-ExecutionQueueSummary`),
      `backend/modules/portfolio/Portfolio.Curation.ps1`,
      `frontend/lib/repoHolds.ts`, `frontend/components/ExecutionQueuePanel.tsx`,
      `frontend/components/OperationsWorkspaceView.tsx` (Dispatch Readiness,
      Dispatch Blockers).
      **Not:** a second copy of the rule in the frontend; it renders
      `reasons[]`.
      **Split:** scout — every place that computes or shows readiness, holds
      or blockers; lead — the rule and its test; builder — repoint each
      consumer at the rule.
      **PR:** review — a suite gate, and it changes what a verdict says.
      `check: pwsh ./tests/Test-DispatchEligibility.ps1 -FailOnError`
- [ ] [[D012-ENV]] **D-012 — the permission envelope binds.** _(state: planned)_
      **Do:** after every adapter run and before push, diff the branch
      against its base. A path matching the packet's `forbiddenPaths`
      (`.github/workflows/**`) fails the packet by name, and the branch is
      not pushed. An agent that needs CI changed writes the proposal to
      `.github/workflows-proposed/`, and the run names it as waiting. A
      packet that needs the network declares an allowlist the owner
      approves; `network: false` is never loosened without it.
      **Done when:** a fixture run that touches `.github/workflows/ci.yml`
      fails by name and is not pushed; the same change under
      `.github/workflows-proposed/` passes and is reported as waiting; a
      packet without an allowlist cannot turn the network on.
      **Start at:** `scripts/Invoke-RoadmapTaskRunner.ps1`
      (`Resolve-PostImplementationTransition`, `Invoke-RunnerBranchPush`),
      `backend/modules/execution/Execution.WorkPacket.ps1` (`forbiddenPaths`),
      `backend/modules/agent-adapters/`, `backend/config/agent-providers.json`.
      **Not:** relying on a provider's own sandbox. It is a second layer,
      never the only one.
      **Split:** scout — every push path and every adapter's permission
      flags; lead — the diff check and its test.
      **PR:** review — a suite gate, config and agent permissions.
      `check: pwsh ./tests/Test-PermissionEnvelope.ps1 -FailOnError`
- [ ] [[T37-LEDGER]] **Accept/reject ledger (steering extension 1, Rung 1).** _(state: planned)_
      **Why:** every next action and top value item is a prediction, and no
      response to one is recorded. The leverage panel therefore shows "not
      captured", and the D-013 weights have no evidence to be revisited
      against.
      **Do:** an append-only ledger under the output root
      (`Resolve-OutputPath`). Each accept, reject or edit is stored with the
      prediction it answers and the index SHA and `modelVersion` that
      prediction was drawn under. The leverage panel computes its "not
      captured" figure from the ledger.
      **Done when:** a recorded response reads back with all three keys; a
      response to an unknown prediction is refused by name; the leverage
      payload reports the metric as available once one response exists.
      **Start at:** `backend/modules/portfolio/Portfolio.Leverage.ps1`
      (`Get-PortfolioLeverage`, its `available = $false` metrics),
      `backend/modules/portfolio/Portfolio.Conclusion.ps1`
      (`Get-PortfolioConclusionsPayload`, `_PC_NextActionFor`),
      `backend/modules/common/Config.OutputRoot.ps1`.
      **Split:** scout — every surface that shows a next action or a top
      value item; lead — the ledger, its route and its test.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-DecisionLedger.ps1 -FailOnError`
- [ ] [[T37-PREV]] **3.7 / M5 prep — previews staged, not applied.** (depends: T37-LEDGER) _(state: planned)_
      **Do:** for each `strengthen` repository in the cohort, generate the
      preview its next action produces and stage it under the gitignored
      `output/trials/release-3.7/previews/`. The tracked record in
      `evidence/trials/release-3.7/` holds only the action, route, preview
      hash and state, never repository text, because this repository is
      public. An AI-routed preview is staged as a confirmation request that
      names the provider and the file; the agent sends nothing. Responses
      land in the `T37-LEDGER` ledger.
      **Done when:** every `strengthen` repository in `cohort.json` has a
      staged preview or a named reason for having none; no tracked file
      holds repository text; no AI route was called.
      **Start at:** `evidence/trials/release-3.7/cohort.json` and its
      `README.md`, `backend/config/foundation-domains.json`
      (`actionsByCase`, the preview each kind of gap routes to).
      **Not:** waiting for OQ-12. If the live index predates it, stage
      against the current index, record its `modelVersion`, and restage
      once OQ-12 is logged.
      **Split:** scout — the `strengthen` repositories and their next-action
      routes from `cohort.json`; lead — staging, the record and the
      no-repository-text guard.
      **PR:** review — a suite gate and trial evidence.
      `check: pwsh ./tests/Test-TrialPreviews.ps1 -Cohort evidence/trials/release-3.7/cohort.json -RequireAll -FailOnError`
- [ ] [[T37-BRIEF]] **Portfolio brief and conclusion diff (steering extension 5, Rung 1).** _(state: planned)_
      **Do:** diff two conclusion payloads by index SHA and render the
      movement as prose with the evidence chain under every claim: one
      exported file that a reader who has never seen the product can act
      on. Deterministic; any narration is limited to the evidence lines and
      marked as narration.
      **Done when:** two fixture payloads produce the same brief on every
      run; every claim cites the evidence line it rests on; an unchanged pair
      produces a brief that says nothing moved.
      **Start at:** `backend/modules/portfolio/Portfolio.Conclusion.ps1`
      (`Get-PortfolioConclusionsPayload`; each conclusion carries
      `modelVersion` and the index SHA).
      **Split:** lead alone; a scout may collect two real payloads to model
      the fixtures on.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-PortfolioBrief.ps1 -FailOnError`
- [ ] [[MANIFEST]] **One manifest walk (steering extension 4).** _(state: planned)_
      **Why:** repository type, the technology profile and kind signals are
      separate walkers over the same files, so they can drift, and a
      checkout is read more than once.
      **Do:** one scan produces all three views.
      **Done when:** a fixture repository is read once, and all three views
      match what today's walkers produce for it.
      **Start at:** `backend/modules/portfolio/Portfolio.Assessment.ps1`
      (`_DetectRepoTypeForStructure`, `Get-RepoTechnologyProfile`),
      `backend/modules/roadmap/Roadmap.Evaluator.ps1` (`_DetectRepoType`, a
      second type detector), `backend/modules/portfolio/Portfolio.KindSignals.ps1`
      (`Get-RepoKindSignalProfile`).
      **Not:** changing any view's output. This is a refactor with a parity
      test.
      **Split:** scout — every caller of the four functions; lead — the
      walker and the parity test.
      **PR:** review — a suite gate, and every kind verdict reads it.
      `check: pwsh ./tests/Test-ManifestWalk.ps1 -FailOnError`
- [ ] [[D001-DEPS]] **D-001 — dependencies gate eligibility everywhere.** (depends: L22-ELIG) _(state: planned)_
      **Already built** (Lane 0.18, archived): the `[[id]]` and
      `(depends: …)` notation, the unknown-id and cycle findings
      (ROADMAP-013/014), `Get-NextEligibleRoadmapItem`, and the execution
      contract's `dependencies` check. Confirm all of that before writing
      code.
      **Do:** add `dependsOn` to the item definition in
      `standards/roadmap/roadmap-contract.schema.json` and its
      `spec/roadmap-contract/` copy (the sync gate covers both). Make an
      incomplete dependency one of `L22-ELIG`'s `reasons[]`, so ranking,
      packaging and the board all skip a blocked item.
      **Done when:** a fixture roadmap with `[[A]]` open and
      `[[B]] (depends: A)` never ranks, packages or offers B; a roadmap
      without the notation ranks exactly as before; the schema accepts an
      item that carries `dependsOn`.
      **Start at:** `backend/modules/roadmap/Roadmap.Dependencies.ps1`,
      `backend/modules/roadmap/Roadmap.ExecutionContract.ps1`,
      `backend/modules/portfolio/Portfolio.ValueScorer.ps1`,
      `backend/modules/automation/Automation.RoadmapPackaging.ps1`
      (`Get-PackagedItemQueue`).
      **PR:** review — a suite gate and the managed-roadmap contract.
      `check: pwsh ./tests/Test-RoadmapDependencies.ps1 -FailOnError`
- [ ] [[L21-POLL]] **Lane 0.21 — polls never pile up behind a slow host.** _(state: planned)_
      **Why:** `/api/agent-runs` returned the same 147 KB seven times in one
      load.
      **Do:** one poll helper. The next poll starts only when the previous
      one settles (a `setTimeout` chain, not `setInterval`); each call has an
      `AbortController` timeout; the interval backs off while calls are slow;
      polling pauses while `document.hidden`. `/api/agent-runs` answers with
      an ETag or a `since=` cursor.
      **Done when:** every poll site uses the helper, and the test finds the
      sites itself rather than listing them; a slow fake host never has two
      calls in flight; a hidden document makes no calls.
      **Start at:** `frontend/components/Dashboard.tsx` (its poll timers and
      the `getPortfolioScanStatus` loop), `frontend/services/apiClient.ts`
      (existing `AbortController` use).
      **Split:** scout — list every `setInterval` and polling `setTimeout` in
      `frontend/`; lead — the helper and its test; builder — move each site
      onto the helper.
      **PR:** engineering; the `since=` cursor is a small API change inside
      the same PR.
      `check: npx vitest run frontend/lib/pollLoop.test.ts`
- [ ] [[L21-SCANDONE]] **Lane 0.21 — a finished scan reaches the page.** _(state: planned)_
      **Why:** the scan ended at 05:17:15 and the snapshot regenerated at
      05:19:05, but the header still read "Last scan 01:09 AM · 64.0s scan ·
      9m ago".
      **Do:** when scan status moves to `completed`, the page refetches the
      snapshot, the assessment and status. A failed background refresh
      retries at that point instead of logging the same warning twice. A
      host with no index answers `GET /api/operations/repos` with 409 until
      the first scan lands; the page shows that as waiting for the first scan
      and refetches when the scan finishes.
      **Done when:** a `completed` status triggers exactly one refetch of each
      of the three; a 409 renders the waiting state, not an error.
      **Start at:** `frontend/components/Dashboard.tsx` (the
      `getPortfolioScanStatus` poll, which today refreshes only operations
      repos), `frontend/components/PortfolioSummarySection.tsx` ("Last
      scan").
      **PR:** engineering.
      `check: npx vitest run frontend/lib/scanCompletionRefresh.test.ts`
- [ ] [[L21-AUTOSCAN]] **Lane 0.21 — "Auto-scan off" means no scan on load.** _(state: planned)_
      **Why:** the page showed Auto-scan off and started a background
      re-scan on load anyway.
      **Do:** with auto-scan off, the page serves the cached index and offers
      the scan. With it on, the startup re-scan is labelled as one.
      **Done when:** the startup policy starts no scan when auto-scan is off
      and starts a labelled one when it is on.
      **Start at:** `frontend/components/Dashboard.tsx` (`scanSchedule.enabled`,
      `startPortfolioScan`). Since #309 the assessment route can also start
      the worker (`scanRequested` in its payload); find out which of the two
      is the load-time scan before changing either.
      **Split:** lead alone: one policy function and its test.
      **PR:** engineering, unless the fix lands in the host.
      `check: npx vitest run frontend/lib/startupRefreshPolicy.test.ts`
- [ ] [[L21-LAZY]] **Lane 0.21 — hidden tabs cost nothing at startup.** _(state: planned)_
      **Why:** sixteen calls fire in parallel on load, including
      `operations/repos` (548 KB), `automation/packages` (374 KB) and
      `roadmap/index` (56 KB) for tabs that are not open.
      **Do:** those three load when their tab opens. Startup marks each phase
      (auth, bootstrap, snapshot, scan start and end) with
      `performance.mark` and writes one `console.debug` line, so a slow
      reload explains itself.
      **Done when:** a startup on Today makes none of the three calls;
      opening each tab makes its call once; the phase marks appear in order.
      **Start at:** `frontend/components/Dashboard.tsx` (the startup effects
      that call `getOperationsRepos` and `getRoadmapIndex`).
      **Split:** scout — every call fired on mount and the tab that uses its
      result; lead — the loading change and its test.
      **PR:** engineering.
      `check: npx vitest run frontend/lib/startupPhases.test.ts`
- [ ] [[L21-TIME]] **Lane 0.21 — every wire timestamp is ISO 8601 UTC.** _(state: planned)_
      **Why:** scan status returned `09/15/2026 05:13:42`, culture-formatted
      with no zone, and `generatedAt` in `repos.index.json` has the same
      shape. PowerShell 7 turns ISO strings into `DateTime` on read, and
      `[string]` then formats them in the machine's culture.
      **Do:** every writer emits `.ToUniversalTime().ToString('o')`. A
      tripwire reads the raw JSON of each route payload (never
      `ConvertFrom-Json` output, which hides the defect) and fails on any
      timestamp without a zone.
      **Done when:** the tripwire finds its own targets, fails on a planted
      culture-formatted value, and passes on the tree.
      **Start at:** `Get-PortfolioScanState` and the scan-status route in
      `backend/api-host/Start-RepoManagementApiHost.ps1`;
      `Save-PortfolioIndexArtifacts` in
      `backend/modules/portfolio/Portfolio.Assessment.ps1` (`generatedAt`);
      `tools/Test-PortfolioTimestamp.ps1`, the existing raw-wire checker.
      **Split:** scout — every serialized field whose name ends in `At`,
      `Time` or `Date`, with its writer; builder — convert each writer the
      lead confirms; lead — the tripwire.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-WireTimestamps.ps1 -FailOnError`
- [ ] [[L21-FIRST]] **Lane 0.21 — the first screen is honest and short.** _(state: planned)_
      **Why:** before the snapshot arrived, counts read "Sample data source"
      with zeros. Today's "Blocking a lane" ran the page to 23,641 px:
      Portfolio-Forge had four cards, and `roadmap-no-checklist` appeared
      nine times.
      **Do:** counts show placeholders until the snapshot arrives. "Blocking
      a lane" shows one card per repository with its reasons as tags. Below
      about 900 px, ranking rows move "Rank basis" into an expandable row,
      and header badges move into a menu instead of wrapping. Each tab's code
      loads on demand (`import()`), off the 858 KB first bundle.
      **Done when:** a repository with four holds renders one card with four
      tags; no zero renders before the snapshot; each tab is its own chunk in
      `npm run build`.
      **Start at:** `frontend/components/TodayView.tsx` ("Blocking a lane",
      `HoldCard`), `frontend/components/Dashboard.tsx` ("Sample data
      source"), `frontend/components/DashboardViewTabs.tsx` (`VIEW_META`).
      **PR:** engineering.
      `check: npx vitest run frontend/components/TodayView.test.tsx`
- [ ] [[L22-WORK]] **Lane 0.22 — only actionable roadmap lines become work.** _(state: planned)_
      **Why:** "Ready" candidates included "Code is implemented", "Monorepo
      structure created", "Work one bounded slice at a time.", a "(Deferred)
      … Not needed for v1" line and truncated fragments. One item completed
      and was re-assigned 17 seconds later.
      **Do:** before ranking, classify each candidate `actionable |
      done-statement | deferred | guidance | fragment`. Only `actionable` is
      ranked, queued or offered for dispatch, and each repository shows
      "Excluded (n)" with the reason for each line. A run that completes
      writes its item back as done, and the same item hash cannot be
      dispatched again inside a cooldown unless the operator overrides.
      **Done when:** each quoted example classifies as its kind; a completed
      item is not re-offered inside the cooldown; an override works and is
      recorded.
      **Start at:** `backend/modules/portfolio/Portfolio.ValueScorer.ps1`,
      `backend/modules/automation/Automation.RoadmapPackaging.ps1`,
      `backend/modules/roadmap/Roadmap.WriteBack.ps1`.
      **Not:** committing lines from other repositories as fixtures; this
      repository is public. Write synthetic fixtures modelled on the quoted
      examples.
      **PR:** review — a suite gate, and it changes which work the product
      offers.
      `check: pwsh ./tests/Test-WorkItemQuality.ps1 -FailOnError`
- [ ] [[L22-STUCK]] **Lane 0.22 — stuck work is detected, not noticed.** _(state: planned)_
      **Why:** the runner heartbeat was 27.6 h old (shown as "99293.3s"), a
      lane had run 1,655 minutes, and a run dispatched six days earlier had
      no branch and no PR. None of it reached Today.
      **Do:** each state has a limit. Stuck means: a runner heartbeat older
      than N minutes while approved work waits; a lane past its limit; a
      dispatch with no branch after 24 h; an approval that never reached the
      queue; a scan stuck in one phase. Each surfaces once, on Today, with
      its remedy (start runner, poll GitHub, re-enqueue or discard, cancel and
      requeue). Durations read "27h", never "99293.3s" or "1655m".
      **Done when:** each of the five fixtures is reported once with its
      remedy; a healthy fixture reports nothing; the three quoted durations
      render in hours.
      **Start at:** `backend/modules/execution/Execution.LaneObservation.ps1`
      (the D-007 patience thresholds), the `GET /api/roadmap/runner` route in
      `backend/api-host/Start-RepoManagementApiHost.ps1`.
      **Not:** failing, cancelling or completing anything automatically. A
      stuck verdict is a signal (D-007), and the operator still clicks to
      complete a lane (D-009); the card shows the merge verdict and the
      matching action. The assessment asked for completion on merge
      evidence, which would reverse D-009; that is the owner's call, so file
      it in `open-decisions.md` rather than build it.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-StuckWork.ps1 -FailOnError`
- [ ] [[L22-SNAP]] **Lane 0.22 — one snapshot, one denominator, honest zeros.** _(state: planned)_
      **Why:** one session read 0, 59, 72, 71 and 1 as the repository count.
      After a reload, Today said "No repositories are indexed yet" while
      Operations said "Indexed entries: 59", and the Operation Log said "Scan
      complete. No repositories found." and then "Operation completed
      successfully."
      **Do:** every count reads the same snapshot: generated-at, discovered,
      in scope, excluded, scanned and failed. A scan that finds 0
      repositories is a warning, never "completed successfully", and the
      last good snapshot stays on screen labelled with its time. An
      unmeasured value renders "—" with its reason, never 0. The Grid's
      empty state never asks for a workspace path that is already set.
      **Done when:** every count surface renders from one snapshot fixture
      and agrees; a zero-repository scan renders a warning and keeps the
      prior snapshot; an unmeasured field renders "—".
      **Start at:** `frontend/services/apiClient.ts` (`getPortfolioSnapshot`),
      `frontend/components/PortfolioSummarySection.tsx`,
      `frontend/lib/todayRanking.ts` ("No repositories are indexed yet"),
      `frontend/components/OperationsWorkspaceView.tsx` ("Indexed entries"),
      `frontend/components/Dashboard.tsx` ("No repositories found"),
      `frontend/components/LogPanel.tsx`.
      **Split:** scout — every rendered repository count and the field it
      reads; lead — the shared selector and its test; builder — repoint each
      surface.
      **PR:** engineering.
      `check: npx vitest run frontend/lib/portfolioSnapshot.test.ts`
- [ ] [[L22-CTRL]] **Lane 0.22 — a control does what its label says.** _(state: planned)_
      **Do:** a "Preview…" next action opens the preview, not the generic Run
      Evaluation modal. Header popovers close on Escape and outside click. A
      disabled control, including the Local/GitHub switch during a scan,
      says why. The "Runner stalled … Use Start runner" banner carries the
      button. Settings never shows "Checking…" or an empty provider list
      indefinitely: it times out into a stated error.
      **Done when:** each of the five behaviours has a component test.
      **Start at:** `frontend/components/Dashboard.tsx` (its `onRunAction`
      opens `RepoEvaluationModal`), `frontend/components/RunnerHealthIndicator.tsx`,
      `frontend/components/SettingsModal.tsx` ("Checking…"),
      `frontend/hooks/useDialogDismiss.ts` (Escape and outside click).
      **Split:** builder — wire the popovers to the existing hook; lead —
      the rest.
      **PR:** engineering.
      `check: npx vitest run frontend/components/HeaderPopovers.test.tsx`
- [ ] [[L22-LABEL]] **Lane 0.22 — labels match what they count.** _(state: planned)_
      **Do:** "N need you" counts repositories, not holds × codes (it read 63
      for 59 repositories). "Blocking a lane" appears only where work is
      under way and stopped. L0-Absent is never shown for a repository whose
      roadmap exists (one read L0-Absent, "No roadmap file present", while
      its roadmap scored 55). Help's "first pass" names tabs that exist.
      "Insufficiently understood" shows its cause in plain words, for example
      that the roadmap is prose, not a checklist.
      **Done when:** each of the five has a unit test on the function that
      produces the label.
      **Start at:** `frontend/lib/repoHolds.ts` (`describeHoldCount`),
      `frontend/components/TodayView.tsx`, `frontend/lib/glossary.ts`
      (L0-Absent), `frontend/components/OutcomeCard.tsx`,
      `frontend/components/HelpModal.tsx` ("first pass"),
      `frontend/lib/foundationConclusion.ts`.
      **Not:** hiding a wrong level in the UI. If the audit assigns L0-Absent
      to a repository whose roadmap exists, fix the audit; that part is a
      review PR.
      **PR:** engineering.
      `check: npx vitest run frontend/lib/glossary.test.ts`
- [ ] [[L22-TREND]] **Lane 0.22 — Insights reports a gap as a gap.** _(state: planned)_
      **Do:** a missing or failed snapshot breaks the trend line instead of
      plotting 0%, and a delta's colour follows its direction (a −32.3% badge
      rendered green). Raw keys (`DifferentialChangedCount`,
      `differential-noop`, `awaiting-first-scan`) move behind a "Scan
      diagnostics" disclosure. Release-number copy ("Release 2.3 scaffold")
      leaves the UI. "Failing Actions" agrees with repository detail. Team
      Activity is scoped to the owner or removed.
      **Done when:** a series with a gap renders a break; a negative delta
      renders in the negative colour; no raw key renders outside the
      disclosure.
      **Start at:** `frontend/lib/portfolioTrendView.ts`,
      `frontend/components/InsightsView.tsx` ("Release 2.3 scaffold"),
      `frontend/components/ChangeHistoryPanel.tsx` (Team Activity).
      **Split:** scout — every place a raw key or a release number renders;
      lead — the rest.
      **PR:** engineering.
      `check: npx vitest run frontend/lib/portfolioTrendView.test.ts`
- [ ] [[L22-DETAIL]] **Lane 0.22 — repository detail agrees with itself.** (depends: L22-ELIG) _(state: planned)_
      **Why:** README 95 sat next to "README file not found", and "blocked"
      sat above "Dispatch Blockers (0)".
      **Do:** each panel shows loading, unavailable or error, never a stale
      score beside "not found". Raw errors ("No operations repo record found
      for repoId …") become operator language with a Retry. Three conditions
      become flags: failing CI, a default branch pointing at an agent
      branch, and two local repositories on one remote.
      **Done when:** each panel's states render from fixtures, and neither
      quoted contradiction can render.
      **Start at:** `frontend/components/OperationsWorkspaceView.tsx` (README
      score, Dispatch Readiness, Dispatch Blockers); `duplicateIdentities`
      from `Group-RepoByRemoteIdentity`
      (`backend/modules/portfolio/Portfolio.Scope.ps1`) for the one-remote
      flag.
      **PR:** engineering.
      `check: npx vitest run frontend/components/OperationsWorkspaceView.test.tsx`
- [ ] [[L22-GRID]] **Lane 0.22 — nothing unfinished in production, and filters stay visible.** _(state: planned)_
      **Do:** remove the "Clone PLANNED" and "Archive PLANNED" controls.
      Active filters show as removable chips, and "Clear filters" also clears
      the ones under Advanced. A Doc Readiness row carries one primary action
      plus an overflow menu, not eight buttons. The Dependencies tab (a
      technology inventory, which developers read as package dependencies)
      is renamed or folded into repository detail.
      **Done when:** no rendered control carries a planned marker; each
      active filter renders a chip; "Clear filters" empties the Advanced set;
      a Doc Readiness row has one primary button.
      **Start at:** `frontend/components/ActionBar.tsx` (the planned
      controls), `frontend/components/RepoGrid.tsx` ("Clear filters", the
      Advanced filters), `frontend/components/WorkQueueView.tsx` (Doc
      Readiness rows).
      **Not:** restructuring the tabs; D-022 (3) does that. Make the smallest
      honest change.
      **PR:** engineering.
      `check: npx vitest run frontend/components/RepoGrid.test.tsx`
- [ ] [[D022-1]] **D-022 (1) — one lifecycle the operator sees.** (depends: L21-POLL, L21-SCANDONE, L21-AUTOSCAN, L21-LAZY, L21-TIME, L21-FIRST, L22-FIX, L22-ELIG, L22-WORK, L22-STUCK, L22-SNAP, L22-CTRL, L22-LABEL, L22-TREND, L22-DETAIL, L22-GRID) _(state: planned)_
      **Why first:** D-022 (2) to (4) render these states. D-022's
      sequencing holds it until Lanes 0.21 and 0.22 are finished, so nothing
      is built into the new shape while it still shows a known false state.
      **Do:** Needs plan → Plan needs approval → Ready for agents → Agent
      working → In review → Healthy / Archived, with flags beside it
      (Uncommitted changes, CI failing, Behind remote, Docs gap). The three
      steering conclusions stay the model's output; the consistency table
      maps every operator state to the conclusion it agrees with. L-levels
      and hold codes become detail. Amend `docs/governance/steering.md` in
      the same PR.
      **Done when:** every repository in a fixture index resolves to exactly
      one operator state; every state maps to an agreeing conclusion; a
      disagreement without an explanation fails.
      **Start at:** `_ResolveLifecycleState` in
      `backend/modules/portfolio/Portfolio.Assessment.ps1`, the D-020
      consistency table, `tests/Test-FoundationConclusions.ps1`
      (`-Assert lifecycle-consistency`), D-020 and D-022 in
      `docs/governance/open-decisions.md`.
      **PR:** review — it amends steering.
      `check: pwsh ./tests/Test-OperatorLifecycle.ps1 -FailOnError`
- [ ] [[D022-2]] **D-022 (2) — Today as an exception inbox.** (depends: D022-1) _(state: planned)_
      **Do:** a system banner only when something is abnormal; decisions
      grouped by type, with bulk actions; actions only the operator can take;
      stuck work with its remedies (from `L22-STUCK`); the next five eligible
      items (from `L22-ELIG`); a digest; everything else collapsed to counts.
      KPIs: Decisions waiting · Stuck · Ready for agents. The first D-022
      surface to build.
      **Done when:** a healthy fixture renders no banner; each section
      renders from fixtures; each KPI counts what its name says.
      **Start at:** `frontend/components/TodayView.tsx`,
      `frontend/lib/todayRanking.ts`.
      **Not:** a banner on a healthy landing.
      **PR:** engineering.
      `check: npx vitest run frontend/components/TodayInbox.test.tsx`
- [ ] [[D022-3]] **D-022 (3) — four destinations.** (depends: D022-1, D022-2) _(state: planned)_
      **Do:** Today · Portfolio (Grid + Operations, Doc Readiness as a
      filter, technology as a column) · Work · Trends, plus a System drawer,
      Settings, Help and the source switch. One repository drawer (Overview ·
      Plan · Work · History) opens from every repository name.
      **Done when:** navigation renders exactly the four destinations and the
      utilities; every rendered repository name opens the drawer.
      **Start at:** `frontend/components/DashboardViewTabs.tsx` (`VIEW_META`),
      `frontend/App.tsx`, `frontend/components/Dashboard.tsx` (`DASH-SPLIT`
      makes this cheaper).
      **Split:** scout — every place a repository name renders; lead —
      navigation and the drawer; builder — wire each name to the drawer.
      **PR:** engineering.
      `check: npx vitest run frontend/components/AppNavigation.test.tsx`
- [ ] [[D022-4]] **D-022 (4) — one Work pipeline.** (depends: D022-1, D022-3) _(state: planned)_
      **Do:** Proposed → Approved → Queued → Running → In review → Done, plus
      a Needs-attention lane. The trace is each card's detail, and its
      broken-link diagnosis is the card's status. One "Send to agent" with a
      preview and a provider choice. Lanes retire as an operator concept; the
      lane count is a Settings knob if anything.
      **Done when:** every run and packaged item in a fixture lands in
      exactly one column; a broken trace link shows as the card's status;
      only the Work destination offers "Send to agent" (D-008).
      **Start at:** `frontend/components/ExecutionQueuePanel.tsx`,
      `frontend/components/WorkItemTraceModal.tsx`,
      `frontend/components/CopilotTaskPreviewModal.tsx`,
      `frontend/lib/packagedItems.ts`.
      **PR:** engineering.
      `check: npx vitest run frontend/components/WorkPipeline.test.tsx`
- [ ] [[L19-VERIFY]] **Lane 0.19 — the operator queue is visible in the console.** (depends: D022-2) _(state: planned)_
      **Why:** `operatorOnlyItemCount` is produced per repository and read
      nowhere, and `docs/governance/operator-queue.md` is visible only in
      this repository.
      **Do:** a route returns the queue's rows (Id, Needs, Action, Ratchets),
      parsed from the file, and Today renders them as its group of actions
      only the operator can take (D-022 (2)). Per D-022 (3) it is never a tab
      of its own.
      **Done when:** the route returns every row of a fixture queue, and an
      empty list rather than an error when the queue is empty; Today renders
      the rows.
      **Start at:** `docs/governance/operator-queue.md` (the table),
      `scripts/Add-OperatorVerification.ps1` (the writer, D-016). A new
      route also has to pass the route census and the deadline tiers.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-OperatorQueueRoute.ps1 -FailOnError`
- [ ] [[D022-5]] **D-022 (5) — proposals with the operator upstream.** (depends: D022-2, T37-LEDGER) _(state: planned)_
      **Do:** the operator picks N repositories and triggers "Generate
      proposals" with a cost preview and the egress confirmation. The review
      queue shows a side-by-side diff with keyboard approve, reject and skip,
      and each response lands in the `T37-LEDGER` ledger.
      **Done when:** no proposal is generated without the trigger and the
      confirmation; a private-scope repository is never sent; each keyboard
      response writes one ledger row.
      **Start at:** the preview-first AI routes, the private-scope setting
      (M4c's no-one-click-egress rule), `frontend/components/DocReviewModal.tsx`.
      **Not:** background generation (the 2026-09-14 no-one-click-egress
      ruling).
      **PR:** review — a suite gate and AI egress.
      `check: pwsh ./tests/Test-ProposalBatch.ps1 -FailOnError`

**Forward arc.** Releases 3.0-3.5 describe the finished product: dispatch that
runs, the loop closing legibly and without a hand-off, numbers an operator can
act on, an 80+ repo portfolio that feels immediate, unattended operation.
Release 3.6 extends it to "every repository ends with an explainable
conclusion"; Release 3.7 makes the product prove, on ten real repositories,
that it returns more time than it takes. Release 3.8 made the execution layer
provider-aware, so that proof is not capped by one agent's subscription.

---

## 1. What This Document Is

> Read [`docs/governance/steering.md`](docs/governance/steering.md) first. It
> says what the product is for, what it must never do, and what "proved" means;
> this file says only what to build next.

This is the **active execution roadmap**. Its job is to answer two questions
for any operator or coding agent:

1. What is the current active release?
2. What is the next concrete work item?

Long-form product direction (thesis, principles, north-star workflow, risks,
guardrails) lives in
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
and is summarized below in section 2. Every completed release lives, verbatim,
in [`docs/history/completed-releases.md`](docs/history/completed-releases.md);
this document references them by version + status only.

Open work is one of four kinds — unbuilt engineering, human verification,
product decisions, calendar-gated accrual — and this file tracks only the
first; the others and their ledgers are named in
[`docs/governance/kinds-of-work.md`](docs/governance/kinds-of-work.md).

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

**Product lens (2026-08-23) — the principle every remaining item is ranked
against.** The product does not prescribe what a repository should become. It
identifies and strengthens the foundations that allow each repository to
succeed at what it is intended to be. Five **foundation domains** are the
starting set — documentation, purpose, planning, structure, and evidence of
intentional engineering — refinable as the product meets new repository types
and operating models, never a fixed scoring taxonomy. Every repository ends
with an **explainable conclusion**: _strengthen_ (with a preview-first next
action), _appropriate as-is_ (healthy, intentionally minimal, externally
managed, archived, or out of scope — and the product says why), or
_insufficiently understood_ (naming what the product would need). Remaining
work is prioritized on operational efficiency and actionable improvement:
purpose obvious from the first interaction, and discovery → remediation as
one workflow that says what was found, why it matters, and what can be
improved. **Admission rule for every item below: one hour spent on this
product must save more than one hour across the portfolio it manages.** An
item that only makes the product better at managing, validating, or
describing itself is maintenance, not roadmap work.

For the full thesis, ten core questions, foundation domains, principles,
risks, and guardrails, see
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md).

---

## 3. Implementation-State Vocabulary

Every milestone carries exactly one state and exactly one `check:` — the command
that decides it. A milestone with no runnable check is not a milestone; it is a
question, and it goes to `docs/governance/open-decisions.md` instead.

| State      | Meaning                                                                   | Closed by |
| ---------- | ------------------------------------------------------------------------- | --------- |
| `planned`  | Contract written (goal, boundary, `check:`); no code on any branch        | agent     |
| `built`    | Code on a branch; `check:` not yet green in CI                            | agent     |
| `verified` | `check:` exits 0 in CI on the PR head; evidence linked from the PR        | agent     |

A `built` or `verified` milestone's `check:` must be a step CI runs, with every
argument the line passes (validator R024). A check CI does not run can never go
green there, so the state would rest on nobody's word.

`verified` is the terminal state for this file. It is the only state that earns `[x]`,
and `[x]` means the item leaves this file for the archive in the same PR.

**Field proof is not a state.** "Seen working on the live portal", "ran under SYSTEM",
"confirmed on the phone" are recorded as ratchets in
[`docs/governance/operator-queue.md`](docs/governance/operator-queue.md) via
`scripts/Add-OperatorVerification.ps1`. A ratchet may be recorded any time after
`verified`, may be recorded never, and never blocks a later milestone. The
promotion boundary — merge to the protected default branch on an operator-approved
verified head SHA — is unchanged and lives in §8; it gates *merge*, not *the next item*.

**Milestone format.** One bullet, action-first. The first line holds a stable
`[[ID]]`, the bold title, any `(depends: ID, ID)` list and the state clause,
because the roadmap parser reads the id, the dependencies and the state from
that line (D-001 notation, `backend/modules/roadmap/Roadmap.Parser.ps1`).
Fields follow on indented lines, and the `check:` is the last line.
`L21-POLL` in Current focus is a complete example.

| Field | What an agent does with it |
| --- | --- |
| `[[ID]]` | Names the item in branches, commits, handoffs and delegation prompts. Never reused. |
| `(depends: …)` | The item is not eligible while any listed id is still in this file. Archiving an item removes its id from every list in the same PR; an id that names nothing fails the module smoke. |
| **Why** | The observed evidence. The first failing test reproduces it. |
| **Do** | The change. |
| **Done when** | What the `check:` must assert. Write these assertions first and show them failing. |
| **Start at** | Entry points that existed when the item was written. Confirm them first; they are hints, not the scope. |
| **Not** | The boundary: what must not change. |
| **Built**, **Already built**, **Verify first**, **Next** | What already exists, what to confirm before writing code, and the step that remains. |
| **Split** | Which parts a fast helper can take (scout: read-only discovery; builder: mechanical edits to named files) and which the lead keeps. |
| **PR** | `engineering` merges on a green check. `review` (config, a CI gate, `docs/governance/`, or what a verdict says) waits for the owner, two at most at a time (D-019). |
| `check:` | The one command that decides the item. |

An item without **Split** is small enough for the lead alone. A **Done when**
the `check:` already passes today is not proof: verify the stated condition
directly.

**The next eligible item, computed.** The product's own selector returns the
first open item in document order whose dependencies are met:

```powershell
pwsh -NoProfile -Command '. ./backend/modules/roadmap/Roadmap.Dependencies.ps1; . ./backend/modules/roadmap/Roadmap.Parser.ps1; (Invoke-ParseRoadmapContent -Content (Get-Content ./ROADMAP.md -Raw)).nextPendingItem'
```

**Checkbox rule.** `[x]` = `verified`. An item whose code is merged but whose field
proof is unrecorded is `[x]` here and open in the operator queue — two ledgers, no
overlap. The old rule ("stays `[ ]` and names the resource it waits on") is retired
2026-09-13: it made the operator the terminal state of every item and taught agents
to end each session by asking for verification.

**Archive rule** unchanged: once `[x]`, the item moves verbatim to
`docs/history/completed-releases.md` in the same PR.

**Operator-work rule.** Nothing in this file may name an action only the operator can
take. If a milestone needs SYSTEM rights, a device, an authenticated session, a grant
outside the repository, or eyes on a browser, the agent-closable half stays here with
its own `check:` and the human half is appended to the operator queue. The validator
(`R021`) rejects the file otherwise.

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
| 2.4       | Agent Integration Protocol and AI Repair Loop                            | `done` — 2026-07-05; live submit-PR proof landed 2026-08-09 (2.7 Phase A, PR #96)          |
| 2.5       | Mobile-Friendly Operator Experience                                      | `done` (engineering) — 2026-07-05; two surfaces + device proof tracked in 2.9              |
| 2.6       | Interface Clarity and Operator Orientation                               | `done` — 2026-07-06; device sign-off tracked in 2.9                                        |
| 2.7       | Guarded Scheduled Automation (Curated-Subset, Preview-First)             | `done` — closed 2026-08-11; see archive. Live service install re-homed to 2.9              |
| 2.8       | Local Claude Code Execution (queue + operator runner)                    | `done` (engineering) — 2026-07-15; real `claude` run tracked in 2.9                        |
| **2.9**   | **Operator Field Proof + Mobile Completion**                             | **active** — promoted 2026-08-19; mobile UN-DEFERRED (its resume condition was met)        |
| 3.0       | Operator-Context Execution                                               | `done` (engineering) — 2026-08-09; see archive. Live proof tracked in 2.9                  |
| 3.1       | Closed-Loop Delivery                                                     | `done` 2026-08-15 — manual loop proof recorded; portal + scheduled proofs re-homed to 2.9  |
| 3.2       | Portfolio Scale and Responsiveness                                       | `done` 2026-08-19 — budget + bounded sweep + observable/cancellable scan + render bound    |
| 3.3       | Steady-State Operation                                                   | `done` 2026-08-19 — retention, rehearsed restore, honest transport, decision-grade exports |
| **3.4**   | **The Delivery Loop Closes**                                             | `done` 2026-08-15 — six milestones + the full-loop proof, driven live and operator-verified |
| 3.5       | Trustworthy Surfaces (UI Quality)                                        | `done` 2026-08-17 — all seven milestones; trust-report per finding; operator sign-off in 2.9 |
| 3.6       | Every Repository Gets an Outcome                                         | `done` — closed 2026-09-14 (D-018 PR 2); see archive. Field proof: OQ-1. Its two non-blockers live on as Current focus M4a and the 2.9 trend accrual |
| **3.7**   | **Portfolio Value Proof**                                                | **`planned`** 2026-08-23 — follows 3.6; ten real repositories decide the 80+ rollout       |
| 3.8       | Provider-Aware Execution                                                 | `done` 2026-09-17 — engineering closed and archived; follow-ons `D012-ENV`, `CHECKRUN`     |
| **3.9**   | **Adaptive Routing**                                                     | **`planned`** 2026-09-08 — routes on evidence; waits for the 3.7 decision (`T37-DECIDE`)   |

> **Note on `.5` numbering.** Reserve it for course corrections like 1.7.5;
> default new work to integer minor releases.

### Execution Order and Dependencies

Release numbers identify scope — they do not dictate sequence. Work through
open items in the order below, and update this section whenever a lane
closes or a new dependency appears.

**Trial sequencing — approved 2026-09-05.** Select the ten by kind now; fix
and validate the remaining Lane 0.15 truth defects before measured execution.
Release 3.6 field proof (OQ-1) and operator approvals remain required. Lane
0.18 acceptance evidence is required for each counted improvement, but an
independent operator check can supply it; completing all of Lane 0.18 is not
a prerequisite. **Dependency ordering is no longer blocked:** D-001 was
answered 2026-09-06 — a managed roadmap may optionally declare dependencies,
within one repository, acyclic, keyed on stable item ids, gating dispatch
eligibility. The cohort is unblocked too; see the D-006 note under Release 3.7.

1. **Release 3.7 — Portfolio Value Proof** is the next engineering
   release (execution contract in §6). The model fixes the first cohort pass
   exposed — kind detection (M4a and its follow-through), limiting foundation
   by kind applicability (M4b), next action by the kind of gap (M4c) — and the
   lifecycle/conclusion consistency contract were verified 2026-09-14 and
   archived. What remains, in order: `T37-LEDGER`, so responses to previews
   are captured from the first one; `T37-PREV`, staging the previews;
   `T37-BRIEF`; measured execution (`T37-EXEC`); the rollout decision
   (`T37-DECIDE`). 3.7 needs the owner for the approvals (OQ-3), not for the
   engineering. Every release from 1.x through 3.6, and 3.8, is
   engineering-closed; new work is still proposed as a release with its own
   contract, never appended to a closed one.
2. **Release 2.9 — the active release.** Its engineering half closed
   2026-08-26 (archived); what remains is the operator half, batched and
   waiting on Ben's presence at the machine.
3. **Release 3.6 field proof** — OQ-1 in the operator queue: eyes on the
   `Today` landing, the outcome card and the Insights leverage panel.
   Engineering closed 2026-09-14; the proof ratchets the archived record and
   holds nothing.
4. **One batched operator session** — an elevated shell covers the watchdog,
   the service installer and 2.7's freeze-prevention deploy; one authenticated
   shell covers the `gh agent-task` run and the re-homed 3.1/3.5 live-portal
   proofs. Batching is the whole point: the operator, not the code, is the
   scarce resource.
5. **Trend accrual** closes itself as calendar time passes, provided capture
   keeps running.
6. **Mobile completion (2.9)** — un-deferred 2026-08-19 when its resume
   condition was met; both engineering items shipped the same day (archived),
   and the physical-Android proof rides the operator batch above.

**Release 3.8 closed 2026-09-17 (engineering; archived).** Its work packet,
capacity ledger, provider routing, push-and-approve binding, remediation and
event vocabulary run today, so the value trial measures the loop with them in
it. Two follow-ons stay open as their own items: `D012-ENV` (the permission
envelope binds) and `CHECKRUN` (check-run detail; the D-003 grant itself is
OQ-5). **Release 3.9 waits for the trial decision** (`T37-DECIDE`): it routes
on evidence, and only executed work produces that evidence.

**Dependency map (agent-closable work only; operator rows live in
[`operator-queue.md`](docs/governance/operator-queue.md)).** The
`(depends: …)` lists on the items are authoritative; this table explains them.

| Open item                                   | Depends on                                                  | Type               |
| ------------------------------------------- | ----------------------------------------------------------- | ------------------ |
| `T37-LEDGER`, `T37-BRIEF`, `MANIFEST`       | nothing                                                     | none               |
| `T37-PREV` previews staged                  | `T37-LEDGER`; OQ-12 (live index carries kind signals)       | soft — sequencing  |
| `T37-EXEC`, `T37-DECIDE`                    | `T37-PREV`; the owner's approvals (OQ-3)                    | **operator queue** |
| `D001-DEPS` dependencies gate eligibility   | `L22-ELIG`, which owns the one eligibility rule             | hard — code        |
| `D022-1` to `D022-5`                        | every open Lane 0.21 and 0.22 item (D-022 sequencing)       | hard — decided     |
| `L19-VERIFY` operator queue in the console  | `D022-2`: it renders in Today, never as a tab (D-022)       | hard — decided     |
| Release 3.9 (`T39-*`)                       | `T37-DECIDE`                                                | soft — sequencing  |
| `CHECKRUN` check-run detail                 | nothing (recorded fixtures); the live grant is OQ-5         | none               |
| 2.9 trend accrual                           | calendar time                                               | time-gated         |

---

## 5. Active Release Snapshot

### Active release detail — 2.9 Operator Field Proof + Mobile Completion

Release 2.9 became the active release 2026-08-19. Its two halves have opposite
shapes: **the operator half waits on Ben and cannot be advanced by an agent**
(SYSTEM rights, a physical device, eyes on a browser, an interactive
credential prompt — listed, batched, ready), and **the engineering half is
closed** — the three foundations-first items resequenced 2026-08-23 closed
2026-08-26 (archived), as did the two mobile engineering items on 2026-08-19.

The full execution contract lives in one place,
[Release 2.9 below](#release-29--operator-field-proof--mobile-completion); this
heading exists so the validator can resolve the active-release pointer.

**Current focus:** the operator batch — it rides Ben's next session at the
machine. The engineering half is closed: the three foundations-first items
(the two readiness gates that disagreed about the same repo, the two routes
that named one concept two ways, the L1/L2 repair path) closed 2026-08-26
([evidence](evidence/verified/release-2.9-foundations-closed-2026-08-26.md));
the two mobile engineering items shipped 2026-08-19. Engineering attention is
on Current focus.

---

## 6. Open Releases

### Release 2.9 — Operator Field Proof + Mobile Completion

**Status:** ACTIVE — promoted 2026-08-19 when Release 3.3 closed and left no
unblocked engineering release behind it. Mobile completion is **un-deferred**
in the same move: its 2026-08-11 resume condition (a PC workflow that runs to
completion) has been met three times over.

**Goal:** convert every surface that is `smoke-tested` but still waits on an
external resource into `operator-verified` with durable evidence. (The three
foundations-first engineering items closed 2026-08-26.) No new capability —
this closes the honesty gap between "the suite is green" and "this works in
the field."

**Prerequisites:** each field-proof milestone names the one external resource
it waits on; none block each other, and several share a session. Batch them:
the operator, not the code, is the scarce resource.

**Resequenced 2026-08-23 under the product lens (§2), closed 2026-08-26.**
Three items that had sat under _Known issues_ led the engineering milestones
because they are what makes a finding explainable — the preconditions in
substance for Release 3.6. They shipped in PR #184 and closed when CI Smoke
proved the canonical module and api-host smoke green; the three items are
[archived in completed-releases.md](docs/history/completed-releases.md#foundations-first-items--closed-2026-08-26).

#### Product outcomes

- No milestone is marked complete on an automated suite alone when what it
  claims needs hardware, elevation, credentials, or a human; `evidence/`
  carries a durable record for each proof, so the next agent reads it instead
  of re-litigating whether something works.

#### Engineering milestones

**Foundations first — resequenced 2026-08-23, closed 2026-08-26.** The
disagreeing readiness gates, the two-names-one-concept routes, and the L1/L2
repair path all shipped in PR #184 (`ba8ffc7`) and closed `smoke-tested`
when CI Smoke run 32949331713 proved the canonical module and api-host smoke
green; [archived](docs/history/completed-releases.md#foundations-first-items--closed-2026-08-26),
[evidence](evidence/verified/release-2.9-foundations-closed-2026-08-26.md).

**Mobile completion — un-deferred 2026-08-19** once the delivery loop had run
end to end three times (PRs #140, #142, scheduled INcendiary#7). The two
engineering items shipped the same day (archived below); the third needs the
operator's device on the LAN.

- Touch ergonomics (device-keyed ~44px floor + `DefinitionHint`) and the tap-through agent-run list (`AgentRunSheet`) — both `smoke-tested` 2026-08-19; [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

**Field proof is operator work, and it lives in the queue.** The live service
install is OQ-4, the real `gh agent-task` run through the runner is OQ-6, and
the device proof is OQ-7. Their agent halves are
[archived](docs/history/completed-releases.md#closed-2026-09-17-archived-from-roadmapmd-before-the-agent-ready-rewrite);
no engineering milestone is open in this release.

- One real `claude` run through the runner — `operator-verified`, proven three times (PRs #140/#142, scheduled 2026-08-18); [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- Release 3.1's scheduled-trigger loop proof — `operator-verified` 2026-08-18 ([evidence](evidence/verified/scheduled-loop-proof-2026-08-18.md)); [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- Release 2.1 operator sign-off — `operator-verified` 2026-08-18 against the live `output/app.db`; [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

**Trend accrual is calendar time, not a milestone** (kind 4 in
[`kinds-of-work.md`](docs/governance/kinds-of-work.md)). `GET
/api/portfolio/trend` has reported a real 7-day window since 2026-08-18, and
the 90-day window fills as long as
[`Invoke-DailyEvidence.ps1`](scripts/Invoke-DailyEvidence.ps1) keeps running.

#### Acceptance criteria

- Every milestone above carries an entry in
  `evidence/operator-verification-log.jsonl`, appended via
  [`Add-OperatorVerification.ps1`](scripts/Add-OperatorVerification.ps1) — an
  unrecorded proof is indistinguishable from one that never happened.
- A deliberately frozen portal is detected and recovered by the installed
  watchdog without intervention, with the ledger line to prove it.
- All four mobile workflows complete on a physical Android phone; the app
  installs to the home screen; every hover-only affordance taps at 390px.
- The visible and enforced readiness models agree for every repo, one concept
  carries one name across `/api/roadmap/audit` and `/api/portfolio/assessment`,
  and an L1/L2 fixture repo reaches a preview-first repair or a stated
  conclusion — each proven by a gate shown red first.

#### Out of scope

- New product capability; remote (non-LAN) mobile access; native apps.

**Validation plan:** the two halves are verified differently, deliberately.
The engineering half lands under the module smoke and api-host smoke with a
gate shown red first, `npm run test:unit` where a surface is touched, and
`npm run typecheck` / `npm run lint` / the PSScriptAnalyzer ratchet at
baseline; CI is the arbiter. The operator half is verified by the operator —
on the device, at the elevated prompt, with eyes on the surface — and recorded
in `evidence/operator-verification-log.jsonl`. No agent may mark an operator
item verified.

**Risks:** the physical-device proof must run against the LAN-bound host, not
loopback; an operator item marked verified from a green suite rather than eyes
on the surface would reintroduce the honesty gap this release exists to close.

**Dependencies:** the operator's presence at the machine (elevated session,
authenticated `gh`, browser), a Galaxy S24 Ultra on the LAN
([`lan-mobile-setup.md`](docs/reference/lan-mobile-setup.md)), and Lane 0.2's
certificate regeneration for the TLS-dependent portal proofs. The engineering
half depends on none of these.

**Known issues:**

- ~~The console cannot answer its own Question 6~~ — **retracted 2026-08-20**, the capability exists; the real defect was the naming drift (now resequenced into the engineering milestones above). [Archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- The three findings-shaped items that used to sit here — the disagreeing
  readiness gates, the two-names-one-concept routes, and the L1/L2 repair
  path — were **resequenced 2026-08-23** to the top of the engineering
  milestones above. They are the release's current focus, not its residue.
- Runner stop marker (`Stop-RoadmapTaskRunner.ps1`) and the smoke's queue isolation (`Get-RoadmapQueuePath` + `REPO_MGMT_QUEUE_PATH`) — both **fixed 2026-08-20**; [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).
- [ ] [[DASH-SPLIT]] **[non-blocker]** Split `frontend/components/Dashboard.tsx` (2,084 lines, mostly hooks and handlers above the return). _(state: planned)_
      Release 3.5 deferred the Operations panels' full stale-keeps-last-good
      rendering to this refactor (inherited 2.7 → 3.2 → 3.3 → here).
      Extract the data hooks by destination, so `D022-3` has seams to cut
      along. Behaviour stays identical, and `npx vitest run frontend` stays
      green. **PR:** engineering.
- The intermittent `L0-Absent` packaging failure — **root-caused and fixed 2026-08-19 (PR #167)**, `Wait-ForPortfolioIndex -RequireAuditedMaturity`; [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

---

### Release 3.7 — Portfolio Value Proof

**Status:** planned — defined 2026-08-23; sequencing approved 2026-09-05.
Follows Release 3.6. Measured execution is held until the truth checks, live
operator verification and ten-category cohort are ready. Its job is to make
the product earn its next release against the real portfolio, not itself.

Preparation and per-repository evidence: [trial record](evidence/trials/release-3.7/README.md)
and `evidence/trials/release-3.7/cohort.json`. Nine candidates are named; the
tenth category is recorded as unrepresented under D-006's 2026-09-06 ruling
rather than filled by a substitute. No improvements are counted yet.

**Goal:** ten representative repositories — chosen by kind, not for
conformance — each receive a credible conclusion and, where warranted, a next
action; at least five are materially improved through the existing preview →
approve → execute → validate workflow with operator effort and outcome quality
recorded; the result decides the full 80+ rollout.

#### Product outcomes

- "Is this product making the portfolio better, faster?" is answered with
  recorded numbers, not impressions; false positives and bad recommendations
  are found on nine repositories before they are found on eighty.

#### Engineering milestones

**Selection closed 2026-09-13 — recorded as prose, because a `[x]` in this file
is a mistake, not a record.** Nine repositories are selected by rule, one per
category, each with its reason; `externally-managed-project` is recorded as
**unrepresented**, which D-006 ruled a valid trial outcome rather than a gap to
fill with a substitute chosen for conformance. Selection is not owner intent:
the abandoned and externally-managed categories carry `ownerIntentConfirmed:
false`, because assigning a repository to a category is not a claim about what
its owner intended.

Nothing engineering-side had been blocking it. D-006's ruling released the
selection on 2026-09-06 and stated its own default — nine named plus one
unrepresented — but `cohort.json` still carried the 2026-09-05 state, with the
tenth slot reading `operator-input-required`. The artifact asked for a decision
that had already been made, and the milestone sat at `scaffolded` for a week on
nothing.

**The trial record was not in the repository.** `/evidence/**` was ignored
except `evidence/verified/**`, so both files this release links —
`evidence/trials/release-3.7/README.md` and `cohort.json` — existed only on one
machine. The acceptance criteria below require results "recorded per repository
in `evidence/`", and not one of them could have shipped with the PR that earned
it. `.gitignore` now excepts `/evidence/trials/**` on the same grounds the file
already states for curated proof: a selection reason written by hand is
judgement, not regenerable run spill.

**Still open:**

**Conclusions recorded 2026-09-13 — prose, not a `[x]`.** All six fields are in
`cohort.json` per repository (kind and its basis, the conclusion and its reason,
the limiting foundation with evidence, the next action, and whether the product
can perform it), drawn by `foundation-conclusions v1` over the index generated
`2026-09-13T21:07:51Z` with that index's SHA-256 recorded beside each result.
Zero conclusion-contract violations. Eight of nine reach **strengthen**, one is
**appropriate-as-is**, one **insufficiently-understood**. Eight name an action
the product performs itself. **Not operator-verified** — the entry gate still
wants eyes on the live surfaces, so this is what the product concluded, not a
confirmed finding, and no improvement is claimed.

**Three false positives the first pass exposed, for milestone 4 to fix.** This
is the trial working: finding them on nine repositories rather than eighty.

1. **Kind detection resolves only `archived`.** Eight of nine were concluded
   with the basis "no kind signal in the index; every scored domain applies",
   so per-kind applicability never engaged and a library was judged by an
   application's yardstick. Already recorded as a 3.6 out-of-scope gap; what is
   new is that it undercuts a cohort selected **by kind**.
2. **Seven of nine share one limiting pair** — `planning` weak plus `structure`
   weak — across a finished LED firmware project, an API client library and an
   orchestration experiment. A ranking that answers the same for most of the
   portfolio cannot say what to do first.
3. **Every actionable repository gets the same next action**,
   `POST /api/roadmap/repair/preview`. Defensible as a default when planning is
   weakest, but as the universal recommendation it means the model is currently
   a planning detector rather than a portfolio advisor.

**All three addressed before measurement, 2026-09-14.** M4a resolves kind from
manifests, entry points and the README purpose line; M4b chooses the limiting
foundation only among the domains that apply to the kind; M4c routes each kind
of planning gap to its own preview. All are verified and archived in
`docs/history/completed-releases.md`. They landed before any improvement was
executed, so no measurement straddles a model change, and every conclusion
carries `modelVersion` and the index SHA it was drawn under.

**Still open:**

- [ ] [[T37-EXEC]] **Execute at least five improvements.** (depends: T37-PREV) _(state: planned)_
      **Do:** for each preview the owner approves (OQ-3 records the
      approvals and the minutes), run the product's own execute → validate
      path, and record per repository in `cohort.json`: operator minutes,
      the agent's first-pass result, an independently checked acceptance
      criterion, before/after evidence, and whether the repository is
      materially stronger afterwards. Appropriate-as-is or archive is a
      conclusion outcome, not one of the five.
      **Done when:** five repositories carry a counted improvement with every
      field above. Merge evidence alone never counts.
      **Not:** waiting idle for approvals. Build the recorder and the check
      against fixtures, leave the item `built`, and take the next item.
      **PR:** review — a suite gate and trial evidence.
      `check: pwsh ./tests/Test-TrialExecution.ps1 -Cohort evidence/trials/release-3.7/cohort.json -MinCountedImprovements 5 -FailOnError`
- [ ] [[T37-DECIDE]] **Adjust and decide.** (depends: T37-EXEC) _(state: planned)_
      **Do:** fix every false positive or bad recommendation the executed
      improvements expose as a rule change carrying `observedOn`, or record
      it with its reason. Write the rollout record: the leverage numbers and
      a go/no-go recommendation. The go/no-go itself is the owner's call;
      file it in `docs/governance/open-decisions.md` with the recommendation
      as the stated default.
      **Done when:** the record exists with its numbers and names its
      decision entry. The check asserts that record, never a distribution
      over the cohort (steering §6).
      **PR:** review — governance and trial evidence.
      `check: pwsh ./tests/Test-TrialDecision.ps1 -Cohort evidence/trials/release-3.7/cohort.json -FailOnError`

#### Acceptance criteria

- All ten categories ruled on by the rule, none selected for conformance: nine
  repositories selected with a recorded reason, and `externally-managed-project`
  recorded as unrepresented (D-006 — an empty category is a valid outcome). Each
  selected repository carries a recorded conclusion and reason. Closed
  2026-09-13; a criterion asking for ten repositories could no longer be met by
  a cohort the ruling settled at nine.
- At least five of the nine materially improved through the product's own workflow, with
  operator minutes, outcome quality, and agent first-pass result recorded per
  repository in `evidence/`; a recorded rollout decision with the numbers.

#### Out of scope

- New product capability; finishing every repository; improvements made outside the product's workflow.

**Validation plan:** conclusions, actions, and outcomes recorded in `evidence/`
via [`Add-OperatorVerification.ps1`](scripts/Add-OperatorVerification.ps1) and
the agent-run ledgers; module smoke and api-host smoke stay green; CI is the
arbiter for any product fix the nine expose.

**Risks:** choosing repositories that flatter the product (the selection rule
prevents it); counting a repair as an improvement when the repository is not
stronger (outcome quality is recorded, not assumed).

**Dependencies:** Lane 0.15 truth validation; Release 3.6 field proof (OQ-1);
the operator's approvals and measured effort. **D-006 no longer blocks the
cohort** (decided 2026-09-06): external management is owner intent and may not
be inferred, so a category with no natural member is recorded as unrepresented
rather than filled by a substitute. The trial proceeds with nine named
repositories and records the tenth category as having no cohort member.

---

### Release 3.9 — Adaptive Routing

**Status:** planned — defined 2026-09-08. Design authority is
[`Agent-Execution-Governance.md`](docs/governance/Agent-Execution-Governance.md),
which absorbed Ben's _Multi-Provider Agent Execution Strategy_ the same day.
Follows Release 3.8, and cannot precede it: every milestone here consumes
telemetry that 3.8 is what starts recording. It also waits for `T37-DECIDE`:
the evidence it routes on comes from executed work.

**Goal:** Release 3.8 routes on _capacity_. This release routes on _evidence_.
The router learns which provider actually completes this repository's workload,
at what cost per verified task, and stops paying a frontier tier for work a
cheaper one finishes first time — or stops sending an agent at all where the
answer is deterministic.

#### Product outcomes

- Work the repository can answer itself never reaches a provider, so the
  cheapest routing decision is also the fastest one.
- The operator can see which provider is genuinely better for a kind of task in
  this repository, rather than which one has the better reputation.
- A cold-start preference that the evidence contradicts is overridden by the
  evidence, not defended by the configuration.

#### Engineering milestones

- [ ] [[T39-PROFILE]] **Classify a task before choosing anything to run it.** (depends: T37-DECIDE) _(state: planned)_
      **Why:** `suitability` scores 1.0 when the packet's `preferredProvider`
      matches the candidate and 0.5 otherwise, which repeats a preference
      someone already stated instead of deriving one from the task.
      **Do:** a task profile (type, complexity, risk, context scope, whether
      verification exists, whether the work is deterministic), attached at
      qualification and carried on the WorkPacket.
      **Done when:** a profile is derived without reading
      `preferredProvider`, and the same task always yields the same profile.
      **Start at:** `backend/modules/execution/Execution.WorkPacket.ps1`,
      `Resolve-ProviderSelection` in
      `backend/modules/execution/Execution.ProviderRouter.ps1`.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-TaskProfile.ps1 -FailOnError`
- [ ] [[T39-NOAGENT]] **`NO_AGENT`: the deterministic tier is a routing outcome, not the absence of one.** (depends: T39-PROFILE) _(state: planned)_
      **Do:** in `Resolve-ProviderSelection`, branch state, CI status, file
      existence, repository metrics, schema validation, mergeability and
      policy evaluation are answered by application logic and recorded as a
      selection like any other.
      **Done when:** a deterministic fixture task completes without an agent,
      and its routing record reads `NO_AGENT`.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-NoAgentTier.ps1 -FailOnError`
- [ ] [[T39-COST]] **A cost estimator that can eventually enforce.** (depends: T37-DECIDE) _(state: planned)_
      **Do:** `effective_cost` = metered cost + quota pressure + retry +
      expected failure; pricing is configured or discovered, never embedded.
      **Done when:** the estimate is reproducible from fixtures, and no
      dispatch is refused on it.
      **Not:** enforcement, until the reserves and the per-task estimate are
      both non-provisional (D-011 left the estimate a guess).
      **PR:** review — a suite gate and config.
      `check: pwsh ./tests/Test-CostEstimator.ps1 -FailOnError`
- [ ] [[T39-PERF]] **A performance store keyed by what actually varies.** (depends: T39-PROFILE) _(state: planned)_
      **Why:** a `provider × repository` success ratio cannot tell a provider
      that is good at documentation from one that is poor at coding work.
      **Do:** rolling first-pass rate, eventual success, cost and duration per
      success, remediation count, human-intervention rate and CI failure
      rate, broken down by `provider × model × taskType × complexity`.
      **Done when:** a slice with history returns every metric; a slice
      without history reads "unmeasured", never "bad".
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-PerformanceStore.ps1 -FailOnError`
- [ ] [[T39-EVIDENCE]] **Evidence overrides the cold-start prior.** (depends: T39-PERF) _(state: planned)_
      **Do:** once a task class has enough history, the empirical result
      wins over the configured preference, and the routing record says which
      of the two decided.
      **Done when:** fixture history that contradicts the configured
      preference changes the selection, and the record names the evidence.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-EvidenceOverridesPrior.ps1 -FailOnError`
- [ ] [[T39-RATE]] **Report the metric the release exists to move.** (depends: T39-COST, T39-PERF) _(state: planned)_
      **Do:** verified tasks ÷ total agent cost, with throughput and
      first-pass rate, on `GET /api/providers` and the Dispatch Board.
      **Done when:** the route and the board show the same three numbers from
      one fixture.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-VerifiedTaskRate.ps1 -FailOnError`

#### Acceptance criteria

- A task carries a classification before any provider is considered, and that
  classification is not derived from a requested provider.
- A deterministic task completes without an agent and records `NO_AGENT` as its
  selection.
- Provider and model are separately represented wherever the provider exposes
  model choice.
- Cost per verified task is computable from stored telemetry for any
  `provider × model × taskType × complexity` slice with history.
- A documented cold-start preference is demonstrably overridden by contrary
  evidence in at least one task class, and the routing record names the
  evidence.

#### Out of scope

- Redundant multi-provider execution of the same task as a default. Two-provider
  work stays deliberate and risk-justified.
- Raising concurrency above one local execution slot, which stays a Release 3.8
  boundary until capacity accounting is proven.

**Validation plan:** the classifier, the cost estimator and the performance
store are pure decision tables, gated offline against fixtures in the shape the
module smoke already uses; no packet spends provider quota to produce a fixture.

**Risks:** a classifier that encodes the same provider preference it was meant
to replace; a performance store confident on too little history — the router
must keep distinguishing "unmeasured" from "measured as bad", as it already does
for capacity; enforcement switched on before consumption is measured.

**Dependencies:** Release 3.8 for the telemetry these milestones read, and in
particular the 3.8 amendment that puts cost and duration into the canonical
event vocabulary as it is defined.

---

## 7. Cross-Cutting Engineering Work

Continuous, not release-scoped. **This section carries open work only.**
Completed cross-cutting items are in
[the archive](docs/history/completed-releases.md#cross-cutting-engineering-work-completed-items)
(2026-08-07) and [the 2026-08-08 batch](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).

### Lane 0.2 — Credential freshness

- [ ] [[CHECKRUN]] **Read check-run detail where it exists; keep `mergeStateStatus` as the fallback.** _(state: planned)_
      **Why:** [`MergeReadiness.ps1`](backend/modules/agent-runs/MergeReadiness.ps1)
      reads `mergeable_state` from the Pulls API, so a `BLOCKED` rollup
      cannot tell a required check still running from one that failed; the
      merge loop works around that by polling. Release 3.8's CI-failure
      evidence wants the finer signal. D-003 decided to grant
      `Checks: Read`; the grant itself is OQ-5.
      **Do:** prefer per-check conclusions, and keep the proxy for a token
      without the scope.
      **Done when:** a fixture with one pending and one failed required check
      reports two different blockers; a token without `Checks: Read` still
      evaluates through the proxy instead of erroring.
      **Start at:** `Get-MergeReadinessEvaluation` in
      `backend/modules/agent-runs/MergeReadiness.ps1`.
      **Not:** calling GitHub from the test; use recorded responses.
      **PR:** review — a suite gate and a merge verdict.
      `check: pwsh ./tests/Test-CheckRunDetail.ps1 -FailOnError`

### Lanes 0.3, 0.4 and 0.6 — closed entirely

All three shipped and closed 2026-08-09; detail moved to
[the archive](docs/history/completed-releases.md#closed-2026-08-11-archived-from-roadmapmd)
on 2026-08-11. Kept as named headings because surviving lanes and the
completed-release history reference them by name: **0.3** layout follow-ups,
**0.4** smoke coverage gaps (the extended deadline tier Release 3.2 inherits),
**0.6** the silent workspace-path failure.

### Lane 0.9 — Portal restart loop: the watchdog was killing healthy scans (P0, 2026-08-10)

**The incident closed 2026-08-10 across four passes and is archived** — the
fix made progress, not liveness or CPU, the contract, and taught the rule every
tripwire here now follows: derive scope from a classifier or the AST, never a
maintained list.

- [ ] [[OWNER]] **A client-supplied GitHub owner never silently overrides configuration.** _(state: planned)_
      **Why:** from 2026-07-07, every scan queried GitHub for the owner
      `Benjamin-Fuhr_genesys`, which answers 404 or 422 (116 occurrences in
      the host log by 2026-08-10). It was not in `settings.json` (correctly
      `xfaith4`) or any environment variable: the browser sent it in the
      request body.
      **Verify first:** the host now remembers an owner GitHub reported
      absent (`Test-GitHubOwnerKnownAbsent`), which removes the repeated
      round-trip but not the override. Read the current host log before
      building.
      **Do:** clear the persisted client value. A scan or status request
      uses the configured owner whatever its body says. A settings save that
      changes the owner validates it first.
      **Done when:** a scan request carrying a different owner uses the
      configured one and reports the mismatch; a settings save naming an
      owner GitHub does not know is refused with the reason; the client no
      longer sends a persisted owner with scans.
      **Start at:** `POST /api/settings` (`githubUser` →
      `reconcile.gitHubOwner`) in
      `backend/api-host/Start-RepoManagementApiHost.ps1`,
      `frontend/services/apiClient.ts` (`githubUser`).
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-OwnerCacheReset.ps1 -FailOnError`

### Lane 0.5 — Portal UX follow-ups (empty-state audit 2026-08-08)

Three of four closed 2026-08-10 and are archived (error boundary, bulk-scope confirmation, tab inversion).

- The progressive-disclosure question — **decided 2026-08-23, resolved 2026-08-27**: the ranked `Today` landing with one primary action per row is Release 3.6's first-interaction milestone, and it shipped — `Today` is now the default view, the six peers sit behind it, and every tab poses the question it answers. The three 2026-08-15 review inputs are [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd). Nothing remains in this lane.

### Lane 0.7 — Roadmap-standard fidelity: split-history awareness (2026-08-08)

Nothing penalizes a roadmap that archives completed work to a separate file
(this repo's shape), but nothing tells one apart from a repo that deleted its
history; the 2026-08-08 survey found zero managed repos using the split layout,
so the live risk is the repair path pushing 32 repos toward in-file history.
Intent: **awareness, not enforcement.**

- [ ] [[HISTORY]] **Record whether a repository externalizes its completion history (D-005).** _(state: planned)_
      **Why:** the contract requires `completedCount`, and a split roadmap
      reports ~0 forever. Nothing tells "history archived to
      `docs/history/`" from "history deleted", so a future consumer that
      treats `completedCount` as progress would read a well-kept split
      repository as inert.
      **Do:** add an explicit field (for example `historyLocation` or
      `archiveRef`) to
      [`roadmap-contract.schema.json`](standards/roadmap/roadmap-contract.schema.json),
      set it from a pointer link in the roadmap, and surface it in the audit
      payload. The `spec/roadmap-contract/` mirror moves with the schema;
      the sync gate is part of this item.
      **Done when:** this repository's roadmap reports its archive location;
      a roadmap without a pointer reports none; no score changes.
      **Start at:** the schema and its mirror,
      `backend/modules/roadmap/Roadmap.Parser.ps1`.
      **Not:** enforcement. D-005 made this awareness metadata: no
      repository is asked to externalize its history, and no archive format
      is prescribed.
      **PR:** review — a suite gate and the managed-roadmap contract.
      `check: pwsh ./tests/Test-ExternalizedHistory.ps1 -FailOnError`
- Sanction the external-archive pattern in the standard — done (`ROADMAP_TEMPLATE.md` §6 "External archive option"); [archived](docs/history/completed-releases.md#release-29--completed-items-archived-2026-08-23-from-roadmapmd).

### Lane 0.8 — Verification gate integrity (CI audit 2026-08-10)

**Re-homed from Release 3.1 on its closure (2026-08-15):**

**Three items closed 2026-09-13 — recorded as prose, because a `[x]` in this
file is a mistake, not a record.**

_The watchdog restart loop — cause confirmed, fixed by the operator._ The
registered `RepoMgmtPortalWatchdog` task kept the `-BaseUrl` it was installed
with, which predated the 2026-08-29 HTTPS switch, so every one-minute probe went
to `http://` and failed the TLS handshake. After three failures in a row the
watchdog force-killed the host and restarted the service, which reset the count:
**a restart every three minutes, around the clock, from 29 August to 12:29 on
13 September — about 7,000 restarts**, roughly 480 a day, almost none preceded
by a clean shutdown. `apihost.log` holds 122,411 handshake failures, the bulk
of them this probe: four per run, once a minute, 5,665–5,771 a day. The Task
Scheduler log shows the operator updating the task at 12:29, 12:40 and 12:44;
the last plain-http failure is 12:44:58, and the task still runs every minute
without killing the host, so its HTTPS probe now succeeds — fixed, not merely
removed. The lesson above about frozen registration arguments stands, and the
runner task carries the same exposure (benign today). Not related: the API
contract test timeouts, which run against their own host on another port.

_Runner heartbeat isolation._ One override, `REPO_MGMT_RUNNER_CONTROL_ROOT`, now
moves all three runner-state files (heartbeat, hold, stop marker), and every
reader and writer resolves through it: the portal, the runner and
`Stop-RoadmapTaskRunner.ps1`. The problem was worse than recorded here: five
api-host smoke steps did not just read the real heartbeat, they deleted it and
wrote a fake runner over it, so the portal flickered while tests ran and the live
runner rewrote the file underneath them. Proved on the operator's machine with
their runner alive: the api-host smoke passed for the first time, and 290 samples
of the real heartbeat taken during the run all showed the live runner's pid,
never missing and never faked. The smoke's pre-flight warning also never fired —
it read `processId` where the field is `pid` — and now correctly reports a live
runner as left alone.

_TLS handshake hardening, found while attributing the flood._ The host serves one
connection at a time, and the handshake ran on that loop before
`Read-HttpRequest` applied its read timeout, so a client that connected and sent
nothing would have stalled every request behind it — the exact condition the
watchdog kills. The socket now gets the 15-second client timeout before
`AuthenticateAsServer`, and a failed handshake logs `remote=<address>`, so the
next flood names its caller in the log line instead of costing an afternoon.
Takes effect on the next service restart.

**Still open:**

_`.gitattributes` — closed 2026-09-13._ The repository now declares
`* text=auto eol=lf`, PNG and other assets `binary`, and `.bat`/`.cmd` CRLF.
Before it, 386 of 414 tracked files were LF in the index while 22 were CRLF and
4 mixed — whichever editor touched them last decided — and a Windows checkout
under `core.autocrlf=true` held CRLF for all of them, so any byte comparison
drifted locally while passing on CI's LF checkout. The 26 were renormalized in
the same commit: 8,852 lines changed, and a CR-stripped comparison of every
file before and after found zero content differences. The index is now 412 LF
files plus the two PNGs.

- [ ] [[QUEUE-COVER]] **[non-blocker]** The scheduled and operator dispatch paths reach the queue through different writers, with one end-to-end test between them. _(state: planned)_
      The behavioural divergence closed in 3.1; the coverage asymmetry
      remains. Give the uncovered writer the same end-to-end module-smoke
      case as the covered one. **PR:** engineering.
- [ ] [[PHASE-DOGFOOD]] **[non-blocker]** `scripts/Invoke-PhaseProtocolTest.ps1` fails its dogfood case on this roadmap. _(state: planned)_
      Found 2026-09-17: "live ROADMAP.md -> phase-plan tables carry protocol
      columns" fails with `no-phase-plan, missing-protocol-columns` (1 of 21
      cases), on the roadmap as it stood before the agent-ready rewrite and
      after it. This file has no phase-plan table, and the script is not in
      the suite, so nothing caught it. Drop the live case, or point it at a
      fixture roadmap that has a phase plan. **PR:** engineering.

**The gate work closed 2026-08-10 (PRs #102–#107) and is
[archived](docs/history/completed-releases.md#closed-2026-08-11-archived-from-roadmapmd):**
`ci-smoke.yml` invokes `Invoke-TestSuite.ps1` itself, both linters fail the
build, `main` requires `smoke` with `enforce_admins` on. What remains is the
debt the ratchets hold, and it is deliberately not a sweep.

**Warning-debt reduction plan (decided 2026-08-10).** The baselines are
controlled debt — **no blanket lint sweep.** Small, behaviorally coherent
batches, each ending with `-UpdateBaseline` / a lowered `--max-warnings`:

- E1 — ESLint `exhaustive-deps` review: [archived](docs/history/completed-releases.md#closed-2026-09-13-archived-from-roadmapmd).
- [ ] [[P2]] **P2 — empty catch blocks: classify and fix the last 15.** _(state: built)_
      **Built:** batches 1 to 3 (the api host, `backend/modules`, and
      `scripts`/`tools`, all 2026-09-13) turned 64 sites into annotated
      best-effort catches, each stating its reason beside a real statement
      (`$null = $_`); none needed surfacing, because each degrades to an
      answer its caller already handles. The ratchet was locked at 420 (was
      484). `PSAvoidUsingEmptyCatchBlock` stands at 15 in
      `scripts/pssa-baseline.json`, all outside the module tree.
      **Do:** make each of the 15 an annotated best-effort (a narrowed catch
      with its reason) or a surfaced failure ("never swallow silently"), then
      lower the baseline with `-UpdateBaseline`.
      **Done when:** the rule's baseline is 0 and the lint gate passes. The
      gate already passes today, so check the baseline value directly.
      **Split:** scout — run PSScriptAnalyzer for this one rule and list the
      15 sites with their surrounding lines; lead — classify each site;
      builder — annotate the sites the lead marks as best-effort.
      **PR:** engineering.
      `check: pwsh ./scripts/Invoke-LintGate.ps1`
- [ ] [[E2]] **E2 — type the API client (`no-explicit-any`, 123 at the last count, most in `apiClient.ts`).** _(state: planned)_
      **Why:** the value is contract drift caught at typecheck, not style.
      **Do:** batch by endpoint group. After each batch, lower
      `--max-warnings` in `frontend/package.json` (153 on 2026-09-17) by the
      number of warnings removed.
      **Done when:** `frontend/services/apiClient.ts` has no explicit `any`,
      and `npm run typecheck` and `npm run lint` pass at the lowered cap.
      **Split:** scout — count `any` per endpoint group; builder — type one
      group at a time against the payload shapes the lead names; lead —
      check each batch's types against its route.
      **PR:** engineering.
      `check: npm run lint`
- [ ] [[P3]] **P3 — plaintext-password parameters (9): a design review per surface.** _(state: planned)_
      **Why:** `PSAvoidUsingPlainTextForPassword` stands at 9 in
      `scripts/pssa-baseline.json`. Each is a credential flow, not a
      mechanical fix.
      **Do:** for each surface choose SecureString or an environment-variable
      flow, coupled to the Lane 0.2 certificate work, and lower the baseline.
      **Done when:** the rule's baseline is 0, or each remaining site has a
      recorded reason in `docs/governance/open-decisions.md`.
      **Start at:** `scripts/Install-RepoManagementService.ps1`
      (`-PfxPassword`), `backend/modules/auth/SessionAuth.ps1`
      (`Get-Pbkdf2Hash -Password`); a scout finds the other seven.
      **Not:** renaming parameters to silence the rule, or writing a secret
      to a log or a tracked file.
      **PR:** review — credential handling.
      `check: pwsh ./scripts/Invoke-LintGate.ps1`
- P4 — BOM/PS5.1 hazard: [archived](docs/history/completed-releases.md#closed-2026-09-14-archived-from-roadmapmd).
- **Deliberately unscheduled (accepted debt, held at baseline):** the naming
  and style tiers (`UseSingularNouns` 90, `UseOutputTypeCorrectly` 136,
  `UseShouldProcessForStateChangingFunctions` 67, five smaller) — churn for
  zero behavior.
- **Separate lane, never batched mechanically:** ESLint `set-state-in-effect`
  (31) — every site needs behavioral review; a "fix" can change rendering.

---

### Lane 0.10 — Scan-snapshot retention (found 2026-08-27)

- [ ] [[RETAIN]] **[non-blocker]** Give `output/index/scans/portfolio-scan-*.json` a retention rule. _(state: planned)_
      `Save-PortfolioIndexArtifacts`
      ([`Portfolio.Assessment.ps1`](backend/modules/portfolio/Portfolio.Assessment.ps1))
      writes one snapshot per scan, and nothing reads or prunes them: 762
      files and 103 MB had accumulated by 2026-08-27, when they were pruned
      by hand to seven days. Either add the directory to
      `Get-LedgerRetentionPolicy`
      ([`Ledger.Retention.ps1`](backend/modules/persistence/Ledger.Retention.ps1)),
      keyed on file age because each file is a whole snapshot, or keep the
      newest N in the writer. Resolve the directory through the output root.
      Gate: a module-smoke fixture writes eight dated snapshots and asserts
      the oldest is gone. **PR:** engineering.

### Lane 0.12 — Two local clones of one repo collapse to one row, arbitrarily (found 2026-08-27)

- [ ] [[CLONES]] **[non-blocker]** Two checkouts of one remote with different folder names still produce two portfolio rows. _(state: planned)_
      `GenesysCloud\Genesys.Core` and `GenesysCloud\Genesys.Core_AuditLogsApp`
      both clone `github.com/xfaith4/Genesys.Core`, but the collision unit is
      the repository _name_, so they never collide and the portfolio counts
      one GitHub repository twice. `Group-RepoByRemoteIdentity`
      ([`Portfolio.Scope.ps1`](backend/modules/portfolio/Portfolio.Scope.ps1))
      already pairs them by remote URL and root-commit SHA, and the status
      response carries the pair as `duplicateIdentities`; the assessment
      does not read it. **Decision first:** `Genesys.Core_AuditLogsApp` has
      its own `docs/ROADMAP.md`, so collapsing the pair would discard a real
      plan. Before writing code, record the question in `open-decisions.md`
      with "keep both rows and flag the pair" as the default (`L22-DETAIL`
      adds that flag).

- [ ] [[NESTED]] **Classify a repository nested inside another as `nested` (D-002).** _(state: planned)_
      **Why:** the portfolio represents managed projects, not every `.git`
      boundary on disk. `custom_SereneHarmonySite` is a working tree inside
      `SereneHarmony_Site_Starter`, which is also one, and the scan counts
      both.
      **Do:** `Get-RepoScopeClassification` gains a `nested` verdict beside
      `vendored` and `archived`. A nested repository is reported, never
      silently dropped, and an explicit opt-in promotes one to independently
      managed when it has its own lifecycle.
      **Done when:** a fixture with a repository inside a repository
      classifies the inner one `nested` and drops it from the managed count,
      and the opt-in promotes it back.
      **Start at:** `Get-RepoScopeClassification` in
      [`Portfolio.Scope.ps1`](backend/modules/portfolio/Portfolio.Scope.ps1).
      **Not:** an unexplained count change. The portfolio total falls by one
      when this lands; record that in `evidence/trials/release-3.7/` so it
      is not read as scan drift.
      **PR:** review — a suite gate and a scope verdict.
      `check: pwsh ./tests/Test-NestedRepoClassification.ps1 -FailOnError`

### Lane 0.13 — Truthful uncertainty: the product could not tell "unreadable" from "not present" (found 2026-08-27)

- [ ] [[WORKUNITS]] **`estimatedSessionWorkUnits` is never silently null.** _(state: planned)_
      **Why:** the field is filled only from `activePhasePlan`, which 0 of 48
      managed roadmaps carry, so Today's effort column is empty across the
      portfolio and `todayRanking`'s cheaper-effort tiebreak never fires on
      real data.
      **Do:** for each repository, either derive an estimate from signals
      that exist (pending item count, item text, repository kind) and name
      its basis, or mark the field unmeasured with a reason, as the leverage
      panel does for its `available: false` metrics. Let the nine cohort
      repositories show which signals are credible; where none is, the
      field is unmeasured.
      **Done when:** every managed repository carries a number with its basis
      or `unmeasured` with a reason, and none is null.
      **Start at:** `estimatedSessionWorkUnits` in
      `backend/modules/automation/Automation.RoadmapPackaging.ps1`,
      `frontend/lib/todayRanking.ts`.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-SessionWorkUnits.ps1 -FailOnError`

---

### Lane 0.14 — Console UI audit follow-ups (operator audit 2026-08-29)

An operator audit of the live console found the product contradicting itself
before it found anything visual: `Blocked` reads 1, 17 and 58 on three surfaces
because six components use one word for different quantities; "how many
repositories" has six denominators; and seven timestamps in one sitting span
three clock bases. Those are Lane 0.15 (below). This lane is the part that is
**component-wide styling debt** — real, counted, and deliberately not blocking
anything.

Four single-location fixes from the same audit already shipped and are not
repeated here: the global `:focus-visible` ring, the muted-foreground token
lift to `#858fa3` (4.51:1 on the worst surface, from 3.03:1), the ARIA tablist
on the seven views, and `Escape`-to-close plus a focus trap on the two dialogs
that had neither.

- [ ] [[BUTTONS]] **CI rejects an ad-hoc button colour.** _(state: planned)_
      **Why:** the audit counted 21 distinct button background colours on one
      tab, and no checker can tell a legitimate new one from an accidental
      one. The Nocturne token sheet
      ([`frontend/styles.css`](frontend/styles.css)) now supplies the
      semantic set (one accent, three status hues), so what remains is
      enforcement.
      **Do:** move every button background onto the tokens, then add the
      rule to [`tools/Measure-UiRatchet.mjs`](tools/Measure-UiRatchet.mjs): a
      raw hex or a bare Tailwind colour utility in a button background fails.
      **Done when:** the test fails on a planted `bg-blue-600` button and
      passes on the tree.
      **Split:** scout — every button background that is not a token, with
      its file and line; lead — map each to a token; builder — apply the
      mapping.
      **PR:** review — it adds a ratchet rule.
      `check: npx vitest run frontend/lib/buttonTokens.test.ts`

- [ ] [[CONTRAST]] **Every text-opacity rung used for body text clears WCAG AA.** _(state: planned)_
      **Why:** the text hierarchy is opacity over `--color-text`. The top four
      rungs pass on `--color-bg` (14.54, 9.21, 7.62 and 5.19 to 1), but 50%
      is 4.55, 45% is 3.91 and 42% is 3.58, all used at 10–11.5 px, where the
      large-text exemption does not apply. 42% is where `unmeasured`
      renders, which MIGRATION.md §5.1 makes load-bearing.
      **Do:** raise the failing rungs or move them off body text, and record
      the measurements.
      **Done when:** the test computes each rung's contrast on both grounds,
      and every rung used for body text is at least 4.5 to 1.
      **Start at:** the ladder note in `frontend/styles.css`, the
      `text-text/45` and `text-text/50` uses under `frontend/components/`.
      **Not:** dropping the `unmeasured` treatment.
      **PR:** engineering.
      `check: npx vitest run frontend/lib/contrast.test.ts`

- [ ] [[BREAKPOINTS]] **Add breakpoints above 768 px.** _(state: planned)_
      **Why:** `frontend/styles.css` declares two breakpoints, both below
      768 px, and `frontend/tailwind.config.cjs` adds none, so every screen
      from a laptop to a wide desktop gets one fixed layout (310 interactive
      controls on a single tab).
      **Do:** define the wide tiers and lay the densest tab out for them.
      **Done when:** the test proves distinct layouts at 1280 px and
      1920 px.
      **PR:** engineering.
      `check: npx vitest run frontend/lib/breakpoints.test.ts`

- [ ] [[SETTINGS]] **`settings.json` is written in a stable key order, and not at all when nothing changed.** _(state: planned)_
      **Why:** a running portal rewrites
      [`backend/config/settings.json`](backend/config/settings.json) with the
      keys reordered and no value changed. The file is tracked, so the tree
      reads dirty in every session for a change nobody made, which trains
      people to stage it without looking.
      **Do:** serialize with a fixed key order, and skip the write when the
      content is unchanged.
      **Done when:** saving unchanged settings leaves the file's bytes and
      modification time alone; saving a change writes the keys in the fixed
      order.
      **Start at:** the `POST /api/settings` handler in
      `backend/api-host/Start-RepoManagementApiHost.ps1`
      (`ConvertTo-Json -Depth 10` piped to `Set-Content`).
      **Not:** hand-editing `settings.json` in the same PR; the fix is the
      writer.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-SettingsWriteOrder.ps1 -FailOnError`

- [ ] [[DIALOGS]] **Every dialog uses the dismiss contract.** _(state: planned)_
      **Why:** [`useDialogDismiss`](frontend/hooks/useDialogDismiss.ts)
      provides Escape-to-close, a focus trap and focus restoration, and only
      `SettingsModal`, `RepositoryImprovementWorkflowModal` and `HelpModal`
      use it. On 2026-09-17, 18 more components matched a dialog pattern
      without it, including `AgentRunSheet`, whose inline version the hook
      replaces.
      **Do:** in each dialog, call the hook and attach the ref to the panel.
      **Done when:** the check finds the dialogs itself (`role="dialog"`,
      `aria-modal`, a fixed full-screen overlay), never from a list, and
      fails on any that does not call the hook.
      **Split:** lead — the check, shown failing first; builder — the
      two-line change, six components per batch, with
      `npx vitest run frontend` after each batch.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-DialogDismissAdoption.ps1 -FailOnError`

---

### Lanes 0.15, 0.17 and 0.18 — closed entirely

Archived 2026-09-17 with their prose
([archive](docs/history/completed-releases.md#closed-2026-09-17-archived-from-roadmapmd-before-the-agent-ready-rewrite)).
Kept as a named heading because Release 3.7 and the execution-order notes cite
them: **0.15** the console contradicting itself (its field proof is OQ-11),
**0.17** the dispatch console that could not dispatch, **0.18** the four
execution mechanisms ported from RoadmapOrchestrator, delivered inside
Release 3.8.

---

### Lane 0.16 — The Dependencies tab answered a different question than it asked (operator feedback 2026-08-30)

The tab led with _"What does this repository depend on?"_ and answered with
roadmap cross-references — for a portfolio, in the plural, and usually with
nothing at all. To an operator, dependencies are what the repositories run
on: Node, Next.js, PostgreSQL, SQLite, Docker. The product had no answer to
that question anywhere.

- [ ] [[VERSIONS]] **[non-blocker]** Detect versions, not just presence. _(state: planned)_
      The technology inventory (`Get-RepoTechnologyProfile` in
      `backend/modules/portfolio/Portfolio.Assessment.ps1`) says _which_
      repositories run Node, not which Node; a version column would make the
      panel an upgrade-planning surface. It needs a per-manifest version
      parse and a staleness policy for `engines` fields. **PR:** engineering.

---

### Lane 0.19 — The queue steered toward work only the operator could do (operator evaluation 2026-09-11)

Two defects, found together while assessing `FowlingScorecard` and reproduced
against its live index entry. They compound: the repository was dispatch-blocked
for a heading, and the work it would have picked once unblocked was work the
operator would have had to perform by hand.

**The ranker could not tell operator-facing from operator-executed.** The impact
dimension in [`value-scoring.json`](backend/config/value-scoring.json) awards its
top score to any item containing "operator", which is right for an outcome and
fatal for a task. `FowlingScorecard`'s top-ranked item scored 71 on
"Record device, network, and operator friction" with the stored rationale
"user-visible or operator-facing outcome" — it ranked first partly because it
named the operator. First-pending selected a live smoke checklist. Both
selectors chose work no agent can run, in a queue whose entire purpose is
dispatching work the operator does not have to do.

**The execution contract demanded a release that pre-release repositories have no
reason to cut.** The four fields the contract actually checks — goal,
acceptance, boundary, and a runnable verification — are exactly the questions an
agent would otherwise stop and ask, and they earn their place. The version
number does not. The parser matched one heading form, so the same four fields
written under "Phase 2.5" produced `activeRelease = null` and failed three of
four checks on content that was present.

**Open item:** `L19-VERIFY` in Current focus. It absorbed this lane's
non-blocker about surfacing the operator-only backlog, which asked for the
same thing.

---

### Lane 0.20 — The console tells the operator to open a terminal (operator evaluation 2026-09-13)

Found while the operator verified the Release 3.1 empty-room gate. The gate
works: previewing a dispatch with no runner alive refuses, says why, and names
the remedy. The remedy is the problem — it is a command to paste into a shell:

> Runner stalled: nothing would pick this up. Start the operator runner first —
> `pwsh -File "F:\Development\GitHubRepoManagement\scripts\Invoke-RoadmapTaskRunner.ps1"`.

A console that hands its operator a terminal command has made them the
mechanism. Operator intent, 2026-09-13: **the app should start the runner
itself when one is not running**, not ask.

**The constraint that makes this non-trivial, stated once so it is not
rediscovered.** The runner must execute as the OPERATOR, because it launches
their authenticated Claude Code. The portal is a LocalSystem service. A runner
spawned by the service would come up as SYSTEM with no Claude credentials,
claim packets and fail them — strictly worse than refusing, and the same
boundary that made this product enqueue rather than dispatch at all. So "start
it from the service" is not a missing button; it is a cross-identity problem.

**Auto-start is not auto-approve.** The runner only claims what approval has
already queued, so starting it unattended does not let unsanctioned work begin.
That separation must survive this lane.

**Two thirds of this lane was closed the day it was written; recorded here as
prose because a `[x]` in this file is a mistake, not a record.**

The logon-triggered task **already existed** and this lane was wrong to propose
building it: [`Install-RoadmapTaskRunner.ps1`](scripts/service/Install-RoadmapTaskRunner.ps1)
registers `RepoMgmtRoadmapTaskRunner` as `xfaith` / `LogonType=Interactive` /
`RunLevel=Limited`, unelevated, and it was present and enabled on THESHIRE with
a clean exit from 2026-09-11. The logon start was never the gap.

The gap was recovery, and it is now shipped. The operator stopped the runner at
17:59 UTC to verify the empty-room gate; two hours later nothing had restarted
it, because a logon trigger cannot fire again until they log out. So the queue
had nobody to work it and the console's only advice was a command to paste.
`-RepeatMinutes` (default 5) now sets `$trigger.Repetition` on that logon
trigger. It is safe **only** because `-MultipleInstances IgnoreNew` makes a
repeat a no-op while a runner is alive, and the module smoke fails if either
half is removed — a repetition without that policy would start a second runner
against the same queue. Proved live 2026-09-13: runner up at PID 28224,
`GET /api/roadmap/runner` reporting `state: present` with a 3.4s heartbeat.

That the repeating trigger brings a stopped runner straight back is the INTENDED
behaviour, not a problem to solve. Keeping it running is the service's job. This
also retires the cross-identity question entirely: a LocalSystem caller never
reaches into a user session at all.

**The remaining three shipped 2026-09-13; recorded as prose, because a `[x]` in
this file is a mistake, not a record.**

*The action, not the command.* `POST /api/roadmap/runner/start` and
`POST /api/roadmap/runner/stop`
([`Automation.RunnerControl.ps1`](backend/modules/automation/Automation.RunnerControl.ps1))
replace the pasted remedy everywhere it was offered: the header popover, the
Insights pane, and the empty-room refusal text. The gate itself is untouched —
it was operator-verified and refusing to queue into an empty room is still
right; only the remedy it names changed. The command survives in exactly one
place, beside the error, when the console tried to start a runner and could not.
Three frontend assertions were INVERTED to hold that line: they used to require
the command in the detail and the precondition, and now forbid it.

The host never spawns a runner. It is LocalSystem, and a runner it spawned would
hold no Claude credential and fail everything it claimed. It triggers the
operator-owned scheduled task and lets Task Scheduler make the cross-identity
hop. A start therefore reports REQUESTED, never STARTED: an Interactive task
cannot run while the operator is logged out, so only the heartbeat may say a
runner exists, and the console watches for it and says plainly when it never
arrives.

*The kill switch.* `roadmap-task-runner.hold.json` is the durable half the stop
marker could never be — the marker is consumed by the runner honoring it, so on
its own "stop" would have lasted one repeat interval. The runner reads the hold
before anything else and leaves, making each five-minute repeat a two-second
no-op instead of a revival. It fails CLOSED, the only reader here that does: an
unreadable record still holds, because a corrupt byte must not resume work the
operator deliberately halted. Resuming is releasing it, as designed above — one
start path, not two.

Both control files sit under `REPO_MGMT_RUNNER_CONTROL_ROOT`, the fifth
resolver of its kind. The api-host smoke starts its host with the operator's
REAL workspace root, so without it a gate exercising the stop route would have
stopped their live runner and — a hold being durable by design — kept it
stopped. Same shape as the gate that twice emptied the portfolio index, with a
worse recovery, and asserted rather than assumed: the gate fails if a hold ever
appears in the operator's own output directory.

*One pane.* [`RunnerControlPanel.tsx`](frontend/components/RunnerControlPanel.tsx)
leads the Insights tab with runner state, queued total, claimable now, stranded
count, oldest-queued age, the per-provider backlog and the live runner's
identity — the two facts that arrive on one route and had never been rendered
together. It carries the kill switch, because a control to halt work put
anywhere but where the work is visible asks the operator to decide blind. The
header pill and this pane share one hook, so they cannot disagree.

Proved 2026-09-13 against a real host on 127.0.0.1:7099 with the control root
isolated: stop answered 202 and wrote both files, `GET /api/roadmap/runner`
then reported `stoppedByOperator=true`, start answered 202 with
`holdReleased=true` and `taskTriggered=true`, and the operator's live runner
(pid 28224) kept beating throughout. The module smoke proves the behavioural
half against a real detached runner: a held runner exits 0 without claiming, and
does NOT consume the hold.

**The limit to state plainly rather than design around.** "If the service is
running, start the runner" cannot be wholly true. The service is LocalSystem and
outlives any session; the runner needs the operator's session for their
authenticated Claude Code. So the runner is up whenever they are **logged in**,
not whenever the service is up. When they are logged out the queue accumulates
and nothing works it — which is correct behaviour, and the console must say so
rather than let a growing queue read as progress.

**Not doing, decided 2026-09-13.** Creating a scenario where the runner is down,
purely to watch how the app reacts to a job that is the app's own
responsibility, spends time to learn nothing. If a real case arrives where the
runner is not running and the service fails to start it, the error that case
produces is the thing to read — a rehearsed one would not have told us what the
real one will.

### Lane 0.21 — The portal freezes while it loads (operator evaluation 2026-09-15)

A timed reload: the shell painted in 0.7 s, then the host barely answered for
3 m 33 s. `/api/log/tail` averaged 37 s, `/health/live` peaked at 48 s, and a
reload mid-scan ended in `ERR_TIMED_OUT`. The host accepts one connection at a
time, so any request that holds the thread holds every route. The host log
names the one that did: each `GET /api/portfolio/assessment?scanMode=differential`
ran 60–72 s inline (`prepMs` 50–61 s), and two page loads back to back held it
twice.

**The largest cause was a defect, fixed in the PR that opened this lane.** The
differential decision counted a repository as `local+github` only if the
route's GitHub API list contained it. The assessment and the index also counted
a local repository whose status carries a GitHub `htmlUrl`. `sourceCoverage` is
a fingerprint token, so every repository with a GitHub remote but no API record
never matched and was re-scanned on every load. That was 40 of 59, measured
2026-09-15; on the same data the fix reuses 58, and the 59th has a new commit.
Both sides now use `Get-PortfolioSourceCoverage`.

**The assessment route no longer holds the request thread (verified
2026-09-16, #309, archived).** With nothing changed, a differential load still
ran `prepMs` 28 s inline (22:59 2026-09-14): the route's own GitHub API pass (a
workflow-run call and a Pages lookup per repository) plus scans of changed
roots. That work moved into the background worker, as `GET /api/status` did on
2026-08-11. `Invoke-PortfolioAssessmentScan` holds the former route body, and
only `scripts/Invoke-StatusCacheRefresh.ps1 -RunAssessment` calls it. The route
serves `assessment-cache.json` under the index root, reports `refreshing`, and
keeps one scan in flight. A forced refresh that arrives mid-scan is queued.
`REPO_MGMT_CACHE_ROOT` isolates the scan caches and the worker lock, as
`REPO_MGMT_INDEX_ROOT` does for the index.

**Open items**, in order of what the operator waits on, lead Current focus
after the trial work: `L21-POLL`, `L21-SCANDONE`, `L21-AUTOSCAN`, `L21-LAZY`,
`L21-TIME`, `L21-FIRST`.

### Lane 0.22 — The console disagrees with itself (UX assessment 2026-09-15)

An assessor used build `fa18be4` through the UI only, without reading code or
docs. They went cold reload, every tab, Help, Settings, one repo detail, one
trace, Dispatch history and the agent-run list, and did not press Dispatch, Run
Evaluation, Start runner or Save. The verdict: **the main UX problem is trust,
not layout.** The findings below are the defects. The structural
recommendations (four destinations, one vocabulary, Today as an exception inbox,
one Work pipeline) are product decisions and live in D-022.

**What the session saw.**

- **Repository counts:** 0 (summary cards), 59 (Today), 72 (scan banner), 71
  (execution ledger), 1 (Doc Readiness, a smoke fixture), and 0 in the
  Repository Grid, which asked for a workspace path already set.
- **After a reload:** Today read "No repositories are indexed yet" while
  Operations read "Indexed entries: 59". The Operation Log said "Scan complete.
  No repositories found." and then "Operation completed successfully."
- **One work item:** the list said "Queued for the runner"; its own trace said
  "no queue entry exists … nothing will pick this up"; Insights said "Queued 0".
- **One repository:** "Ready" on the Dispatch Board, "Dispatch Readiness:
  blocked" above "Dispatch Blockers (0)" in its detail, and "L0-Absent" on Today.
  The glossary defines L0-Absent as "No roadmap file present", yet its roadmap
  scores 55.
- **Board labels:** repositories Today marks "always held" for uncommitted
  changes, and a curated-out archived repository, read "Ready" on the board.
- **Unnoticed stuck work:** the runner heartbeat was 27.6 h old, shown as
  "99293.3s". A lane had run 1,655 minutes. A run dispatched six days earlier had
  no branch and no PR.
- **Non-tasks in the work queue:** "Ready" candidates included "Code is
  implemented", "Monorepo structure created", "Work one bounded slice at a
  time.", a "(Deferred) … Not needed for v1" line and truncated fragments.
  One item completed and was re-assigned 17 seconds later.

**Checked against the code and data (2026-09-15).**

- **Test data in the live ledger: confirmed.** 175 of 192 agent-run records in
  the live `output/agent-runs` are `dispatch-success-smoke`. The api-host smoke
  writes the real agent-run ledger and the packaging queue, and also work
  packets, run summaries and the `app.db` mirror. It does not write
  `roadmap-writeback.jsonl`. The write-back ledger is
  `output\roadmap-writeback\history.jsonl`, and the smoke only reaches its
  refusals, which write nothing. (2026-09-16: 251 of 257 packaged items are
  `smoke-packaging-repo`.)
- **"One click, no preview": not true.** The board's Dispatch button opens the
  task preview, not a dispatch. Its "Ready" label still ignores holds.

**Keep as they are:** the work-item trace (a stage-by-stage chain with a named
broken link, the best diagnostic in the product); Leverage's "Not captured yet",
which names missing measurements instead of showing zeros; the "Previews first;
nothing is applied" copy and Private Scope; and Help's "Computed from" lines.

**Open items** lead Current focus, in this order: `L22-FIX`, `L22-ELIG`
(first, ahead of the trial work), then `L22-WORK`, `L22-STUCK`, `L22-SNAP`,
`L22-CTRL`, `L22-LABEL`, `L22-TREND`, `L22-DETAIL`, `L22-GRID`. The
non-blocker stays here:

- [ ] [[README-HIST]] **[non-blocker] README standardization history is read where it is written.** _(state: planned)_
      Found by the fixture-isolation sweep (2026-09-16). The apply step
      treats the target repository as its workspace, so it writes backups and
      `standardization-history.jsonl` under `output\` inside the managed
      repository, while the host reads that history from this workspace's
      output root, so an applied change never shows in its history. Write
      both to the workspace output root, and stop writing into the managed
      repository. Start at
      `backend/modules/docstandardization/DocStandardization.Previewer.ps1`.
      **PR:** review — a suite gate.
      `check: pwsh ./tests/Test-ReadmeStandardizationHistory.ps1 -FailOnError`

---

## 8. Risks and Guardrails

Full list in [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md);
headline guardrails for the active release and near-term roadmap:

- Do not auto-dispatch tasks without a visible readiness model.
- Do not silently mark roadmap items complete based only on code churn.
- Prefer preview-first workflows before write-back or autonomous mutation.
- Preserve genuine completion history when rewriting roadmaps.
- Require a sufficient execution contract before any dispatch — scope,
  acceptance criteria, a runnable verification — sized to repository kind and
  task scope; L3+ roadmap maturity is how roadmap-sourced work supplies it,
  not a universal precondition (changed 2026-08-23).
- Do not treat an AI-improved README or ROADMAP as accepted until the
  operator reviews the side-by-side diff and explicitly applies it.
- Do not show merge readiness unless the app can identify the PR, latest
  Actions result, validation evidence, and unresolved blockers.
- Do not let dashboard badges become decorative; every badge must drill
  into the source data or explanation that produced it.
- Do not merge automatically; merge must remain an explicit operator action
  after readiness passes.
- **Do not leave a control enabled that cannot succeed.** A disabled control
  names its unmet precondition; an enabled one is a promise.
- **Do not mark an item `[x]` while it still names an outstanding proof.**
  Split it: archive the shipped half, keep the unproven half open.
- **A pull request that ships a capability updates the milestone that claims it,
  in the same pull request** (recorded 2026-08-15 after
  [PR #134](https://github.com/xfaith4/GitHubRepoManagement/pull/134) left six
  shipped milestones reading `planned`). Enforced by
  `Test-RoadmapCapabilityRecord.ps1`: a stated rule drifts; a derived one does
  not.
- **A provider limit is state, not an execution failure** (added 2026-09-06
  from the [execution-governance spec](docs/governance/Agent-Execution-Governance.md)).
  Reaching a subscription limit returns the task to the queue with its
  workspace, branch, attempt count and session identifier intact. It must never
  mark the roadmap item failed, and `CAPACITY_WAIT` is a normal operating state.
  Ordinary roadmap work may not consume a provider's configured reserve.
- **Operator approval applies to a verified head SHA, not a pull request
  number.** Any change to the pull request head after verification invalidates
  readiness and requires re-approval. Agent execution may be autonomous;
  promotion to the protected default branch is not.

---

## 9. Roadmap Contract Standard for Managed Repos

The full standard is documented in
[`docs/reference/roadmap-contracts.md`](docs/reference/roadmap-contracts.md),
shipped under [`standards/roadmap/`](standards/roadmap/) (template, schema,
audit rules, maturity model, repair prompt) with the publishable copy under
[`spec/roadmap-contract/`](spec/roadmap-contract/); managed repos converge
toward it.

---

## 10. Definition of Done

**A milestone is done when its `check:` exits 0 in CI on the PR head.** Nothing
else. Everything below is what a `check:` must cover to be admitted, so that the
sentence above stays true:

- the check exercises real behaviour — a route returning mock data fails it
- the check is in the repository and runs under `-FailOnError` in the smoke workflow
- affected docs changed in the same PR when behaviour changed (`Test-RoadmapCapabilityRecord.ps1`)
- the milestone it closes is marked `[x]` and archived in the same PR
- a signal it adds to a dashboard resolves to source data (`Test-BadgeProvenance.ps1`, or add it)

**A release is done when every milestone in it is `[x]`.** Field proof for the
release is a separate line in the operator queue and does not hold the release.

A check you cannot write is a design decision you have not made. Record it in
`open-decisions.md`, take the next item, and do not ask the operator in chat.

---

## 11. Roadmap Structure Validation

Run the validator before handing this file to another coding agent:

```powershell
pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md
```

The check is read-only: release order, missing sections, active-release
pointer/detail mismatches, duplicate headings, archived detail left behind,
oversized future releases, file-length drift. CI runs it with `-FailOnError`:
warnings stay advisory, structural errors fail the smoke workflow.

**The warnings are load-bearing, not decoration.** `R010-FILE-LENGTH` and
`R013-FUTURE-RELEASE-SIZE` caught this file at 2,020 lines on 2026-08-11 — a
roadmap that could no longer answer "what is the next work item?" without a
long read.

<!-- Release 2.7 Phase A — live submit-PR evidence.
     This note was written, committed, pushed, and opened as a pull request by
     POST /api/roadmap/repair/submit-pr (createPr=true) at 2026-08-09 12:43:32 UTC.
     Its existence in a PR IS the Phase A artifact: it proves the write path
     runs end to end against a real repo, not just the dry-run plan. -->
