<!-- markdownlint-disable MD036 -->
<!--
  MD036 (emphasis-as-heading) is disabled for this file only. A packet's
  **Why** / **Scope** / **Steps** / **Gate** / **Stop if** labels are a fixed
  form the executing agent matches on, not section headings: promoting them to
  real headings would flood the document outline and break R1's reading budget.
  Every other rule applies normally.
-->

# Haiku Work Packets — GitHubRepoManagement

> **Derived from:** `ROADMAP.md` as of 2026-09-06. This file is a *rendering* of
> that roadmap for a small executing model. `ROADMAP.md` stays the source of
> truth. If the two disagree, **stop and report** — do not reconcile them.
>
> **Who this is for:** an autonomous coding agent (Claude Haiku 4.5 or similar)
> working one packet at a time in Claude Code. Each packet is a bounded unit:
> named files, numbered steps, a gate that must be red before it is green, exact
> verification commands, and a written stop condition. Nothing in a packet
> requires a judgement call; where the roadmap left one, this file either made
> it (and says so) or excluded the item (§3).

---

## 0. Operating rules — read in full at the start of every session

**R1. Reading budget.** Read, in this order and nothing else unless a packet
names it: this §0, `ROADMAP.md` §8 (Risks and Guardrails), the packet you are
executing, and the roadmap item text that packet links to. Do **not** read
`docs/history/completed-releases.md`. Do not read `ROADMAP.md` end to end.

**R2. Scope is a whitelist.** A packet lists the paths you may edit. If the
task appears to need an edit anywhere else, stop and report (R9). Reading any
file is always allowed.

**R3. Never mark `[x]`.** You change a roadmap item only as its packet's
*Roadmap write-back* section instructs, and only the state string inside
`_(state: …)_`. The two exceptions (H-01, H-02) spell out the archive move
step by step.

**R4. Gate red first, always.** Every packet has a gate. The order is fixed:
(1) write the test or fixture, (2) run it against the unchanged code, (3)
confirm it **fails with the message the packet predicts**, (4) implement,
(5) run again, (6) confirm it passes. If step 3 passes instead of failing, the
gate is vacuous — stop; do not proceed to step 4.

**R5. Discovery steps are exact-match.** When a step says *locate X using
pattern P*, run the search. If it returns **zero** matches or **more than one**
where one is expected, stop and report the matches. Never pick one.

**R6. Branch and PR hygiene.**

- Start from a clean tree: `git status --porcelain` must print nothing.
- Branch name: `haiku/<packet-id>-<short-slug>`, e.g. `haiku/H-04-scan-retention`.
- One packet per PR. The PR body is the *Report* block from R9.
- The same PR that ships a capability updates its roadmap item (§8 guardrail).

**R7. Verification commands.** Run after every packet, in this order. Any
failure that is not the packet's own gate is a stop condition.

```powershell
pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md
pwsh ./scripts/Invoke-TestSuite.ps1
```

Plus, when `frontend/` was touched:

```powershell
npm run typecheck
npm run lint
npm run test:unit
```

If `Invoke-TestSuite.ps1` takes parameters you do not know, read the script's
header comment. Do not guess flags. Two **known environmental failures** are
not regressions and must not be "fixed": the api-host smoke asserting no
runner is present while the operator's runner is alive (H-05 fixes this), and
anything on port 7071 (the smoke uses 7171; never pass 7071).

**R8. Never run these.** Anything requiring elevation (`Install-*.ps1`,
`Enable-SharedLanAccess.ps1`, service restarts, `schtasks`), anything against
the live portal at `https://127.0.0.1:7071`, `gh auth login`, `git push --force`,
or any command that edits `backend/config/settings.json` on the operator's
tree. These are operator actions (§3).

**R9. Report format.** Written to `output/haiku/<packet-id>.md` and pasted as
the PR body. Every section is mandatory; "none" is a valid value.

```text
Packet: H-NN — <title>
Branch: haiku/H-NN-<slug>
Gate: RED at <commit/step> with message "<...>" → GREEN at <commit>
Files changed: <list>
Roadmap write-back: <the exact state string now on the item>
Verification: <each R7 command and its result>
Deviations from packet: <none | list>
Blockers: <none | what stopped you, what you saw, what you did not do>
```

**R10. Time box.** A packet that is not green after the number of attempts its
*Stop if* section allows is reported as blocked, with the last failing output
attached. A blocked packet is a normal outcome, not a failure.

---

## 1. Packet index (execute in this order)

Ordering is by dependency and then by risk: mechanical packets first, so a
problem with the environment surfaces before a problem with the code.

| Id | Title | Roadmap source | Decision basis | Risk |
| --- | --- | --- | --- | --- |
| H-01 | `.gitattributes` with LF normalization | Lane 0.8 | roadmap states the fix | low |
| H-02 | Archive Lane 0.17's eight closed items | Lane 0.17 | archive rule §3 | low |
| H-03 | `settings.json` stable key order; no write when unchanged | Lane 0.14 | roadmap states the fix | low |
| H-04 | Retention for `output/index/scans/` snapshots | Lane 0.10 | **decided here: cap-in-writer** | low |
| H-05 | Runner heartbeat path override for the smokes | Lane 0.8 + 0.17 | pattern of `REPO_MGMT_QUEUE_PATH` | low |
| H-06 | Dialog dismiss contract in the remaining modals | Lane 0.14 | roadmap states the fix | low |
| H-07 | Dispatch authority restricted to the Dispatch Board | Lane 0.17 | D-008 | medium |
| H-08 | `nested` scope classification | Lane 0.12 | D-002 | medium |
| H-09 | External-history awareness metadata | Lane 0.7 | D-005 | medium |
| H-10 | Check-run detail with `mergeStateStatus` fallback | Lane 0.2 | D-003 | medium |
| H-11 | Stale browser-persisted GitHub owner | Lane 0.9 | roadmap states the fix | medium |
| H-12a | Button-palette ratchet rule (measure + baseline only) | Lane 0.14 | roadmap states the fix | low |
| H-13a | Roadmap dependency notation: schema + parser + audit | Lane 0.18 | D-001 | high |
| H-13b | Dependency-aware next-item selector | Lane 0.18 | D-001 | high |

