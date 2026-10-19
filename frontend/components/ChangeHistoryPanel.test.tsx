// @vitest-environment jsdom
//
// Issue #343. The panel was "Team Activity Dashboard" and summed every
// author's commits from the portfolio index. There is no team, and the totals
// cannot tell the operator's commits from the product's. These assert the
// panel names what it counts and reports the product's own commits from the
// runner's records, separately.
import { it, expect, afterEach } from 'vitest';
import { render, screen, cleanup, within } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import ChangeHistoryPanel from './ChangeHistoryPanel';
import type { RepoStatus, RunnerRunOutcomes } from '../types';

afterEach(() => { cleanup(); });

const repos = [
  { name: 'FreshStartFamily', commitsLastWeek: 3, commitsLastMonth: 9, lastCommitAuthor: 'Xfaith4', lastCommitDate: null },
  { name: 'SystemDashboard', commitsLastWeek: 1, commitsLastMonth: 2, lastCommitAuthor: 'Xfaith4', lastCommitDate: null },
] as unknown as RepoStatus[];

const runnerRuns: RunnerRunOutcomes = {
  windowDays: 14, total: 5, finished: 5, failed: 4, inFlight: 0, cancelled: 0, committed: 1, errorRatePct: 80, basis: 'runner summaries',
};

it('names what it counts and claims no team', () => {
  render(<ChangeHistoryPanel repos={repos} runnerRuns={runnerRuns} />);
  expect(screen.getByRole('heading', { name: /Commit Activity/ })).toBeVisible();
  expect(screen.getByText('All authors, local clones in the portfolio index')).toBeVisible();
  expect(document.body.textContent).not.toMatch(/Team|Contributors|Real-time/);
});

it('reports commits the product made separately from all-author totals', () => {
  render(<ChangeHistoryPanel repos={repos} runnerRuns={runnerRuns} />);
  const product = screen.getByTestId('product-commit-activity');
  expect(product).toHaveTextContent('1 of 5 runner runs in the last 14 days recorded a commit.');
  expect(screen.getByText(/by all authors across/)).toBeVisible();
});

it('says the product share is unknown when runner outcomes are missing', () => {
  render(<ChangeHistoryPanel repos={repos} />);
  expect(within(screen.getByTestId('product-commit-activity')).getByText(/cannot be separated/)).toBeVisible();
});
