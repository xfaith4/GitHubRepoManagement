/**
 * The console's shared vocabulary, in one place.
 *
 * WHY THIS EXISTS. The audit's headline was that the console contradicts
 * itself: the same word means different things on different tabs, and a
 * number arrives with no statement of what produced it.
 * `docs/reference/status-vocabulary.md` settled the first half — five
 * independent dimensions, no two sharing a word — but it settled it in a file
 * the operator never opens. Badge meanings lived in a legend inside the
 * Repository Grid; readiness meanings lived in a hover title; maturity levels
 * lived in a modal you can only reach from a repo that already has a roadmap.
 * An operator on the Today tab had nowhere to look up "Stale".
 *
 * So this module is the definitions the Help dialog renders, and it is
 * deliberately typed against the same unions the UI switches on
 * (`RoadmapMaturityLevel`, `DispatchReadiness`): adding a value to either
 * union without documenting it is a COMPILE error, not a silently
 * undocumented badge. `glossary.test.ts` closes the other direction by
 * reading the vocabulary doc and failing when a documented value has no
 * entry here.
 *
 * EVERY TERM CARRIES ITS BASIS. Not decoration — the second half of the
 * audit finding. "Stale" is useless without "computed from GitHub's
 * pushed_at against your last local commit", because that is what tells you
 * a repo with no GitHub metadata reads not-stale for want of evidence rather
 * than for want of drift. Where a displayed value can be mistaken for a
 * measurement it is not, `caveat` says so in the operator's words.
 */
import type { DispatchReadiness, RoadmapMaturityLevel } from '../types';

export interface GlossaryTerm {
  /** What the operator actually sees on screen. */
  term: string;
  /**
   * The canonical machine value from `docs/reference/status-vocabulary.md`,
   * where one exists. This is the join key the sync test uses, so a value
   * documented in the vocabulary table but missing here fails the suite.
   */
  token?: string;
  /** What it means, in one or two sentences. */
  definition: string;
  /** What computes it. A number whose engine is unnamed is a number on trust. */
  basis: string;
  /** Present only when the rendered value can be mistaken for something it isn't. */
  caveat?: string;
}

export interface GlossaryGroup {
  id: string;
  title: string;
  /** The question this group of terms answers. */
  blurb: string;
  terms: GlossaryTerm[];
}

// --- Dimension 1: working tree ---------------------------------------------

const WORKING_TREE_TERMS: GlossaryTerm[] = [
  {
    term: 'Clean',
    token: 'clean',
    definition: 'The working tree has no uncommitted or untracked changes.',
    basis: 'The local scan\'s `git status` count, via Adapters.ps1.',
    caveat:
      'Only measured in Local mode. The GitHub-API and gh-CLI views have no working tree to read, so they report every repository as Clean — that is "not measured", not "nothing to commit".',
  },
  {
    term: 'Dirty',
    token: 'dirty',
    definition:
      'At least one file in the working tree is modified, staged, or untracked. The chip is clickable and opens the file list.',
    basis: 'The local scan\'s `git status` count — Dirty is exactly "uncommitted files > 0".',
    caveat: 'Same as Clean: GitHub-sourced views never compute it, so a Dirty count of 0 there means unmeasured.',
  },
  {
    term: 'Changes',
    definition: 'The number of files with uncommitted changes in a repository — the count behind the Dirty chip.',
    basis: 'The local scan\'s `git status` file count (`uncommittedChanges`).',
  },
  {
    term: 'Low / Medium / High / Critical',
    definition:
      'Severity bands for the Changes count: Low is 1–10 files, Medium 11–100, High 101–999, Critical 1000 or more.',
    basis: 'Computed in the grid from `uncommittedChanges` alone — file count, not diff size or content.',
    caveat:
      'A single generated folder can push a repository to Critical. The band measures how much is uncommitted, never how risky it is.',
  },
];

// --- Dimension 2: remote drift ---------------------------------------------