Everything not in this table is in §3, with the reason.

---

## 2. Packets

### H-01 — `.gitattributes` with LF normalization

**Roadmap item:** Lane 0.8, `[non-blocker] No .gitattributes, with core.autocrlf=true`.

**Why:** byte comparisons differ between local (CRLF) and CI (LF) checkouts.

**Scope (edit only):** `.gitattributes` (new), `ROADMAP.md`, `docs/history/completed-releases.md`, `CHANGELOG.md`.

**Steps**

1. Confirm no `.gitattributes` exists at the repo root. If one exists, stop.
2. Create `.gitattributes`:

   ```text
   * text=auto eol=lf
   *.cmd text eol=crlf
   *.bat text eol=crlf
   *.ps1xml text eol=lf
   *.pfx binary
   *.cer binary
   *.png binary
   *.jpg binary
   *.ico binary
   *.woff binary
   *.woff2 binary
   ```

3. Run `git add --renormalize .` then `git status --porcelain | Measure-Object -Line`. Record the count. A large count is **expected** (every CRLF file rewrites). Commit this renormalization **alone**, message `chore: normalize line endings via .gitattributes`.
4. Run R7. The roadmap's own logic fingerprint is CRLF-insensitive by design, so no index should read stale from this change; if the smoke reports staleness attributable to line endings, stop and report — that is a finding, not something to patch.

**Gate (red first):** on the unchanged tree, `git ls-files --eol | Select-String 'w/crlf'` returns lines. After step 3 it returns none for text files.

**Roadmap write-back (archive move — the R3 exception):** nothing remains on this item, so it leaves the roadmap. (a) Copy the item's bullet **verbatim** to the end of `docs/history/completed-releases.md` under a new heading `## Lane 0.8 — .gitattributes (archived <date> from ROADMAP.md)`, appending  `_(state: done <date> — renormalized <N> files)_` to it. (b) Delete the bullet from `ROADMAP.md`. (c) Add one line to `CHANGELOG.md` under today's date. Run the validator (R7).

**Stop if:** step 3 changes any file under `backend/config/tls/` or any `*.pfx` (binary marked wrong); or the validator reports a new error.

---

### H-02 — Archive Lane 0.17's eight closed items

**Roadmap item:** Lane 0.17, `[non-blocker] Archive this lane's eight closed items…`.

**Why:** the roadmap's rule is that it carries open work only; eight `[x]` items have sat in Lane 0.17 since 2026-08-30 and drive the `R010-FILE-LENGTH` warning.

**Scope (edit only):** `ROADMAP.md`, `docs/history/completed-releases.md`, `CHANGELOG.md`.

**Steps**

