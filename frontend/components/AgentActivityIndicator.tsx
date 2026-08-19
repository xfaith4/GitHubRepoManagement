import React, { useState, useEffect } from 'react';
import { getAgentRuns } from '../services/apiClient';
import AgentRunSheet from './AgentRunSheet';

// Release 2.5 Phase 2 — always-visible agent-activity indicator. Shows within
// one screen whether any agent run is currently in progress; polls the ledger
// on an interval and is safe to render on mobile (compact pill, 44px tap area).
const ACTIVE_STATUSES = ['running', 'in-progress', 'in_progress', 'dispatched', 'monitoring', 'working'];

function AgentActivityIndicator() {
  const [activeCount, setActiveCount] = useState<number>(0);
  const [activeSummary, setActiveSummary] = useState<string>('');
  const [loaded, setLoaded] = useState(false);
  // Release 2.9 — the list behind the pill. Until now the only way to learn
  // WHICH runs were active was to hover the title, which does nothing on a
  // phone.
  const [sheetOpen, setSheetOpen] = useState(false);

  useEffect(() => {
    let cancelled = false;
    const poll = async () => {
      try {
        const res = await getAgentRuns({ limit: 100 });
        if (cancelled) return;
        const activeRuns = res.items.filter(r => ACTIVE_STATUSES.includes(String(r.status).toLowerCase()));
        setActiveCount(activeRuns.length);
        // Release 3.5 milestone 6 — "6 active" must say six WHAT. The title
        // names the runs; the label names the noun.
        setActiveSummary(activeRuns.slice(0, 5).map(r => `${String((r as { repoName?: string }).repoName ?? 'unknown repo')}: ${String(r.status)}`).join('; '));
        setLoaded(true);
      } catch {
        if (!cancelled) setLoaded(true);
      }
    };
    poll();
    const timer = setInterval(poll, 30000);
    return () => { cancelled = true; clearInterval(timer); };
  }, []);

  const isActive = activeCount > 0;
  const label = isActive ? `${activeCount} agent run${activeCount === 1 ? '' : 's'}` : 'Agents idle';
  const detail = loaded
    ? (isActive ? `${activeCount} agent run(s) in progress${activeSummary ? ` — ${activeSummary}` : ''}` : 'No agent runs active')
    : 'Checking agent activity…';

  return (
    <>
      <button
        type="button"
        onClick={() => setSheetOpen(true)}
        data-testid="agent-activity-indicator"
        className={`inline-flex items-center gap-1.5 min-h-[44px] sm:min-h-0 px-2.5 py-1 rounded-full text-xs font-medium ${
          isActive ? 'bg-green-900/50 text-green-300 border border-green-700' : 'bg-gray-700 text-gray-400'
        }`}
        title={detail}
        aria-label={`${label}. Open the agent run list.`}
        aria-haspopup="dialog"
      >
        <span className={`inline-block w-2 h-2 rounded-full ${isActive ? 'bg-green-400 animate-pulse' : 'bg-gray-500'}`} />
        <span aria-live="polite">{label}</span>
      </button>
      {sheetOpen && <AgentRunSheet onClose={() => setSheetOpen(false)} />}
    </>
  );
}

export default AgentActivityIndicator;
