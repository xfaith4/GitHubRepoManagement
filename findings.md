# Findings

## 2026-07-05 (Release 2.3 Phase 5 planning: repository curation + change-aware indexing)

- The current startup path is still `GET /api/status?stale=true` followed
  by `GET /api/status?refresh=true` in `frontend/App.tsx`. The UI labels
  the second step as a background differential re-scan, but the live route
  contract still performs a fresh status scan there.
- The repo portal already has two parallel data shapes: transient
  `RepoStatus` rows for the Repository Grid and persisted
  `repos.index.json` / Operations payloads for portfolio-aware views.
  Favorites and portfolio-candidate choices should not live only in the
  transient status cache; they need a stable operator-authored store that
  is merged into both read models.
- Existing differential portfolio reassessment is useful but incomplete for
  this feature: it compares a stable fingerprint from the persisted index,
  yet the underlying status adapter does not emit a commit SHA and the
  changed/unchanged merge still keys repos by repo name rather than stable
  repo identity.
- The repo already exposes a better identity seam than repo name alone:
  `Get-OperationsRepoId` derives a stable repo identifier from
  `scanFingerprint`, local path, or GitHub full name. Phase 5 should reuse
  that boundary so curation and change-awareness do not collide on duplicate
  names or folder renames.

## 2026-07-03 (Release 2.3 analytics scaffold)

- Release 2.3 currently has roadmap goals and milestone bullets but no
  phase plan. That makes it hard to start the work without either over-
  claiming broad analytics scope or drifting into unrelated distribution
  work.
- The real dependency chain matters: Release 2.3's promised 90-day trend
  charts depend on Release 2.1 history capture (`maturity_history`,
  `portfolio_index_history`, `merge_readiness_snapshots`) becoming real,
  queryable data rather than empty schema tables.
- A truthful first scaffold is still possible now because the dashboard
  already has a rich `Portfolio Mission` surface and the persistence module
  already defines the future history tables. That supports a forward-
  compatible `GET /api/portfolio/trend` contract with current-snapshot
  fallback instead of a fake 90-day history.
- The scaffold still provides operator value even when the indexed
  portfolio is empty. In that state the route returns a truthful
  `current-snapshot-only` payload with a 1-day window and zeroed summary
  cards, which keeps the dashboard contract stable without inventing data.
- Release 2.3 also overlaps existing report/export surfaces rather than
  replacing them. `Portfolio.Report.ps1` already generates collection-level
  HTML/CSV reports, so trend analytics should layer on top of the current
  portfolio model instead of creating a parallel reporting pipeline.
- Frontend smoke for dashboard analytics needs panel-scoped locators.
  `Portfolio Analytics` intentionally repeats labels like `Avg Maturity`
  across summary and chart cards, so global text probes create strict-mode
  false negatives even when the section has rendered correctly.

## 2026-07-03 (Release 1.2 execution-throughput dashboard card)

- The roadmap item is still truthfully incomplete on this checkout even
  though the backend route and typed client already exist. The current
  dashboard consumer in `frontend/components/Dashboard.tsx` is a one-shot
  mount-time fetch with silent failure handling and no refresh path.
- The existing UI also disappears entirely when the queue is idle because
  it only renders when `totalCompleted > 0` or there are `running` / `ready`
  entries. That means the operator cannot see the execution-throughput
  surface in the zero-state, which does not satisfy "card in the dashboard."
- This repo's Release 1.2 roadmap text has drift elsewhere too: the
  auto-scan indicator is already present in the dashboard header while the
  roadmap still marks that milestone `planned`. That broader cleanup is out
  of scope for this slice unless the user asks for a Release 1.2 sweep.
- Validation environment note: `frontend/scripts/ensure-rollup-native.mjs`
  looks for Rollup's native package under `frontend/node_modules`, but this
  workspace resolves Rollup from the repo-root `node_modules`. That let the
  build fail even though the repo already has a native-package recovery
  script.
- Validation environment note: `scripts/Invoke-FrontendSmokeTest.ps1`
  defaults `WorkspaceRoot` to the Windows `G:\Development\GitHubRepoManagement`
  path. From WSL or any non-`G:` checkout, the smoke must be invoked with an
  explicit `-WorkspaceRoot` override.

## 2026-07-03 (Test-harness: api-host smoke end-to-end reliability)