1. In `ROADMAP.md`, find the section heading beginning `### Lane 0.17`. Count top-level bullets in that section that start with `- [x]`. **The count must be exactly 8.** If it is not, stop and report the count and the first line of each.
2. Open `docs/history/completed-releases.md`. Read only its last 40 lines to learn the heading style in use. Append a heading `## Lane 0.17 — closed items (archived <date> from ROADMAP.md)` followed by a one-paragraph copy of the lane's intro paragraph (the one beginning `An operator evaluation of the Copilot Execution Lanes tab…`) and then the eight bullets **verbatim** — every character, including their `_(state: …)_` text and nested content.
3. In `ROADMAP.md`, replace the eight bullets with a single line: `- Eight items closed 2026-08-30 → 2026-09-06 (route errors over TLS, roadmapPath carriage, modal dispatch, filtered queue, tab rename, sparse-repo crash, array-collapse sweep, lane observation) — [archived](docs/history/completed-releases.md#lane-017--closed-items-archived-<date>-from-roadmapmd).` Adjust the anchor to whatever slug the existing archive anchors use (read two existing anchors to match the convention).
4. Delete the `[ ] [non-blocker] Archive this lane's eight closed items…` bullet itself — it is now done.
5. `CHANGELOG.md`: one line under today's date, `Roadmap: archived Lane 0.17's eight closed items to completed-releases.md.`
6. Run the validator (R7). `R010-FILE-LENGTH` should report a lower line count than before; record before/after in the report.

**Gate (red first):** before step 3, `Select-String -Path ROADMAP.md -Pattern '^- \[x\]' | Measure-Object` counts ≥ 8 inside the Lane 0.17 range. After, it counts 0 inside that range.

**Roadmap write-back:** steps 3–4 above. Do **not** touch `[x]` items in any other lane (Lanes 0.2, 0.8, 0.11, 0.12, 0.13, 0.14, 0.15, 0.16 also hold some). Report their count under *Deviations* so the operator can schedule a second archive packet.

**Stop if:** the count in step 1 is not 8; or the validator reports a new *error* (a warning is fine).

---

### H-03 — `settings.json`: stable key order, and no write when unchanged

**Roadmap item:** Lane 0.14, `Write settings.json with a stable key order, and not at all when nothing changed.`

**Why:** the host rewrites the tracked file with keys reordered and no value changed, so the tree is dirty every session.

**Scope (edit only):** `backend/api-host/Start-RepoManagementApiHost.ps1`, the file that defines `Get-PortalSettingsPath` (discover in step 1), the module-smoke script, `ROADMAP.md`.

**Steps**

1. Locate `function Get-PortalSettingsPath` (exactly one definition). Note its file; a sibling `Write-PortalSettings` will live there.
2. Locate every site that **writes** the settings file: search `backend/` for `Set-Content|Out-File` on lines within 5 lines of a `Get-PortalSettingsPath` call, and for `ConvertTo-Json` feeding them. The roadmap names two writers in the api-host (setup config write; `POST /api/settings`). If you find more than three writers, stop and list them.
3. For each writer, record the `ConvertTo-Json -Depth N` value in use. If any writer omits `-Depth`, record "default (2)". You will preserve the **largest** N found.
4. Add `Write-PortalSettings -Path <string> -Settings <object>` beside the resolver. It must:
   - Convert the object to an `[ordered]` hashtable **recursively**, sorting keys with `[StringComparer]::Ordinal` at every level; arrays keep their order.
   - Serialize with `ConvertTo-Json -Depth <largest N from step 3>`.
   - If the target file exists and its content (read as UTF-8, line endings normalized to `\n`) equals the new content, **return without writing**, and emit `Write-Verbose "settings unchanged; skipped write"`.
   - Otherwise write with the same encoding the current writers use (read one to find out; do not change encoding).
5. Route every writer from step 2 through `Write-PortalSettings`. No other behaviour changes.

**Gate (red first) — module smoke, new section `Settings write stability`:**

- Fixture: a temp settings path via `REPO_MGMT_SETTINGS_PATH`. Write object A. Write the same values with top-level and nested keys permuted. Assert the file bytes are identical after both writes **and** `LastWriteTime` did not change on the second write.
- Predicted red message on the unchanged code: the bytes differ (key order) — assertion 1 fails.
- Also assert a value change **does** produce a write (so the skip cannot be a no-op).

**Roadmap write-back:** on the item, replace `_(state: planned)_` with `_(state: smoke-tested <date> — Write-PortalSettings sorts keys recursively and skips byte-identical writes; gated by the "Settings write stability" module-smoke section)_`.

**Stop if:** step 2 finds a writer that does not go through `Get-PortalSettingsPath` (that is a regression of Lane 0.8's fix — report it, do not fix it here); or the smoke shows any other settings assertion changed.

---

### H-04 — Retention for `output/index/scans/portfolio-scan-*.json`

**Roadmap item:** Lane 0.10, `[non-blocker] Give output/index/scans/portfolio-scan-*.json a retention rule.`

**Why:** one snapshot per scan, nothing prunes; 762 files / 103 MB accumulated.

**Decision made here (the roadmap offered two):** cap the directory at the N newest **in the writer**. Reason: `Ledger.Retention.ps1` is line-based over JSONL ledgers; adding a whole-file target changes its model. Default N = **50** (≈ one week at the observed ~7 scans/day), exposed as a parameter so the gate can set it low.

**Scope (edit only):** `backend/modules/portfolio/Portfolio.Assessment.ps1`, the module-smoke script, `ROADMAP.md`.

**Steps**

1. Locate `function Save-PortfolioIndexArtifacts` (exactly one). Find the statement that writes `portfolio-scan-*.json`.
2. Add a parameter `[int]$ScanSnapshotRetainCount = 50` to the function. Validate `>= 1`.
3. Immediately **after** the new snapshot is written successfully, enumerate `portfolio-scan-*.json` in the same directory, sort by `LastWriteTimeUtc` descending, and remove every file past index `$ScanSnapshotRetainCount - 1`. Wrap removal in `try/catch`; a failed delete is logged with the file name via the module's existing logging function (discover its name from the surrounding code) and does not fail the scan.
4. Do not touch how the snapshot itself is written.

**Gate (red first) — module smoke, new section `Scan snapshot retention`:**

- Fixture dir. Write 8 snapshot files with `LastWriteTimeUtc` set to 8 distinct past minutes. Call `Save-PortfolioIndexArtifacts -ScanSnapshotRetainCount 7` with a minimal valid index payload (copy the shape an existing smoke section already passes to this function).
- Assert: 7 files remain; the missing one is the oldest by time; the newest (just written) is present.
- Predicted red message on unchanged code: 9 files remain / parameter does not exist.

**Roadmap write-back:** replace `_(state: planned)_` with `_(state: smoke-tested <date> — Save-PortfolioIndexArtifacts keeps the newest 50 snapshots (parameter ScanSnapshotRetainCount); gated by "Scan snapshot retention")_`.

**Stop if:** `Save-PortfolioIndexArtifacts` writes snapshots to more than one directory; or an existing smoke assertion counts files in that directory.

---

### H-05 — Runner heartbeat path override for the smokes

**Roadmap items:** Lane 0.8 `[non-blocker] Isolate the runner heartbeat…` and the duplicate in Lane 0.17 `[non-blocker] The api-host smoke fails on any machine where the operator is actually running a runner.`

**Why:** the presence route reads the real `output/roadmap-task-runner.heartbeat.json`; a live runner makes the api-host smoke's *no runner present* assertion fail on an untouched tree. The queue (`REPO_MGMT_QUEUE_PATH`) and settings (`REPO_MGMT_SETTINGS_PATH`) already solved this exact shape.

**Scope (edit only):** the file that defines `Get-RoadmapQueuePath` (discover), `backend/modules/automation/Automation.RunnerPresence.ps1`, `scripts/Invoke-RoadmapTaskRunner.ps1`, `backend/api-host/Start-RepoManagementApiHost.ps1` (only if it constructs the heartbeat path inline), `scripts/Invoke-ApiHostSmokeTest.ps1`, the module-smoke script, `ROADMAP.md`.

**Steps**

1. Locate `function Get-RoadmapQueuePath` (one). Read it; copy its shape exactly for `Get-RoadmapRunnerHeartbeatPath -WorkspaceRoot`, honouring env var `REPO_MGMT_RUNNER_HEARTBEAT_PATH`, falling back to `<workspace>\output\roadmap-task-runner.heartbeat.json`.
2. Search the whole repo (excluding `docs/`, `evidence/`) for the literal `roadmap-task-runner.heartbeat.json`. Every hit that **constructs a path** must be routed through the new resolver. Expect hits in the runner (writer) and the presence module and/or api-host (reader). List all hits in the report.
3. In `Invoke-ApiHostSmokeTest.ps1`, set `REPO_MGMT_RUNNER_HEARTBEAT_PATH` to a path under its existing `output/smoke/api-host/…` isolation directory, in the same place and manner it sets `REPO_MGMT_QUEUE_PATH`. Restore it on exit the same way.
4. Extend the module-smoke *inline path construction* gate (the one Lane 0.8 added for settings) so an inline heartbeat path build under `backend/` or `scripts/` (other than the resolver and the operator-only paths it already exempts) is refused.

**Gate (red first):**

- Module smoke: create a heartbeat file at the default path inside a fixture workspace **and** set the override to a path with no file → the presence function reports no runner. Predicted red on unchanged code: reports a runner present.
- Injection: re-add one inline `Join-Path … 'roadmap-task-runner.heartbeat.json'` under `backend/` → the inline-path gate names the file. Remove it after confirming.

**Roadmap write-back:** both items → `_(state: smoke-tested <date> — Get-RoadmapRunnerHeartbeatPath + REPO_MGMT_RUNNER_HEARTBEAT_PATH, set by the api-host smoke; inline construction refused by the path gate)_`. Since they describe one fix, also add to the Lane 0.17 copy:  `Same fix as Lane 0.8's heartbeat item.`

