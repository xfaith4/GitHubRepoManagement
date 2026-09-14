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
  isRunnableNextAction,
  summarizeNextActionResult,
  AI_EGRESS_ROUTES,
  RUNNABLE_NEXT_ACTION_ROUTES,
  egressRequestFromError,
  explainPrivateScopeAction,
  isAiEgressAction,
  parseAiEgressRequest,
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

// 3.7 M4c - each kind of planning gap reaches its own preview, and a preview
// that declines must read as declined, never as "ready".
describe('summarizeNextActionResult', () => {
  it('reports a declined repair preview as not previewable, with the reason', () => {
    const summary = summarizeNextActionResult({ previewState: 'repair-blocked', blockReason: 'No roadmap file found.', actions: [] });
    expect(summary).toBe('Not previewable: No roadmap file found.');
  });

  it('reports a complete roadmap the repair flow will not rewrite as not previewable', () => {
    expect(summarizeNextActionResult({ previewState: 'rewrite-not-recommended', actions: [] })).toBe('Not previewable: rewrite-not-recommended');
  });

  it('reports an evaluation that drafted a roadmap', () => {
    expect(summarizeNextActionResult({ suggestedRoadmapContent: '# Roadmap', findings: [{}, {}] })).toBe('Draft roadmap ready. Nothing has been applied.');
  });

  it('counts candidate items when the repository already has a roadmap', () => {
    expect(summarizeNextActionResult({ suggestedRoadmapContent: null, suggestedAdditions: [{}, {}, {}], findings: [{}] })).toBe('Preview ready — 3 candidate item(s). Nothing has been applied.');
  });

  it('reports a rewrite preview', () => {
    expect(summarizeNextActionResult({ proposedContent: '- [ ] one', changeSummary: 'x' })).toBe('Rewrite preview ready. Nothing has been applied.');
  });

  it('still counts proposed changes for the flows that return them', () => {
    expect(summarizeNextActionResult({ previewState: 'repair-preview-ready', actions: [{}, {}] })).toBe('Preview ready — 2 proposed change(s). Nothing has been applied.');
  });
});

describe('isRunnableNextAction - M4c routes', () => {
  const base = { domain: 'planning', kind: 'k', label: 'l', method: 'POST' as const, previewFirst: true };
  it('runs the evaluation and the roadmap rewrite preview', () => {
    expect(isRunnableNextAction({ ...base, route: '/api/repo/evaluate', body: { repoName: 'r', localPath: 'p' } })).toBe(true);
    expect(isRunnableNextAction({ ...base, route: '/api/ai/docs/improve/preview', body: { repoName: 'r', docType: 'roadmap', templateId: 'roadmap-contract' } })).toBe(true);
  });

  it('still refuses a route outside the preview-first flows', () => {
    expect(isRunnableNextAction({ ...base, route: '/api/roadmap/repair/apply', body: { repoName: 'r' } })).toBe(false);
  });
});

describe('AI egress - no one-click egress (M4c)', () => {
  const base = { domain: 'planning', kind: 'k', label: 'l', method: 'POST' as const, previewFirst: true };
  const aiAction = { ...base, route: '/api/ai/docs/improve/preview', body: { repoName: 'Private-Repo', docType: 'roadmap' } };
  const asking = {
    previewState: 'ai-egress-confirmation-required',
    previewId: null,
    egress: { state: 'confirmation-required', providerId: 'anthropic', providerLabel: 'Anthropic', modelId: 'claude-x', file: 'C:\\r\\ROADMAP.md', reason: 'needs your confirmation' },
  };

  it('every AI egress route is a runnable route, and only AI routes count as egress', () => {
    for (const route of AI_EGRESS_ROUTES) expect(RUNNABLE_NEXT_ACTION_ROUTES).toContain(route);
    expect(isAiEgressAction(aiAction)).toBe(true);
    expect(isAiEgressAction({ ...base, route: '/api/roadmap/repair/preview', body: { repoName: 'r' } })).toBe(false);
  });

  it('reads the confirmation request, naming the provider and the file', () => {
    expect(parseAiEgressRequest(asking)).toEqual({ providerId: 'anthropic', providerLabel: 'Anthropic', modelId: 'claude-x', file: 'C:\\r\\ROADMAP.md', reason: 'needs your confirmation' });
    expect(summarizeNextActionResult(asking)).toBe('Waiting for your confirmation. Nothing has been sent.');
  });

  it('cannot confirm a request that names no provider or no file', () => {
    expect(parseAiEgressRequest({ ...asking, egress: { ...asking.egress, file: '' } })).toBeNull();
    expect(parseAiEgressRequest({ ...asking, egress: { ...asking.egress, providerId: '' } })).toBeNull();
    expect(parseAiEgressRequest({ proposedContent: '# plan' })).toBeNull();
  });

  it('reports a private-scope refusal as not previewable, with its reason', () => {
    expect(summarizeNextActionResult({ previewState: 'ai-egress-blocked', blockReason: 'Private-Repo is marked private scope in Settings.' }))
      .toBe('Not previewable: Private-Repo is marked private scope in Settings.');
  });

  it('disables an AI action for a private-scope repository, matching names without case', () => {
    expect(explainPrivateScopeAction(aiAction, ['private-repo'])).toMatch(/marked private scope in Settings/);
    expect(explainPrivateScopeAction(aiAction, ['Other'])).toBeNull();
    expect(explainPrivateScopeAction({ ...base, route: '/api/roadmap/repair/preview', body: { repoName: 'Private-Repo' } }, ['Private-Repo'])).toBeNull();
  });

  it('recognizes only the confirmation-required error as an egress request', () => {
    const err = Object.assign(new Error('needs your confirmation'), { name: 'AiEgressConfirmationRequiredError', egressRequest: parseAiEgressRequest(asking) });
    expect(egressRequestFromError(err)?.file).toBe('C:\\r\\ROADMAP.md');
    expect(egressRequestFromError(new Error('boom'))).toBeNull();
    expect(egressRequestFromError('not an error')).toBeNull();
  });
});
