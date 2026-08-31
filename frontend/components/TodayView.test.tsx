// @vitest-environment jsdom
//
// Release 3.6 milestone 3 — the ranked `Today` landing.
//
// The failure this prevents: a first screen that shows a portfolio without
// saying what the product evaluated, what it concluded, or what to do next —
// the state the product lens (§2) exists to end. These assert the four things
// the milestone promises: an orientation paragraph, a ranked table, one
// primary action per row, and effort — with every conclusion filterable.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, within, fireEvent, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import TodayView from './TodayView';
import type { OperationsRepoEntry } from '../types';
import { normalizeRepositoryOutcomeSummary } from '../lib/foundationConclusion';

afterEach(() => cleanup());

function entry(name: string, over: Partial<OperationsRepoEntry> = {}): OperationsRepoEntry {
  return {
    repoId: `repo:${name}`,
    repoName: name,
    outcome: normalizeRepositoryOutcomeSummary({
      conclusion: 'strengthen',
      reason: `${name}: Planning is missing: no plan recorded (no ROADMAP.md).`,
      kind: 'unknown',
      gapCount: 1,
      gapDomains: ['planning'],
      nextActionKind: 'roadmap-repair-preview',
      nextActionLabel: 'Preview the smallest credible plan',
      nextActionRoute: '/api/roadmap/repair/preview',
      holds: true,
    }),
    estimatedSessionWorkUnits: 3,
    curationState: 'none',
    ...over,
  } as OperationsRepoEntry;
}

const healthy = (name: string) =>
  entry(name, {
    outcome: normalizeRepositoryOutcomeSummary({
      conclusion: 'appropriate-as-is',
      reason: `${name}: Every applicable foundation is present.`,
      kind: 'unknown',
      gapCount: 0,
      gapDomains: [],
      holds: true,
    }),
  });

describe('TodayView — the first screen explains the product', () => {
  it('opens with an orientation naming what was evaluated and concluded', () => {
    render(<TodayView entries={[entry('alpha'), healthy('bravo')]} />);
    const orientation = screen.getByTestId('today-orientation').textContent ?? '';
    expect(orientation).toContain('assessed 2 repositories');
    expect(orientation).toContain('five foundations');
    expect(orientation).toContain('1 would be strengthened');
    expect(orientation).toContain('1 is appropriate as-is');
  });

  it('ranks the table and gives each row a why-now, one action, and an effort', () => {
    render(<TodayView entries={[healthy('zulu'), entry('alpha')]} />);
    const rows = within(screen.getByTestId('today-table')).getAllByRole('row').slice(1);
    expect(rows).toHaveLength(2);
    // Actionable work leads; finished work is still listed.
    expect(within(rows[0]).getByText('alpha')).toBeInTheDocument();
    expect(within(rows[0]).getByText(/Planning is missing/)).toBeInTheDocument();
    expect(within(rows[0]).getByRole('button', { name: 'Preview the smallest credible plan' })).toBeInTheDocument();
    expect(within(rows[0]).getByText('3 work units')).toBeInTheDocument();
    expect(within(rows[1]).getByText('zulu')).toBeInTheDocument();
    expect(within(rows[1]).getByText('None warranted')).toBeInTheDocument();
  });

  it('states the columns the milestone promises', () => {
    render(<TodayView entries={[entry('alpha')]} />);
    for (const column of ['Repository', 'Why now', 'Next action', 'Effort']) {
      expect(screen.getByRole('columnheader', { name: column })).toBeInTheDocument();
    }
  });

  it('says "effort not estimated" rather than inventing a number', () => {
    render(<TodayView entries={[entry('alpha', { estimatedSessionWorkUnits: null })]} />);
    expect(screen.getByText('Effort not estimated')).toBeInTheDocument();
  });
});