- The carried-forward "harness hangs at the quota-refusal route" belief was
  wrong. The orphaned host from the last hung run was still alive on port
  7071 eight hours later, and its log showed the 409 quota refusal had been
  delivered and the smoke had continued into the merge-readiness checks —
  which print under the quota step's `[STEP]` banner, creating the illusion
  that the quota route was the blocker.
- On this machine, `http://localhost:<port>` against an IPv4-only loopback
  listener costs ~2,050 ms per request versus ~2 ms for
  `http://127.0.0.1:<port>`: the firewall silently drops `[::1]` connects
  instead of refusing them, so .NET's dual-stack fallback waits out a SYN
  timeout on every request. Any local HTTP harness here should target
  `127.0.0.1` explicitly.
- On pwsh 7.6.3, `Invoke-WebRequest -TimeoutSec` is an alias of
  `-ConnectionTimeoutSeconds` and sets `HttpClient.Timeout`, so it bounds
  the whole request including the connect phase (verified empirically:
  black-holed connects throw at exactly the configured value). Passing both
  parameters fails with "specified more than once".
- `Stop-Job` against a background job whose pipeline is blocked inside a
  native call (e.g. a wedged synchronous socket operation) can block
  indefinitely. Teardown for job-hosted servers must make the process exit
  first (graceful signal, then port-sweep kill) and call
  `Stop-Job`/`Remove-Job` only afterwards.
- Vite emits base64url content hashes, which can contain `-`
  (`index-BbNsaX-S.js`); any "hashed asset" filename regex must allow the
  dash inside the hash segment or immutable caching silently degrades to
  no-cache for a subset of builds.

## 2026-07-03 (Release 2.1 Phase 1: SQLite Persistence Foundation)

- No SQLite execution path existed on this machine beyond the OS itself: no
  `sqlite3` CLI on PATH and no loadable `Microsoft.Data.Sqlite` assembly.
  The dependable zero-install provider is the OS-shipped native library
  (`winsqlite3.dll` ships with Windows 10/11; WSL/Linux/macOS ship
  `libsqlite3`), reached via a compiled `NativeLibrary` + delegate bridge.
  That satisfies the Release 2.1 risk note that provider availability must
  stay reliable on Windows and WSL without adding a package dependency.
- pwsh 7.6.3 gotcha found during implementation: a
  `System.Collections.Generic.List[object]` created with `New-Object` is
  PSObject-wrapped, and `@()` enumeration of PSCustomObject elements then
  fails with `Argument types do not match`, while the same list created
  with `[List[object]]::new()` works. The codebase convention
  (`Execution.Ledger.ps1` et al.) already uses `::new()`; the persistence
  module follows it and returns `.ToArray()`.
- The module smoke chain was broken before this slice started, by the
  2026-06-26 standards-schema commit `db62f0b`, not by Release 2.1 work:
  `DocAudit.Scanner.ps1` strictly dereferenced
  `readmeStandards.recommendedSections`, which the new doc-standards v1
  schema removed (section contracts now live in `ai-doc-templates.json`
  per its `sectionAuthority` note), and the smoke read the renamed
  `version`/`schemaVersion` key from `repo-structure-standards.json`.
- Wiring the new section-authority contract into the doc audit is real
  follow-up work, deliberately not done here: universal-section warnings
  (Overview/License headings) would flip many repos from `ready` to
  `needs-doc-standardization`, which is a product-behavior decision that
  should ship as its own reviewed slice, not ride along in a persistence
  release. This slice only made the scanner StrictMode-safe so old-style
  configs keep their checks and v1 configs skip them.
- The dual-write seam is deliberately additive-only: `Write-AgentRunEvent`
  keeps JSONL authoritative and mirrors via a guarded, non-fatal call that
  no-ops until `Initialize-AppDatabase` succeeds, so JSON-only environments
  and earlier smoke sections behave exactly as before.

## 2026-06-26 (Release 2.0 Closeout / Release 2.1 Promotion)

- The active roadmap snapshot and the detailed Release 2.0 section had
  drifted: section 5 said only closeout remained, but the detailed release
  text still left one Agent Runs milestone unchecked.
- The code confirms that milestone is functionally landed:
  `frontend/components/OperationsWorkspaceView.tsx` already renders
  time-to-deliver, token usage, and work-unit metrics for agent runs. The
  only truthful caveat is that token values stay `n/a` until providers or
  operators supply them.
