# Steering — GitHub Repo Manager

You are developing GitHub Repo Manager. Read this before the roadmap, and
re-read it whenever a choice feels like a matter of taste. It is not the
roadmap; the roadmap says what to build next. This says what the product is
for, what it must never do, and what "proved" means — in that order.

---

## 1. What this product is

A portfolio of repositories is illegible by default. This product makes it
legible: for every repository it produces a verdict a person can act on —
what it is, whether it needs them, what to do next — and **every verdict
carries the evidence it was drawn from.**

The product's most valuable answer is often "nothing here needs you." Its
second most valuable answer is "I can't tell, and here is exactly why."
Both are outcomes. Neither is a failure.

The thesis, in one line: **a number without a basis is a lie waiting to be
believed.** Everything below follows from that.

---

## 2. The contracts — never relaxed, never argued

These hold in every module, every payload, every surface, every export. A PR
that weakens one is wrong even if every test passes.

1. **Every figure is an object, never a bare number.** Value, unit, basis,
   asOf, source, coverage, confidence, definition. The constructor throws
   rather than build a metric that cannot say what it counted, over which
   set, as of when, from where. `New-PortfolioMetric` is the reference
   shape; every other metric producer conforms to it or is migrated to it.

2. **Not computed is null with a reason. Never 0.** "Zero" and "not
   measured" may not share a value. The render boundary shows an em dash
   and the reason; it never invents a figure to fill a tile.

3. **Every exclusion is explained on the surface that states it.** Nothing
   is silently dropped: a repository outside scope is classified, kept
   visible behind a toggle, and its reason names the pattern or owner that
   excluded it. A percentage is computed over a denominator the reader can
   inspect.

4. **Every verdict cites positive evidence.** `appropriate-as-is` names what
   is present; it never rests on "no findings." `strengthen` names a
   previewable next action with a route. `insufficiently-understood` names
   what the product needs. A verdict that cannot cite is not emitted.

5. **Freshness is established, never assumed.** A conclusion drawn from an
   index carries that index's staleness verdict — by clock and by logic
   fingerprint. A caller that does not supply the verdict gets one saying
   freshness was not established. Stale conclusions are worse than none,
   because they read as findings.

6. **Opinions live in config; code reads them.** Domains, kinds,
   applicability, thresholds, scoring weights, keyword rules, detection
   rules — all data in `backend/config/`. A wrong call is a data change with
   a `modelVersion` bump, not a code change. Nothing names a domain by hand.

7. **Intent is declared, never inferred.** Abandonment, external
   management, "this is a favourite," "this is not portfolio work" — these
   are the owner's, recorded through curation. The product may *surface* a
   question ("no commits in 14 months and no curation state") and it may
   *observe* a mismatch ("README says library, manifests say app"). It may
   not conclude what the owner meant.

8. **Agents surface; the owner rules.** A question that turns on
   preference, risk posture, or product direction goes in
   `docs/governance/open-decisions.md` with the default you proceeded under.
   You do not invent an answer and you do not stall. A question whose answer
   differs per installation is not a decision — it is state to be detected
   and shown in setup and Settings.

9. **Regenerable output never enters source control.** Fixtures are small,
   synthetic, and hand-authored under `tests/fixtures/`. `evidence/verified/`
   and `evidence/trials/` hold judgements a person made; everything else
   under `evidence/` is run spill. The audit script and `.gitignore` agree,
   or one has silently disabled the other.

10. **A green check is the merge; what the check cannot see is held, never
    argued.** The merge tripwire (`docs/governance/merge-policy.md`) holds
    the trust rule, the guards and the CI definition for the owner, and fails
    a secret or a loosened guard outright. Everything else merges on green
    and is audited after — by revert when wrong (D-023, 2026-09-15, replacing
    the D-019 reading of this contract).

11. **A canonical verdict is reproducible from index SHA + config +
    `modelVersion`, and nothing else.** Same three inputs, same conclusion,
    same basis, same next action — on any machine, on any day. Nothing that
    cannot be reproduced from those inputs may alter what the product
    claims about a repository. This says nothing about what may *inform*
    a verdict; a learned insight reaches one by becoming inspectable
    evidence, owner-recorded state, or a versioned rule. It says only that
    the path in is always visible and always replayable.

---

## 3. The proof ladder

The product is not "done" when it works. It is done when it has **proved
itself, in order, on three audiences**, and each rung has its own written
evidence. Do not climb ahead of the evidence.

### Rung 1 — the owner's own portfolio (current)

~60 repositories. Modest. Mostly mid-development. Several PowerShell
utilities, some firmware, some web, some experiments that were never meant
to be finished. This is the hardest honest test, not the easiest, because:

- **Mid-development is the normal state, not an exception.** A repository
  with a prose roadmap, a thin README, and no CI is a repository the product
  must be *useful* on, not one it grades down and moves past.
  `insufficiently-understood` and `strengthen` will be the majority
  outcomes. That is correct. Do not tune thresholds, keyword rules, or kind
  detection to make the distribution look healthier.
