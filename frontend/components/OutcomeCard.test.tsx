// @vitest-environment jsdom
//
// Release 3.6 milestone 2 — the outcome card.
//
// The failures these prevent are the ones the release exists to end: a
// repository that reads as `L0-Absent` and nothing else, an `appropriate
// as-is` verdict rendered as an empty state, a `strengthen` verdict with no
// runnable next step, and a next action that would POST somewhere this console
// does not actually expose.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import OutcomeCard from './OutcomeCard';
import { normalizeRepositoryConclusion, type RepositoryConclusion } from '../lib/foundationConclusion';

afterEach(() => cleanup());

function conclusion(overrides: Record<string, unknown> = {}): RepositoryConclusion {
  const base = {
    schemaVersion: 'v1',
    repoId: 'repo:demo',
    repoName: 'demo',
    kind: 'unknown',
    kindBasis: 'no kind signal in the index',
    conclusion: 'strengthen',
    reason: 'Planning is missing: no plan recorded (no ROADMAP.md).',
    basis: ['planning=missing'],
    domains: [
      { domain: 'documentation', title: 'Documentation', status: 'present', evidence: ['README present, score 80/100'], nextAction: null },
      { domain: 'purpose', title: 'Purpose', status: 'present', evidence: ['README states the purpose'], nextAction: null },
      { domain: 'planning', title: 'Planning', status: 'missing', evidence: ['no plan recorded (no ROADMAP.md)'], nextAction: null },
      { domain: 'structure', title: 'Structure', status: 'present', evidence: ['layout meets the other structure standard'], nextAction: null },
      { domain: 'intentional-engineering', title: 'Intentional engineering', status: 'not-scored', evidence: ['no CI workflow observed', 'observed, not judged'], nextAction: null },
    ],
    nextAction: {
      domain: 'planning',
      kind: 'roadmap-repair-preview',
      label: 'Preview the smallest credible plan',
      method: 'POST',
      route: '/api/roadmap/repair/preview',
      body: { repoName: 'demo' },
      previewFirst: true,
    },
    maturityLevel: 'L0-Absent',
    lifecycleState: 'needs-roadmap',
    generatedAt: '2026-08-27T12:00:00.000Z',
    ...overrides,
  };
  const normalized = normalizeRepositoryConclusion(base);
  if (!normalized) throw new Error('fixture did not normalize');
  return normalized;
}

describe('OutcomeCard — a repository never reads as only a maturity code', () => {
  it('shows a conclusion and its reason for a repo with no roadmap, not a bare L0-Absent', () => {
    render(<OutcomeCard conclusion={conclusion()} />);
    expect(screen.getByText('Strengthen')).toBeInTheDocument();
    // The reason states the verdict; the same evidence also appears under its
    // domain, which is why this targets the reason paragraph specifically.
    expect(screen.getByText('Planning is missing: no plan recorded (no ROADMAP.md).')).toBeInTheDocument();
    // The maturity level may appear as supporting detail, but never as the whole story.
    const body = document.body.textContent ?? '';
    expect(body).toContain('Planning is missing');
    expect(body.trim()).not.toBe('L0-Absent');
  });

  it('renders every foundation domain with its status and evidence', () => {
    render(<OutcomeCard conclusion={conclusion()} />);
    for (const title of ['Documentation', 'Purpose', 'Planning', 'Structure', 'Intentional engineering']) {
      expect(screen.getByText(title)).toBeInTheDocument();
    }
    expect(screen.getByText('Missing')).toBeInTheDocument();
    expect(screen.getByText('Observed, not scored')).toBeInTheDocument();
    expect(screen.getByText('README present, score 80/100')).toBeInTheDocument();
  });
});