- Because Release 2.0 already shipped its code-bearing seams on 2026-06-11
  and 2026-06-12, the next bounded slice is documentation closeout, not
  another backend feature. The correct move is archive promotion plus
  activating Release 2.1 with a real Phase 1 current focus.
- The full api-host smoke harness hang after the quota-refusal step is still
  carried context, but it does not block Release 2.0 closeout because
  targeted Phase 4 validation already passed and the hang is documented as a
  broader harness issue.

## 2026-06-12 (Release 2.0 Phase 4: Budget Guard + Scan Annotations)

- The live roadmap and planning files diverged again: `ROADMAP.md` already had Release 2.0 active with Phases 1-3 shipped, while `task_plan.md` was still tracking a completed Release 1.9 slice. The next logical work therefore has to start from the active Release 2.0 Phase 4 seam, not by extending the stale 1.9 plan.
- The smallest truthful remaining seam is backend-first. The repo already has the agent-run ledger, refresh flow, merge-readiness routes, and Operations UI; the missing Phase 4 behavior is budget/quota enforcement before dispatch plus roadmap-derived estimation metadata.
- `Invoke-ParseRoadmapContent` currently only returns checkbox sections, counts, and tags. It does not surface the roadmap template's `Phase plan` table or `Budget guardrail` annotations yet, so dispatch estimates still cannot come from managed-roadmap metadata.
- `New-AgentRunRecord` still hardcodes `workUnitsEstimated = 3`, and `POST /api/roadmap/dispatch/execute` launches Copilot before any budget/quota check. Phase 4 therefore needs to connect roadmap metadata, settings-backed budget config, and the dispatch route in one coherent path.
- The worktree is already dirty with unrelated line-ending churn and other edits (`README.md`, `ROADMAP.md`, `.github/*`, `Start-App.ps1`, `Portfolio.ValueScorer.ps1`, archive docs). Future validation and artifact updates need to stay scoped to touched files instead of assuming a clean tree.
- The first Phase 4 regression after implementation was real: ASCII `-` placeholders in phase-plan `Completed` cells were being treated as completion markers, which erased the active phase from annotated roadmaps. Normalizing placeholder cells fixed the parser and the module smoke.
- The new quota-refusal route works in isolated scratch-port validation, but the broad `Invoke-ApiHostSmokeTest.ps1` harness still does not return after entering that route. That points to an end-to-end harness/runtime interaction, not to missing core Phase 4 logic, so the verification notes need to distinguish those two facts.

## 2026-06-09 (Release 1.8: Operations Prompt Dispatch Tracking)

- The next unfinished Release 1.8 seam was not a new 1.9 capability. The live repo already had prompt refinement history and an older dispatch path, but there was no durable link between a refined Operations prompt and the Copilot run it launched.
- Adding a second history store inside the route body would have made the feature brittle. The safer approach was to append dispatch records alongside the existing per-repo refinement JSONL and merge them in `GET /api/operations/prompt/history` by refinement `runId`.
- The Operations UI did not need a brand-new dispatch modal to close this gap. The refined prompt was already editable in-panel, so the smallest viable slice was to add an explicit Dispatch action there while still requiring operator intent and honoring readiness/maturity gating in the UI.
- The first verification failure was not in the product code. The new smoke regression harness used `Split-Path -LiteralPath ... -Parent`, which PowerShell rejects as an invalid parameter combination; changing that to `-Path` fixed the harness and the full host smoke passed.

## 2026-05-28 (Roadmap Viewer Task-Source Mismatch)

- The ROADMAP modal had a real contract bug: the lower pane could load a local roadmap file successfully while the upper Preview Task / Start Task actions still attempted to rediscover roadmap content through the GitHub repository field.
- The failure was not in roadmap parsing. `RoadmapViewerModal.tsx` never passed the already-loaded local `content.path`, and `Start-RoadmapCopilotTask.ps1` treated every `-RoadmapPath` candidate as a GitHub contents path instead of honoring an explicit local file first.
- That mismatch produced the contradictory operator experience shown in the bug report: a visible roadmap in the modal plus a "No roadmap markdown file found in repository ..." error in the task-preview area.
- The fix path is now explicit and regression-covered: the modal passes the loaded local roadmap path, and the roadmap-agent script prefers a real local file before any GitHub lookup.

