// Release 3.6 milestone 3 — the ranked `Today` landing.
//
// The first screen answers one question: what should I do next, and why now?
// Everything here is pure and explainable — a row that cannot say why it is
// ranked where it is has no business being at the top of the operator's day.
//
// The inputs already exist. The work-unit estimate was three clicks deep; the
// conclusion arrived with milestone 1. This module only decides an order and
// states the reason for it.
//
// Correction, 2026-09-01: the fourth sort key was the highest-value pending
// item's score, which ordered repositories by business value. Every repository
// in this portfolio has its own purpose and all of them are useful, so nothing
// may rank by usefulness. The key is now readiness for unattended work — how
// much of the repository an agent can act in without asking — which is the
// thing that legitimately differs between two otherwise-tied rows.

import type { FoundationConclusionKind, RepositoryOutcomeSummary } from './foundationConclusion';
import { assessUnattendedReadiness, type UnattendedReadiness } from './unattendedReadiness';

/**
 * Readiness for one input. Assessed here rather than passed in, so the sort,
 * the row and the audit trail can never disagree about what a rank meant.
 */
function readinessOf(input: TodayRankingInput): UnattendedReadiness {
  return assessUnattendedReadiness(input);
}

export interface TodayRankingInput {
  repoId: string;
  repoName: string;
  outcome?: RepositoryOutcomeSummary | null;
  topValueItem?: { text: string; valueScore: number; valueTier: string } | null;
  estimatedSessionWorkUnits?: number | null;
  pendingCount?: number;
  curationState?: string;
  lifecycleState?: string;
  // Signals for readiness for unattended work — the tiebreak that replaced the
  // item value score. Forwarded straight off OperationsRepoEntry; the ranking
  // assesses them itself so the rule and its explanation stay in one place.
  hasReadme?: boolean;
  hasRoadmap?: boolean;
  roadmapState?: 'pending' | 'complete' | 'missing' | 'no-checklist' | 'parse-error';
  localDirtyCount?: number;
  hasCiSignal?: boolean;
}

export interface TodayRow {
  rank: number;
  repoId: string;
  repoName: string;
  conclusion: FoundationConclusionKind | 'unknown';
  /** One sentence: why this repository is where it is in the list. */
  whyNow: string;
  /** The single action this row offers. Null when none is warranted. */
  nextActionLabel: string | null;
  nextActionRoute: string | null;
  /** Human effort estimate, or null when the product genuinely does not know. */
  effort: TodayEffort | null;
  /**
   * Whether an agent can work in this repository without asking — the four
   * checks, carried on the row so the table and the sort cannot disagree about
   * what they mean.
   */
  readiness: UnattendedReadiness;
  /** The ordered signals behind the rank, most significant first — the audit trail. */
  rankBasis: string[];
  /**
   * Set only when this row sits ABOVE a repository that is strictly READIER
   * for unattended work, and names the key that put it there. Null on every
   * row whose position the readiness column already explains.
   *
   * The sort is not the defect: conclusion, then curation, then whether a row
   * offers an action, all legitimately outrank readiness. The defect was that
   * the winning key was invisible, so a 1-of-4 row above a 4-of-4 row read as
   * a broken sort. A rank that cannot say why it is a rank is a guess.
   */
  pinReason: string | null;
}

export interface TodayEffort {
  workUnits: number | null;
  label: string;
  /** Cheap work first is a tiebreak, not a ranking principle. */
  band: 'small' | 'medium' | 'large' | 'unknown';
}

/**
 * Conclusion precedence. `strengthen` is actionable now; `insufficiently
 * understood` is a gap in the product's own knowledge and worth a look;
 * `appropriate as-is` is finished work and sinks — but is never hidden,
 * because "nothing to do here" is an outcome the operator is entitled to see.
 */
const CONCLUSION_PRECEDENCE: Record<string, number> = {
  strengthen: 0,
  'insufficiently-understood': 1,
  'appropriate-as-is': 2,
  unknown: 3,
};

/** Curated repositories lead: the operator already said these matter. */
const CURATION_PRECEDENCE: Record<string, number> = {
  favorite: 0,
  'portfolio-candidate': 1,
  none: 2,
  'archived-ignore': 3,
};

export function describeEffort(workUnits: number | null | undefined): TodayEffort {
  if (workUnits === null || workUnits === undefined || !Number.isFinite(workUnits) || workUnits <= 0) {
    return { workUnits: null, label: 'Effort not estimated', band: 'unknown' };
  }
  const units = Math.round(workUnits * 10) / 10;
  if (units <= 3) return { workUnits: units, label: `${units} work unit${units === 1 ? '' : 's'}`, band: 'small' };
  if (units <= 8) return { workUnits: units, label: `${units} work units`, band: 'medium' };
  return { workUnits: units, label: `${units} work units`, band: 'large' };
}

