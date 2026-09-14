# Kinds of Work

Moved verbatim from `ROADMAP.md` on 2026-09-13 (D-017): the roadmap follows a
contract imposed on every repository in the portfolio, and that contract should
not carry a description of how this one repository organises its work. This is
the one place all four kinds and their homes are named together.

What remains falls into four kinds of work that are **not** interchangeable —
mixing them once made the roadmap read "everything is done" over real gaps:

1. **Genuinely unbuilt engineering** — Release 3.7's four milestones, Release
   3.8's six (defined 2026-09-06, sequenced after 3.7) and the recorded
   cross-cutting items. This is the only kind an autonomous agent can close on
   its own. Ledger: [`ROADMAP.md`](../../ROADMAP.md) — every open `[ ]` there
   is this kind, and only this kind.
2. **Elevated / hardware / human verification** — SYSTEM rights, a physical
   Android phone, or an operator at an authenticated session; no autonomous
   test can produce these. Ledger: [`operator-queue.md`](operator-queue.md),
   with each recorded verification in `evidence/operator-verification-log.jsonl`.
3. **Product / design decisions** — waiting on a judgement, not on time or
   engineering. These have one durable home:
   [`docs/governance/open-decisions.md`](open-decisions.md).
   **Nine of the ten are now answered** (2026-09-06 closed D-001 through D-005,
   D-007 and D-008); only D-006's owner-intent labels remain open, and its
   ruling already released the work it was blocking. A decision raised only in
   conversation gets made by default, by whichever agent next touches the code.
4. **Calendar-gated accrual** — the 7/90-day trend windows fill only as
   time passes with capture running. No ledger of its own: the trend series in
   `GET /api/portfolio/trend` is the record, and this file is its pointer until
   it has one.