## 2026-05-28 (Release 1.8 Phase 1: Operations Workspace Foundation)

- Release 1.8 did not need a fresh UI buildout first. The live repo already had an Operations tab, an `OperationsWorkspaceView`, frontend types, and client wiring, so the real product gap was the missing backend route and proof that the view consumed a stable indexed model.
- The safest backend implementation was to reuse the persisted portfolio index instead of recomputing another repo-detail model in parallel. That kept the Operations workspace aligned with the same lifecycle, ranking, and GitHub signals already used by Portfolio Mission and Work Queue.
- A hard failure when the index was absent would have made the Operations tab fragile during startup or cache warmup. The route therefore needed an assessment-cache fallback so a recent portfolio warm path could still power the workspace.
- The most important validation point for this slice was not just PowerShell parse success. It was expanding `Invoke-ApiHostSmokeTest.ps1` so `/api/operations/repos` is exercised after `/api/portfolio/assessment`, proving the persisted-index handoff is live.

## 2026-05-28 (Phase 7B)

- The next real gap after differential scan completion was not another assessment tweak; the roadmap called for a collection-level reporting surface backed by the portfolio model, and the live app still exported only a generic repo-status snapshot.
- Replacing `/api/export` outright would have been a behavioral regression for non-portfolio scenarios, so the safe slice was to extend it for `portfolioEntries` while keeping the older repo-status path as a fallback.
- The documentation gap was real user-facing scope, not cleanup. Help, API reference, and the portfolio assessment reference all needed to describe the same scan → classify → rank → refine prompt → dispatch → report loop or the product story would remain internally inconsistent.
- Parser and build success were not enough for this phase because the risk was runtime wiring. The important proof point was the API smoke path opening the saved HTML report and confirming it served Collection Status Report content.

## 2026-05-28 (Phase 6)

- The next real gap after the expanded evaluator was not a new route. The repo already had a `CopilotTaskPacket` preview path, but it only carried roadmap-item, doc-finding, acceptance-criteria, and guardrail basics.
- Phase 6 required enriching that existing packet in place with README context, release context, lifecycle and scoring context from portfolio assessment, explicit constraints, and value rationale.
- The older task-preview flow still selected the first pending roadmap item by file order. Phase 6 was the right place to teach the packet builder to prefer the portfolio-ranked top-value item when that context is available.
- API smoke initially looked like a contract failure, but the live `/api/copilot-task/preview` payload already contained the new fields; the real issue was that the smoke check treated an empty `constraints` array as "missing".

## 2026-05-28

- The live repo evaluator was still effectively hardening-first; Release 1.7.5 Phase 5 required broader opportunity detection for missing-roadmap repos, not just structural gap reporting.
- Phase 5 was not only about more findings. The roadmap also needed the generated draft roadmap to separate foundational hardening from user-value and modernization work so the output could drive realistic execution ordering.
- The frontend repo-evaluation surface and help text still described the feature as a structure/hardening tool, so the UI contract needed to expand alongside the backend.
- Full-module verification exposed an unrelated pre-existing failure later in the portfolio-assessment smoke path (`The term 'if' is not recognized...`), so the Phase 5 evidence had to rely on the new evaluator smoke step, targeted evaluator execution, and the frontend production build.

## 2026-05-27

- `ROADMAP.md` and live code diverged: the roadmap already claimed Phase 3C shipped, but `WorkQueueView.tsx` still ignored the assessment value model and sorted only by docs-audit readiness.
- The smallest real next slice was Release 1.7.5 Phase 4, not a new release: consume `topValueItem` in Work Queue, show the rationale, and rank ready repos by value.
- Work Queue refresh behavior would have left stale value rankings in place because `getDocsAudit(true)` did not also invalidate `getPortfolioAssessment()`.
- Frontend verification was initially blocked by a missing Rollup optional dependency in `node_modules`, which the repo-local `npm run install:frontend` path repaired cleanly.

## 2026-04-26

