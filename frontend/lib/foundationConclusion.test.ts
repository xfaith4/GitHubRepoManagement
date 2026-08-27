import { describe, it, expect } from 'vitest';
import {
  MISSING_REASON_TEXT,
  describeConclusion,
  describeDomainStatus,
  filterByConclusion,
  normalizeConclusionContract,
  normalizePortfolioConclusionsResult,
  normalizeRepositoryConclusion,
  normalizeRepositoryOutcomeSummary,
  summarizeRepositoryConclusion,
} from './foundationConclusion';

// The wire shape GET /api/portfolio/conclusions/{repoId} serves (data.conclusion),
// as the api-host smoke asserts it for the seeded fixture.
const wireConclusion = {
  schemaVersion: 'v1',
  model: 'foundation-conclusion',
  repoId: 'repo:smoke-managed-repo',
  repoName: 'smoke-managed-repo',
  kind: 'unknown',
  kindBasis: 'no kind signal in the index; every scored domain applies',
  conclusion: 'strengthen',
  reason: 'Structure is missing: 1 critical structure gap(s) for a other repository: LICENSE.',
  basis: ['kind=unknown (no kind signal)', 'structure=missing'],
  domains: [
    { domain: 'documentation', title: 'Documentation', status: 'present', evidence: ['README present, score 80/100'], nextAction: null },
    { domain: 'purpose', title: 'Purpose', status: 'present', evidence: ['README states the purpose (score 80/100 against the README contract)'], nextAction: null },
    { domain: 'planning', title: 'Planning', status: 'weak', evidence: ['roadmap at L1-Informal - below the contract-ready bar - with 1 pending item(s)'],
      nextAction: { domain: 'planning', kind: 'roadmap-repair-preview', label: 'Preview the smallest credible plan', method: 'POST', route: '/api/roadmap/repair/preview', body: { repoName: 'smoke-managed-repo' }, previewFirst: true } },
    { domain: 'structure', title: 'Structure', status: 'missing', evidence: ['1 critical structure gap(s) for a other repository: LICENSE'],
      nextAction: { domain: 'structure', kind: 'repository-improvement-preview', label: 'Preview the structure repairs', method: 'POST', route: '/api/repository-improvement/preview', body: { repoName: 'smoke-managed-repo', repoPath: 'C:\\repos\\smoke-managed-repo' }, previewFirst: true } },
    { domain: 'intentional-engineering', title: 'Intentional engineering', status: 'not-scored', evidence: ['no test signal observed', 'observed, not judged'], nextAction: null },
  ],
  nextAction: { domain: 'structure', kind: 'repository-improvement-preview', label: 'Preview the structure repairs', method: 'POST', route: '/api/repository-improvement/preview', body: { repoName: 'smoke-managed-repo', repoPath: 'C:\\repos\\smoke-managed-repo' }, previewFirst: true },
  maturityLevel: 'L1-Informal',
  lifecycleState: 'needs-roadmap-repair',
  generatedAt: '2026-08-26T20:00:00.000Z',
};

describe('normalizeRepositoryConclusion — the card renders exactly what the backend concluded', () => {
  it('keeps the conclusion, the reason, every domain and the primary next action with its body', () => {
    const c = normalizeRepositoryConclusion(wireConclusion);
    expect(c).not.toBeNull();
    expect(c!.conclusion).toBe('strengthen');
    expect(c!.reason).toMatch(/^Structure is missing/);
    expect(c!.domains.map(d => d.domain)).toEqual(['documentation', 'purpose', 'planning', 'structure', 'intentional-engineering']);
    expect(c!.domains[3].status).toBe('missing');
    expect(c!.nextAction?.route).toBe('/api/repository-improvement/preview');
    expect(c!.nextAction?.body).toEqual({ repoName: 'smoke-managed-repo', repoPath: 'C:\\repos\\smoke-managed-repo' });
    expect(c!.nextAction?.previewFirst).toBe(true);
  });

  it('refuses a payload whose conclusion is outside the set (the card must not invent one)', () => {
    expect(normalizeRepositoryConclusion({ ...wireConclusion, conclusion: 'L0-Absent' })).toBeNull();
    expect(normalizeRepositoryConclusion(null)).toBeNull();
    expect(normalizeRepositoryConclusion('strengthen')).toBeNull();
  });

  it('never prints a bare maturity code as the reason — a repo without a roadmap shows a conclusion, not L0-Absent', () => {
    expect(normalizeRepositoryConclusion({ ...wireConclusion, reason: 'L0-Absent' })!.reason).toBe(MISSING_REASON_TEXT);
    expect(normalizeRepositoryConclusion({ ...wireConclusion, reason: '   ' })!.reason).toBe(MISSING_REASON_TEXT);
    expect(normalizeRepositoryConclusion({ ...wireConclusion, reason: 'Planning is missing: no plan recorded (no ROADMAP.md).' })!.reason).toMatch(/no plan recorded/);
  });

  it('drops a next action with no route and coerces an unknown domain status to not-scored', () => {
    const c = normalizeRepositoryConclusion({
      ...wireConclusion,
      nextAction: { kind: 'x', label: 'no route here' },
      domains: [{ domain: 'planning', title: 'Planning', status: 'banana', evidence: ['x'] }],
    })!;
    expect(c.nextAction).toBeNull();
    expect(c.domains[0].status).toBe('not-scored');
    expect(c.domains[0].nextAction).toBeNull();
  });
});