function conclusionOf(input: TodayRankingInput): FoundationConclusionKind | 'unknown' {
  return input.outcome?.conclusion ?? 'unknown';
}

/**
 * Why this row sits where it does. Leads with the conclusion's own reason —
 * the product already explained itself — and adds only what the ranking added.
 */
export function buildWhyNow(input: TodayRankingInput): string {
  const conclusion = conclusionOf(input);
  const reason = input.outcome?.reason?.trim();
  if (conclusion === 'unknown' || !reason) {
    return 'Not yet concluded: this repository has no recorded outcome, so the product cannot say whether it needs work.';
  }
  const parts = [reason];
  const value = input.topValueItem;
  if (conclusion === 'strengthen' && value && value.valueScore > 0) {
    parts.push(`Highest-value pending work scores ${value.valueScore} (${value.valueTier}).`);
  }
  return parts.join(' ');
}

function rankBasisFor(input: TodayRankingInput): string[] {
  const basis: string[] = [];
  const conclusion = conclusionOf(input);
  basis.push(`conclusion=${conclusion}`);
  const curation = input.curationState ?? 'none';
  if (curation !== 'none') basis.push(`curation=${curation}`);
  if (input.outcome && input.outcome.gapCount > 0) {
    basis.push(`${input.outcome.gapCount} foundation gap(s): ${input.outcome.gapDomains.join(', ')}`);
  }
  // Says what it measures in its own label: not a score out of anything, but
  // how many of the four unattended-work checks this repository passes.
  const readiness = readinessOf(input);
  basis.push(
    readiness.measured === 0
      ? 'unattendedReadiness=unmeasured'
      : `unattendedReadiness=${readiness.ready}/${readiness.measured} checks ready`,
  );
  const effort = describeEffort(input.estimatedSessionWorkUnits);
  if (effort.workUnits !== null) basis.push(`effort=${effort.workUnits}`);
  if (!input.outcome?.nextActionRoute) basis.push('no next action offered');
  return basis;
}

function compare(a: TodayRankingInput, b: TodayRankingInput): number {
  // 1. What the product concluded.
  const byConclusion =
    (CONCLUSION_PRECEDENCE[conclusionOf(a)] ?? 9) - (CONCLUSION_PRECEDENCE[conclusionOf(b)] ?? 9);
  if (byConclusion !== 0) return byConclusion;

  // 2. What the operator already marked as mattering.
  const byCuration =
    (CURATION_PRECEDENCE[a.curationState ?? 'none'] ?? 2) - (CURATION_PRECEDENCE[b.curationState ?? 'none'] ?? 2);
  if (byCuration !== 0) return byCuration;

  // 3. A row that offers an action outranks one that does not: the landing
  //    exists to be acted on.
  const actionable = (x: TodayRankingInput) => (x.outcome?.nextActionRoute ? 0 : 1);
  const byActionable = actionable(a) - actionable(b);
  if (byActionable !== 0) return byActionable;

  // 4. Readiness for unattended work, descending — the repository an agent can
  //    actually work in without asking goes first.
  //
  //    This key used to be the highest-value pending item's score, which
  //    ordered repositories by business value. Every repository in this
  //    portfolio has its own purpose and all of them are useful, so nothing
  //    here may rank by usefulness. Readiness is the thing that legitimately
  //    differs: at the point where conclusion, curation and actionability have
  //    all tied, prefer the work that can proceed without the operator.
  //
  //    Unmeasured sorts LAST among ties, and is not the same as zero. "We know
  //    an agent cannot work here" and "nobody has looked" are different
  //    statements; a repo with no checks run is not claimed to be unready, it
  //    is just weaker information than a repo that was actually assessed.
  const readinessRank = (x: TodayRankingInput) => {
    const r = readinessOf(x);
    return r.measured === 0 ? -1 : r.ready;
  };
  const byReadiness = readinessRank(b) - readinessRank(a);
  if (byReadiness !== 0) return byReadiness;

  // 5. More foundation gaps first — more of the repository is unsupported.
  const gaps = (x: TodayRankingInput) => x.outcome?.gapCount ?? 0;
  const byGaps = gaps(b) - gaps(a);
  if (byGaps !== 0) return byGaps;

  // 6. Cheaper work first, as a tiebreak only.
  const effort = (x: TodayRankingInput) => {
    const units = describeEffort(x.estimatedSessionWorkUnits).workUnits;
    return units === null ? Number.MAX_SAFE_INTEGER : units;
  };
  const byEffort = effort(a) - effort(b);
  if (byEffort !== 0) return byEffort;

  // 7. Stable, name-ordered, so the same portfolio always renders the same way.
  return a.repoName.localeCompare(b.repoName);
}

