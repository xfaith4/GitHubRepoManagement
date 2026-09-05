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

describe('TodayView — no warning banner on the landing page', () => {
  // Lane 0.13 shipped a staleness banner here; the operator removed it
  // (2026-08-30): the first screen opening with an amber warning reads as a
  // broken product. The verdict still rides every payload as `basis` — it is
  // simply not rendered on this view. This pins the removal.
  it('renders no staleness banner even when the basis is stale or absent', () => {
    const { unmount } = render(
      <TodayView
        entries={[entry('alpha')]}
        basis={{ indexStale: true, indexAgeHours: 14.2, indexGeneratedAt: '2026-08-27T09:46:23Z', reasons: ['stale by logic'] }}
      />
    );
    expect(screen.queryByTestId('today-staleness')).toBeNull();
    unmount();

    render(<TodayView entries={[entry('alpha')]} />);
    expect(screen.queryByTestId('today-staleness')).toBeNull();
  });
});

describe('TodayView — the toolbar offers the portfolio scan', () => {
  // The scan control survives the banner's removal, as a quiet toolbar
  // control rather than an alarm: rebuilding the index must stay one click
  // away from the ranking drawn from it.
  it('starts the scan and says the ranking will refresh', async () => {
    const onRunScan = vi.fn().mockResolvedValue({ started: true, alreadyRunning: false });
    render(<TodayView entries={[entry('alpha')]} onRunScan={onRunScan} />);
    fireEvent.click(screen.getByRole('button', { name: 'Run portfolio scan' }));
    expect(onRunScan).toHaveBeenCalledTimes(1);
    expect(await screen.findByTestId('today-scan-note')).toHaveTextContent(/Scan started/);
    // One request per click: the button yields to the note while the scan runs.
    expect(screen.queryByRole('button', { name: 'Run portfolio scan' })).toBeNull();
  });

  it('says so when a scan is already running instead of pretending to start one', async () => {
    const onRunScan = vi.fn().mockResolvedValue({ started: false, alreadyRunning: true });
    render(<TodayView entries={[entry('alpha')]} onRunScan={onRunScan} />);
    fireEvent.click(screen.getByRole('button', { name: 'Run portfolio scan' }));
    expect(await screen.findByTestId('today-scan-note')).toHaveTextContent(/already running/);
  });

  it('shows the failure and offers the button again when the start is refused', async () => {
    const onRunScan = vi.fn().mockRejectedValue(new Error('The API host is not reachable.'));
    render(<TodayView entries={[entry('alpha')]} onRunScan={onRunScan} />);
    fireEvent.click(screen.getByRole('button', { name: 'Run portfolio scan' }));
    expect(await screen.findByTestId('today-scan-note')).toHaveTextContent('The API host is not reachable.');
    expect(screen.getByRole('button', { name: 'Run portfolio scan' })).toBeEnabled();
  });

  it('re-offers the button when a refresh re-draws the ranking', async () => {
    const staleBasis = { indexStale: true, indexAgeHours: 14.2, indexGeneratedAt: '2026-08-27T09:46:23Z', reasons: [] };
    const onRunScan = vi.fn().mockResolvedValue({ started: true, alreadyRunning: false });
    const { rerender } = render(<TodayView entries={[entry('alpha')]} basis={staleBasis} onRunScan={onRunScan} />);
    fireEvent.click(screen.getByRole('button', { name: 'Run portfolio scan' }));
    await screen.findByTestId('today-scan-note');
    rerender(<TodayView entries={[entry('alpha')]} basis={{ ...staleBasis, indexAgeHours: 0.1 }} onRunScan={onRunScan} />);
    expect(screen.getByRole('button', { name: 'Run portfolio scan' })).toBeEnabled();
    expect(screen.queryByTestId('today-scan-note')).toBeNull();
  });

  it('renders no dead control when no scan handler is wired', () => {
    render(<TodayView entries={[entry('alpha')]} />);
    expect(screen.queryByRole('button', { name: 'Run portfolio scan' })).toBeNull();
  });
});

// --- Unit 1: Now — holds, gaps, and readiness -----------------------------
//
// The failures these prevent, in order:
//   1. A landing screen that opens as a wall of red. The staleness banner was
//      removed for that reason (2026-08-30); "Needs you" must not bring it
//      back in another form, so actionable holds start collapsed.
//   2. A stuck lane hidden behind a click. Work already under way and stopped
//      is the one thing that must never be collapsed.
//   3. Ambient documentation gaps presented as alarms — the mistake
//      `needsAttention.ts` avoids by excluding them from the attention signal.
//   4. A repository ranked by business value. Every repository here is useful,
//      so the figure beside a row measures readiness for unattended work.

