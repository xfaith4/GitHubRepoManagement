# Trial truth readiness — 2026-09-05

Status: implementation connected and canonically validated on Windows; live operator proof still pending.

Changes: stable source selection after credential connection; named execution, dispatch and PR blockers with aggregate denominators; visible Today rank basis; removed nonexistent Settings instruction; UTC ISO 8601 normalization before DateTime coercion, including cached index reads; raw-wire timezone gate covering assessment and operations.

Red proof: four frontend regressions failed against original behavior (4 failed, 48 passed). `tools/Test-PortfolioTimestamp.ps1` failed against original index projection with createdAt = 01/12/2026 05:25:34. The raw-wire checker rejects naive and invalid date fixtures and counts valid ISO date tokens instead of skipping parsed dates.

Defect found by the native run: the cached-read normalization covered the repo rows but not the payload's own `generatedAt`. `ConvertFrom-Json` turns the ISO token into a `[datetime]`, and the downstream `[string]` coercion then renders it in the host's culture — `09/05/2026 12:00:00` reached the wire through both `Get-PortfolioIndexStaleness` and the snapshot payload. Normalized on the single read path both consumers go through. The assertion at `tools/Test-PortfolioTimestamp.ps1:39` fails without the fix and runs inside the module smoke gate. The Linux pass did not reach this; the Windows-native run did.

Validation (native PowerShell 7, Windows, 2026-09-05): **all 19 suite gates green**, `Invoke-TestSuite.ps1 -SkipApiHost` exit 0 — module smoke (79.6s, including the three new timestamp assertions), adapter smoke, UI debt ratchet, frontend typecheck, frontend lint at the existing 161-warning cap, 472 frontend unit tests across 47 files, frontend build, PowerShell lint gate, API contract (37 Pester tests, 0 failed), auth smoke, repo structure, roadmap structure lint and capability record. The PSSA ratchet baseline moved down where the gate reported improvements below it: `PSUseBOMForUnicodeEncodedFile` 59 → 56 and `PSUseUsingScopeModifierInNewRunspaces` 40 → 12 (total 571 → 540); the second was stale rather than newly earned, and both counts reproduce across an independent recursive scan.

Not covered here: `Invoke-ApiHostSmokeTest.ps1`. A roadmap task runner was live on this machine (heartbeat one second old, 15s poll), and that smoke enqueues into the real queue and deletes its fixture seconds later; running the two together risks the runner claiming the fixture mid-test. CI runs that gate with no competing runner. The API contract gate, which exercises the modified `ApiHost.Contract.Tests.ps1`, did run and passed.

Windows 5.1 found BOM-less host parsing; touched host now has UTF-8 BOM.

Live: RepoMgmtPortal service running; Windows curl HTTPS /health/live returns ok. Auth status confirms enforced login. This proves liveness, not deployment currency or operator verification of Today/outcomes/Insights.

Trial: see `evidence/trials/release-3.7/README.md`. Nine provisional candidates plus an unfilled external-management slot, D-006. Zero measured improvements; cached conclusions are diagnostic only. No managed repository has been changed or dispatched.
