import { describe, it, expect } from 'vitest';
import { buildOrientation, buildTodayRows, buildWhyNow, describeEffort, type TodayRankingInput } from './todayRanking';
import { normalizeRepositoryOutcomeSummary } from './foundationConclusion';

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

const repo = (name: string, over: Partial<TodayRankingInput> = {}): TodayRankingInput => ({
  repoId: `repo:${name}`,
  repoName: name,
  outcome: outcome('strengthen'),
  topValueItem: null,
  estimatedSessionWorkUnits: null,
  pendingCount: 0,
  curationState: 'none',
  ...over,
});

describe('buildTodayRows — what to do first, and why', () => {
  it('ranks actionable work above finished work, and never hides the finished work', () => {
    const rows = buildTodayRows([
      repo('healthy', { outcome: outcome('appropriate-as-is') }),
      repo('needs-work'),
      repo('unclear', { outcome: outcome('insufficiently-understood') }),
    ]);
    expect(rows.map(r => r.repoName)).toEqual(['needs-work', 'unclear', 'healthy']);
    expect(rows).toHaveLength(3); // appropriate-as-is sinks; it does not vanish
    expect(rows[0].rank).toBe(1);
  });

  it('puts curated repositories first among equals — the operator already said they matter', () => {
    const rows = buildTodayRows([
      repo('ordinary'),
      repo('favourite', { curationState: 'favorite' }),
      repo('candidate', { curationState: 'portfolio-candidate' }),
    ]);
    expect(rows.map(r => r.repoName)).toEqual(['favourite', 'candidate', 'ordinary']);
  });

  it('prefers a row that offers an action over one that does not', () => {
    const rows = buildTodayRows([
      repo('no-action', { outcome: outcome('strengthen', { nextActionRoute: null, nextActionLabel: null }) }),
      repo('actionable'),
    ]);
    expect(rows[0].repoName).toBe('actionable');
    expect(rows[1].nextActionRoute).toBeNull();
  });

  it('orders by value score, then by gap count, then by cheaper effort', () => {
    const byValue = buildTodayRows([
      repo('low', { topValueItem: { text: 'x', valueScore: 20, valueTier: 'low' } }),
      repo('high', { topValueItem: { text: 'y', valueScore: 90, valueTier: 'highest' } }),
    ]);
    expect(byValue.map(r => r.repoName)).toEqual(['high', 'low']);

    const byGaps = buildTodayRows([
      repo('one-gap', { outcome: outcome('strengthen', { gapCount: 1, gapDomains: ['planning'] }) }),
      repo('three-gaps', { outcome: outcome('strengthen', { gapCount: 3, gapDomains: ['planning', 'structure', 'purpose'] }) }),
    ]);
    expect(byGaps.map(r => r.repoName)).toEqual(['three-gaps', 'one-gap']);

    const byEffort = buildTodayRows([
      repo('expensive', { estimatedSessionWorkUnits: 12 }),
      repo('cheap', { estimatedSessionWorkUnits: 2 }),
    ]);
    expect(byEffort.map(r => r.repoName)).toEqual(['cheap', 'expensive']);
  });

  it('is stable: the same portfolio always renders in the same order', () => {
    const input = [repo('charlie'), repo('alpha'), repo('bravo')];
    const first = buildTodayRows(input).map(r => r.repoName);
    const again = buildTodayRows([...input].reverse()).map(r => r.repoName);
    expect(first).toEqual(['alpha', 'bravo', 'charlie']);
    expect(again).toEqual(first);
  });

  it('gives every row an audit trail for its rank', () => {
    const rows = buildTodayRows([
      repo('demo', {
        curationState: 'favorite',
        outcome: outcome('strengthen', { gapCount: 2, gapDomains: ['planning', 'structure'] }),
        topValueItem: { text: 'x', valueScore: 77, valueTier: 'high' },
        estimatedSessionWorkUnits: 5,
      }),
    ]);
    expect(rows[0].rankBasis).toEqual([
      'conclusion=strengthen',
      'curation=favorite',
      '2 foundation gap(s): planning, structure',
      'valueScore=77',
      'effort=5',
    ]);
  });
});

describe('buildWhyNow — the row explains itself', () => {
  it("leads with the product's own reason and adds the value signal", () => {
    const why = buildWhyNow(repo('demo', {
      outcome: outcome('strengthen', { reason: 'Planning is missing: no plan recorded (no ROADMAP.md).' }),
      topValueItem: { text: 'x', valueScore: 88, valueTier: 'highest' },
    }));
    expect(why).toContain('Planning is missing');
    expect(why).toContain('scores 88 (highest)');
  });

  it('says plainly when there is no conclusion rather than inventing one', () => {
    expect(buildWhyNow(repo('demo', { outcome: null }))).toMatch(/no recorded outcome/);
  });

  it('does not attach a value signal to work that is already appropriate as-is', () => {
    const why = buildWhyNow(repo('demo', {
      outcome: outcome('appropriate-as-is', { reason: 'Every applicable foundation is present.' }),
      topValueItem: { text: 'x', valueScore: 88, valueTier: 'highest' },
    }));
    expect(why).not.toContain('scores 88');
  });
});