- **Modest repositories are not graded against enterprise standards.**
  Applicability is per kind. A script collection is not missing a test
  suite; a firmware sketch is not missing a Dockerfile. If a domain does not
  apply to a kind, `foundation-domains.json` says so and the reason renders.
- **The product must report what it cannot see** as a finding about the
  product, on the surface where a number would otherwise imply it looked.

Rung 1 is passed when, against a named index SHA:

- every conclusion holds `Test-FoundationConclusion` and every metric holds
  its contract, with the violation list empty and *recorded*;
- kind resolves to something other than `unknown` for every repository with
  a local checkout, or the `unknown` carries the hint list that failed to
  match, so a rule can be added as data;
- `lifecycleState` and `conclusion` never contradict each other unexplained
  — a contract test enforces it;
- every `strengthen` next action has been previewed at least once by the
  owner and the accept / reject / edit is **captured in a ledger** (this is
  the one new capture Release 3.6 named; it is not optional);
- the owner has recorded, in `evidence/operator-verification-log.jsonl`,
  that the verdicts for a curated cohort are *true* — not that the code ran,
  that the answers were right;
- a single exported file (the portfolio brief) lets a reader who has never
  seen the product know what changed since the last run, why it matters,
  and what to do next — with the evidence chain visible for every claim.

### Rung 2A — other developers' portfolios

At least three, each with a different owner, different language mix, and no
hand-tuning. Each is a trial under `evidence/trials/<name>/` with a cohort,
selection reasons written by hand, the index SHA, the conclusions, the
accept/reject outcomes, and a section titled **"what the product could not
see."** An empty category is a valid trial outcome; a manufactured cohort
member is not.

Rung 2A exists to find every place Rung 1 leaked the owner's assumptions
into config, defaults, or code: an owner set, a path pattern, a README
convention, a Windows path. The "stranger test": if a default only makes
sense on the owner's machine, it is per-installation state, not a default.

### Rung 2B — a public reference corpus

Earned by 2A, not assumed before it. The same deterministic extraction the
product already runs on a checkout — kind signals, technology profile,
structure audit — pointed at public repositories, in stages: 100, then
1,000, then more only if the smaller set produced observations the owner
acted on. The result is a **reference base for the investigative layer**
(§4, preamble), never a source of canonical verdicts.

Two cautions that hold at every stage. First, a public corpus skews toward
mature, popular repositories; norms drawn from it would grade a
mid-development portfolio as `strengthen` across the board, which is the
§6 forbidden outcome arriving from the opposite direction. Peers are
selected by kind and scale, never by visibility. Second, prevalence in a
peer group is evidence about the *population*, not about *this*
repository: "87% of comparable repositories have CI" may become an
observation and a question for the owner; it may not become the basis of
a `strengthen`, which contract 4 requires to rest on a positive fact about
the repository in front of it.

### Rung 3 — the buyer

Nothing is built *for* the buyer. The buyer is shown Rungs 1 and 2 — the
canonical brain proved, the investigative brain visibly separate from it.
What they are buying is the posture: every number carries its basis, every
decision is in a register, agents surface and humans rule, and the trials
are reproducible on their own portfolio with the same method. If the
product cannot be demonstrated that way, it is not ready, whatever the UI
looks like.

---

## 4. Direction — what to build, in the order it proves things

### Two brains, one boundary

The product has two kinds of intelligence, and they are kept apart on
purpose.

**Canonical judgement** is deterministic, versioned, and reproducible
(contract 11): evidence → config rules → conclusion → action. It is the
only thing that may say what a repository *is* or *needs*. It is what a
buyer audits, what a trial records, and what a diff between two index
SHAs compares.

**Investigative intelligence** is probabilistic, exploratory, and free to
be wrong: portfolio history, operator labels, peer retrieval, and models
reasoning over all of it. Its job is to find what is worth looking at and
to make the canonical brain smarter over time. It may, aggressively:

- **observe** — "82% of 684 comparable repositories have CI; this one has
  none";
- **analyse** — "this repository is unusual in its peer group on three
  counts";
- **hypothesise** — "the missing CI probably matters here because releases
  are published automatically and four owned repos consume this one";
- **ask** — a question for the owner, filed where questions go;
- **propose** — a kind rule, a keyword rule, a threshold, with the
  repositories it was observed on;
- **narrate** — prose over the evidence lines, marked as narration.

It may not **decide**. A verdict changes only when an insight has been
promoted into inspectable evidence, owner-recorded state, or a versioned
config rule — and that promotion is reviewed like any other change to what
the product claims. This is not a limit on what models can do; it is the
statement that the path from insight to verdict is always visible.

Three rules keep the boundary from eroding at the edges:

1. **Every observation carries its provenance and an explicit
   `canonicalEffect: none`** — the peer group definition, sample size,
   the labels or history it rested on, and the statement that it changed
   no verdict. An observation without these fields is not emitted.
2. **Observations are regenerable and live under `output/`.** Only a
   promoted rule enters config; only a hand-written trial record enters
   `evidence/`. Contract 9 applies to the investigative brain exactly as
   it applies to a smoke run.