describe('TodayView — Needs you collapses, blocking never does', () => {
  it('collapses actionable holds behind a count on first paint', () => {
    render(<TodayView entries={[entry('alpha', { localDirtyCount: 12, executionState: 'idle' })]} />);

    expect(screen.getByTestId('today-holds-toggle')).toHaveTextContent('1 needs you');
    // The card itself is not in the document until asked for.
    expect(screen.queryByTestId('today-hold-working-tree-dirty')).not.toBeInTheDocument();
  });

  it('opens the holds and shows each rule with its reason', () => {
    render(<TodayView entries={[entry('alpha', { localDirtyCount: 12, executionState: 'idle' })]} />);
    fireEvent.click(screen.getByTestId('today-holds-toggle'));

    const card = screen.getByTestId('today-hold-working-tree-dirty');
    expect(card).toHaveTextContent('12 uncommitted files block dispatch');
    expect(card).toHaveTextContent('destructive');
    expect(within(card).getByText('always held')).toBeInTheDocument();
  });

  it('never collapses a hold that is blocking a lane', () => {
    render(<TodayView entries={[entry('alpha', { localDirtyCount: 12, executionState: 'running' })]} />);

    // Visible with no interaction, and not behind the collapse control.
    const card = screen.getByTestId('today-hold-working-tree-dirty');
    expect(card).toHaveAttribute('data-severity', 'blocking');
    expect(screen.queryByTestId('today-holds-toggle')).not.toBeInTheDocument();
  });

  it('keeps ambient gaps out of Needs you and in the quiet list', () => {
    render(<TodayView entries={[entry('alpha', { roadmapState: 'missing', executionState: 'idle' })]} />);

    expect(screen.queryByTestId('today-needs-you')).not.toBeInTheDocument();
    const gap = screen.getByTestId('today-gap-roadmap-missing');
    expect(gap).toHaveTextContent('authors a new contract');
  });

  it('promotes an ambient gap to blocking when the lane is stuck on it', () => {
    render(<TodayView entries={[entry('alpha', { roadmapState: 'missing', executionState: 'running' })]} />);

    expect(screen.getByTestId('today-hold-roadmap-missing')).toHaveAttribute('data-severity', 'blocking');
    expect(screen.queryByTestId('today-gap-roadmap-missing')).not.toBeInTheDocument();
  });
});

describe('TodayView — readiness replaces the value score', () => {
  it('measures readiness for unattended work, not worth', () => {
    render(<TodayView entries={[entry('alpha', {
      hasReadme: true, hasRoadmap: true, roadmapState: 'pending', localDirtyCount: 0, hasCiSignal: true,
    })]} />);

    expect(screen.getByRole('columnheader', { name: 'Ready for unattended work' })).toBeInTheDocument();
    expect(screen.getByTestId('today-readiness')).toHaveTextContent('4 of 4 ready');
  });

  it('reports an unmeasured check as unmeasured rather than as a failure', () => {
    render(<TodayView entries={[entry('alpha', {
      hasReadme: true, hasRoadmap: true, roadmapState: 'pending', localDirtyCount: 0, hasCiSignal: undefined,
    })]} />);

    expect(screen.getByTestId('today-readiness')).toHaveTextContent('3 of 3 ready · ci present unmeasured');
  });

  it('stamps how old the assessment is, because a stale score is actionable', () => {
    render(<TodayView
      entries={[entry('alpha')]}
      basis={{ indexStale: false, indexAgeHours: 5, indexGeneratedAt: '2026-09-01T00:00:00Z', reasons: [] }}
    />);

    expect(screen.getByText('assessed 5 hours ago')).toBeInTheDocument();
  });

  it('no longer prints a business-value figure anywhere', () => {
    render(<TodayView entries={[entry('alpha')]} />);
    expect(screen.queryByText(/^value \d+$/)).not.toBeInTheDocument();
  });
});

it('shows the ranking basis as visible text without hovering', () => {
  render(<TodayView entries={[entry('alpha')]} />);
  expect(screen.getByTestId('today-rank-basis')).toBeVisible();
  expect(screen.getByTestId('today-rank-basis')).toHaveTextContent('Rank basis:');
});
