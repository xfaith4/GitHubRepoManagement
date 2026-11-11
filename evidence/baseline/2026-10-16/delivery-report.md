# Delivery baseline: the 2026-10-16 evaluation, recomputed

Generated 2026-11-11T06:05:43.6488890Z. Window: records through 2026-10-16.

| Figure | Value | Unit | Basis | Source | Since last |
| --- | --- | --- | --- | --- | --- |
| prsInitiated | 11 | count |  | github (PRs named by the delivery ledger, run summaries and runner branches) | No earlier report to compare with. |
| prsPassedCi | 0 | count | 0 of 3 | github (PRs named by the delivery ledger, run summaries and runner branches) | No earlier report to compare with. |
| prsMerged | 10 | count |  | github (PRs named by the delivery ledger, run summaries and runner branches) | No earlier report to compare with. |
| proposalsRejected | not measured: The delivery ledger held no decision by the window end: accepts and rejects were not recorded. | count |  |  | No earlier report to compare with. |
| operatorSeconds | not measured: The delivery ledger held no decision by the window end: operator time was not recorded. | seconds |  |  | No earlier report to compare with. |
| operatorSecondsPerMergedImprovement | not measured: The delivery ledger held no decision by the window end: operator time was not recorded. | seconds |  |  | No earlier report to compare with. |
| agentRuns | 80 | count |  | runner run summaries (output\roadmap-task-history\runs) | No earlier report to compare with. |
| agentRunsFailed | 52 | count | 52 of 80 | runner run summaries (output\roadmap-task-history\runs) | No earlier report to compare with. |
| reposReady | not measured: The docs audit cache keeps only its latest audit (2026-11-01), which is after the window ends; readiness at the window end was not recorded. | count |  |  | No earlier report to compare with. |

## Agent-run failures by cause

| Cause | Runs | Example run |
| --- | --- | --- |
| missing-roadmap | 17 | 20260323-012705-d8de03fc |
| copilot-task-create | 13 | 20260529-070323-58f47058 |
| runner-pid-mismatch | 7 | 20260901-055444-53285e6c |
| other | 6 | 20260815-050740-5e127a98 |
| github-token | 4 | 20260712-035842-05da82e5 |
| no-actionable-item | 4 | 20260801-020414-6a6dabea |
| gh-cli-missing | 1 | 20260320-063348-be0a5123 |

## Against the 2026-10-16 evaluation

| Figure | Evaluation | This report | Note |
| --- | --- | --- | --- |
| prsInitiated | 11 | 11 | Matches: verified product-originated PRs created 2026-03-01 to 2026-10-16 (trial README). |
| prsMerged | 10 | 10 | Matches: of those merged (trial README; ROADMAP.md said "about eight"). |
| prsPassedCi | not stated | 0 of 3 | Differs from the evaluation (four merged with failing checks and one was open with failing checks (trial README)): Initiated PRs whose current head commit passed CI (check runs and commit statuses), out of those whose CI could be read; coverage counts them against every initiated PR. A PR whose CI was unreadable is never counted as failed. |
| agentRuns | 80 | 80 | Matches: non-smoke runner runs. |
| agentRunsFailed | 51 | 52 of 80 | Differs from the evaluation (failed, blocked or refused (trial README; ROADMAP.md said 45 failed)): Runner runs in the window that failed, were blocked by a gate, or were refused (cancelled runs are not counted); failureCauses names why. |
| proposalsRejected | not recorded | not measured | The delivery ledger held no decision by the window end: accepts and rejects were not recorded. Evaluation: no decision ledger existed. |
| operatorSeconds | not recorded | not measured | The delivery ledger held no decision by the window end: operator time was not recorded. Evaluation: operator minutes never recorded. |
| operatorSecondsPerMergedImprovement | not recorded | not measured | The delivery ledger held no decision by the window end: operator time was not recorded. Evaluation: operator minutes never recorded. |
| reposReady | 1 of 62 | not measured | The docs audit cache keeps only its latest audit (2026-11-01), which is after the window ends; readiness at the window end was not recorded. Evaluation: PhotoToolboxv2 (trial README). |

## Reads that failed

- xfaith4/administatortools#roadmap/20260808-160411-e22a2f35: gh api /repos/xfaith4/administatortools/pulls?state=all&head=xfaith4:roadmap%2F20260808-160411-e22a2f35: gh: Not Found (HTTP 404)
- xfaith4/administatortools#roadmap/20260808-160711-838aec7e: gh api /repos/xfaith4/administatortools/pulls?state=all&head=xfaith4:roadmap%2F20260808-160711-838aec7e: gh: Not Found (HTTP 404)
- xfaith4/administatortools#roadmap/20260906-152241-29e177b8: gh api /repos/xfaith4/administatortools/pulls?state=all&head=xfaith4:roadmap%2F20260906-152241-29e177b8: gh: Not Found (HTTP 404)