**Stop if:** step 2 finds the heartbeat read in a frontend file or a place outside the listed scope; or the presence route reads anything other than that file to decide presence (report what it reads).

---

### H-06 — Dialog dismiss contract in the remaining modals

**Roadmap item:** Lane 0.14, `Adopt the dialog dismiss contract in the remaining 17 modals.`

**Why:** `useDialogDismiss` (Escape-to-close, focus trap, focus restore) is wired into 3 of 20 modals.

**Scope (edit only):** `frontend/components/**/*.tsx` that are modal components (discovered in step 1), `frontend/components/AgentRunSheet.tsx`, one new test file under the existing test directory, `ROADMAP.md`.

**Steps**

1. Read `frontend/hooks/useDialogDismiss.ts` and how `HelpModal` calls it (the reference wiring). Note the hook's signature and what ref it wants attached.
2. Enumerate modal components **by rule, not by list**: every file under `frontend/components/` whose name matches `*Modal.tsx` or `*Sheet.tsx`, **or** whose JSX contains `role="dialog"` or `aria-modal`. Expect **20 ± 2**. If outside that range, stop and report the list.
3. Partition into already-wired (imports `useDialogDismiss`) and not. Expect 3 wired. Report both lists.
4. For each unwired modal: import the hook, call it with the same arguments pattern `HelpModal` uses (its `onClose` prop and open state), attach the returned ref to the dialog panel's outermost element. Two changes per file; no layout or copy change.
5. `AgentRunSheet.tsx`: remove its inline `Escape` handler and replace with the hook, as the roadmap says.
6. Do this in **up to four PRs of ≤ 5 modals**, each green under R7, so no single diff is unreviewable.

**Gate (red first) — one new tripwire test:** a test that applies the rule from step 2 over `frontend/components/` at test time (read the directory; do not hard-code names) and asserts every matched file imports `useDialogDismiss`. Predicted red on unchanged code: it names 17 files. It also asserts the matched count is ≥ 15 so an over-narrow rule cannot pass by matching nothing. Existing per-modal tests must stay green.

**Roadmap write-back (after the last PR):** `_(state: smoke-tested <date> — 20/20 dialogs on useDialogDismiss; a directory-derived tripwire test refuses a dialog component that does not import the hook)_`.

**Stop if:** a modal has no single "panel" element to attach the ref to (report which); or attaching the hook breaks an existing test in a way not explained by focus behaviour (report the assertion).

---

### H-07 — Dispatch authority restricted to the Dispatch Board (D-008)

**Roadmap item:** Lane 0.17, `Restrict dispatch authority to the Dispatch Board.`

**Why:** `CopilotTaskPreviewModal` opens from three views and `Dashboard.tsx` passes its dispatch callback unconditionally, so previewing from Work Queue or Operations can spend agent quota. Decided 2026-09-06 (D-008).

**Scope (edit only):** `frontend/components/Dashboard.tsx`, `frontend/components/CopilotTaskPreviewModal.tsx`, the modal's existing test file, `ROADMAP.md`.

**Steps**