const REMOTE_DRIFT_TERMS: GlossaryTerm[] = [
  {
    term: 'Stale / Behind',
    token: 'behind',
    definition:
      'The remote has moved since this clone\'s last commit — someone pushed from elsewhere. Pull before writing to it.',
    basis:
      'GitHub\'s `pushed_at` compared against your last local commit date (`git log -1 --format=%cI`), with a 5-minute tolerance for push latency and clock skew. Basis name: `remote-push-vs-local-commit`.',
    caveat:
      'Drift, not age. A repository untouched for two years is NOT stale if nobody has pushed to it since your last commit.',
  },
  {
    term: 'Current',
    token: 'current',
    definition: 'Local and remote last moved at the same time, within the 5-minute tolerance.',
    basis: 'The same timestamp comparison as Behind.',
  },
  {
    term: 'Ahead or unpushed',
    token: 'ahead-or-unpushed',
    definition: 'This clone has local work newer than the last push to the remote.',
    basis: 'The same timestamp comparison as Behind, with the sign reversed.',
    caveat:
      'Two timestamps cannot yield a commit count, so no "ahead by N" is shown. An exact count needs a real ref comparison (`git ls-remote`) and a network round trip per repository.',
  },
  {
    term: 'Unknown drift',
    token: 'unknown',
    definition:
      'The scan has no local commit date, no remote push time, or neither — so drift could not be classified.',
    basis: 'Absence of one or both timestamps.',
    caveat:
      'Unknown is NOT stale. Absence of evidence is not evidence of divergence, so an unreadable repository never lights up the Stale filter.',
  },
];

// --- Dimension 3: dispatch readiness ---------------------------------------
// Typed as a Record over the union: a seventh readiness value cannot be added
// to types.ts without an entry appearing here.

const DISPATCH_READINESS_TERMS: Record<DispatchReadiness, GlossaryTerm> = {
  ready: {
    term: 'Ready (Dispatch-ready)',
    token: 'ready',
    definition:
      'The repository\'s documentation is in shape to receive agent work: a roadmap exists, parses, and has pending items.',
    basis: 'The docs-audit cache, surfaced as the snapshot metric `dispatchReadyCount`.',
    caveat:
      'One of three different "ready" measures. This one is about documentation, not about whether a lane can run it (Claimable lanes) or how mature the roadmap is (Work-ready L3+).',
  },
  'needs-doc-standardization': {
    term: 'Needs Docs',
    token: 'needs-doc-standardization',
    definition:
      'A roadmap is present, but the repository\'s documentation does not meet the standard an agent needs to work from.',
    basis: 'The docs-audit cache.',
  },
  'missing-roadmap': {
    term: 'No Roadmap',
    token: 'missing-roadmap',
    definition: 'The repository has no ROADMAP file at all. Start from Evaluate, which proposes one.',
    basis: 'The roadmap index — no roadmap file found at any scanned path.',
  },
  'roadmap-complete': {
    term: 'Roadmap Complete',
    token: 'roadmap-complete',
    definition: 'The roadmap parses and every checklist item is already checked. There is nothing left to dispatch.',
    basis: 'The parsed roadmap contract — pending item count is zero.',
    caveat: 'Not a problem state. It is the success state, and it is deliberately not counted as Needs Attention.',
  },
  'no-checklist': {
    term: 'No Checklist Items',
    token: 'no-checklist',
    definition:
      'The roadmap is a sound document but records no `- [ ]` items, so nothing in it can be ranked or dispatched.',
    basis: 'The parsed roadmap contract — zero checklist items of any state.',
    caveat:
      'This is NOT a parse error. The file is readable and valid; it just has no work items. Never treat it as a damaged file needing repair.',
  },
  'parse-error': {
    term: 'Parse Error',
    token: 'parse-error',
    definition: 'The roadmap file exists but could not be read as a roadmap contract.',
    basis: 'The roadmap parser failing on the file.',
  },
  blocked: {
    term: 'Blocked (dispatch)',
    token: 'blocked',
    definition:
      'The repository cannot receive dispatched work — a precondition the docs audit checks is unmet.',
    basis: 'The docs-audit cache.',
    caveat:
      'Distinct from Blocked (execution lane), which is about a queued item that cannot run. The two counts are different quantities and will not agree; see both entries before reconciling them.',
  },
};

// --- Dimension 4: roadmap maturity -----------------------------------------
// Same exhaustiveness guarantee as readiness, over RoadmapMaturityLevel.

