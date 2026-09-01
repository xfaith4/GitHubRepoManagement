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

  it('orders by readiness for unattended work, then by gap count, then by cheaper effort', () => {
    // The tiebreak used to be the highest-value pending item's score, which
    // ranked repositories by business value. Every repository here is useful,
    // so the tiebreak is now the one thing that legitimately differs: whether
    // an agent can work in it without asking.
    const byReadiness = buildTodayRows([
      repo('not-ready', { hasReadme: false, hasRoadmap: false, roadmapState: 'missing', localDirtyCount: 9, hasCiSignal: false }),
      repo('ready', { hasReadme: true, hasRoadmap: true, roadmapState: 'pending', localDirtyCount: 0, hasCiSignal: true }),
    ]);
    expect(byReadiness.map(r => r.repoName)).toEqual(['ready', 'not-ready']);

    // Unmeasured is not zero: a repository nobody assessed sorts BELOW one
    // measured at 0 of 4, because "we looked and it cannot" is a stronger
    // statement than "nobody looked".
    const unmeasuredLast = buildTodayRows([
      repo('never-assessed'),
      repo('measured-zero', { hasReadme: false, hasRoadmap: false, roadmapState: 'missing', localDirtyCount: 4, hasCiSignal: false }),
    ]);
    expect(unmeasuredLast.map(r => r.repoName)).toEqual(['measured-zero', 'never-assessed']);

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
      'unattendedReadiness=unmeasured',
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

  it('names curation when a favorite outranks a readier repository', () => {
    const rows = buildTodayRows([
      entry({
        repoName: 'CupHandleDetectionv2',
        outcome: outcome('strengthen'),
        curationState: 'favorite',
        topValueItem: null,
      }),
      entry({
        repoName: 'Readier',
        outcome: outcome('strengthen'),
        curationState: 'none',
        hasReadme: true,
        hasRoadmap: true,
        roadmapState: 'pending',
        localDirtyCount: 0,
        hasCiSignal: true,
      }),
    ]);

    expect(rows[0].repoName).toBe('CupHandleDetectionv2');
    expect(rows[0].pinReason).toContain('favorite');
    // The row whose position the readiness column already explains says nothing.
    expect(rows[1].pinReason).toBeNull();
  });

  it('names the conclusion when it is the key that won', () => {
    const rows = buildTodayRows([
      entry({
        repoName: 'StrengthenNotReady',
        outcome: outcome('strengthen'),
        curationState: 'none',
      }),
      entry({
        repoName: 'HealthyReadier',
        outcome: outcome('appropriate-as-is'),
        curationState: 'none',
        hasReadme: true,
        hasRoadmap: true,
        roadmapState: 'pending',
        localDirtyCount: 0,
        hasCiSignal: true,
      }),
    ]);

    expect(rows[0].repoName).toBe('StrengthenNotReady');
    expect(rows[0].pinReason).toContain('next step');
    expect(rows[1].pinReason).toBeNull();
  });

  it('names actionability when only that separates the two', () => {
    const rows = buildTodayRows([
      entry({
        repoName: 'Actionable',
        outcome: outcome('strengthen', true),
        curationState: 'none',
      }),
      entry({
        repoName: 'NoActionButReadier',
        outcome: outcome('strengthen', false),
        curationState: 'none',
        hasReadme: true,
        hasRoadmap: true,
        roadmapState: 'pending',
        localDirtyCount: 0,
        hasCiSignal: true,
      }),
    ]);

    expect(rows[0].repoName).toBe('Actionable');
    expect(rows[0].pinReason).toContain('offers an action');
  });

  it('stays silent when the list is already in readiness order', () => {
    const rows = buildTodayRows([
      entry({
        repoName: 'Top',
        outcome: outcome('strengthen'),
        curationState: 'none',
        hasReadme: true, hasRoadmap: true, roadmapState: 'pending', localDirtyCount: 0, hasCiSignal: true,
      }),
      entry({
        repoName: 'Next',
        outcome: outcome('strengthen'),
        curationState: 'none',
        hasReadme: true, hasRoadmap: true, roadmapState: 'pending', localDirtyCount: 3, hasCiSignal: true,
      }),
    ]);

    expect(rows.map(r => r.pinReason)).toEqual([null, null]);
  });

  it('does not rank by business value at all — the correction, guarded', () => {
    // Two repositories identical in every ranking key EXCEPT the item value
    // score. If value still influenced the order, 'rich' would lead. It must
    // not: every repository in this portfolio is useful, so worth cannot order
    // them. With every key tied the sort falls through to its stable
    // name-ordered tiebreak.
    const rows = buildTodayRows([
      entry({
        repoName: 'zulu-rich',
        outcome: outcome('strengthen'),
        curationState: 'none',
        topValueItem: { text: 'x', valueScore: 99, valueTier: 'highest' },
      }),
      entry({
        repoName: 'alpha-poor',
        outcome: outcome('strengthen'),
        curationState: 'none',
        topValueItem: { text: 'y', valueScore: 1, valueTier: 'low' },
      }),
    ]);

    expect(rows.map(r => r.repoName)).toEqual(['alpha-poor', 'zulu-rich']);
    expect(rows.flatMap(r => r.rankBasis).join(' ')).not.toContain('valueScore');
  });
});