describe('OutcomeCard — appropriate as-is is a first-class outcome', () => {
  const healthy = () =>
    conclusion({
      conclusion: 'appropriate-as-is',
      reason: 'Every applicable foundation is present - documentation: README present, score 90/100.',
      nextAction: null,
      domains: [
        { domain: 'documentation', title: 'Documentation', status: 'present', evidence: ['README present, score 90/100'], nextAction: null },
        { domain: 'planning', title: 'Planning', status: 'not-applicable', evidence: ['An archived repository plans no further work.'], nextAction: null },
      ],
    });

  it('renders the verdict, its reason and its evidence — not an empty state', () => {
    render(<OutcomeCard conclusion={healthy()} />);
    expect(screen.getByText('Appropriate as-is')).toBeInTheDocument();
    expect(screen.getByText(/Every applicable foundation is present/)).toBeInTheDocument();
    expect(screen.getByText('An archived repository plans no further work.')).toBeInTheDocument();
    expect(screen.getByText(/This is an outcome, not an absence of one/)).toBeInTheDocument();
  });

  it('states why a not-applicable domain does not apply', () => {
    render(<OutcomeCard conclusion={healthy()} />);
    expect(screen.getByText('Not applicable')).toBeInTheDocument();
  });
});

describe('OutcomeCard — the next action', () => {
  it('runs the preview-first action and hands the caller the whole action object', async () => {
    const onRun = vi.fn().mockResolvedValue(undefined);
    render(<OutcomeCard conclusion={conclusion()} onRunNextAction={onRun} />);
    const button = screen.getByRole('button', { name: 'Preview the smallest credible plan' });
    expect(button).toBeEnabled();
    fireEvent.click(button);
    await waitFor(() => expect(onRun).toHaveBeenCalledTimes(1));
    expect(onRun.mock.calls[0][0]).toMatchObject({
      route: '/api/roadmap/repair/preview',
      method: 'POST',
      body: { repoName: 'demo' },
    });
    expect(screen.getByText(/Preview first — nothing is applied/)).toBeInTheDocument();
  });

  it('surfaces a failure instead of leaving the operator to guess', async () => {
    const onRun = vi.fn().mockRejectedValue(new Error('the host refused: repoPath is required'));
    render(<OutcomeCard conclusion={conclusion()} onRunNextAction={onRun} />);
    fireEvent.click(screen.getByRole('button', { name: 'Preview the smallest credible plan' }));
    await waitFor(() => expect(screen.getByText(/the host refused: repoPath is required/)).toBeInTheDocument());
  });

  it('refuses to run a route this console does not expose, and says why', () => {
    const rogue = conclusion({
      nextAction: {
        domain: 'planning', kind: 'x', label: 'Do the thing', method: 'POST',
        route: '/api/admin/delete-everything', body: { repoName: 'demo' }, previewFirst: true,
      },
    });
    render(<OutcomeCard conclusion={rogue} onRunNextAction={vi.fn()} />);
    const button = screen.getByRole('button', { name: 'Do the thing' });
    expect(button).toBeDisabled();
    expect(screen.getByText(/is not one of this console's preview-first flows/)).toBeInTheDocument();
  });

  it('refuses an action that names no repository', () => {
    const empty = conclusion({
      nextAction: {
        domain: 'planning', kind: 'roadmap-repair-preview', label: 'Preview the plan', method: 'POST',
        route: '/api/roadmap/repair/preview', body: { repoName: '' }, previewFirst: true,
      },
    });
    render(<OutcomeCard conclusion={empty} onRunNextAction={vi.fn()} />);
    expect(screen.getByRole('button', { name: 'Preview the plan' })).toBeDisabled();
    expect(screen.getByText(/names no repository/)).toBeInTheDocument();
  });
});

describe('OutcomeCard — the contract', () => {
  it('shows the product breaking its own contract rather than hiding it', () => {
    render(
      <OutcomeCard
        conclusion={conclusion()}
        contractViolations={['demo concludes strengthen but names no next-action route']}
      />
    );
    expect(screen.getByText(/did not satisfy the product's own contract/)).toBeInTheDocument();
    expect(screen.getByText(/names no next-action route/)).toBeInTheDocument();
  });
});