1. In `Dashboard.tsx`, locate where `CopilotTaskPreviewModal` is rendered and where the dispatch callback (the one that calls `POST /api/roadmap/dispatch/execute` then `/api/execution/assign`) is passed. Locate how the Dashboard knows which view opened the preview (a state variable or the active view key; the board's key is `execution-queue`). If no such origin information exists, stop and report — it must be added, and how is a design choice.
2. Pass the dispatch callback **only** when the origin view is `execution-queue`. For the other two, pass a new prop `onOpenOnBoard: (repoId) => void` that switches the active view to `execution-queue` and (if the panel supports it) focuses/filters to that repo's row; if it does not support focusing a row, switching view is sufficient — record that.
3. In `CopilotTaskPreviewModal.tsx`: when `onOpenOnBoard` is provided and the dispatch callback is not, render a button labelled `Open on Dispatch Board` in the place *Dispatch to Lane* would occupy. Keep the preview content (readiness, resource estimate, intended provider) unchanged on all three surfaces.
4. Update any modal copy that says the preview can dispatch from where it cannot.

**Gate (red first) — component tests, in the modal's existing test file:**

- Rendered with the dispatch callback → `Dispatch to Lane` present, `Open on Dispatch Board` absent.
- Rendered with `onOpenOnBoard` only → the reverse; clicking it calls the handler once.
- Rendered with neither → neither button (the existing preview-only behaviour; must stay green).
- Dashboard-level test (if a Dashboard test harness exists — check; if not, skip and report): opening the preview from Work Queue yields a modal without a dispatch action.
- Predicted red on unchanged code: test 2 fails because the button does not exist.

**Roadmap write-back:** `_(state: smoke-tested <date> — dispatch callback passed only from the execution-queue view; Work Queue and Operations previews offer "Open on Dispatch Board"; gated by component tests)_`.

**Stop if:** step 1 finds no origin information; or the dispatch callback is wired inside the modal itself rather than passed in (report the structure).

---

### H-08 — `nested` scope classification (D-002)

**Roadmap item:** Lane 0.12, `Classify a repository nested inside another as nested, not as its own portfolio entry.`

**Why:** the portfolio counts every `.git` boundary; a working tree inside another repo (`custom_SereneHarmonySite` inside `SereneHarmony_Site_Starter`) is a managed project only if someone says so. Decided 2026-09-06 (D-002).

**Scope (edit only):** `backend/modules/portfolio/Portfolio.Scope.ps1`, `backend/modules/portfolio/Portfolio.Assessment.ps1` (managed-count only), `docs/reference/status-vocabulary.md`, `frontend/lib/glossary.ts`, `frontend/types.ts` (only if the scope verdict is a typed union there), the module-smoke script, `evidence/trials/release-3.7/README.md`, `ROADMAP.md`.

**Steps**

1. Locate `function Get-RepoScopeClassification` (one). Read how `vendored` and `archived` verdicts are produced and **how an operator overrides one today** (an exclusion/inclusion list, a settings field, a marker file). Record the mechanism. **If no override mechanism exists, stop** — inventing a config file is a design decision.
2. Add verdict `nested`: a repository is `nested` when any ancestor directory of its root, up to (not including) the scan root, is itself a repository root (`.git` directory **or** `.git` file — linked worktrees store a file). Reason text: `working tree inside <ancestor repo name>`.
3. Opt-in: reuse the mechanism from step 1 so a listed repository is promoted from `nested` to its otherwise-computed verdict. Follow the existing mechanism's naming exactly.
4. In `Portfolio.Assessment.ps1`, ensure a `nested` repo is **reported** (appears in the index with its verdict, like `vendored`) but excluded from the managed count, exactly as `vendored` is. Change nothing else.
5. `status-vocabulary.md`: add `nested` to the scope verdict row. `glossary.ts`: add the entry (what it means, what computed it). The existing `glossary.test.ts` reads the doc and fails on an undocumented value — that test is your tripwire for step 5; if the scope verdict is a TypeScript union, adding the member is a compile error until the glossary Record has it, which is the intended drift gate.
6. `evidence/trials/release-3.7/README.md`: append one dated line: `<date>: scope classification gained 'nested' (D-002); expected portfolio total 72 → 71 on next scan. Not scan drift.`

**Gate (red first) — module smoke, new section `Nested repositories`:**

- Fixture: repo A containing repo B in a subdirectory. Classify both. Assert B is `nested` with reason naming A, A is not `nested`, managed count is 1. Predicted red on unchanged code: B is not `nested` / count is 2.
- Opt-in fixture: B listed via the step-1 mechanism → B is not `nested`, count is 2.
- Worktree fixture: B's `.git` is a file → still `nested`.

**Roadmap write-back:** `_(state: smoke-tested <date> — Get-RepoScopeClassification returns 'nested' for a working tree inside another repository; opt-in via <mechanism>; managed count excludes nested; glossary and vocabulary updated; trial README records the 72→71 expectation)_`.

**Stop if:** step 1 finds no override mechanism; or `vendored` exclusion from the managed count happens in more than one place (report them; do not duplicate logic into all of them).

---

### H-09 — External-history awareness metadata (D-005)

**Roadmap item:** Lane 0.7, `Record whether a repo externalizes its completion history.`

**Why:** `completedCount` reads ~0 forever for a split roadmap; nothing distinguishes archived history from deleted history. Decided 2026-09-06 (D-005): awareness metadata, never enforcement.

**Scope (edit only):** `standards/roadmap/roadmap-contract.schema.json`, its mirror under `spec/roadmap-contract/`, `backend/modules/roadmap/Roadmap.Parser.ps1`, `backend/modules/roadmap/Roadmap.Auditor.ps1` (payload only), the module-smoke script, `ROADMAP.md`.

**Steps**

1. Read `standards/roadmap/ROADMAP_TEMPLATE.md` §6 *External archive option*. **The detection rule is whatever that section prescribes** (a header line, a link text, a marker). Quote it in your report. If §6 does not prescribe a machine-detectable marker, stop — the marker is a spec decision.
2. Schema: add optional `historyLocation` (string, relative path) and `historyArchiveRef` (string, the link text or anchor) to the contract object. Both optional. No `required` changes. Bump `schemaVersion` only if the schema's own convention does so for additive fields (read the file's history/comments; if unclear, do not bump and say so).
3. Copy the schema change to the `spec/roadmap-contract/` mirror byte-for-byte; the existing sync gate must stay green.
4. Parser: when the §6 marker is present, populate the two fields. When absent, omit them (do not emit `null`).
5. Auditor: surface the fields in the audit payload unchanged. **Do not** add a rule that penalizes or rewards their presence.