- `ROADMAP.md` says the active release is `1.7.5` and Phase 2 is the next active target.
- Phase 2 scope is `Portfolio.ValueScorer.ps1`, `value-scoring.json`, and value score on each pending item in the assessment response.
- Existing worktree is heavily dirty with unrelated changes; edits must be scoped and avoid reverting user work.
- Existing portfolio assessment backend is `backend/modules/portfolio/Portfolio.Assessment.ps1`.
- Existing module smoke coverage for portfolio assessment starts around `scripts/Invoke-ModuleSmokeTest.ps1` release 1.7.5 section.
- Assessment entries now need additive fields only to preserve existing UI/API consumers: `pendingItems` and `topValueItem`.

## 2026-07-12

Existing Dispatch & Task-History Code Map

1. scripts/Start-RoadmapCopilotTask.ps1 (the orchestrator)
   Params (lines 1–33): -Repository (default "OWNER/REPO"), -BaseBranch, -CustomAgent, -Follow (switch), -PreviewOnly (switch), -HistoryRoot, -RoadmapPath, -RoadmapPathCandidates (default list: ROADMAP.md, Roadmap.md, docs/planning/roadmap.md, docs/ROADMAP.md, roadmap.md).

Flow:

Initialize-HistoryStore (38–63) creates output\roadmap-task-history\ + runs\, mints a runId = yyyyMMdd-HHmmss-<8hexguid>, and returns paths for history.jsonl, <runId>.events.jsonl, <runId>.summary.json.
Roadmap resolution: if -RoadmapPath given → Get-LocalRoadmapContent (134) reads it locally; otherwise Get-GitHubRoadmapContent (169) pulls it via gh api repos/{repo}/contents/{path} and base64-decodes.
Get-NextRoadmapTask (247–331) picks the first unchecked - [ ] item by heading priority (active/next, near-term, must, mid-term, long-term, technical debt), skipping process sections.
Task packet = a plain-text $taskDescription array (375–393): "Continue roadmap execution for $Repository.", "Roadmap source: <path> (line N, section '<H>').", "Primary task: <text>", a 4-item "Execution requirements" block, and up to 3 "Follow-up candidates". This is the string shown in the preview UI's textarea.
Does it call Start-GitHubCopilotTask.ps1? Yes. Lines 405–408 resolve Join-Path $PSScriptRoot 'Start-GitHubCopilotTask.ps1'; lines 410–418 build a $startParams hashtable (Repository, TaskDescription, HistoryRoot, ParentRunId=$runId, InitiatedBy='roadmap-script', RoadmapSourcePath, PrimaryRoadmapTask, plus optional BaseBranch/CustomAgent/Follow); and line 493 invokes it: & $startScriptPath @startParams.

Preview vs Start branch: If -PreviewOnly (435–483) it emits a JSON $previewPayload (runId, repository, roadmapPath, selectedTask{heading,lineNumber,text}, followUpCandidates, generatedTaskDescription, history paths) to stdout and writes a status='preview' summary — it does NOT call the launcher. Otherwise it calls the launcher (493) and writes a status='started' summary.

1b. scripts/Start-GitHubCopilotTask.ps1 (the actual dispatcher)
The external command that dispatches is gh agent-task create, assembled at lines 207–226 and executed at line 231 via Invoke-GhCommand (which shells & $script:GhCommandPath @Args, line 144):

$ghArgs.Add("agent-task"); $ghArgs.Add("create"); $ghArgs.Add($TaskDescription)
$ghArgs.Add("--repo"); $ghArgs.Add($Repository)

# optional: --base $BaseBranch, --custom-agent $CustomAgent, --follow

It requires GitHub_Token/GITHUB_TOKEN (184–193), resolves gh.exe (Resolve-GhCommandPath, 48), runs gh auth status, then gh agent-task create. This is the single line to replace with a queue-writer. It logs a copilot_result event (233) and writes its own status='success'/'failed' summary.

1. Task-history store
   Get-RoadmapTaskHistory — backend/api-host/Start-RepoManagementApiHost.ps1:3538. Reads output\roadmap-task-history\runs\*.summary.json (NOT the jsonl), sorted by LastWriteTime desc, and projects each into: runId, status, repository, selectedTask, roadmapPath, startedAt, completedAt, error, summaryPath (3561–3571).

Writers live in the two scripts, not the API host:

