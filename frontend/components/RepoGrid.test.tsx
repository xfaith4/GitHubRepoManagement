// @vitest-environment jsdom
//
// Release 3.2 milestone 3 — row count must not drive render cost.
//
// The milestone was written 2026-08-11 as "virtualize the repo grid", when a
// scan's every repo landed in the DOM. Pagination has since bounded both
// render modes (mobile cards and the desktop table draw from `pagedRepos`,
// default 50/page), which satisfies the milestone's INTENT — render cost is
// O(pageSize), not O(portfolio) — without a windowing dependency. What was
// missing is the assertion that keeps it true: these tests render a portfolio
// far larger than a page and prove the DOM stays bounded, so a future change
// that quietly maps the full list again fails here, not in the operator's
// browser. If the portfolio ever outgrows pagination UX, virtualization is
// the successor — behind the same tests.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import RepoGrid from './RepoGrid';
import type { RepoStatus } from '../types';

function makeRepo(i: number): RepoStatus {
  return {
    name: `repo-${String(i).padStart(3, '0')}`,
    status: 'clean',
    branch: 'main',
    lastCommitDate: new Date().toISOString(),
    lastCommitMessage: `commit in repo ${i}`,
    lastCommitAuthor: 'Fixture',
    localAhead: 0,
    remoteAhead: 0,
    uncommittedChanges: 0,
    isArchived: false,
    isStale: false,
  } as RepoStatus;
}

const REPO_COUNT = 500;
const PAGE_SIZE_DEFAULT = 50;

function renderGrid(repos: RepoStatus[]) {
  return render(
    <RepoGrid
      repos={repos}
      onViewArtifacts={vi.fn()}
      dataSource={{ source: 'local', workspacePath: 'F:\\fixture' }}
      selectedRepos={new Set<string>()}
      setSelectedRepos={vi.fn()}
      groupBy="none"
      setGroupBy={vi.fn()}
    />
  );
}

afterEach(() => {
  cleanup();
});

describe('RepoGrid render bound (Release 3.2 M3)', () => {
  it(`renders at most one page of rows for a ${REPO_COUNT}-repo portfolio`, () => {
    renderGrid(Array.from({ length: REPO_COUNT }, (_, i) => makeRepo(i)));

    // Repo names appear once per visible render mode (card + table row are
    // both in the DOM; CSS hides one). The bound that matters: occurrences
    // scale with PAGE SIZE, never with portfolio size.
    const firstPageRepo = screen.getAllByText('repo-000');
    expect(firstPageRepo.length).toBeGreaterThan(0);
    expect(firstPageRepo.length).toBeLessThanOrEqual(2);

    const offPageRepo = screen.queryAllByText(`repo-${PAGE_SIZE_DEFAULT + 10}`.replace(/^repo-(\d+)$/, (_m, n) => `repo-${String(n).padStart(3, '0')}`));
    expect(offPageRepo.length).toBe(0);

    // Total rendered repo-name nodes stay within two render modes of one page.
    const allRepoNameNodes = screen.getAllByText(/^repo-\d{3}$/);
    expect(allRepoNameNodes.length).toBeLessThanOrEqual(PAGE_SIZE_DEFAULT * 2);
  });

  it('the pager states the true total, so the bound is pagination, not truncation', () => {
    renderGrid(Array.from({ length: REPO_COUNT }, (_, i) => makeRepo(i)));
    // A bounded render that silently dropped repos would be the same lie as a
    // metric that drops them. The pager must account for every repo.
    const summaryCounts = screen.getAllByText(String(REPO_COUNT));
    expect(summaryCounts.length).toBeGreaterThanOrEqual(2); // "Showing 500 of 500"
    const pageIndicator = screen.getByText((_, element) =>
      element?.tagName === 'SPAN' && element.textContent === `Page 1 / ${REPO_COUNT / PAGE_SIZE_DEFAULT}`
    );
    expect(pageIndicator).toBeInTheDocument();
  });

  it('a small portfolio renders every repo (the bound is a cap, not a floor)', () => {
    renderGrid(Array.from({ length: 7 }, (_, i) => makeRepo(i)));
    const nodes = screen.getAllByText(/^repo-\d{3}$/);
    expect(nodes.length).toBeGreaterThanOrEqual(7);
    expect(nodes.length).toBeLessThanOrEqual(14);
  });
});
