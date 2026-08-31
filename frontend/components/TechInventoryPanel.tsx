/**
 * Lane 0.16 — the technology inventory: what the portfolio runs on.
 *
 * The Dependencies tab asked "what does this repository depend on?" and
 * answered with roadmap cross-references — which is not what an operator
 * means by dependencies. This panel answers with technologies: how many
 * repositories run Node, Next.js, PostgreSQL, Docker, and so on, each
 * detection carrying the manifest evidence that produced it.
 *
 * Detection happens in the index build (a scan belongs to the background
 * worker, never to a request), so this panel renders what the last portfolio
 * scan found and says so — including when the index predates detection or no
 * longer describes the portfolio.
 */
import React from 'react';
import type { PortfolioTechInventoryResult, TechInventoryEntry } from '../types';
import type { AsyncPanelState } from '../lib/asyncPanel';
import { SpinnerIcon } from './icons';

const CATEGORY_ORDER = ['language', 'framework', 'data', 'infrastructure'] as const;

const CATEGORY_TITLE: Record<string, string> = {
  language: 'Languages & runtimes',
  framework: 'Frameworks & libraries',
  data: 'Data stores',
  infrastructure: 'Infrastructure & CI',
};

export interface TechInventoryPanelProps {
  panel: AsyncPanelState<PortfolioTechInventoryResult>;
  onRefresh: () => void;
}

function groupByCategory(technologies: TechInventoryEntry[]): Array<{ category: string; title: string; entries: TechInventoryEntry[] }> {
  const known = CATEGORY_ORDER.map(category => ({
    category: category as string,
    title: CATEGORY_TITLE[category],
    entries: technologies.filter(t => t.category === category),
  }));
  const other = technologies.filter(t => !(CATEGORY_ORDER as readonly string[]).includes(t.category));
  if (other.length > 0) known.push({ category: 'other', title: 'Other', entries: other });
  return known.filter(group => group.entries.length > 0);
}

export const TechInventoryPanel: React.FC<TechInventoryPanelProps> = ({ panel, onRefresh }) => {
  const inventory = panel.data;

  return (
    <section data-testid="tech-inventory" className="mb-8">
      <div className="flex items-center justify-between mb-3 flex-wrap gap-3">
        <div>
          <h2 className="text-lg font-semibold text-white">Technology inventory</h2>
          <p className="text-sm text-gray-400 mt-0.5">
            What the portfolio runs on — languages, frameworks, data stores, and infrastructure detected from each
            repository&apos;s manifests when the index was built.
          </p>
        </div>
        <button
          onClick={onRefresh}
          disabled={panel.phase === 'loading'}
          title="Re-read the inventory from the current index. Detection itself runs during a portfolio scan."
          className="px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-200 rounded border border-gray-600 disabled:opacity-50 transition-colors"
        >
          {panel.phase === 'loading' ? 'Loading…' : 'Refresh'}
        </button>
      </div>

      {panel.phase === 'loading' && !inventory && (
        <div className="flex items-center gap-3 py-8 text-gray-400 justify-center">
          <SpinnerIcon className="w-5 h-5 animate-spin" />
          <span>Reading the technology inventory…</span>
        </div>
      )}

      {panel.phase === 'error' && (
        <div className="text-center py-8 text-sm" data-testid="tech-inventory-error">
          <p className="mb-1 text-red-300">The technology inventory could not be read — this is not an empty result.</p>
          <p className="text-gray-500 text-sm mb-3">{panel.error?.endpoint}: {panel.error?.message}</p>
          <button onClick={onRefresh} className="px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-200 rounded border border-gray-600 transition-colors">Retry</button>
        </div>
      )}

      {panel.phase === 'stale' && inventory && (
        <p className="mb-3 rounded border border-amber-800/50 bg-amber-900/20 px-3 py-2 text-sm text-amber-200" data-testid="tech-inventory-stale-fetch">
          Showing the inventory as of {panel.lastGoodAt ? new Date(panel.lastGoodAt).toLocaleTimeString() : '—'} — the refresh at {panel.failedAt ? new Date(panel.failedAt).toLocaleTimeString() : '—'} failed ({panel.error?.message}).
        </p>
      )}

      {inventory && panel.phase !== 'error' && (
        <>
          {/* No amber basis banner here, deliberately (operator principle,
              2026-08-30): amber means an actual problem with the manager,
              never a statement about the validity of the data. Freshness is
              quiet metadata — the footer names when the index was generated
              and, when stale, that a portfolio scan refreshes it. */}

          {inventory.reposWithTechnologyData === 0 ? (
            <div className="text-center py-8 text-gray-500 text-sm" data-testid="tech-inventory-predates">
              <p className="mb-1">The current index predates technology detection.</p>
              <p className="text-gray-600 text-sm">Run a portfolio scan and this inventory fills in from what the scan finds in each repository&apos;s manifests.</p>
            </div>
          ) : inventory.technologies.length === 0 ? (
            <p className="text-center py-8 text-gray-500 text-sm" data-testid="tech-inventory-empty">
              No known technologies were detected in {inventory.reposWithTechnologyData} scanned repositories.
            </p>
          ) : (
            <div className="grid gap-4 md:grid-cols-2" data-testid="tech-inventory-groups">
              {groupByCategory(inventory.technologies).map(group => (
                <div key={group.category} className="border border-gray-700 rounded-lg bg-gray-800/40 px-4 py-3">
                  <h3 className="text-sm uppercase tracking-wide text-gray-400 font-semibold mb-2">{group.title}</h3>
                  <ul className="space-y-2">
                    {group.entries.map(entry => (
                      <li key={entry.id}>
                        <details>
                          <summary className="cursor-pointer list-none">
                            <div className="flex items-center justify-between gap-3 text-sm">
                              <span className="text-white">{entry.label}</span>
                              <span className="text-gray-400 text-sm whitespace-nowrap">{entry.repoCount} {entry.repoCount === 1 ? 'repo' : 'repos'}</span>
                            </div>
                            <div className="mt-1 h-1.5 rounded bg-gray-700/60 overflow-hidden" aria-hidden="true">
                              <div
                                className="h-full rounded bg-indigo-500"
                                style={{ width: `${Math.max(3, Math.round((100 * entry.repoCount) / Math.max(1, inventory.repoCount)))}%` }}
                              />
                            </div>
                          </summary>
                          <ul className="mt-2 mb-1 pl-3 border-l border-gray-700 space-y-1">
                            {entry.repos.map(repo => (
                              <li key={`${entry.id}:${repo.repoName}`} className="text-sm">
                                <span className="text-gray-200">{repo.repoName}</span>
                                {repo.evidence && <span className="text-gray-500"> — {repo.evidence}</span>}
                              </li>
                            ))}
                          </ul>
                        </details>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </div>
          )}

          <p className="text-sm text-gray-600 text-right pt-2" data-testid="tech-inventory-footer">
            {inventory.reposWithTechnologyData} of {inventory.repoCount} indexed repositories carry technology data
            {inventory.generatedAt ? ` · index generated ${new Date(inventory.generatedAt).toLocaleString()}` : ''}
            {inventory.basis.indexStale ? ' · a portfolio scan refreshes this' : ''}
          </p>
        </>
      )}
    </section>
  );
};

export default TechInventoryPanel;