**Gate (red first) — module smoke, new section `External history awareness`:**

- Fixture roadmap with the §6 marker → contract carries `historyLocation` matching the link path. Predicted red on unchanged code: property absent.
- Fixture without the marker → property absent, and the rest of the contract is **byte-identical** to what the unchanged parser produced (capture the golden output before you change anything).
- Schema mirror sync gate green.

**Roadmap write-back:** `_(state: smoke-tested <date> — optional historyLocation/historyArchiveRef in contract + mirror, set from the ROADMAP_TEMPLATE §6 marker, surfaced in the audit payload; no rule reads it)_`.

**Stop if:** step 1 yields no marker; or the auditor already has a rule touching `completedCount` that would change behaviour (report it).

---

### H-10 — Check-run detail with `mergeStateStatus` fallback (D-003)

**Roadmap item:** Lane 0.2, `Read check-run detail where it exists; keep mergeStateStatus as the documented fallback.`

**Why:** `MergeReadiness.ps1` reads `mergeable_state`, which cannot tell a pending required check from a failed one. The PAT grant (D-003) is an operator action; this packet must work **with or without** it.

**Scope (edit only):** `backend/modules/agent-runs/MergeReadiness.ps1`, the module-smoke script, `ROADMAP.md`.

**Steps**

1. Locate where `MergeReadiness.ps1` calls the Pulls API and reads `mergeable_state`. Locate the module's HTTP helper (the function every GitHub call goes through — discover; if calls are made inline with `Invoke-RestMethod`, use the same pattern).
2. Add `Get-PullRequestCheckRuns -Owner -Repo -HeadSha` calling `GET /repos/{owner}/{repo}/commits/{sha}/check-runs`. On HTTP 403 **or** 404, return `$null` and set a module-visible `$script:CheckRunsBasis = 'mergeStateStatus-proxy'`; on success return the check-run array and set `'check-runs'`.
3. In the readiness evaluation: if check-runs are available, derive blockers per check — `pending` for `status -ne 'completed'`, `failed` for `conclusion -in @('failure','timed_out','cancelled','action_required')`. Each blocker names the check. If unavailable, keep the **existing** proxy logic untouched.
4. Add `basis` to the readiness result (`'check-runs'` or `'mergeStateStatus-proxy'`). Never invent a basis.

**Gate (red first) — module smoke, new section `Merge readiness check-run detail`:** all offline, HTTP helper mocked.

- Fixture: one required check `in_progress`, one `completed/failure` → two blockers with **different** kinds and the check names. Predicted red on unchanged code: one undifferentiated `BLOCKED` blocker.
- Fixture: helper throws 403 → evaluation completes via proxy, `basis = 'mergeStateStatus-proxy'`, no error surfaced.
- Fixture: the pre-change proxy inputs → output identical to the golden capture from before your change.

**Roadmap write-back:** `_(state: smoke-tested <date> — per-check blockers when the token can read check-runs, proxy retained on 403 with basis recorded; gated offline)_`. Do **not** touch the sibling `Grant the PAT Checks: Read` item (operator).

**Stop if:** the module has no single HTTP entry point and more than three inline call sites (report them); or the readiness result shape is consumed by a frontend type you would need to change (report the type; the frontend is out of scope here).

---

### H-11 — Stale browser-persisted GitHub owner

**Roadmap item:** Lane 0.9, `Clear and harden the stale browser-persisted GitHub owner.`

**Why:** the browser sends owner `Benjamin-Fuhr_genesys` in the scan request body (116 occurrences since 2026-07-07); it is not in `settings.json` (`xfaith4`) or env. Two halves: stop the client override, and clear the persisted value.

**Scope (edit only):** the frontend file(s) that persist and send `owner` (discover), the api-host route(s) that accept an owner in a request body (discover), `scripts/Invoke-ApiHostSmokeTest.ps1`, a frontend test file, `ROADMAP.md`.

**Steps**

1. Frontend discovery: search `frontend/` for the key under which the owner is persisted (search `localStorage|sessionStorage` near `owner`). Expect one persistence site and one read site. If the owner is persisted in more than one key, stop and list.
2. Backend discovery: search the api-host for request-body reads of `owner` (`$body.owner`, `.owner`). List every route that honours it.
3. Backend rule: a body-supplied `owner` is honoured **only if** it equals the configured owner from settings **or** the configured owner is empty. Otherwise the route uses the configured owner and logs once per request: `client-supplied owner '<x>' ignored; configured owner '<y>' used`. Do not return an error — the scan should proceed with the right owner.
4. Frontend rule: on app load, read the persisted owner; if it differs from the owner the server reports in settings (use the existing settings fetch — do not add a request), delete the persisted key and log to console once. Do not surface a banner (Lane 0.16 amber rule).

**Gate (red first):**

- Api-host smoke step: with the fixture settings owner `fixture-owner`, POST the scan route with body owner `wrong-owner` → the response/log shows `fixture-owner` was used. Predicted red on unchanged code: `wrong-owner` reaches the GitHub call (mock it to record the owner).
- Frontend test: persisted `wrong-owner`, server settings `right-owner` → after load, persisted key is absent and outgoing request carries `right-owner`.

