import React, { useState, useEffect } from 'react';
import { getAgentRuns } from '../services/apiClient';

// Release 2.5 Phase 2 — always-visible agent-activity indicator. Shows within
// one screen whether any agent run is currently in progress; polls the ledger
// on an interval and is safe to render on mobile (compact pill, 44px tap area).
const ACTIVE_STATUSES = ['running', 'in-progress', 'in_progress', 'dispatched', 'monitoring', 'working'];

function AgentActivityIndicator() {
  const [activeCount, setActiveCount] = useState<number>(0);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let cancelled = false;
    const poll = async () => {
      try {
        const res = await getAgentRuns({ limit: 100 });
        if (cancelled) return;
        const active = res.items.filter(r => ACTIVE_STATUSES.includes(String(r.status).toLowerCase())).length;
        setActiveCount(active);
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
  return (
    <span
      data-testid="agent-activity-indicator"
      className={`inline-flex items-center gap-1.5 min-h-[44px] sm:min-h-0 px-2.5 py-1 rounded-full text-xs font-medium ${
        isActive ? 'bg-green-900/50 text-green-300 border border-green-700' : 'bg-gray-700 text-gray-400'
      }`}
      title={loaded ? (isActive ? `${activeCount} agent run(s) in progress` : 'No agent runs active') : 'Checking agent activity…'}
      aria-live="polite"
    >
      <span className={`inline-block w-2 h-2 rounded-full ${isActive ? 'bg-green-400 animate-pulse' : 'bg-gray-500'}`} />
      {isActive ? `${activeCount} active` : 'Agents idle'}
    </span>
  );
}

export default AgentActivityIndicator;