const CURATION_PHRASE: Record<string, string> = {
  favorite: 'you marked it a favorite',
  'portfolio-candidate': 'you marked it a portfolio candidate',
};

/**
 * Why `pinned` outranks `outvalued`, which carries more value. Walks the same
 * keys as `compare`, in the same order, and reports the first one that decided
 * it — so the explanation cannot drift from the ordering it explains.
 */
function explainPin(pinned: TodayRankingInput, outranked: TodayRankingInput): string | null {
  const conclusionRank = (x: TodayRankingInput) => CONCLUSION_PRECEDENCE[conclusionOf(x)] ?? 9;
  if (conclusionRank(pinned) !== conclusionRank(outranked)) {
    const kind = conclusionOf(pinned);
    return kind === 'strengthen'
      ? 'Ranked above a repository that is readier for unattended work because this one has a specific next step and that one does not.'
      : `Ranked above a repository that is readier for unattended work because its conclusion is "${kind}".`;
  }

  const curationRank = (x: TodayRankingInput) => CURATION_PRECEDENCE[x.curationState ?? 'none'] ?? 2;
  if (curationRank(pinned) !== curationRank(outranked)) {
    const phrase = CURATION_PHRASE[pinned.curationState ?? 'none'] ?? `its curation is ${pinned.curationState}`;
    return `Ranked above a repository that is readier for unattended work because ${phrase}.`;
  }

  const actionable = (x: TodayRankingInput) => (x.outcome?.nextActionRoute ? 0 : 1);
  if (actionable(pinned) !== actionable(outranked)) {
    return 'Ranked above a repository that is readier for unattended work because it offers an action to take and that one does not.';
  }

  return null;
}

export function buildTodayRows(entries: TodayRankingInput[]): TodayRow[] {
  const ordered = [...entries].filter(entry => Boolean(entry) && Boolean(entry.repoId)).sort(compare);
  // Unmeasured is not zero, and a row is not "outranked" by one nobody
  // assessed — so an unmeasured repository never triggers a pin explanation.
  const readyOf = (x: TodayRankingInput) => {
    const r = readinessOf(x);
    return r.measured === 0 ? -1 : r.ready;
  };

  return ordered
    .map((entry, index) => ({
      rank: index + 1,
      repoId: entry.repoId,
      repoName: entry.repoName,
      conclusion: conclusionOf(entry),
      whyNow: buildWhyNow(entry),
      nextActionLabel: entry.outcome?.nextActionLabel ?? null,
      nextActionRoute: entry.outcome?.nextActionRoute ?? null,
      effort: describeEffort(entry.estimatedSessionWorkUnits),
      readiness: readinessOf(entry),
      rankBasis: rankBasisFor(entry),
      // The first row below this one that is READIER is the row this position
      // has to justify itself against.
      pinReason: (() => {
        const readier = ordered.slice(index + 1).find(other => readyOf(other) > readyOf(entry));
        return readier ? explainPin(entry, readier) : null;
      })(),
    }));
}

/**
 * The one-paragraph orientation above the table. It names what the product
 * evaluated, what it concluded, and what the operator can do — the newcomer
 * test from Release 3.6's product outcomes.
 */
export function buildOrientation(rows: TodayRow[]): string {
  if (rows.length === 0) {
    return 'No repositories are indexed yet. Run a portfolio scan and this page will rank what to do first, and say why.';
  }
  const counts = rows.reduce<Record<string, number>>((acc, row) => {
    acc[row.conclusion] = (acc[row.conclusion] ?? 0) + 1;
    return acc;
  }, {});
  const strengthen = counts.strengthen ?? 0;
  const healthy = counts['appropriate-as-is'] ?? 0;
  const unclear = counts['insufficiently-understood'] ?? 0;
  const actionable = rows.filter(row => row.nextActionRoute).length;

  const parts = [
    `This console assessed ${rows.length} repositor${rows.length === 1 ? 'y' : 'ies'} against five foundations — documentation, purpose, planning, structure, and evidence of intentional engineering — and reached a conclusion for every one.`,
  ];
  const verdicts: string[] = [];
  if (strengthen > 0) verdicts.push(`${strengthen} would be strengthened by a specific next step`);
  if (healthy > 0) verdicts.push(`${healthy} ${healthy === 1 ? 'is' : 'are'} appropriate as-is`);
  if (unclear > 0) verdicts.push(`${unclear} ${unclear === 1 ? 'needs' : 'need'} something the product does not yet have`);
  if (verdicts.length > 0) parts.push(`${verdicts.join(', ')}.`);
  parts.push(
    actionable > 0
      ? `The rows below are ordered by what to do first; ${actionable} offer${actionable === 1 ? 's' : ''} an action you can preview without applying anything.`
      : 'Nothing here needs an action right now.'
  );
  return parts.join(' ');
}
