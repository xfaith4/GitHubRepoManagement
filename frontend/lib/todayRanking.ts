// Release 3.6 milestone 3 — the ranked `Today` landing.
//
// The first screen answers one question: what should I do next, and why now?
// A row that cannot say why it is ranked where it is has no business being at
// the top of the operator's day.
//
// Release 4.0 phase A: the ranking itself moved to the server
// (backend/modules/portfolio/Portfolio.Ranking.ps1), because Today and the
// Dispatch Board ranked the same portfolio two different ways — one repository
// read #1 here and #8 on the board. Every entry now arrives with `ranking`,
// and the board reads the same rank. This module maps that payload to rows and
// writes the orientation paragraph; it decides no order of its own.
// `tests/Test-OneRanking.ps1` fails if a sort key or precedence table returns.

import type { FoundationConclusionKind, RepositoryOutcomeSummary } from './foundationConclusion';
import type { PortfolioRanking, RankingEffort } from './portfolioRanking';
import type { UnattendedReadiness } from './unattendedReadiness';

export interface TodayRankingInput {
  repoId: string;
  repoName: string;
  outcome?: RepositoryOutcomeSummary | null;
  /** The server's rank for this entry; null when the host sent none. */
  ranking?: PortfolioRanking | null;
}

export type TodayEffort = RankingEffort;

export interface TodayRow {
  /** Null only when the host sent no ranking — rendered as "—", never guessed. */
  rank: number | null;
  repoId: string;
  repoName: string;
  conclusion: FoundationConclusionKind | 'unknown';
  /** One sentence: why this repository is where it is in the list. */
  whyNow: string;
  /** The single action this row offers. Null when none is warranted. */
  nextActionLabel: string | null;
  nextActionRoute: string | null;
  effort: TodayEffort;
  /** Whether an agent can work in this repository without asking — four named checks. */
  readiness: UnattendedReadiness;
  /** The ordered signals behind the rank, most significant first — the audit trail. */
  rankBasis: string[];
  /**
   * Set only when this row sits ABOVE a repository that is strictly READIER
   * for unattended work, and names the key that put it there. A rank that
   * cannot say why it is a rank is a guess.
   */
  pinReason: string | null;
}

const UNRANKED_READINESS: UnattendedReadiness = {
  factors: [],
  ready: 0,
  measured: 0,
  total: 4,
  summary: 'unmeasured — the host sent no ranking for this repository',
};

const UNRANKED_EFFORT: TodayEffort = { workUnits: null, label: 'Effort not estimated', band: 'unknown' };

/** Server rank ascending; rows the host did not rank keep their payload order, after the ranked ones. */
function byServerRank(a: { position: number; rank: number | null }, b: { position: number; rank: number | null }): number {
  if (a.rank !== null && b.rank !== null) return a.rank - b.rank;
  if (a.rank !== null) return -1;
  if (b.rank !== null) return 1;
  return a.position - b.position;
}

export function buildTodayRows(entries: TodayRankingInput[]): TodayRow[] {
  const positioned = entries
    .filter(entry => Boolean(entry) && Boolean(entry.repoId))
    .map((entry, position) => ({ entry, position, rank: entry.ranking?.rank ?? null }));
  positioned.sort(byServerRank);

  return positioned.map(({ entry }) => {
    const ranking = entry.ranking ?? null;
    const conclusion = entry.outcome?.conclusion ?? 'unknown';
    return {
      rank: ranking?.rank ?? null,
      repoId: entry.repoId,
      repoName: entry.repoName,
      conclusion,
      whyNow:
        ranking?.whyNow ||
        entry.outcome?.reason?.trim() ||
        'Not yet concluded: this repository has no recorded outcome, so the product cannot say whether it needs work.',
      nextActionLabel: entry.outcome?.nextActionLabel ?? null,
      nextActionRoute: entry.outcome?.nextActionRoute ?? null,
      effort: ranking?.effort ?? UNRANKED_EFFORT,
      readiness: ranking?.readiness ?? UNRANKED_READINESS,
      rankBasis: ranking ? ranking.basis : ['rank unavailable: the portal host sent no ranking'],
      pinReason: ranking?.pinReason ?? null,
    };
  });
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
