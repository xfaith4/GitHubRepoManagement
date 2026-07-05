import React, { useState, useEffect } from 'react';
import { getPortfolioAssessment } from '../services/apiClient';
import { type PortfolioAssessmentSummary } from '../types';

// Release 2.5 Phase 2 — glanceable mobile Repo-Health summary. Shows portfolio
// lifecycle counts + documentation health in a compact grid so an operator can
// read collection health on a phone without opening the full grid. Mobile-only
// (md:hidden); the desktop Insights view carries the richer panels.
function MobileRepoHealth() {
  const [summary, setSummary] = useState<PortfolioAssessmentSummary | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    // Only fetch on a mobile viewport, where this panel is actually shown
    // (md:hidden). On desktop the panel is hidden, so skipping the fetch avoids
    // a scan-triggering call contending with the dashboard on the single-
    // threaded host. Deferred so it never blocks the primary initial load.
    const isMobile = typeof window !== 'undefined' && window.matchMedia && window.matchMedia('(max-width: 767px)').matches;
    if (!isMobile) { setLoading(false); return; }
    const timer = setTimeout(() => {
      getPortfolioAssessment({ scanMode: 'differential' })
        .then(res => { if (!cancelled) { setSummary(res.summary); setLoading(false); } })
        .catch(() => { if (!cancelled) setLoading(false); });
    }, 1500);
    return () => { cancelled = true; clearTimeout(timer); };
  }, []);

  const tiles: Array<{ label: string; value: number; cls: string }> = summary
    ? [
        { label: 'Repos', value: summary.totalRepos, cls: 'text-gray-200' },
        { label: 'Ready', value: summary.readyForWorkCount, cls: 'text-green-300' },
        { label: 'Running', value: summary.runningCount, cls: 'text-sky-300' },
        { label: 'Blocked', value: summary.blockedCount, cls: 'text-red-300' },
        { label: 'No README', value: summary.missingReadmeCount, cls: 'text-yellow-300' },
        { label: 'No roadmap', value: summary.missingRoadmapCount, cls: 'text-yellow-300' },
      ]
    : [];

  return (
    <section
      data-testid="mobile-repo-health"
      className="md:hidden mx-3 mt-3 rounded-lg border border-gray-700 bg-gray-800/50 p-3"
      aria-label="Repository health summary"
    >
      <h2 className="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-2">Repo Health</h2>
      {loading ? (
        <p className="text-xs text-gray-500">Loading portfolio health…</p>
      ) : summary ? (
        <div className="grid grid-cols-3 gap-2">
          {tiles.map(t => (
            <div key={t.label} className="rounded bg-gray-900/60 px-2 py-1.5 text-center">
              <div className={`text-lg font-bold ${t.cls}`}>{t.value}</div>
              <div className="text-[10px] text-gray-500 leading-tight">{t.label}</div>
            </div>
          ))}
        </div>
      ) : (
        <p className="text-xs text-gray-500">Portfolio health unavailable.</p>
      )}
    </section>
  );
}

export default MobileRepoHealth;
