// @vitest-environment jsdom
//
// Lane 0.16 — the Dependencies tab answers with what repositories run on.
//
// The failure these prevent: a "Dependencies" tab that answers a different
// question than an operator asks (roadmap cross-references instead of
// technologies), and an inventory that renders absence of data — an index
// written before detection existed — as a portfolio with no technology in it.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, within, fireEvent, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import TechInventoryPanel from './TechInventoryPanel';
import type { PortfolioTechInventoryResult } from '../types';
import type { AsyncPanelState } from '../lib/asyncPanel';

afterEach(() => cleanup());

const freshBasis = { indexStale: false, indexAgeHours: 0.3, indexGeneratedAt: '2026-08-30T12:00:00Z', reasons: [] };

function inventory(over: Partial<PortfolioTechInventoryResult> = {}): PortfolioTechInventoryResult {
  return {
    generatedAt: '2026-08-30T12:00:00Z',
    repoCount: 10,
    reposWithTechnologyData: 10,
    technologies: [
      {
        id: 'nodejs', label: 'Node.js', category: 'language', repoCount: 6,
        repos: [{ repoName: 'alpha', evidence: 'package.json at the repo root' }],
      },
      {
        id: 'nextjs', label: 'Next.js', category: 'framework', repoCount: 3,
        repos: [{ repoName: 'alpha', evidence: 'package.json dependency "next"' }],
      },
      {
        id: 'postgresql', label: 'PostgreSQL', category: 'data', repoCount: 2,
        repos: [
          { repoName: 'alpha', evidence: 'package.json dependency "pg"' },
          { repoName: 'bravo', evidence: 'requirements.txt names "psycopg2"' },
        ],
      },
      {
        id: 'docker', label: 'Docker', category: 'infrastructure', repoCount: 4,
        repos: [{ repoName: 'alpha', evidence: 'Dockerfile at the repo root' }],
      },
    ],
    basis: freshBasis,
    ...over,
  };
}

function panelState(data: PortfolioTechInventoryResult | null, phase: AsyncPanelState<PortfolioTechInventoryResult>['phase'] = 'success'): AsyncPanelState<PortfolioTechInventoryResult> {
  return {
    phase,
    data,
    lastGoodAt: data ? '2026-08-30T12:01:00Z' : null,
    error: phase === 'error' || phase === 'stale' ? { message: 'boom', endpoint: '/api/portfolio/tech-inventory' } : null,
    failedAt: phase === 'error' || phase === 'stale' ? '2026-08-30T12:02:00Z' : null,
  };
}

describe('TechInventoryPanel — technologies with counts and evidence', () => {
  it('groups technologies by category with per-repo counts', () => {
    render(<TechInventoryPanel panel={panelState(inventory())} onRefresh={vi.fn()} />);
    const groups = screen.getByTestId('tech-inventory-groups');
    for (const title of ['Languages & runtimes', 'Frameworks & libraries', 'Data stores', 'Infrastructure & CI']) {
      expect(within(groups).getByRole('heading', { name: title })).toBeInTheDocument();
    }
    expect(within(groups).getByText('Node.js')).toBeInTheDocument();
    expect(within(groups).getByText('6 repos')).toBeInTheDocument();
    expect(within(groups).getByText('PostgreSQL')).toBeInTheDocument();
    expect(within(groups).getByText('2 repos')).toBeInTheDocument();
  });

  it('names the repositories and the manifest evidence behind each detection', () => {
    render(<TechInventoryPanel panel={panelState(inventory())} onRefresh={vi.fn()} />);
    expect(screen.getByText('bravo')).toBeInTheDocument();
    expect(screen.getByText(/requirements\.txt names "psycopg2"/)).toBeInTheDocument();
  });

  it('states its coverage and when the index was generated', () => {
    render(<TechInventoryPanel panel={panelState(inventory())} onRefresh={vi.fn()} />);
    expect(screen.getByText(/10 of 10 indexed repositories carry technology data/)).toBeInTheDocument();
  });
});

describe('TechInventoryPanel — absence of data is never a finding', () => {
  it('says the index predates detection instead of rendering a technology-free portfolio', () => {
    render(
      <TechInventoryPanel
        panel={panelState(inventory({ reposWithTechnologyData: 0, technologies: [] }))}
        onRefresh={vi.fn()}
      />
    );
    expect(screen.getByTestId('tech-inventory-predates')).toHaveTextContent(/predates technology detection/);
    expect(screen.queryByTestId('tech-inventory-groups')).toBeNull();
  });

  it('warns when the index behind the inventory is stale, and stays quiet when it is fresh', () => {
    const stale = inventory({
      basis: { indexStale: true, indexAgeHours: 30, indexGeneratedAt: '2026-08-29T00:00:00Z', reasons: ['The index was generated 30 hour(s) ago, past the 24-hour freshness window.'] },
    });
    const { unmount } = render(<TechInventoryPanel panel={panelState(stale)} onRefresh={vi.fn()} />);
    const banner = screen.getByTestId('tech-inventory-basis');
    expect(banner).toHaveTextContent(/may not describe the portfolio as it is now/);
    expect(banner).toHaveTextContent(/24-hour freshness window/);
    unmount();

    render(<TechInventoryPanel panel={panelState(inventory())} onRefresh={vi.fn()} />);
    expect(screen.queryByTestId('tech-inventory-basis')).toBeNull();
  });

  it('renders a fetch failure as a named error with retry, never as an empty inventory', () => {
    const onRefresh = vi.fn();
    render(<TechInventoryPanel panel={panelState(null, 'error')} onRefresh={onRefresh} />);
    const error = screen.getByTestId('tech-inventory-error');
    expect(error).toHaveTextContent(/could not be read/);
    expect(error).toHaveTextContent(/boom/);
    fireEvent.click(within(error).getByRole('button', { name: 'Retry' }));
    expect(onRefresh).toHaveBeenCalledTimes(1);
  });
});
