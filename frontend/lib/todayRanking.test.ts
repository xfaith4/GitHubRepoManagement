import { describe, it, expect } from 'vitest';
import { buildOrientation, buildTodayRows, type TodayRankingInput } from './todayRanking';
import { normalizeRepositoryOutcomeSummary } from './foundationConclusion';
import { normalizePortfolioRanking, type PortfolioRanking } from './portfolioRanking';

// Release 4.0 phase A: the ranking keys (conclusion, curation, an offered
// action, readiness, gaps, effort, name) are the server's and are tested in
// tests/Test-OneRanking.ps1. These cases hold what is left here: rows follow
// the server's rank and carry its explanation, and nothing is re-ranked.

const outcome = (conclusion: string, over: Record<string, unknown> = {}) =>
  normalizeRepositoryOutcomeSummary({
    conclusion,
    reason: `reason for ${conclusion}`,
    kind: 'unknown',
    gapCount: 0,
    gapDomains: [],
    nextActionRoute: conclusion === 'strengthen' ? '/api/roadmap/repair/preview' : null,
    nextActionLabel: conclusion === 'strengthen' ? 'Preview the smallest credible plan' : null,
    holds: true,
    ...over,
  });

const ranking = (rank: number, over: Partial<PortfolioRanking> = {}): PortfolioRanking => ({
  rank,
  scale: 'portfolio',
  basis: ['conclusion=strengthen', 'unattendedReadiness=unmeasured'],
  whyNow: `why rank ${rank}`,
  pinReason: null,
  readiness: { factors: [], ready: 0, measured: 0, total: 4, summary: 'unmeasured — no check has run for this repository' },
  effort: { workUnits: null, label: 'Effort not estimated', band: 'unknown' },
  ...over,
});

const repo = (name: string, over: Partial<TodayRankingInput> = {}): TodayRankingInput => ({
  repoId: `repo:${name}`,
  repoName: name,
  outcome: outcome('strengthen'),
  ranking: null,
  ...over,
});

describe('buildTodayRows — the server ranks, the row explains', () => {
  it('orders rows by the server rank, whatever order they arrive in', () => {
    const rows = buildTodayRows([
      repo('third', { ranking: ranking(3) }),
      repo('first', { ranking: ranking(1) }),
      repo('second', { ranking: ranking(2) }),
    ]);
    expect(rows.map(r => r.repoName)).toEqual(['first', 'second', 'third']);
    expect(rows.map(r => r.rank)).toEqual([1, 2, 3]);
  });

  it('carries the server explanation unchanged: why-now, basis, pin reason, readiness, effort', () => {
    const [row] = buildTodayRows([
      repo('demo', {
        ranking: ranking(1, {
          basis: ['conclusion=strengthen', 'curation=favorite'],
          whyNow: 'Planning is missing: no plan recorded.',
          pinReason: 'Ranked above a repository that is readier for unattended work because you marked it a favorite.',
          readiness: { factors: [], ready: 3, measured: 4, total: 4, summary: '3 of 4 ready' },
          effort: { workUnits: 5, label: '5 work units', band: 'medium' },
        }),
      }),
    ]);
    expect(row.whyNow).toBe('Planning is missing: no plan recorded.');
    expect(row.rankBasis).toEqual(['conclusion=strengthen', 'curation=favorite']);
    expect(row.pinReason).toContain('favorite');
    expect(row.readiness.summary).toBe('3 of 4 ready');
    expect(row.effort.label).toBe('5 work units');
    expect(row.nextActionRoute).toBe('/api/roadmap/repair/preview');
  });

  it('never re-ranks: a healthy repository the server put first stays first', () => {
    const rows = buildTodayRows([
      repo('needs-work', { ranking: ranking(2) }),
      repo('healthy', { outcome: outcome('appropriate-as-is'), ranking: ranking(1) }),
    ]);
    expect(rows.map(r => r.repoName)).toEqual(['healthy', 'needs-work']);
  });

  it('shows "no rank" rather than inventing one when the host sent none', () => {
    const rows = buildTodayRows([repo('unranked-b'), repo('ranked', { ranking: ranking(1) }), repo('unranked-a')]);
    // Ranked first; the rest keep the order they arrived in.
    expect(rows.map(r => r.repoName)).toEqual(['ranked', 'unranked-b', 'unranked-a']);
    expect(rows[1].rank).toBeNull();
    expect(rows[1].rankBasis[0]).toMatch(/rank unavailable/);
    expect(rows[1].readiness.measured).toBe(0);
    expect(rows[1].whyNow).toBe('reason for strengthen');
  });

  it('says plainly when there is no conclusion rather than inventing one', () => {
    const [row] = buildTodayRows([repo('demo', { outcome: null })]);
    expect(row.conclusion).toBe('unknown');
    expect(row.whyNow).toMatch(/no recorded outcome/);
  });
});

describe('normalizePortfolioRanking', () => {
  it('reads the server shape and rejects a rank that is not a positive integer', () => {
    const r = normalizePortfolioRanking({
      rank: 4,
      scale: 'portfolio',
      basis: 'conclusion=strengthen',
      whyNow: 'x',
      pinReason: '',
      readiness: { factors: { key: 'ci', label: 'CI present', state: 'ready', detail: 'd' }, ready: 1, measured: 1, total: 4, summary: '1 of 1 ready' },
      effort: { workUnits: 2, label: '2 work units', band: 'small' },
    });
    expect(r?.rank).toBe(4);
    // PowerShell can collapse a one-element array to its element.
    expect(r?.basis).toEqual(['conclusion=strengthen']);
    expect(r?.readiness.factors).toHaveLength(1);
    expect(r?.pinReason).toBeNull();
    expect(normalizePortfolioRanking({ rank: 0 })).toBeNull();
    expect(normalizePortfolioRanking(null)).toBeNull();
  });
});

describe('buildOrientation — the newcomer test', () => {
  it('names what was evaluated, what was concluded, and what can be done', () => {
    const text = buildOrientation(buildTodayRows([
      repo('a'),
      repo('b', { outcome: outcome('appropriate-as-is') }),
      repo('c', { outcome: outcome('insufficiently-understood') }),
    ]));
    expect(text).toContain('assessed 3 repositories');
    expect(text).toContain('five foundations');
    expect(text).toContain('1 would be strengthened');
    expect(text).toContain('1 is appropriate as-is');
    expect(text).toContain('1 needs something the product does not yet have');
    expect(text).toContain('without applying anything');
  });

  it('says what to do when the index is empty instead of showing a blank page', () => {
    expect(buildOrientation([])).toMatch(/Run a portfolio scan/);
  });

  it('does not promise actions when none are offered', () => {
    const text = buildOrientation(buildTodayRows([repo('b', { outcome: outcome('appropriate-as-is') })]));
    expect(text).toContain('Nothing here needs an action right now.');
  });
});