Write-HistoryEvent (both scripts, e.g. Start-RoadmapCopilotTask.ps1:65) appends one compact JSON line to BOTH history.jsonl (shared, append-only) and <runId>.events.jsonl (per-run). Event record shape: { timestamp(o), runId, type, data{} }. Event type values seen: run_started, local_roadmap_read_started/completed, api_call_started/completed, roadmap_selection, preview_generated, copilot_task_start_requested, copilot_result, run_completed, run_failed.
The <runId>.summary.json is what the UI reads. Confirmed shape (from output/.../runs/20260706-160310-c0eba7b6.summary.json):

{ "runId":"20260706-160310-c0eba7b6", "status":"preview",
"startedAt":"...o...", "completedAt":"...o...",
"repository":"smoke-owner/smoke-repo", "roadmapPath":"F:\\...md",
"selectedTask":"A pending fixture item to preview.",
"historyEventsPath":"F:\\...\\<runId>.events.jsonl" }
status ∈ preview | started | success | failed. The UI line 20260712-035858-d1b813ca / xfaith4/AdministatorTools / <task> / preview|failed maps directly to runId / repository / selectedTask / status.

Files/dir: root output\roadmap-task-history\; shared log history.jsonl; per-run runs\<runId>.events.jsonl + runs\<runId>.summary.json.

1. Task-prompt / packet builder — backend/modules/roadmap/Roadmap.Dispatcher.ps1
   Note: there are TWO prompt systems. The # Copilot Task: Implement ... prompt at line 297 is \_BuildDispatchPrompt (287–360), used by the release-level dispatch (RoadmapDispatchModal / Build-ReleaseDispatchPacket), which is a separate flow from the roadmap-agent Preview/Start scripts above.

Get-NextPendingRelease (111–201): parses ## Release X.Y — Title blocks, returns first block with an unchecked - [ ]; output includes releaseName, releaseVersion, releaseTitle, goal, pendingMilestones[], completedMilestones[], acceptanceCriteria[], outOfScope[], counts.
Build-ReleaseDispatchPacket (228–285): inputs RepoName, RoadmapContent, RoadmapPath, GitHubRepo, AuditContract. Returns a packet: packetVersion='2.0', packetId, createdAt, repoName, githubRepo, roadmapPath, releaseName, releaseVersion, releaseGoal, pendingMilestones[], acceptanceCriteria[], outOfScope[], generatedPrompt, maturityLevel, maturityScore. This is the richest reusable structure for a queue entry.
\_BuildDispatchPrompt (287–360): assembles the markdown prompt — # Copilot Task: Implement <release> for <repo>, ## Repository Context (Repository/Roadmap/Release/Goal), ## Engineering Milestones to Implement (numbered [ ] list), ## Acceptance Criteria, ## Guardrails (Out of Scope…), ## Execution Requirements (5 steps incl. "Create a PR titled …").
Resolve-GitHubRepoIdentity (378–446): local clone → owner/repo via git -C <path> remote get-url origin, regex github\.com[/:]([^/]+)/([^/.]+). 4. Repo-name → local filesystem path resolution
Two mechanisms, both in Start-RepoManagementApiHost.ps1:

Resolve-RoadmapPathForRepo (3800–3827): given RepoName, optional LocalPath, and a RoadmapEntry, returns the roadmap file. Prefers RoadmapEntry.roadmapPath if it exists; else probes LocalPath for ROADMAP.md, Roadmap.md, docs\planning\roadmap.md, docs\ROADMAP.md, roadmap.md.
GET /api/roadmap/content route (6677–6719): the actual source of the preview UI's Roadmap source: path. Given repo, it runs/reads the roadmap scan index (Get-RoadmapFromCache / Invoke-RoadmapScan, 6689–6690), finds $\_.repoName -eq $repoName, and takes $match.roadmapPath (6691–6692). Returns { repoName, content, path, sizeBytes, lastModified }. The scan index entries carry both roadmapPath and (per the README route at 6732) localPath — so roadmapPath's parent directory is the target repo's local checkout (e.g. F:\Development\20_Staging\AdministatorTools\).
Important for the pivot: The preview/start API routes do NOT resolve the local path themselves. POST /api/roadmap-agent/preview (6552–6577) and POST /api/roadmap-agent/start (6578–6610) only read repository, baseBranch, customAgent, roadmapPath, follow from the body and forward them as args to Start-RoadmapCopilotTask.ps1 via Invoke-PowerShellScriptFile. The roadmapPath is supplied by the frontend, which got it from getRoadmapContent (content.path). The start route then reads back Get-RoadmapTaskHistory -Limit 1 for latestHistory (6598–6607). So a queue-writer replacing the gh dispatch would sit inside Start-GitHubCopilotTask.ps1 (or the start route), and the target repo's working dir = Split-Path -Parent $roadmapPath.

