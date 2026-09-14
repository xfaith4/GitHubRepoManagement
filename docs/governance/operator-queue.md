# Operator Queue

Work only Ben can do. Nothing here blocks engineering; each row records what it
ratchets when done. Batch by resource — one elevated shell, one authenticated
session, one phone on the LAN — and take the batch when convenient.

| Id    | Needs                   | Action                                                                                     | Ratchets                     |
| ----- | ----------------------- | ------------------------------------------------------------------------------------------ | ---------------------------- |
| OQ-1  | Browser, logged in      | Eyes on `Today` landing, outcome card, Insights leverage panel                             | Release 3.6 field proof      |
| OQ-2  | Browser, logged in      | Eyes on 3.1 empty-room gate, 3.1 engine attribution, 3.5 before/after                      | Release 2.9 re-homed proofs  |
| OQ-3  | Browser, ~10 min/repo   | Approve/reject staged previews in `evidence/trials/release-3.7/previews/`; record minutes  | 3.7 measured execution       |
| OQ-4  | Elevated (SYSTEM) shell | Watchdog + service-installer run; 2.7 freeze-prevention deploy                             | Release 2.9 privilege proofs |
| OQ-5  | github.com              | Grant PAT `Checks: Read` (D-003)                                                           | 3.8 scheduler dependency     |
| OQ-6  | Authenticated shell     | One real `gh agent-task` run through the runner                                            | Release 2.9 field proof      |
| OQ-7  | Galaxy S24 Ultra on LAN | Mobile surfaces (2.5/2.6)                                                                  | Release 2.9 device proof     |
| OQ-8  | Judgement               | D-006 owner-intent labels                                                                  | cohort metadata only         |
| OQ-9  | Elevated shell          | Run `Enable-SharedLanAccess.ps1`; confirm an anonymous request is refused after the rebind | Release 2.9 shared-LAN proof |
| OQ-11 | Browser, logged in      | Clock and denominator presentation on the console (Lane 0.15)                              | Lane 0.15 field proof        |
| OQ-10 | Registered GitHub App   | Prove live installation-token exchange and refresh (optional; PAT supersedes)              | Release 2.9 optional proof   |

Done rows move to `evidence/operator-verification-log.jsonl` and are deleted here.