const ROADMAP_MATURITY_TERMS: Record<RoadmapMaturityLevel, GlossaryTerm> = {
  'L0-Absent': {
    term: 'L0 — Absent',
    token: 'L0-Absent',
    definition: 'No roadmap file present.',
    basis: 'The roadmap contract audit.',
  },
  'L1-Informal': {
    term: 'L1 — Informal',
    token: 'L1-Informal',
    definition: 'A roadmap exists but is a flat list, lacks structure, or has parse errors.',
    basis: 'The roadmap contract audit, scored against the maturity model.',
  },
  'L2-Structured': {
    term: 'L2 — Structured',
    token: 'L2-Structured',
    definition:
      'The roadmap has checkboxes and some organization, but lacks release sections or acceptance criteria.',
    basis: 'The roadmap contract audit.',
  },
  'L3-Contract-Ready': {
    term: 'L3 — Contract-Ready',
    token: 'L3-Contract-Ready',
    definition: 'The roadmap uses release sections, has acceptance criteria, and parses cleanly.',
    basis: 'The roadmap contract audit.',
    caveat: 'L3 is the bar for "Work-ready". Below it, ranked work is not considered dispatchable.',
  },
  'L4-Orchestration-Ready': {
    term: 'L4 — Orchestration-Ready',
    token: 'L4-Orchestration-Ready',
    definition: 'The roadmap passes every critical and warning rule. Suitable for unattended orchestration.',
    basis: 'The roadmap contract audit with no critical or warning findings.',
  },
};

// --- Dimension 5: execution lane -------------------------------------------

const EXECUTION_LANE_TERMS: GlossaryTerm[] = [
  {
    term: 'Idle',
    token: 'idle',
    definition: 'A lane with nothing assigned to it.',
    basis: 'The execution ledger.',
  },
  {
    term: 'Ready (Claimable lane)',
    token: 'ready',
    definition: 'An execution-ledger entry a runner could claim right now.',
    basis: 'The execution ledger, surfaced as the snapshot metric `executionReadyCount`.',
    caveat: 'Not the same as Dispatch-ready. This one is about a queued lane, not about documentation.',
  },
  {
    term: 'Running',
    token: 'running',
    definition: 'A runner has claimed the entry and the agent task is in flight.',
    basis: 'The execution ledger.',
  },
  {
    term: 'Blocked (execution lane)',
    token: 'blocked',
    definition: 'A queued entry that cannot start — its preconditions are unmet or a dependency has not cleared.',
    basis: 'The execution ledger.',
    caveat:
      'The most commonly confused label in the console. Blocked here counts LEDGER ENTRIES; Blocked under dispatch readiness counts REPOSITORIES. Both are correct and they are not the same number.',
  },
  {
    term: 'Complete',
    token: 'complete',
    definition: 'The entry finished. Its outcome is in the run history, not in the queue.',
    basis: 'The execution ledger.',
  },
];

// --- Portfolio figures -----------------------------------------------------

const PORTFOLIO_TERMS: GlossaryTerm[] = [
  {
    term: 'PRs',
    definition: 'The number of open pull requests on the repository.',
    basis: 'The GitHub API (or `gh`), aggregated per owner at scan time.',
    caveat:
      'Only ever populated on GitHub-sourced paths. In Local mode nothing sets it, so the column reads 0 for every repository — unmeasured, not "no open PRs".',
  },
  {
    term: 'Needs Attention',
    definition:
      'A repository with an ACTIONABLE problem: uncommitted changes, a failing build, a blocked or parse-error dispatch state, or a roadmap with no checklist items.',
    basis: 'A single shared predicate, `frontend/lib/needsAttention.ts`, used by both the KPI and the grid filter.',
    caveat:
      'Deliberately excludes baseline conditions — no CI configured, a merely-pending roadmap, staleness, missing roadmaps — so the signal stays a meaningful subset instead of matching nearly the whole portfolio. Those have their own filters.',
  },
  {
    term: 'Dispatch-ready',
    definition: 'Audited repositories whose documentation can receive agent work.',
    basis: 'Snapshot metric `dispatchReadyCount`.',
  },
  {
    term: 'Claimable lanes',
    definition: 'Execution-ledger entries a runner could claim now.',
    basis: 'Snapshot metric `executionReadyCount`.',
  },
  {
    term: 'Work-ready (L3+)',
    definition: 'Assessed repositories at maturity L3 or above that still have pending roadmap items.',
    basis: 'Snapshot metric `maturityReadyCount`.',
  },
  {
    term: 'In scope',
    definition:
      'The repositories a figure was computed over, after curation filters (ignored/archived) are applied. Portfolio figures state this denominator rather than assuming the scanned total.',
    basis: 'The portfolio snapshot, which carries its denominator alongside each count.',
    caveat:
      'The scanned total and the in-scope total are different numbers by design. A count without a stated denominator is the ambiguity this field exists to remove.',
  },
];