**Roadmap write-back:** `_(state: smoke-tested <date> — body-supplied owner honoured only when it matches configuration; stale persisted owner cleared on load; gated in api-host smoke and a frontend test)_`.

**Stop if:** the owner is used server-side to select between *local* and *GitHub* mode rather than as a GitHub account (report — that is a different fix); or step 1 finds the owner persisted server-side too.

---

### H-12a — Button-palette ratchet rule (measure and baseline only)

**Roadmap item:** Lane 0.14, `Collapse the ad-hoc button palette into a semantic token set.` **This packet is the enforcement half only.** Migrating 21 colors onto four semantic tokens is a mapping decision and is excluded (§3, H-12b).

**Scope (edit only):** `tools/Measure-UiRatchet.mjs`, its baseline file (discover), `ROADMAP.md`.

**Steps**

1. Read `Measure-UiRatchet.mjs` to learn how the existing `outlineNone` rule matches, counts, and compares against baseline.
2. Add rule `rawButtonColor`: within any JSX element whose tag is `button` or whose `role="button"`, count `className` tokens matching `^bg-(?!\[var\()` (a bare Tailwind color utility) and any inline `style` or class containing a raw hex `#[0-9a-fA-F]{3,8}` in a background property. Tokens that reference the semantic set in `frontend/styles.css` (discover the names of the accent and three status token classes) are **not** counted.
3. Run the tool. Record the count. Write it to the baseline as the ratchet's current value, exactly as the other rules are baselined.
4. Confirm the tool's compare mode fails when the count is **raised by one** (inject a `bg-red-500` on any button, run, observe failure, remove).

**Gate (red first):** step 4 is the gate. Predicted red: the tool has no `rawButtonColor` rule / the injection is not detected.

**Roadmap write-back:** replace `_(state: planned)_` with `_(state: scaffolded <date> — rawButtonColor ratchet rule counts <N> and holds baseline; migration to the semantic token set still open, see H-12b)_`.

**Stop if:** the tool has no baseline/compare mechanism to extend (report its actual structure).

---

### H-13a — Roadmap dependency notation: schema, parser, audit (D-001)

**Roadmap item:** Lane 0.18, `Order work inside one repository's roadmap, and detect dead ends.` — first half. D-001 (2026-09-06): dependencies are optional, within one repository, acyclic, keyed on stable item ids, and gate dispatch eligibility. `ROADMAP_TEMPLATE.md` already recommends `[[M3]]` ids and an inline `(depends: M3)` tag.

**Scope (edit only):** `standards/roadmap/roadmap-contract.schema.json` + `spec/roadmap-contract/` mirror, `standards/roadmap/ROADMAP_TEMPLATE.md` (only to make the existing convention precise), `backend/modules/roadmap/Roadmap.Parser.ps1`, `backend/modules/roadmap/Roadmap.Auditor.ps1`, the audit rules file (discover where `ROADMAP-002` is defined), the module-smoke script, `ROADMAP.md`.

**Steps**

1. Read `ROADMAP_TEMPLATE.md` and quote the exact id and depends syntax it recommends. If the syntax is ambiguous (e.g., separator for multiple ids unspecified), fix the template to: ids `[[<A-Za-z0-9._-]+>]]` immediately after the checkbox, tag `(depends: id1, id2)` anywhere in the item's first line, comma-separated. Record what you changed.
2. Schema: each item gains optional `id` (string) and `dependsOn` (array of string). Mirror the change to `spec/`.
3. Parser: extract both per item. Items without them carry neither property (not `null`, not `[]`).
4. Auditor, two new rules using the existing rule-id convention (read how `ROADMAP-002` is declared and wired to `Roadmap.Auditor.ps1`):
   - `ROADMAP-00N`: a `dependsOn` id that matches no item id in the same file → finding naming the item and the id.
   - `ROADMAP-00N+1`: a cycle among `dependsOn` edges → finding naming the cycle's ids.
   Both are findings, not parse errors; a roadmap with them is still `no-checklist`/`ok` for every other purpose.

**Gate (red first) — module smoke, new section `Roadmap dependencies (notation)`:**

- Fixture with ids and tags → items carry `id`/`dependsOn`. Predicted red on unchanged code: properties absent.
- Fixture with an unknown id → the first finding. Fixture with `A→B→A` → the second.
- **Golden:** the existing fixture roadmaps with no notation produce a contract byte-identical to the pre-change capture, and no new findings.
- Spec mirror sync gate green.

**Roadmap write-back:** on the Lane 0.18 item, change `_(state: planned)_` to `_(state: backend-complete <date> — notation parsed into id/dependsOn, unknown-id and cycle findings; selector is H-13b)_`.

**Stop if:** items in the current parser have no stable identity object to hang `id` on (report the item shape); or the audit rules live in two copies that must be edited together and you find them already out of sync.

---

### H-13b — Dependency-aware next-item selector

**Roadmap item:** Lane 0.18, same item — second half. Depends on H-13a merged.

**Scope (edit only):** a new `backend/modules/roadmap/Roadmap.Dependencies.ps1`, the module manifest/loader that dot-sources roadmap modules (discover), the one function that currently picks the next pending item for dispatch (discover: search for how `nextPendingRoadmapItem` is computed), the module-smoke script, `ROADMAP.md`.

**Steps**