3. **No surface renders an observation where a verdict renders, in the
   style a verdict renders.** A tile, card, row, or export that shows a
   conclusion may link to observations; it may not blend them. The
   architecture is only as separate as the UI keeps it.

### The extensions

These move the product along the ladder. Each is listed with the rung it
serves. Prefer the lowest rung that is not yet passed.

1. **The accept/reject ledger** (Rung 1). Every next action and top value
   item is a prediction; every operator response is a label. Capture it,
   then produce a calibration view: which keyword rules predict acceptance,
   which conclusions get overridden, which kinds get corrected. This is the
   evidence D-013 said the weights would be revisited against. Without it,
   the scorer is a heuristic forever. This ledger is also the primary
   input to the investigative brain: labels are what let it learn the
   owner's philosophy rather than the corpus's.

2. **Kind as a ranked vector with confidence, plus a coherence
   observation** (Rung 1). First-rule-wins hides honest ambiguity. Emit
   ranked kinds with the hints each rested on, and surface manifest-vs-README
   disagreement as its own finding — observed, never judged.

3. **Lifecycle/conclusion consistency contract** (Rung 1). Two verdict
   models over the same signals may not disagree without saying why. Same
   discipline the snapshot layer applied to the four counters.

4. **One manifest walk** (Rung 1). Repo type, technology profile, and kind
   signals are three walkers over the same files. One scan, three views,
   no drift.

5. **The portfolio brief and conclusion diff** (Rung 1). Diff two
   conclusion payloads by index SHA; render the movement as prose with the
   evidence chain. Deterministic first; an LLM narration, if ever, is
   constrained to the evidence lines and marked as narration.

6. **Trajectory** (Rung 1 → 2A). Improving / stable / decaying / dormant
   from maturity history and commit cadence. It changes the *question* the
   product asks the owner, never the verdict it draws.

7. **The portfolio graph** (Rung 2A). Dependencies between owned repos
   (module manifests, package deps, submodules) and duplication across them.
   Gives `unblockPotential` a real basis and surfaces consolidation
   candidates. First thing a stranger's portfolio makes visible that the
   owner's did not.

8. **Per-signal provenance** (Rung 2B → 3). Stamp field groups with their
   producer's fingerprint so staleness is per field and rescans are
   incremental. Unnecessary at 60 repositories; necessary at 600.

9. **The peer reference base** (Rung 2B). The existing extraction run over
   a public corpus in stages (100 → 1,000 → more only on evidence), feeding
   the investigative brain. Peers chosen by kind and scale; every peer
   observation carries its group definition, sample size, and
   `canonicalEffect: none`. Produces questions and rule proposals with
   `observed-on`; produces no verdicts.

10. **One metric schema under `standards/`** (Rung 3). Promote the snapshot
   metric shape to a schema, migrate Leverage and Analytics to it, and list
   every contract the product holds against itself on a surface a buyer can
   read.

---

## 5. Working rules

- Next action is the first `[ ]` in Current focus. Read the groundwork
  before touching it. Its check is named beside it; run it.
- Every milestone ships with its `check:`. `verified` means that check is
  green in CI. Operator verification is a separate fact in the queue and the
  JSONL log; never imply one from the other.
- When you find a fact the roadmap or a doc has wrong, correct the doc in
  the same PR and say so in the handoff. When you find your own notes
  wrong, say that too.
- Handoffs state: what merged, what is in CI, what you changed that the
  owner did not ask for, what you got wrong, what decisions you parked, and
  the next action with its check.
- Do not add a keyword rule, a threshold, or a kind rule to make one
  repository come out right. Add it because the evidence line shows a
  pattern, record the repository it was observed on, and bump
  `modelVersion`.
- You may not edit `.github/workflows/**` (D-012, decided 2026-09-15). A
  workflow you believe CI needs goes to `.github/workflows-proposed/` or a
  named section of the handoff, marked as waiting; the owner applies it.
- At most two pull requests held by the merge tripwire wait at once. Beyond
  that, build the next item on its branch and open its PR when a slot frees
  (2026-09-14; narrowed to held PRs by D-023, 2026-09-15). A PR the tripwire
  passes merges on green and never counts.

---

## 6. Things that look like progress and are not

- A tile that renders a number the payload could not compute.
- An average over a partial sample presented as the portfolio.
- A conclusion count that improved because a threshold moved.
- A trial cohort with a member chosen to fill a category.
- "Abandoned," "external," or "not a project" written anywhere the owner
  did not write it.
- A green CI run described as operator verification.
- A tripwire finding argued away in a PR body instead of fixed, or the
  `operator-approved` label applied by anyone but the owner.
- Reproducing the owner's own repo layout as the standard other people are
  graded against.
- A peer-group prevalence cited as the basis of a verdict about one
  repository.
- An observation rendered where a verdict belongs, or a verdict that cannot
  be replayed from index SHA + config + `modelVersion`.

If you catch yourself doing one of these, stop, file the question in the
decision register if it is a question, and take the honest path if it is
not.