describe('describeEffort', () => {
  it('bands the estimate and never guesses one it does not have', () => {
    expect(describeEffort(2)).toEqual({ workUnits: 2, label: '2 work units', band: 'small' });
    expect(describeEffort(1)).toEqual({ workUnits: 1, label: '1 work unit', band: 'small' });
    expect(describeEffort(6).band).toBe('medium');
    expect(describeEffort(20).band).toBe('large');
    expect(describeEffort(null)).toEqual({ workUnits: null, label: 'Effort not estimated', band: 'unknown' });
    expect(describeEffort(0).band).toBe('unknown');
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

// ---------------------------------------------------------------------------
// Pin reasons (audit follow-up 2026-08-29).
//
// The live Today tab sorted correctly from row 3 down (90, 90, 87, 87, 86...)
// while rows 1 and 2 carried 72 and NO score at all. The sort was right; a
// second ordering key was simply undisclosed. These prove the row now says
// which key put it there -- and, just as importantly, that rows the value
// column already explains stay silent.
// ---------------------------------------------------------------------------
describe('pinReason', () => {
  const outcome = (conclusion: string, withAction = true) => ({
    conclusion,
    reason: 'because.',
    gapCount: 0,
    gapDomains: [],
    nextActionLabel: withAction ? 'Do the thing' : null,
    nextActionRoute: withAction ? '/route' : null,
  }) as never;

  const entry = (over: Record<string, unknown>) => ({
    repoId: String(over.repoId ?? over.repoName),
    repoName: String(over.repoName),
    ...over,
  }) as never;

  it('names curation when a favorite outranks higher-value work', () => {
    const rows = buildTodayRows([
      entry({
        repoName: 'CupHandleDetectionv2',
        outcome: outcome('strengthen'),
        curationState: 'favorite',
        topValueItem: null,
      }),
      entry({
        repoName: 'HigherValue',
        outcome: outcome('strengthen'),
        curationState: 'none',
        topValueItem: { text: 'x', valueScore: 90, valueTier: 'high' },
      }),
    ]);

    expect(rows[0].repoName).toBe('CupHandleDetectionv2');
    expect(rows[0].pinReason).toContain('favorite');
    // The row whose position value already explains says nothing.
    expect(rows[1].pinReason).toBeNull();
  });

  it('names the conclusion when it is the key that won', () => {
    const rows = buildTodayRows([
      entry({
        repoName: 'Strengthen72',
        outcome: outcome('strengthen'),
        curationState: 'none',
        topValueItem: { text: 'x', valueScore: 72, valueTier: 'medium' },
      }),
      entry({
        repoName: 'Healthy90',
        outcome: outcome('appropriate-as-is'),
        curationState: 'none',
        topValueItem: { text: 'y', valueScore: 90, valueTier: 'high' },
      }),
    ]);

    expect(rows[0].repoName).toBe('Strengthen72');
    expect(rows[0].pinReason).toContain('next step');
    expect(rows[1].pinReason).toBeNull();
  });

  it('names actionability when only that separates the two', () => {
    const rows = buildTodayRows([
      entry({
        repoName: 'Actionable',
        outcome: outcome('strengthen', true),
        curationState: 'none',
        topValueItem: { text: 'x', valueScore: 10, valueTier: 'low' },
      }),
      entry({
        repoName: 'NoAction',
        outcome: outcome('strengthen', false),
        curationState: 'none',
        topValueItem: { text: 'y', valueScore: 99, valueTier: 'high' },
      }),
    ]);

    expect(rows[0].repoName).toBe('Actionable');
    expect(rows[0].pinReason).toContain('offers an action');
  });

  it('stays silent when the list is already in value order', () => {
    const rows = buildTodayRows([
      entry({
        repoName: 'Top',
        outcome: outcome('strengthen'),
        curationState: 'none',
        topValueItem: { text: 'x', valueScore: 90, valueTier: 'high' },
      }),
      entry({
        repoName: 'Next',
        outcome: outcome('strengthen'),
        curationState: 'none',
        topValueItem: { text: 'y', valueScore: 80, valueTier: 'high' },
      }),
    ]);

    expect(rows.map(r => r.pinReason)).toEqual([null, null]);
  });
});