1. Frontend dispatch UI
   The modal you described ("Preview Task / Start Task / Refresh History", disabled "Run AI Agent") is frontend/components/RoadmapViewerModal.tsx — NOT RoadmapDispatchModal.tsx (that's the separate release-to-Copilot flow).

State + handlers: handlePreviewTask (86–106), handleStartTask (108–128), loadHistory (61–71). Both pass roadmapPath = content?.path (the locally-loaded roadmap) into the request.
API calls (frontend/services/apiClient.ts): previewRoadmapTask → POST /roadmap-agent/preview (768–774); startRoadmapTask → POST /roadmap-agent/start (776–786), returns {message, output, latestHistory}; getRoadmapTaskHistory(limit) → GET /roadmap-agent/history?limit= (788–790). Roadmap content via getRoadmapContent(name) → GET /api/roadmap/content.
History render (277–289): maps taskHistory to rows showing item.runId (mono), item.status (red if failed, else green), item.repository, item.selectedTask.
The "Copilot task preview issue / Failed to fetch" warning (245–256): isTaskError (line 142) = taskMessage matches /failed|error|not found|not installed|required/i. Header text toggles "Copilot task preview issue" vs "Copilot task preview" (248); a red sub-note (251–255) references content?.path. taskMessage is set to the caught error string in the handlers.
"Run AI Agent" (173–178) is a disabled <span> labeled "AI Agent — Phase 2 coming soon" — a placeholder, not wired to anything yet. 6. Existing queue / runner / append-only JSONL patterns to model on
Execution ledger — backend/modules/execution/Execution.Ledger.ps1: two-lane state machine with states idle | ready | running | blocked | complete (header 6–16), single JSON doc at output\execution\execution-ledger.json (Get-ExecutionLedgerPath, 35–46) with {schemaVersion, updatedAt, entries[], history[]}; Read-ExecutionLedger (53) / Write-ExecutionLedger (109), optional SQLite bridge (Read/Write-AppDbExecutionLedger). This already models "at most two repos running / no duplicate dispatch" — closest thing to a queue today.
Append-only JSONL run history — backend/modules/automation/Automation.DocRefinement.ps1: $AutomationRunsRelPath = 'output/automation/automation-runs.jsonl' (24); Write-AutomationRunRecord (201–224) appends one compact JSON line via Add-Content -Encoding UTF8; Get-AutomationRunHistory (226+) reads it with a limit. Clean template for a task-queue.jsonl writer/reader. (Note its preview-first guardrail at 214–216.)
Roadmap-agent history JSONL — the Write-HistoryEvent dual-append pattern (§2) is the existing per-run event log to reuse.
Roadmap-events contract/spec — spec/roadmap-contract/roadmap-events.md, standards/roadmap/roadmap-events.md (append-only event schema docs).
Agent HTTP protocol — docs/reference/agent-api.yaml defines /api/v1/agent/\*; frontend WorkQueueView.tsx and OperationsWorkspaceView.tsx already render queue/work views. Persistence primitives in backend/modules/persistence/Persistence.Store.ps1.
Other JSONL stores under output\: roadmap-task-history\prompt-refinements\<Repo>.refinements.jsonl and ai-doc-improvements\<Repo>.improvements.jsonl — same per-repo append-only convention.
Quick pointers for the pivot
Queue-writer replaces the gh agent-task create block (Start-GitHubCopilotTask.ps1:207–231); everything else in both scripts (history store init, Write-HistoryEvent, summary.json emission) can be kept so the existing Get-RoadmapTaskHistory + UI keep working unchanged.
Target local working dir for a claude runner = parent of the resolved roadmapPath (from GET /api/roadmap/content / Resolve-RoadmapPathForRepo); GitHub slug (if needed) via Resolve-GitHubRepoIdentity.
The reusable prompt/packet content is either the plain generatedTaskDescription (Start-RoadmapCopilotTask.ps1:375–393) or the richer Build-ReleaseDispatchPacket structure (Roadmap.Dispatcher.ps1:228–285).