describe('TodayView — appropriate as-is filters like any other outcome', () => {
  it('offers a filter for every conclusion with its count', () => {
    render(<TodayView entries={[entry('a'), healthy('b'), healthy('c')]} />);
    expect(screen.getByRole('button', { name: 'All 3' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Strengthen 1' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Appropriate as-is 2' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Insufficiently understood 0' })).toBeInTheDocument();
  });

  it('filters to appropriate-as-is and back', () => {
    render(<TodayView entries={[entry('a'), healthy('b'), healthy('c')]} />);
    fireEvent.click(screen.getByRole('button', { name: 'Appropriate as-is 2' }));
    let rows = within(screen.getByTestId('today-table')).getAllByRole('row').slice(1);
    expect(rows).toHaveLength(2);
    expect(screen.queryByText('a')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Appropriate as-is 2' }));
    rows = within(screen.getByTestId('today-table')).getAllByRole('row').slice(1);
    expect(rows).toHaveLength(3);
  });

  it('explains an empty filter result instead of showing a blank table', () => {
    render(<TodayView entries={[entry('a')]} />);
    fireEvent.click(screen.getByRole('button', { name: 'Appropriate as-is 0' }));
    expect(screen.getByTestId('today-empty')).toHaveTextContent(/Clear the filter/);
  });
});

describe('TodayView — the row is a way in', () => {
  it('opens the repository and runs the action through its callbacks', () => {
    const onOpenRepo = vi.fn();
    const onRunAction = vi.fn();
    render(<TodayView entries={[entry('alpha')]} onOpenRepo={onOpenRepo} onRunAction={onRunAction} />);
    fireEvent.click(screen.getByRole('button', { name: 'alpha' }));
    expect(onOpenRepo).toHaveBeenCalledWith('repo:alpha', 'alpha');
    fireEvent.click(screen.getByRole('button', { name: 'Preview the smallest credible plan' }));
    expect(onRunAction).toHaveBeenCalledTimes(1);
    expect(onRunAction.mock.calls[0][0]).toMatchObject({ repoName: 'alpha', nextActionRoute: '/api/roadmap/repair/preview' });
  });

  it('tells the operator what to do when nothing is indexed', () => {
    render(<TodayView entries={[]} />);
    expect(screen.getByTestId('today-orientation')).toHaveTextContent(/Run a portfolio scan/);
    expect(screen.getByTestId('today-empty')).toHaveTextContent('No repositories are indexed yet.');
  });

  it('shows a repository with no recorded outcome as not concluded, never as blank', () => {
    render(<TodayView entries={[entry('mystery', { outcome: null })]} />);
    expect(screen.getByText('Not concluded')).toBeInTheDocument();
    expect(screen.getByText(/no recorded outcome/)).toBeInTheDocument();
  });
});

describe('TodayView — a ranking says whether it still describes the portfolio', () => {
  // On 2026-08-27 a stale index reported 0 of 9 dispatch-ready repositories and
  // every surface rendered it as fact. Silence about freshness is the defect.
  it('warns when the index behind the ranking is stale, and says why', () => {
    render(
      <TodayView
        entries={[entry('alpha')]}
        basis={{
          indexStale: true,
          indexAgeHours: 14.2,
          indexGeneratedAt: '2026-08-27T09:46:23Z',
          reasons: ['The index does not record which version of the assessment logic produced it.'],
        }}
      />
    );
    const banner = screen.getByTestId('today-staleness');
    expect(banner).toHaveTextContent(/may not describe the portfolio as it is now/);
    expect(banner).toHaveTextContent(/14.2 hour/);
    expect(banner).toHaveTextContent(/does not record which version/);
    expect(banner).toHaveTextContent(/Run a portfolio scan/);
  });

  it('treats an absent verdict as unestablished, not as fresh', () => {
    render(<TodayView entries={[entry('alpha')]} />);
    expect(screen.getByTestId('today-staleness')).toHaveTextContent(/was not established/);
  });

  it('stays out of the way when the index is current', () => {
    render(
      <TodayView
        entries={[entry('alpha')]}
        basis={{ indexStale: false, indexAgeHours: 0.2, indexGeneratedAt: '2026-08-28T00:00:00Z', reasons: [] }}
      />
    );
    expect(screen.queryByTestId('today-staleness')).toBeNull();
  });
});

describe('TodayView — the banner offers the scan it asks for', () => {
  // The banner used to name a remedy ("run a portfolio scan") that no control
  // on the screen could perform; the operator had to know it lived two tabs
  // away under a different name. The warning and its remedy belong together.
  const staleBasis = {
    indexStale: true,
    indexAgeHours: 14.2,
    indexGeneratedAt: '2026-08-27T09:46:23Z',
    reasons: ['The index does not record which version of the assessment logic produced it.'],
  };

  it('starts the scan from the banner and says the ranking will refresh', async () => {
    const onRunScan = vi.fn().mockResolvedValue({ started: true, alreadyRunning: false });
    render(<TodayView entries={[entry('alpha')]} basis={staleBasis} onRunScan={onRunScan} />);
    fireEvent.click(screen.getByRole('button', { name: 'Run portfolio scan' }));
    expect(onRunScan).toHaveBeenCalledTimes(1);
    expect(await screen.findByTestId('today-scan-note')).toHaveTextContent(/Scan started/);
    // One request per click: the button yields to the note while the scan runs.
    expect(screen.queryByRole('button', { name: 'Run portfolio scan' })).toBeNull();
  });

  it('says so when a scan is already running instead of pretending to start one', async () => {
    const onRunScan = vi.fn().mockResolvedValue({ started: false, alreadyRunning: true });
    render(<TodayView entries={[entry('alpha')]} basis={staleBasis} onRunScan={onRunScan} />);
    fireEvent.click(screen.getByRole('button', { name: 'Run portfolio scan' }));
    expect(await screen.findByTestId('today-scan-note')).toHaveTextContent(/already running/);
  });

  it('shows the failure and offers the button again when the start is refused', async () => {
    const onRunScan = vi.fn().mockRejectedValue(new Error('The API host is not reachable.'));
    render(<TodayView entries={[entry('alpha')]} basis={staleBasis} onRunScan={onRunScan} />);
    fireEvent.click(screen.getByRole('button', { name: 'Run portfolio scan' }));
    expect(await screen.findByTestId('today-scan-note')).toHaveTextContent('The API host is not reachable.');
    expect(screen.getByRole('button', { name: 'Run portfolio scan' })).toBeEnabled();
  });

  it('re-offers the button when a refresh delivers a basis that is still stale', async () => {
    const onRunScan = vi.fn().mockResolvedValue({ started: true, alreadyRunning: false });
    const { rerender } = render(<TodayView entries={[entry('alpha')]} basis={staleBasis} onRunScan={onRunScan} />);
    fireEvent.click(screen.getByRole('button', { name: 'Run portfolio scan' }));
    await screen.findByTestId('today-scan-note');
    rerender(<TodayView entries={[entry('alpha')]} basis={{ ...staleBasis, indexAgeHours: 0.1 }} onRunScan={onRunScan} />);
    expect(screen.getByRole('button', { name: 'Run portfolio scan' })).toBeEnabled();
    expect(screen.queryByTestId('today-scan-note')).toBeNull();
  });

  it('renders the guidance without a dead control when no scan handler is wired', () => {
    render(<TodayView entries={[entry('alpha')]} basis={staleBasis} />);
    expect(screen.getByTestId('today-staleness')).toHaveTextContent(/Run a portfolio scan/);
    expect(screen.queryByRole('button', { name: 'Run portfolio scan' })).toBeNull();
  });
});