1. Reference reading (read-only, do not copy files): `F:\Development\20_Staging\AI Projects\RoadmapOrchestrator\orchestrator\Invoke-RoadmapOrchestrator.ps1`, function `Get-NextPhase`, and its Phase 3 dead-end rule. If the path does not exist, proceed from the specification below; do not search for it elsewhere.
2. Implement pure `Get-NextEligibleRoadmapItem -Items <array> -CompletedIds <string[]>`:
   - Eligible = pending, and every `dependsOn` id ∈ `CompletedIds`.
   - Return the **first** eligible item in document order (deterministic).
   - If no item is eligible **and** at least one pending item exists → return an object `{ verdict = 'blocked'; reason = 'dependencies unresolved'; items = <pending ids> }`.
   - If a pending item references an unknown id or a cycle exists → `verdict = 'blocked'` with the ids, regardless of other eligibility.
   - If no pending items → `verdict = 'complete'`.
   - Items with no `dependsOn` are eligible immediately — so a roadmap with no notation returns exactly what today's first-pending logic returns.
3. Wire it into the single selection site from the scope. The site keeps its current signature; a `blocked` verdict surfaces wherever a *not dispatchable* reason already surfaces (find the existing field; do not add a new one).

**Gate (red first) — module smoke, new section `Roadmap dependencies (selection)`:**

- Linear chain A→B→C with A complete → returns B. Predicted red: function does not exist.
- Nothing complete, B depends on A → returns A (not B).
- Cycle → `blocked` naming both ids. Unknown id → `blocked`.
- **Golden:** every existing dispatch fixture with no notation selects the same item as before (capture before changing).

**Roadmap write-back:** `_(state: smoke-tested <date> — Get-NextEligibleRoadmapItem gates dispatch eligibility on dependsOn; cycle/unknown id halt as blocked; notation-free roadmaps unchanged)_`.

**Stop if:** next-item selection happens in more than one place (report all); or the dispatch readiness object has no existing field for a blocking reason.

---

## 3. Not for Haiku — and why

These are open roadmap items that this file deliberately does **not** render. A
small model must not attempt them. Each names the resource or judgement it
waits on.

| Roadmap item(s) | Reason | Who closes it |
| --- | --- | --- |
| **Release 2.9** — every remaining item | Elevated shell, physical Android device, authenticated `gh`, eyes on the live portal. No autonomous test can produce these. | Operator, batched |
| **Release 3.6** — operator verification; two uncaptured leverage metrics | Eyes on the live portal; the metrics wait on a 3.7 decision. | Operator; 3.7 |
| **Release 3.7** — all four milestones | Cohort freeze, approvals, measured operator minutes. Engineering half already landed 2026-09-05. | Operator |
| **Release 3.8** — six milestones | Genuinely unbuilt and architectural. Each milestone needed decomposition into 4–8 packets **against the code** (`Roadmap.Dispatcher.ps1`, `BudgetLedger.ps1`, `Automation.RoadmapQueue.ps1`, the runner, `types.ts`, the event vocabulary). This file was written from the roadmap alone and could not do that honestly. **Done 2026-09-06:** [`HAIKU-WORK-PACKETS-3.8.md`](HAIKU-WORK-PACKETS-3.8.md) renders all six milestones as 37 packets. Its §0 adds rules R11–R17 on top of this file's R1–R10, which still apply in full. | Haiku executes the 3.8 file, packet at a time |
| Lane 0.18 — carryover, acceptance gate, cumulative cap | Re-scoped into 3.8 by the roadmap itself. | With 3.8 |
| Lane 0.2 — grant `Checks: Read` | Operator action outside the repository. | Operator |
| Lane 0.8 — watchdog re-registration | One elevated command. | Operator |
| Lane 0.8 — E1 `exhaustive-deps`, P2 empty catches, P3 plaintext params, `set-state-in-effect` | Per-site behavioural judgement; a mechanical "fix" can change rendering or swallow a real failure. | Fable-class, or Haiku with a per-site decision table supplied first |
| Lane 0.8 — E2 type the API client; P4 BOM | Feasible for Haiku but not rendered here: E2 needs endpoint-group batching decided against `apiClient.ts`; P4 needs the "which files can run under 5.1" rule stated. Both are one short packet each once those are decided. | Operator decides batching/rule → packet |
| Lane 0.8 — dispatch-path coverage asymmetry | Under-specified (which writer, which test). | Needs a spec line |
| Lane 0.12 — two clones with different folder names | Roadmap says "needs a product judgement." | Operator (D-0xx) |
| Lane 0.13 — `estimatedSessionWorkUnits` null | Roadmap defers the derive-vs-unmeasured decision to 3.7's ten repositories. | 3.7 |
| Lane 0.14 — opacity ladder vs WCAG; breakpoints >768px; H-12b palette migration | Design decisions (which rungs move off body text; what the wide tiers are; which color maps to which token). | Operator supplies the mapping/tiers → packet |
| Lane 0.15 — everything still `[ ]` | All `ui-connected` awaiting **operator** proof on the live console. Touching these would re-open the honesty gap. | Operator |
| Lane 0.16 — version detection | Needs a staleness policy for engines fields. | Needs a spec line |
| Lane 0.17 — board self-refresh cadence | Roadmap assigns it to 3.8's fourth milestone. | With 3.8 |

---

## 4. Maintaining this file

- When a packet lands, delete it from §2 and remove its row from §1. The
  roadmap item's state string is the record; this file carries open packets only.
- When `ROADMAP.md` gains an autonomous engineering item, render it here before
  handing it to Haiku. The test for "rendered enough": every step names a file
  or a discovery rule with an expected match count; the gate predicts its red
  message; the stop condition is a sentence Haiku can evaluate without taste.
- If Haiku reports a *Stop if* three times on the same packet, the packet is
  under-specified, not the model. Rewrite the packet.