describe('outcome summary — the list row', () => {
  it('normalizes the backend summary and treats appropriate-as-is as first-class', () => {
    const s = normalizeRepositoryOutcomeSummary({
      conclusion: 'appropriate-as-is', reason: 'Every applicable foundation is present - documentation: README present, score 90/100.',
      kind: 'unknown', gapCount: 0, gapDomains: [], nextActionKind: 'dispatch-readiness-check', nextActionLabel: 'Check the top-value item is ready to package',
      nextActionRoute: '/api/roadmap/dispatch/check', holds: true,
    })!;
    expect(s.conclusion).toBe('appropriate-as-is');
    expect(s.nextActionRoute).toBe('/api/roadmap/dispatch/check');
    expect(describeConclusion(s.conclusion)).toEqual({ label: 'Appropriate as-is', tone: 'healthy', filterable: true });
  });

  it('derives the same summary from a full conclusion as the backend would send', () => {
    const c = normalizeRepositoryConclusion(wireConclusion)!;
    const s = summarizeRepositoryConclusion(c, { holds: true, violations: [] });
    expect(s).toEqual({
      conclusion: 'strengthen',
      reason: c.reason,
      kind: 'unknown',
      gapCount: 2,
      gapDomains: ['planning', 'structure'],
      nextActionKind: 'repository-improvement-preview',
      nextActionLabel: 'Preview the structure repairs',
      nextActionRoute: '/api/repository-improvement/preview',
      holds: true,
    });
  });

  it('filters every conclusion the same way, including appropriate-as-is, and null keeps everything', () => {
    const entries = [
      { repoName: 'a', outcome: normalizeRepositoryOutcomeSummary({ conclusion: 'strengthen', reason: 'r', gapCount: 1 }) },
      { repoName: 'b', outcome: normalizeRepositoryOutcomeSummary({ conclusion: 'appropriate-as-is', reason: 'r' }) },
      { repoName: 'c', outcome: normalizeRepositoryOutcomeSummary({ conclusion: 'insufficiently-understood', reason: 'needs a clone' }) },
      { repoName: 'd', outcome: null },
    ];
    expect(filterByConclusion(entries, 'appropriate-as-is').map(e => e.repoName)).toEqual(['b']);
    expect(filterByConclusion(entries, 'strengthen').map(e => e.repoName)).toEqual(['a']);
    expect(filterByConclusion(entries, null)).toHaveLength(4);
  });

  it('reads a missing summary as absent rather than inventing a conclusion', () => {
    expect(normalizeRepositoryOutcomeSummary(undefined)).toBeNull();
    expect(normalizeRepositoryOutcomeSummary({ conclusion: 'L0-Absent' })).toBeNull();
  });
});

describe('portfolio conclusions result + contract', () => {
  it('normalizes counts, coverage and the contract, and drops unusable items', () => {
    const r = normalizePortfolioConclusionsResult({
      schemaVersion: 'v1', generatedAt: 'now', count: 2, totalCount: 2, filter: null,
      byConclusion: { strengthen: 1, 'appropriate-as-is': 1, 'insufficiently-understood': 0 },
      byKind: { unknown: 2 },
      coverage: { planning: { present: 1, weak: 1, missing: 0, 'not-applicable': 0, 'not-scored': 0 } },
      contract: { holds: true, violations: [] },
      items: [wireConclusion, { conclusion: 'nope' }],
      cacheSource: 'portfolio-index',
    });
    expect(r.items).toHaveLength(1);
    expect(r.byConclusion['appropriate-as-is']).toBe(1);
    expect(r.coverage.planning.weak).toBe(1);
    expect(r.contract.holds).toBe(true);
    expect(r.cacheSource).toBe('portfolio-index');
  });

  it('a missing contract block reads as not holding — the card must not claim a guarantee nobody made', () => {
    expect(normalizeConclusionContract(undefined).holds).toBe(false);
    expect(normalizeConclusionContract({ holds: true, violations: [] })).toEqual({ holds: true, violations: [] });
  });

  it('labels every domain status and says which ones count toward a gap', () => {
    expect(describeDomainStatus('missing')).toEqual({ label: 'Missing', counts: true });
    expect(describeDomainStatus('not-applicable').counts).toBe(false);
    expect(describeDomainStatus('not-scored').label).toBe('Observed, not scored');
  });
});
