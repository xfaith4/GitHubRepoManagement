# Operator Queue

Work only Ben can do. Nothing here blocks engineering; each row records what it
ratchets when done. Batch by resource — one elevated shell, one authenticated
session, one phone on the LAN — and take the batch when convenient.

| Id    | Needs                   | Action                                                                                     | Ratchets                     |
| ----- | ----------------------- | ------------------------------------------------------------------------------------------ | ---------------------------- |
| OQ-1  | Browser, logged in      | Eyes on `Today` landing, outcome card, Insights leverage panel                             | Release 3.6 field proof      |
| OQ-2  | Browser, logged in      | Eyes on 3.1 empty-room gate, 3.1 engine attribution, 3.5 before/after                      | Release 2.9 re-homed proofs  |
| OQ-3  | Browser, ~10 min/repo   | Approve/reject staged previews in `evidence/trials/release-3.7/previews/`; record minutes  | 3.7 measured execution — 3.7 deferred 2026-10-16; superseded by OQ-15 |
| OQ-4  | Elevated (SYSTEM) shell | Watchdog + service-installer run; 2.7 freeze-prevention deploy                             | Release 2.9 privilege proofs |
| OQ-5  | github.com              | Grant PAT `Checks: Read` (D-003)                                                           | 3.8 scheduler dependency     |
| OQ-6  | Authenticated shell     | One real `gh agent-task` run through the runner                                            | Release 2.9 field proof      |
| OQ-7  | Galaxy S24 Ultra on LAN | Mobile surfaces (2.5/2.6)                                                                  | Release 2.9 device proof     |
| OQ-9  | Elevated shell          | Run `Enable-SharedLanAccess.ps1`; confirm an anonymous request is refused after the rebind | Release 2.9 shared-LAN proof |
| OQ-11 | Browser, logged in      | Clock and denominator presentation on the console (Lane 0.15)                              | Lane 0.15 field proof        |
| OQ-10 | Registered GitHub App   | Prove live installation-token exchange and refresh (optional; PAT supersedes)              | Release 2.9 optional proof   |
| OQ-12 | Elevated (UAC) shell    | Restart the portal service so the M4a `kindSignals` scanner goes live; then refresh the index | 3.7 M4a field proof — the next agent session re-concludes the cohort on v2 |
| OQ-14 | Elevated (UAC) shell, then browser | After the Release 4.0 slice 4.0-1 PR merges: restart the portal service (loads `Portfolio.Ranking.ps1`; the same restart satisfies OQ-12), then `npm run build`. Confirm Today's #1 and the Dispatch Board's #1 name the same repository, and a repository with several holds shows one card | 4.0 phase A field proof — its exit question |
| OQ-13 | Judgement               | Confirm or correct the resolved kind for each of the nine cohort repositories once re-concluded on v2 (`kind`, `kindCandidates`, `kindHints` in `cohort.json`); a correction becomes a rule with `observedOn`, never a code change | Steering Rung 1 — kind verdicts true on the cohort, not just computed |
| OQ-15 | Elevated (UAC) shell, then browser | Through 2026-11-15: after each Release 4.1 PR that changes the backend merges, restart the portal service so the change is live. Review every proposal the product makes in the console and accept, edit or reject it there, so the decision ledger captures the minutes. Merge approved PRs on other repositories on their verified head SHA | Release 4.1 proof of value — the operator-effort figure and the merged-PR count |
| OQ-16 | Elevated (UAC) shell, then browser | After PR #346 merges: fast-forward this checkout to `origin/main` (it is the live product), restart the portal service, then `npm run build`. Open Insights: "Runner Failures (14d)" reads a real rate with "n of m finished runs failed", Avg Active Run reads "—" when no lane runs, the commit panel reads "Commit Activity". Open the header agent pill: the three runs stuck `dispatched` on 2026-10-19 read `failed`, `failed` and `blocked` with their reasons, and the sheet closes on a backdrop click | Field proof for issues #338–#343 (closed by #346 on CI evidence) |

Done rows move to `evidence/operator-verification-log.jsonl` and are deleted here.