// --- Scanning and curation -------------------------------------------------

const SCANNING_TERMS: GlossaryTerm[] = [
  {
    term: 'Refresh',
    definition: 'Re-read from the current source (cache or index). Invalidates nothing.',
    basis: 'One of exactly two refresh verbs in the console. Cost: seconds.',
  },
  {
    term: 'Rescan',
    definition: 'Invalidate the index and recompute from disk and remote.',
    basis: 'The other refresh verb. Cost: minutes — the control says so before you press it.',
  },
  {
    term: 'Index: Reused',
    definition: 'The repository was unchanged since the last scan and was served from the persisted index.',
    basis: 'Change-aware scanning: HEAD and metadata signals matched the indexed row.',
  },
  {
    term: 'Index: New Commits / Metadata Changed / Rescanned / Scan Failed',
    definition:
      'Why this row was reindexed: HEAD moved; docs/PR/Actions signals changed without new commits; no usable cache row existed; or the probe errored.',
    basis: 'The scan decision recorded per repository. Hover any Index badge for HEAD vs indexed commit and any error.',
  },
  {
    term: 'Favorite / Candidate / Ignored',
    definition:
      'Operator-set curation labels. Favorites sort first, Candidates are being evaluated for active work, Ignored is parked and hidden while "Hide ignored" is on.',
    basis: 'Set from a repository\'s Details panel. Persisted across restarts, and never a trigger for a rescan.',
  },
];

export const GLOSSARY_GROUPS: GlossaryGroup[] = [
  {
    id: 'working-tree',
    title: 'Working tree',
    blurb: 'What is uncommitted in your local clone right now.',
    terms: WORKING_TREE_TERMS,
  },
  {
    id: 'remote-drift',
    title: 'Remote drift',
    blurb: 'Whether the remote has moved relative to your clone. Drift, not age.',
    terms: REMOTE_DRIFT_TERMS,
  },
  {
    id: 'dispatch-readiness',
    title: 'Dispatch readiness',
    blurb: 'Whether a repository\'s documentation is in shape to receive agent work.',
    terms: Object.values(DISPATCH_READINESS_TERMS),
  },
  {
    id: 'roadmap-maturity',
    title: 'Roadmap maturity (L0–L4)',
    blurb: 'How complete a roadmap contract is, from absent to orchestration-ready.',
    terms: Object.values(ROADMAP_MATURITY_TERMS),
  },
  {
    id: 'execution-lane',
    title: 'Execution lane',
    blurb: 'The state of queued and running agent work in the execution ledger.',
    terms: EXECUTION_LANE_TERMS,
  },
  {
    id: 'portfolio',
    title: 'Portfolio figures',
    blurb: 'The counts on the summary cards, and what each was computed over.',
    terms: PORTFOLIO_TERMS,
  },
  {
    id: 'scanning',
    title: 'Scanning and curation',
    blurb: 'The two refresh verbs, the index badges, and the labels you set yourself.',
    terms: SCANNING_TERMS,
  },
];

/**
 * The five independent dimensions, named as the vocabulary doc names them.
 * Rendered above the terms so the operator sees WHY two labels that look
 * alike are allowed to disagree, before they read either one.
 */
export const DIMENSION_GROUP_IDS = [
  'working-tree',
  'remote-drift',
  'dispatch-readiness',
  'roadmap-maturity',
  'execution-lane',
] as const;

/** Every documented term, flattened — the search corpus and the test's corpus. */
export function allGlossaryTerms(): GlossaryTerm[] {
  return GLOSSARY_GROUPS.flatMap(group => group.terms);
}

/**
 * Case-insensitive substring match across term, token, definition, basis and
 * caveat, returning groups with their non-matching terms removed and empty
 * groups dropped. An empty query returns everything unchanged.
 */
export function filterGlossary(query: string): GlossaryGroup[] {
  const q = query.trim().toLowerCase();
  if (!q) return GLOSSARY_GROUPS;
  return GLOSSARY_GROUPS
    .map(group => ({
      ...group,
      terms: group.terms.filter(t =>
        t.term.toLowerCase().includes(q) ||
        (t.token ?? '').toLowerCase().includes(q) ||
        t.definition.toLowerCase().includes(q) ||
        t.basis.toLowerCase().includes(q) ||
        (t.caveat ?? '').toLowerCase().includes(q)
      ),
    }))
    .filter(group => group.terms.length > 0);
}
